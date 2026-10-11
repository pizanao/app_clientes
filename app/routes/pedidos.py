from datetime import datetime
from flask import Blueprint, render_template, redirect, url_for, flash, request
from flask_login import login_required
from sqlalchemy import or_
from app.extensions import db
from app.models.cliente import Cliente
from app.models.pedido import Pedido, ItemPedido
from app.models.plano import Plano
from app.forms.pedido_forms import PedidoForm
from app.utils.auth_decorators import lider_required

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


def processar_itens_post(request_form):
    """
    Processa e valida os itens submetidos no formulário.
    Regras de negócio:
    - Pelo menos 1 item e no máximo 10 itens por pedido
    - Descrição não vazia
    - Quantidade > 0
    - Valor unitário > 0
    - Valor total do item = round(quantidade * valor_unitario, 2)
    - Valor total do pedido = soma dos valores totais dos itens

    Retorna: (itens_data, lista_de_erros, valor_total_pedido)
    """
    indices = set()
    for key in request_form.keys():
        if key.startswith('itens-') and '-' in key[6:]:
            part = key[6:].split('-')[0]
            if part.isdigit():
                indices.add(int(part))

    itens_data = []
    erros = []

    # Se não houver campos itens-* mas houver descricao e valor_total (compatibilidade legada)
    if not indices:
        desc_legado = (request_form.get('descricao') or '').strip()
        val_legado_str = (request_form.get('valor_total') or '').replace(',', '.').strip()
        if desc_legado and val_legado_str:
            try:
                val_legado = float(val_legado_str)
                if val_legado > 0:
                    item_legado = {
                        'id': '',
                        'descricao': desc_legado,
                        'quantidade': 1.0,
                        'valor_unitario': val_legado,
                        'valor_total': val_legado
                    }
                    return [item_legado], [], val_legado
            except ValueError:
                pass

        erros.append('O pedido deve conter pelo menos 1 item.')
        return itens_data, erros, 0.0

    sorted_indices = sorted(list(indices))

    for idx in sorted_indices:
        desc = (request_form.get(f'itens-{idx}-descricao') or '').strip()
        qtd_raw = (request_form.get(f'itens-{idx}-quantidade') or '').replace(',', '.').strip()
        unit_raw = (request_form.get(f'itens-{idx}-valor_unitario') or '').replace(',', '.').strip()
        item_id = (request_form.get(f'itens-{idx}-id') or '').strip()

        # Se a linha estiver inteiramente em branco e houver outras preenchidas, podemos ignorar
        if not desc and not qtd_raw and not unit_raw:
            continue

        item_pos = len(itens_data) + 1

        if not desc:
            erros.append(f'Item #{item_pos}: A descrição do item é obrigatória.')

        try:
            qtd = float(qtd_raw)
            if qtd <= 0:
                erros.append(f'Item #{item_pos}: A quantidade deve ser maior que zero.')
        except (ValueError, TypeError):
            erros.append(f'Item #{item_pos}: Quantidade inválida.')
            qtd = 0.0

        try:
            unit = float(unit_raw)
            if unit <= 0:
                erros.append(f'Item #{item_pos}: O valor unitário deve ser maior que zero.')
        except (ValueError, TypeError):
            erros.append(f'Item #{item_pos}: Valor unitário inválido.')
            unit = 0.0

        total_item = round(qtd * unit, 2)

        itens_data.append({
            'id': item_id,
            'descricao': desc,
            'quantidade': qtd,
            'valor_unitario': unit,
            'valor_total': total_item
        })

    # Validação do limite de 1 a 10 itens
    if len(itens_data) < 1:
        erros.append('O pedido deve conter pelo menos 1 item.')
    elif len(itens_data) > 10:
        erros.append(f'O pedido pode conter no máximo 10 itens (atualmente possui {len(itens_data)}).')

    total_pedido = round(sum(it['valor_total'] for it in itens_data), 2)
    return itens_data, erros, total_pedido


@pedidos_bp.route('/')
@login_required
def index():
    search = request.args.get('q', '').strip()
    status_filter = request.args.get('status', 'todos')
    cliente_filter = request.args.get('cliente_id', type=int)

    query = Pedido.query.join(Cliente)

    if search:
        search_term = f"%{search}%"
        query = query.outerjoin(ItemPedido).filter(
            or_(
                Pedido.numero_pedido.ilike(search_term),
                Pedido.descricao.ilike(search_term),
                ItemPedido.descricao.ilike(search_term),
                Cliente.nome.ilike(search_term)
            )
        ).distinct()

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

    planos = Plano.query.filter_by(ativo=True).order_by(Plano.tipo.asc(), Plano.velocidade_download.asc()).all()
    form = PedidoForm()
    form.cliente_id.choices = [(c.id, f"{c.nome} ({c.documento or c.email})") for c in clientes]

    # Pre-select client if passed via URL
    preselected_cliente_id = request.args.get('cliente_id', type=int)
    if request.method == 'GET':
        if preselected_cliente_id and any(c.id == preselected_cliente_id for c in clientes):
            form.cliente_id.data = preselected_cliente_id
        form.numero_pedido.data = gerar_numero_pedido()
        form.data_pedido.data = datetime.now()
        initial_itens = [{'id': '', 'descricao': '', 'quantidade': 1, 'valor_unitario': '', 'valor_total': 0.0}]
        return render_template('pedidos/form.html', form=form, itens=initial_itens, titulo='Novo Pedido', acao='Cadastrar', planos=planos)

    if request.method == 'POST':
        itens_data, itens_erros, valor_total_itens = processar_itens_post(request.form)

        # Check if order number already exists
        existente = Pedido.query.filter_by(numero_pedido=form.numero_pedido.data.strip().upper()).first()
        if existente:
            flash(f'O número de pedido "{form.numero_pedido.data}" já existe. Geramos outro para você.', 'warning')
            form.numero_pedido.data = gerar_numero_pedido()
            return render_template(
                'pedidos/form.html',
                form=form,
                itens=itens_data or [{'id': '', 'descricao': '', 'quantidade': 1, 'valor_unitario': '', 'valor_total': 0.0}],
                titulo='Novo Pedido',
                acao='Cadastrar',
                planos=planos
            )

        if itens_erros:
            for erro in itens_erros:
                flash(erro, 'danger')
            return render_template(
                'pedidos/form.html',
                form=form,
                itens=itens_data or [{'id': '', 'descricao': '', 'quantidade': 1, 'valor_unitario': '', 'valor_total': 0.0}],
                titulo='Novo Pedido',
                acao='Cadastrar',
                planos=planos
            )

        if form.validate_on_submit():
            # Build general description if empty
            descricao_pedido = form.descricao.data.strip() if form.descricao.data else ""
            if not descricao_pedido and itens_data:
                descricao_pedido = ", ".join(f"{it['quantidade']:g}x {it['descricao']}" for it in itens_data)

            pedido = Pedido(
                cliente_id=form.cliente_id.data,
                numero_pedido=form.numero_pedido.data.strip().upper(),
                data_pedido=form.data_pedido.data,
                status=form.status.data,
                metodo_pagamento=form.metodo_pagamento.data,
                valor_total=valor_total_itens,
                descricao=descricao_pedido,
                observacoes=form.observacoes.data.strip() if form.observacoes.data else None
            )
            db.session.add(pedido)
            db.session.flush()

            # Add items
            for it in itens_data:
                item_obj = ItemPedido(
                    pedido_id=pedido.id,
                    descricao=it['descricao'],
                    quantidade=it['quantidade'],
                    valor_unitario=it['valor_unitario'],
                    valor_total=it['valor_total']
                )
                db.session.add(item_obj)

            db.session.commit()

            flash(f'Pedido #{pedido.numero_pedido} criado com sucesso!', 'success')
            return redirect(url_for('pedidos.detalhe', id=pedido.id))

    return render_template(
        'pedidos/form.html',
        form=form,
        itens=itens_data if 'itens_data' in locals() else [{'id': '', 'descricao': '', 'quantidade': 1, 'valor_unitario': '', 'valor_total': 0.0}],
        titulo='Novo Pedido',
        acao='Cadastrar',
        planos=planos
    )


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
    planos = Plano.query.filter_by(ativo=True).order_by(Plano.tipo.asc(), Plano.velocidade_download.asc()).all()
    form = PedidoForm(obj=pedido)
    form.cliente_id.choices = [(c.id, f"{c.nome} ({c.documento or c.email})") for c in clientes]

    if request.method == 'GET':
        itens_data = [
            {
                'id': item.id,
                'descricao': item.descricao,
                'quantidade': item.quantidade,
                'valor_unitario': item.valor_unitario,
                'valor_total': item.valor_total
            }
            for item in pedido.itens
        ]
        if not itens_data:
            itens_data = [{
                'id': '',
                'descricao': pedido.descricao or 'Item do Pedido',
                'quantidade': 1,
                'valor_unitario': pedido.valor_total,
                'valor_total': pedido.valor_total
            }]
        return render_template('pedidos/form.html', form=form, pedido=pedido, itens=itens_data, titulo='Editar Pedido', acao='Salvar Alterações', planos=planos)

    if request.method == 'POST':
        itens_data, itens_erros, valor_total_itens = processar_itens_post(request.form)

        # Check unique order number if modified
        num_novo = form.numero_pedido.data.strip().upper()
        if num_novo != pedido.numero_pedido:
            existente = Pedido.query.filter_by(numero_pedido=num_novo).first()
            if existente:
                flash(f'Já existe outro pedido com o número {num_novo}.', 'danger')
                return render_template(
                    'pedidos/form.html',
                    form=form,
                    pedido=pedido,
                    itens=itens_data,
                    titulo='Editar Pedido',
                    acao='Salvar Alterações',
                    planos=planos
                )

        if itens_erros:
            for erro in itens_erros:
                flash(erro, 'danger')
            return render_template(
                'pedidos/form.html',
                form=form,
                pedido=pedido,
                itens=itens_data,
                titulo='Editar Pedido',
                acao='Salvar Alterações',
                planos=planos
            )

        if form.validate_on_submit():
            pedido.cliente_id = form.cliente_id.data
            pedido.numero_pedido = num_novo
            pedido.data_pedido = form.data_pedido.data
            pedido.status = form.status.data
            pedido.metodo_pagamento = form.metodo_pagamento.data
            pedido.valor_total = valor_total_itens
            if form.descricao.data and form.descricao.data.strip():
                pedido.descricao = form.descricao.data.strip()
            elif not pedido.descricao and itens_data:
                pedido.descricao = ", ".join(f"{it['quantidade']:g}x {it['descricao']}" for it in itens_data)
            pedido.observacoes = form.observacoes.data.strip() if form.observacoes.data else None

            # Remove existing items and add updated
            ItemPedido.query.filter_by(pedido_id=pedido.id).delete()
            for it in itens_data:
                item_obj = ItemPedido(
                    pedido_id=pedido.id,
                    descricao=it['descricao'],
                    quantidade=it['quantidade'],
                    valor_unitario=it['valor_unitario'],
                    valor_total=it['valor_total']
                )
                db.session.add(item_obj)

            db.session.commit()
            flash(f'Pedido #{pedido.numero_pedido} atualizado com sucesso!', 'success')
            return redirect(url_for('pedidos.detalhe', id=pedido.id))

    return render_template(
        'pedidos/form.html',
        form=form,
        pedido=pedido,
        itens=itens_data if 'itens_data' in locals() else [],
        titulo='Editar Pedido',
        acao='Salvar Alterações',
        planos=planos
    )


@pedidos_bp.route('/<int:id>/excluir', methods=['POST'])
@login_required
@lider_required
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
