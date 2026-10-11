from flask import Blueprint, render_template, redirect, url_for, flash, request
from flask_login import login_required
from sqlalchemy import or_
from app.extensions import db
from app.models.cliente import Cliente
from app.models.pedido import Pedido
from app.forms.cliente_forms import ClienteForm
from app.utils.auth_decorators import lider_required

clientes_bp = Blueprint('clientes', __name__, url_prefix='/clientes')


@clientes_bp.route('/')
@login_required
def index():
    search = request.args.get('q', '').strip()
    status_filter = request.args.get('status', 'todos')
    
    query = Cliente.query

    if search:
        search_term = f"%{search}%"
        query = query.filter(
            or_(
                Cliente.nome.ilike(search_term),
                Cliente.email.ilike(search_term),
                Cliente.documento.ilike(search_term),
                Cliente.telefone.ilike(search_term),
                Cliente.cidade.ilike(search_term)
            )
        )

    if status_filter == 'ativo':
        query = query.filter(Cliente.ativo == True)
    elif status_filter == 'inativo':
        query = query.filter(Cliente.ativo == False)

    clientes = query.order_by(Cliente.nome.asc()).all()
    
    return render_template(
        'clientes/index.html',
        clientes=clientes,
        search=search,
        status_filter=status_filter,
        total_encontrados=len(clientes)
    )


@clientes_bp.route('/novo', methods=['GET', 'POST'])
@login_required
def novo():
    form = ClienteForm()
    if form.validate_on_submit():
        cliente = Cliente(
            nome=form.nome.data.strip(),
            email=form.email.data.strip().lower(),
            telefone=form.telefone.data.strip() if form.telefone.data else None,
            documento=form.documento.data.strip() if form.documento.data else None,
            cep=form.cep.data.strip() if form.cep.data else None,
            logradouro=form.logradouro.data.strip() if form.logradouro.data else None,
            numero=form.numero.data.strip() if form.numero.data else None,
            complemento=form.complemento.data.strip() if form.complemento.data else None,
            bairro=form.bairro.data.strip() if form.bairro.data else None,
            cidade=form.cidade.data.strip() if form.cidade.data else None,
            estado=form.estado.data if form.estado.data else None,
            ativo=form.ativo.data,
            observacoes=form.observacoes.data.strip() if form.observacoes.data else None
        )
        db.session.add(cliente)
        db.session.commit()
        flash(f'Cliente "{cliente.nome}" cadastrado com sucesso!', 'success')
        return redirect(url_for('clientes.detalhe', id=cliente.id))

    return render_template('clientes/form.html', form=form, titulo='Novo Cliente', acao='Cadastrar')


@clientes_bp.route('/<int:id>')
@login_required
def detalhe(id):
    cliente = db.session.get(Cliente, id)
    if not cliente:
        flash('Cliente não encontrado.', 'danger')
        return redirect(url_for('clientes.index'))

    # Statistics for this client
    pedidos = cliente.pedidos
    pedidos_concluidos = [p for p in pedidos if p.status == 'concluido']
    total_gasto = sum(p.valor_total for p in pedidos if p.status != 'cancelado')

    return render_template(
        'clientes/detail.html',
        cliente=cliente,
        pedidos=pedidos,
        pedidos_concluidos=pedidos_concluidos,
        total_gasto=total_gasto
    )


@clientes_bp.route('/<int:id>/editar', methods=['GET', 'POST'])
@login_required
def editar(id):
    cliente = db.session.get(Cliente, id)
    if not cliente:
        flash('Cliente não encontrado.', 'danger')
        return redirect(url_for('clientes.index'))

    form = ClienteForm(obj=cliente)
    if form.validate_on_submit():
        cliente.nome = form.nome.data.strip()
        cliente.email = form.email.data.strip().lower()
        cliente.telefone = form.telefone.data.strip() if form.telefone.data else None
        cliente.documento = form.documento.data.strip() if form.documento.data else None
        cliente.cep = form.cep.data.strip() if form.cep.data else None
        cliente.logradouro = form.logradouro.data.strip() if form.logradouro.data else None
        cliente.numero = form.numero.data.strip() if form.numero.data else None
        cliente.complemento = form.complemento.data.strip() if form.complemento.data else None
        cliente.bairro = form.bairro.data.strip() if form.bairro.data else None
        cliente.cidade = form.cidade.data.strip() if form.cidade.data else None
        cliente.estado = form.estado.data if form.estado.data else None
        cliente.ativo = form.ativo.data
        cliente.observacoes = form.observacoes.data.strip() if form.observacoes.data else None

        db.session.commit()
        flash(f'Cliente "{cliente.nome}" atualizado com sucesso!', 'success')
        return redirect(url_for('clientes.detalhe', id=cliente.id))

    return render_template('clientes/form.html', form=form, cliente=cliente, titulo='Editar Cliente', acao='Salvar Alterações')


@clientes_bp.route('/<int:id>/excluir', methods=['POST'])
@login_required
@lider_required
def excluir(id):
    cliente = db.session.get(Cliente, id)
    if not cliente:
        flash('Cliente não encontrado.', 'danger')
        return redirect(url_for('clientes.index'))

    nome = cliente.nome
    total_pedidos = len(cliente.pedidos)
    db.session.delete(cliente)
    db.session.commit()

    if total_pedidos > 0:
        flash(f'Cliente "{nome}" e seus {total_pedidos} pedidos vinculados foram excluídos com sucesso.', 'info')
    else:
        flash(f'Cliente "{nome}" excluído com sucesso.', 'info')

    return redirect(url_for('clientes.index'))
