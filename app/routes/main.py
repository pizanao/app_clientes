from flask import Blueprint, render_template, redirect, url_for
from flask_login import login_required, current_user
from sqlalchemy import func
from sqlalchemy.orm import selectinload
from app.extensions import db
from app.models.cliente import Cliente
from app.models.pedido import Pedido
from app.models.lead import Lead
from app.models.plano import Plano, TIPO_PF, TIPO_PJ

main_bp = Blueprint('main', __name__)


@main_bp.route('/')
def index():
    if current_user.is_authenticated:
        return redirect(url_for('main.dashboard'))
    return redirect(url_for('auth.login'))


@main_bp.route('/dashboard')
@login_required
def dashboard():
    # 1. Métricas de Clientes
    total_clientes = Cliente.query.count()
    clientes_ativos = Cliente.query.filter_by(ativo=True).count()

    # 2. Métricas de Pedidos e Ordens de Serviço
    total_pedidos = Pedido.query.count()
    pedidos_pendentes = Pedido.query.filter_by(status='pendente').count()
    pedidos_processando = Pedido.query.filter_by(status='processando').count()
    pedidos_concluidos = Pedido.query.filter_by(status='concluido').count()
    pedidos_cancelados = Pedido.query.filter_by(status='cancelado').count()
    ordens_em_aberto = pedidos_pendentes + pedidos_processando

    # 3. Faturamento e MRR
    faturamento_total = db.session.query(
        func.coalesce(func.sum(Pedido.valor_total), 0.0)
    ).filter(Pedido.status != 'cancelado').scalar() or 0.0

    faturamento_concluido = db.session.query(
        func.coalesce(func.sum(Pedido.valor_total), 0.0)
    ).filter(Pedido.status == 'concluido').scalar() or 0.0

    # MRR (Mensalidades Recorrentes de pedidos ativos/concluídos)
    mrr_estimado = db.session.query(
        func.coalesce(func.sum(Pedido.valor_total), 0.0)
    ).filter(Pedido.status.in_(['processando', 'concluido'])).scalar() or 0.0

    pedidos_validos = total_pedidos - pedidos_cancelados
    ticket_medio = (faturamento_total / pedidos_validos) if pedidos_validos > 0 else 0.0

    # 4. Atendimento & Funil de Leads (Radar Telecom / SDR)
    total_leads = Lead.query.count()
    leads_novos = Lead.query.filter_by(status='novo').count()
    leads_optin_solicitado = Lead.query.filter_by(status='optin_solicitado').count()
    leads_optin_aceito = Lead.query.filter_by(optin_status='aceito').count()
    leads_proposta = Lead.query.filter_by(status='proposta_enviada').count()
    leads_convertidos = Lead.query.filter_by(status='convertido').count()
    leads_optin_recusado = Lead.query.filter_by(optin_status='recusado').count()

    total_optin_tentativas = leads_optin_aceito + leads_optin_recusado
    taxa_optin = round((leads_optin_aceito / total_optin_tentativas) * 100, 1) if total_optin_tentativas > 0 else (100.0 if leads_optin_aceito > 0 else 0.0)
    taxa_conversao_leads = round((leads_convertidos / total_leads) * 100, 1) if total_leads > 0 else 0.0

    # Fila de atendimento rápido de leads (opt-in aceito ou alta pontuação)
    leads_atendimento = Lead.query.filter(
        Lead.status.in_(['optin_aceito', 'proposta_enviada', 'novo'])
    ).order_by(
        Lead.optin_status.asc(),
        Lead.lead_score.desc(),
        Lead.created_at.desc()
    ).limit(5).all()

    # Radar de substituição da concorrência
    radar_concorrencia = db.session.query(
        Lead.operadora_atual,
        func.count(Lead.id)
    ).filter(
        Lead.operadora_atual.isnot(None),
        Lead.operadora_atual != ''
    ).group_by(
        Lead.operadora_atual
    ).order_by(
        func.count(Lead.id).desc()
    ).limit(4).all()

    # 5. Monitoramento Operacional & Despacho de Ordens
    ordens_fila = Pedido.query.options(
        selectinload(Pedido.cliente),
        selectinload(Pedido.plano)
    ).filter(
        Pedido.status.in_(['pendente', 'processando'])
    ).order_by(
        Pedido.data_pedido.asc()
    ).limit(5).all()

    if len(ordens_fila) < 5:
        # Complementa com os pedidos mais recentes para a lista não ficar vazia
        ordens_fila = Pedido.query.options(
            selectinload(Pedido.cliente),
            selectinload(Pedido.plano)
        ).order_by(
            Pedido.data_pedido.desc()
        ).limit(5).all()

    # Comodatos de Wi-Fi 6 e pedidos corporativos com SLA
    comodato_wifi6 = Pedido.query.join(
        Plano, Pedido.plano_id == Plano.id
    ).filter(
        Pedido.status != 'cancelado',
        Plano.roteador_wifi.isnot(None)
    ).count()

    pedidos_sla_pj = Pedido.query.join(
        Plano, Pedido.plano_id == Plano.id
    ).filter(
        Pedido.status.in_(['pendente', 'processando']),
        Plano.sla_horas.isnot(None)
    ).count()

    # 6. Inteligência Territorial (Top Bairros) & Mix de Planos
    top_bairros = db.session.query(
        Cliente.bairro,
        func.count(Cliente.id)
    ).filter(
        Cliente.bairro.isnot(None),
        Cliente.bairro != ''
    ).group_by(
        Cliente.bairro
    ).order_by(
        func.count(Cliente.id).desc()
    ).limit(5).all()

    mix_pf = Pedido.query.join(
        Plano, Pedido.plano_id == Plano.id
    ).filter(
        Pedido.status != 'cancelado',
        Plano.tipo == TIPO_PF
    ).count()

    mix_pj = Pedido.query.join(
        Plano, Pedido.plano_id == Plano.id
    ).filter(
        Pedido.status != 'cancelado',
        Plano.tipo == TIPO_PJ
    ).count()

    mix_outros = total_pedidos - pedidos_cancelados - (mix_pf + mix_pj)
    if mix_outros < 0:
        mix_outros = 0

    # 7. Itens Recentes (compatibilidade)
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
        ordens_em_aberto=ordens_em_aberto,
        faturamento_total=faturamento_total,
        faturamento_concluido=faturamento_concluido,
        mrr_estimado=mrr_estimado,
        ticket_medio=ticket_medio,
        total_leads=total_leads,
        leads_novos=leads_novos,
        leads_optin_solicitado=leads_optin_solicitado,
        leads_optin_aceito=leads_optin_aceito,
        leads_proposta=leads_proposta,
        leads_convertidos=leads_convertidos,
        taxa_optin=taxa_optin,
        taxa_conversao_leads=taxa_conversao_leads,
        leads_atendimento=leads_atendimento,
        radar_concorrencia=radar_concorrencia,
        ordens_fila=ordens_fila,
        comodato_wifi6=comodato_wifi6,
        pedidos_sla_pj=pedidos_sla_pj,
        top_bairros=top_bairros,
        mix_pf=mix_pf,
        mix_pj=mix_pj,
        mix_outros=mix_outros,
        ultimos_clientes=ultimos_clientes,
        ultimos_pedidos=ultimos_pedidos
    )
