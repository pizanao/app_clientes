from datetime import datetime
from flask import Blueprint, render_template, redirect, url_for, flash, request
from flask_login import login_required
from sqlalchemy import or_
from app.extensions import db
from app.models.cliente import Cliente
from app.models.pedido import Pedido
from app.forms.pedido_forms import PedidoForm

pedidos_bp = Blueprint('pedidos', __name__, url_prefix='/pedidos')


def gerar_numero_pedido():
    """Generates an automatic order code: PED-YYYY-XXXX."""
    ano_atual = datetime.utcnow().year
    ultimo_pedido = Pedido.query.filter(
        Pedido.numero_pedido.like(f"PED-{ano_atual}-%")
    ).order_by(Pedido.id.desc()).first()

    if ultimo_pedido:
        try:
            ultimo_num = int(ultimo_pedido.numero_pedido.split('-')[-1])
            proximo = ultimo_num + 1
        except (ValueError, IndexError):
            proximo = Pedido.query.count() + 1
    else:
        proximo = 1

    return f"PED-{ano_atual}-{proximo:04d}"


@pedidos_bp.route('/')
@login_required
def index():
    search = request.args.get('q', '').strip()
    status_filter = request.args.get('status', 'todos')
    cliente_filter = request.args.get('cliente_id', type=int)

    query = Pedido.query.join(Cliente)

    if search:
        search_term = f"%{search}%"
        query = query.filter(
            or_(
                Pedido.numero_pedido.ilike(search_term),
                Pedido.descricao.ilike(search_term),
                Cliente.nome.ilike(search_term)
            )
        )

    if status_filter and status_filter != 'todos':
        query = query.filter(Pedido.status == status_filter)

    if cliente_filter:
        query = query.filter(Pedido.cliente_id == cliente_filter)

    pedidos = query.order_by(Pedido.data_pedido.desc()).all()
    clientes = Cliente.query.order_by(Cliente.nome.asc()).all()

    total_valor = sum(p.valor_total for p in pedidos if p.status != 'cancelado')

    return render_template(
        'pedidos/index.html',
        pedidos=pedidos,
        clientes=clientes,
        search=search,
        status_filter=status_filter,
        cliente_filter=cliente_filter,
        total_valor=total_valor,
        total_encontrados=len(pedidos)
    )


@pedidos_bp.route('/novo', methods=['GET', 'POST'])
@login_required
def novo():
    clientes = Cliente.query.filter_by(ativo=True).order_by(Cliente.nome.asc()).all()
    if not clientes:
        flash('É necessário cadastrar ao menos um cliente ativo antes de criar um pedido.', 'warning')
        return redirect(url_for('clientes.novo'))

    form = PedidoForm()
    form.cliente_id.choices = [(c.id, f"{c.nome} ({c.documento or c.email})") for c in clientes]

    # Pre-select client if passed via URL
    preselected_cliente_id = request.args.get('cliente_id', type=int)
    if request.method == 'GET':
        if preselected_cliente_id and any(c.id == preselected_cliente_id for c in clientes):
            form.cliente_id.data = preselected_cliente_id
        form.numero_pedido.data = gerar_numero_pedido()
        form.data_pedido.data = datetime.now()

    if form.validate_on_submit():
        # Check if order number already exists
        existente = Pedido.query.filter_by(numero_pedido=form.numero_pedido.data.strip()).first()
        if existente:
            flash(f'O número de pedido "{form.numero_pedido.data}" já existe. Geramos outro para você.', 'warning')
            form.numero_pedido.data = gerar_numero_pedido()
            return render_template('pedidos/form.html', form=form, titulo='Novo Pedido', acao='Cadastrar')

        pedido = Pedido(
            cliente_id=form.cliente_id.data,
            numero_pedido=form.numero_pedido.data.strip().upper(),
            data_pedido=form.data_pedido.data,
            status=form.status.data,
            metodo_pagamento=form.metodo_pagamento.data,
            valor_total=float(form.valor_total.data),
            descricao=form.descricao.data.strip(),
            observacoes=form.observacoes.data.strip() if form.observacoes.data else None
        )
        db.session.add(pedido)
        db.session.commit()

        flash(f'Pedido #{pedido.numero_pedido} criado com sucesso!', 'success')
        return redirect(url_for('pedidos.detalhe', id=pedido.id))

    return render_template('pedidos/form.html', form=form, titulo='Novo Pedido', acao='Cadastrar')


@pedidos_bp.route('/<int:id>')
@login_required
def detalhe(id):
    pedido = db.session.get(Pedido, id)
    if not pedido:
        flash('Pedido não encontrado.', 'danger')
        return redirect(url_for('pedidos.index'))

    return render_template('pedidos/detail.html', pedido=pedido)


@pedidos_bp.route('/<int:id>/editar', methods=['GET', 'POST'])
@login_required
def editar(id):
    pedido = db.session.get(Pedido, id)
    if not pedido:
        flash('Pedido não encontrado.', 'danger')
        return redirect(url_for('pedidos.index'))

    clientes = Cliente.query.order_by(Cliente.nome.asc()).all()
    form = PedidoForm(obj=pedido)
    form.cliente_id.choices = [(c.id, f"{c.nome} ({c.documento or c.email})") for c in clientes]

    if form.validate_on_submit():
        # Check unique order number if modified
        num_novo = form.numero_pedido.data.strip().upper()
        if num_novo != pedido.numero_pedido:
            existente = Pedido.query.filter_by(numero_pedido=num_novo).first()
            if existente:
                flash(f'Já existe outro pedido com o número {num_novo}.', 'danger')
                return render_template('pedidos/form.html', form=form, pedido=pedido, titulo='Editar Pedido', acao='Salvar Alterações')

        pedido.cliente_id = form.cliente_id.data
        pedido.numero_pedido = num_novo
        pedido.data_pedido = form.data_pedido.data
        pedido.status = form.status.data
        pedido.metodo_pagamento = form.metodo_pagamento.data
        pedido.valor_total = float(form.valor_total.data)
        pedido.descricao = form.descricao.data.strip()
        pedido.observacoes = form.observacoes.data.strip() if form.observacoes.data else None

        db.session.commit()
        flash(f'Pedido #{pedido.numero_pedido} atualizado com sucesso!', 'success')
        return redirect(url_for('pedidos.detalhe', id=pedido.id))

    return render_template('pedidos/form.html', form=form, pedido=pedido, titulo='Editar Pedido', acao='Salvar Alterações')


@pedidos_bp.route('/<int:id>/excluir', methods=['POST'])
@login_required
def excluir(id):
    pedido = db.session.get(Pedido, id)
    if not pedido:
        flash('Pedido não encontrado.', 'danger')
        return redirect(url_for('pedidos.index'))

    num = pedido.numero_pedido
    db.session.delete(pedido)
    db.session.commit()

    flash(f'Pedido #{num} excluído com sucesso.', 'info')
    return redirect(url_for('pedidos.index'))
