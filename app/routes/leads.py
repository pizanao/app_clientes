import os
from flask import Blueprint, render_template, request, redirect, url_for, flash, jsonify, send_file, abort, current_app
from flask_login import login_required, current_user
from app.extensions import db
from app.models.lead import Lead
from app.models.cliente import Cliente
from app.models.plano import Plano
from app.data.perfis_sisgran import normalizar_bairro
from app.services.prospector import TelecomProspectorService, PLANOS_DIGITALNET

leads_bp = Blueprint('leads', __name__, url_prefix='/leads')


def obter_planos_ativos():
    """Retorna os planos oficiais ativos do banco. Se a base estiver vazia, roda o seed inicial."""
    planos = Plano.query.filter_by(ativo=True).order_by(Plano.tipo.asc(), Plano.velocidade_download.asc()).all()
    if not planos:
        Plano.seed_planos_iniciais()
        planos = Plano.query.filter_by(ativo=True).order_by(Plano.tipo.asc(), Plano.velocidade_download.asc()).all()
    return planos


# -----------------------------------------------------------------------------
# ROTAS WEB (INTERFACE HTML/BOOTSTRAP)
# -----------------------------------------------------------------------------

@leads_bp.route('/')
@login_required
def index():
    """Painel de Prospecção Geo-Localizada & Funil de Leads."""
    raw_bairro = request.args.get('bairro', '').strip()
    bairro_filtro = normalizar_bairro(raw_bairro) if raw_bairro else ''
    status_filtro = request.args.get('status', '').strip()
    busca = request.args.get('busca', '').strip()

    # Clusters de bairros com clientes ativos (densidade de rede)
    clusters = TelecomProspectorService.get_neighborhood_clusters()

    # Query de Leads
    query = Lead.query
    if bairro_filtro:
        query = query.filter(Lead.bairro.ilike(f"%{bairro_filtro}%"))
    if status_filtro:
        query = query.filter(Lead.status == status_filtro)
    if busca:
        termo = f"%{busca}%"
        query = query.filter(
            (Lead.empresa.ilike(termo)) |
            (Lead.nome.ilike(termo)) |
            (Lead.telefone.ilike(termo)) |
            (Lead.logradouro.ilike(termo))
        )

    leads = query.order_by(Lead.lead_score.desc(), Lead.created_at.desc()).all()

    # Métricas do Funil
    total_leads = Lead.query.count()
    total_novos = Lead.query.filter_by(status='novo').count()
    total_optin_solicitado = Lead.query.filter_by(status='optin_solicitado').count()
    total_optin_aceito = Lead.query.filter_by(optin_status='aceito').count()
    total_proposta = Lead.query.filter_by(status='proposta_enviada').count()
    total_convertidos = Lead.query.filter_by(status='convertido').count()

    # Pontos para o Mapa de Calor & Nós de Fibra
    map_points = []
    for c in clusters:
        map_points.append({
            'tipo': 'cluster_fibra',
            'titulo': f"Nó Óptico: {c['bairro']}",
            'bairro': c['bairro'],
            'lat': c.get('lat', -20.4697),
            'lng': c.get('lng', -54.6201),
            'clientes': c['total_clientes'],
            'leads': c['total_leads'],
            'viabilidade': c['viabilidade_estimada'],
            'cor': '#1b4f99',
            'intensidade': round(min(1.0, 0.4 + (c['total_clientes'] * 0.15)), 2),
        })

    for l in leads:
        base_coords = TelecomProspectorService.get_bairro_coordenadas(l.bairro)
        jitter_lat = ((l.id * 17) % 19 - 9) * 0.00075
        jitter_lng = ((l.id * 31) % 19 - 9) * 0.00075
        map_points.append({
            'tipo': 'lead_oportunidade',
            'id': l.id,
            'titulo': l.empresa,
            'contato': l.nome,
            'cargo': l.cargo or '',
            'bairro': l.bairro,
            'endereco': l.endereco_resumido,
            'lat': round(base_coords[0] + jitter_lat, 6),
            'lng': round(base_coords[1] + jitter_lng, 6),
            'score': l.lead_score,
            'plano': l.plano_sugerido,
            'valor': f"R$ {l.valor_mensal_sugerido:.2f}".replace('.', ','),
            'operadora': l.operadora_atual,
            'status': l.status_label,
            'optin': l.optin_label,
            'whatsapp_url': l.whatsapp_url,
            'detail_url': url_for('leads.detail', lead_id=l.id),
            'cor': '#f59e0b',
            'intensidade': round(l.lead_score / 100.0, 2),
        })

    return render_template(
        'leads/index.html',
        leads=leads,
        clusters=clusters,
        planos=obter_planos_ativos(),
        total_leads=total_leads,
        total_novos=total_novos,
        total_optin_solicitado=total_optin_solicitado,
        total_optin_aceito=total_optin_aceito,
        total_proposta=total_proposta,
        total_convertidos=total_convertidos,
        bairro_selecionado=bairro_filtro,
        status_selecionado=status_filtro,
        busca=busca,
        map_points=map_points,
        mapbox_api_key=current_app.config.get('MAPBOX_API_KEY') or '',
    )


@leads_bp.route('/prospectar', methods=['POST'])
@login_required
def prospectar_regiao():
    """Dispara a geração de leads vizinhos baseada na região selecionada."""
    raw_bairro = request.form.get('bairro', '').strip()
    bairro = normalizar_bairro(raw_bairro) or 'Chácara Cachoeira'
    cidade = request.form.get('cidade', '').strip() or 'Campo Grande'
    niche = request.form.get('niche', '').strip() or 'Empresas e Clínicas e Comércios'
    count = int(request.form.get('count', 5))
    cliente_ref_id = request.form.get('cliente_referencia_id')

    cliente_ref_id_int = int(cliente_ref_id) if cliente_ref_id and cliente_ref_id.isdigit() else None

    # Executa a prospecção com IA / Heurística de Campo Grande
    novos_dados = TelecomProspectorService.prospect_neighborhood(
        bairro=bairro,
        cidade=cidade,
        estado='MS',
        niche=niche,
        count=count,
        cliente_ref_id=cliente_ref_id_int
    )

    salvos = TelecomProspectorService.save_prospects(novos_dados, cliente_ref_id=cliente_ref_id_int)

    if salvos:
        flash(f"Sucesso! {len(salvos)} novos leads foram gerados no bairro {bairro} com viabilidade óptica mapeada.", 'success')
    else:
        flash(f"Nenhum novo lead precisou ser gerado (empresas da região já cadastradas no bairro {bairro}).", 'info')

    return redirect(url_for('leads.index', bairro=bairro))


@leads_bp.route('/<int:lead_id>')
@login_required
def detail(lead_id: int):
    """Exibe o dossiê comercial, central de WhatsApp e quebra de objeções."""
    lead = Lead.query.get_or_404(lead_id)

    # Garante script anti-ban atualizado
    if not lead.icebreaker_optin:
        lead.icebreaker_optin = TelecomProspectorService.generate_anti_ban_whatsapp_script(lead)
        db.session.commit()

    # Prepara tutores de objeção
    obj_key = request.args.get('obj', 'fidelidade')
    tutor_obj = TelecomProspectorService.get_objection_tutor(obj_key, lead)

    planos_ativos = obter_planos_ativos()
    return render_template(
        'leads/detail.html',
        lead=lead,
        tutor_obj=tutor_obj,
        obj_key=obj_key,
        planos=planos_ativos
    )


@leads_bp.route('/<int:lead_id>/status', methods=['POST'])
@login_required
def atualizar_status(lead_id: int):
    """Atualiza o status de funil e/ou opt-in do lead."""
    lead = Lead.query.get_or_404(lead_id)

    novo_status = request.form.get('status')
    novo_optin = request.form.get('optin_status')

    if novo_status and novo_status in Lead.STATUS_CONFIG:
        lead.status = novo_status
    if novo_optin and novo_optin in Lead.OPTIN_CONFIG:
        lead.optin_status = novo_optin
        if novo_optin == 'aceito' and lead.status in ('novo', 'optin_solicitado'):
            lead.status = 'optin_aceito'

    db.session.commit()
    flash(f"Status do lead #{lead.id} ({lead.empresa}) atualizado com sucesso!", 'success')
    return redirect(url_for('leads.detail', lead_id=lead.id))


@leads_bp.route('/<int:lead_id>/converter', methods=['POST'])
@login_required
def converter_cliente(lead_id: int):
    """Converte o lead em cliente e cria o pedido da assinatura DigitalNet vinculado ao Plano."""
    lead = Lead.query.get_or_404(lead_id)

    plano_id = request.form.get('plano_id', type=int)
    plano_escolhido = request.form.get('plano_sugerido')
    valor_escolhido = request.form.get('valor_mensal_sugerido')

    plano_obj = None
    if plano_id and plano_id > 0:
        plano_obj = db.session.get(Plano, plano_id)
    elif plano_escolhido:
        plano_obj = Plano.query.filter(Plano.nome == plano_escolhido.strip()).first()
        if not plano_obj:
            plano_clean = plano_escolhido.split('(')[0].strip()
            plano_obj = Plano.query.filter(Plano.nome.ilike(f"%{plano_clean}%")).first()

    if plano_obj:
        lead.plano_sugerido = plano_obj.nome
        if not valor_escolhido:
            lead.valor_mensal_sugerido = plano_obj.valor_mensal
    elif plano_escolhido:
        lead.plano_sugerido = plano_escolhido

    if valor_escolhido:
        try:
            lead.valor_mensal_sugerido = float(valor_escolhido)
        except ValueError:
            pass

    cliente = TelecomProspectorService.convert_lead_to_client(lead, plano=plano_obj)
    flash(f"Parabéns! Lead convertido em Cliente '{cliente.nome}' com Pedido de Ativação gerado!", 'success')
    return redirect(url_for('clientes.detalhe', id=cliente.id))


@leads_bp.route('/<int:lead_id>/excluir', methods=['POST'])
@login_required
def excluir(lead_id: int):
    """Exclui um lead do sistema."""
    lead = Lead.query.get_or_404(lead_id)
    empresa = lead.empresa
    db.session.delete(lead)
    db.session.commit()
    flash(f"Lead '{empresa}' removido com sucesso.", 'warning')
    return redirect(url_for('leads.index'))


# -----------------------------------------------------------------------------
# REST API (JSON PARA REACT 19 / VITE / INTEGRACAO)
# -----------------------------------------------------------------------------

@leads_bp.route('/api/clusters', methods=['GET'])
@login_required
def api_clusters():
    """Retorna clusters de bairros de clientes em JSON."""
    clusters = TelecomProspectorService.get_neighborhood_clusters()
    return jsonify({'success': True, 'clusters': clusters})


@leads_bp.route('/api/nodo/<bairro>/empresas', methods=['GET'])
@leads_bp.route('/api/nodo/empresas', methods=['GET', 'POST'])
@login_required
def api_nodo_empresas(bairro: str = ''):
    """
    Retorna as empresas ativas e oportunidades no raio do Nó Óptico.
    Suporta rota direta /api/nodo/<bairro>/empresas ou query params / JSON.
    """
    if not bairro:
        if request.is_json and request.get_json():
            bairro = request.get_json().get('bairro', '')
        else:
            bairro = request.args.get('bairro', '')

    bairro = normalizar_bairro((bairro or 'Chácara Cachoeira').strip()) or 'Chácara Cachoeira'
    lat = request.args.get('lat', type=float)
    lng = request.args.get('lng', type=float)
    limite = request.args.get('limite', default=8, type=int)

    empresas = TelecomProspectorService.get_empresas_no_nodo(
        bairro=bairro,
        lat=lat,
        lng=lng,
        limite=min(limite, 20)
    )

    return jsonify({
        'success': True,
        'bairro': bairro,
        'lat': lat,
        'lng': lng,
        'total': len(empresas),
        'empresas': empresas
    })


@leads_bp.route('/api/prospectar', methods=['POST'])
@login_required
def api_prospectar():
    """Endpoint REST para acionar a prospecção via frontend moderno."""
    data = request.get_json() or {}
    bairro = normalizar_bairro(data.get('bairro', 'Chácara Cachoeira')) or 'Chácara Cachoeira'
    cidade = data.get('cidade', 'Campo Grande')
    niche = data.get('niche', 'Empresas e Clínicas')
    count = int(data.get('count', 5))

    novos_dados = TelecomProspectorService.prospect_neighborhood(
        bairro=bairro,
        cidade=cidade,
        estado='MS',
        niche=niche,
        count=count
    )
    salvos = TelecomProspectorService.save_prospects(novos_dados)

    return jsonify({
        'success': True,
        'count': len(salvos),
        'leads': [
            {
                'id': l.id,
                'empresa': l.empresa,
                'nome': l.nome,
                'telefone': l.telefone,
                'bairro': l.bairro,
                'plano_sugerido': l.plano_sugerido,
                'valor': l.valor_mensal_sugerido,
                'lead_score': l.lead_score,
                'whatsapp_url': l.whatsapp_url,
                'optin_status': l.optin_status
            }
            for l in salvos
        ]
    })


GEOJSON_LAYERS = {
    'bairros': 'bairros.geojson',
    'macrozonas': 'pd-macrozonas-urbanas.geojson',
    'parcelamentos': 'parcelamentos.geojson',
}


@leads_bp.route('/api/geojson/<camada>', methods=['GET'])
@login_required
def api_geojson(camada: str):
    """Retorna os dados GeoJSON das camadas municipais de Campo Grande MS."""
    key = camada.lower().strip()
    filename = GEOJSON_LAYERS.get(key)
    if not filename:
        abort(404, description=f"Camada '{camada}' não reconhecida.")

    base_dir = os.path.abspath(os.path.join(current_app.root_path, '..'))
    file_path = os.path.join(base_dir, 'geojson', filename)

    if not os.path.isfile(file_path):
        abort(404, description=f"Arquivo '{filename}' não encontrado.")

    return send_file(
        file_path,
        mimetype='application/geo+json',
        as_attachment=False,
        max_age=3600
    )


@leads_bp.route('/api/aisa/status', methods=['GET'])
@login_required
def api_aisa_status():
    """Retorna o status de conexão dos motores de IA (AIsa e Gemini)."""
    aisa_key = current_app.config.get('AISA_API_KEY')
    gemini_key = current_app.config.get('GEMINI_API_KEY')
    aisa_model = current_app.config.get('AISA_MODEL') or 'asi1-mini'

    has_aisa = bool(aisa_key and aisa_key.strip())
    has_gemini = bool(gemini_key and gemini_key.strip())

    active_provider = 'AIsa (api.aisa.one)' if has_aisa else ('Google Gemini' if has_gemini else 'Motor Heurístico Local')

    return jsonify({
        'success': True,
        'aisa_configured': has_aisa,
        'aisa_model': aisa_model,
        'gemini_configured': has_gemini,
        'active_provider': active_provider,
    })


@leads_bp.route('/api/aisa/connect', methods=['POST'])
@login_required
def api_aisa_connect():
    """Valida uma API Key da AIsa diretamente com a api.aisa.one."""
    data = request.get_json() or {}
    api_key = data.get('apiKey', '').strip() or (current_app.config.get('AISA_API_KEY') or '').strip()

    if not api_key:
        return jsonify({'success': False, 'error': 'Chave de API não informada.'}), 400

    model = data.get('model', '').strip() or current_app.config.get('AISA_MODEL') or 'asi1-mini'
    resultado = TelecomProspectorService.test_aisa_connection(api_key, model=model)
    return jsonify(resultado)


@leads_bp.route('/api/aisa/pitch', methods=['POST'])
@login_required
def api_aisa_pitch():
    """Gera script/pitch consultivo para um lead específico via IA da AIsa."""
    data = request.get_json() or {}
    lead_id = data.get('lead_id')
    channel = data.get('channel', 'whatsapp')
    tone = data.get('tone', 'consultative')

    if not lead_id:
        return jsonify({'success': False, 'error': 'lead_id é obrigatório.'}), 400

    lead = Lead.query.get_or_404(lead_id)
    pitch_data = TelecomProspectorService.generate_pitch(lead, channel=channel, tone=tone)

    return jsonify({
        'success': True,
        'lead_id': lead.id,
        'empresa': lead.empresa,
        'pitch': pitch_data
    })

