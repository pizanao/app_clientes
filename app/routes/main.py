from flask import Blueprint, render_template, redirect, url_for
from flask_login import login_required, current_user
from sqlalchemy import func
from app.extensions import db
from app.models.cliente import Cliente
from app.models.pedido import Pedido

main_bp = Blueprint('main', __name__)


@main_bp.route('/')
def index():
    if current_user.is_authenticated:
        return redirect(url_for('main.dashboard'))
    return redirect(url_for('auth.login'))


@main_bp.route('/dashboard')
@login_required
def dashboard():
    # Metrics
    total_clientes = Cliente.query.count()
    clientes_ativos = Cliente.query.filter_by(ativo=True).count()
    total_pedidos = Pedido.query.count()

    # Pedidos counts by status
    pedidos_pendentes = Pedido.query.filter_by(status='pendente').count()
    pedidos_processando = Pedido.query.filter_by(status='processando').count()
    pedidos_concluidos = Pedido.query.filter_by(status='concluido').count()
    pedidos_cancelados = Pedido.query.filter_by(status='cancelado').count()

    # Revenue
    faturamento_total = db.session.query(
        func.coalesce(func.sum(Pedido.valor_total), 0.0)
    ).filter(Pedido.status != 'cancelado').scalar() or 0.0

    faturamento_concluido = db.session.query(
        func.coalesce(func.sum(Pedido.valor_total), 0.0)
    ).filter(Pedido.status == 'concluido').scalar() or 0.0

    ticket_medio = (faturamento_total / total_pedidos) if total_pedidos > 0 else 0.0

    # Recent items
    ultimos_clientes = Cliente.query.order_by(Cliente.created_at.desc()).limit(5).all()
    ultimos_pedidos = Pedido.query.order_by(Pedido.data_pedido.desc()).limit(5).all()

    return render_template(
        'dashboard/index.html',
        total_clientes=total_clientes,
        clientes_ativos=clientes_ativos,
        total_pedidos=total_pedidos,
        pedidos_pendentes=pedidos_pendentes,
        pedidos_processando=pedidos_processando,
        pedidos_concluidos=pedidos_concluidos,
        pedidos_cancelados=pedidos_cancelados,
        faturamento_total=faturamento_total,
        faturamento_concluido=faturamento_concluido,
        ticket_medio=ticket_medio,
        ultimos_clientes=ultimos_clientes,
        ultimos_pedidos=ultimos_pedidos
    )
