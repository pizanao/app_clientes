from datetime import datetime
import json
import logging
import os
import random
import re
import urllib.parse
import urllib.request
from typing import Dict, List, Any, Optional, Tuple
from flask import current_app
from sqlalchemy import func
from app.extensions import db
from app.models.cliente import Cliente
from app.models.lead import Lead
from app.models.pedido import Pedido, ItemPedido
from app.models.plano import Plano

logger = logging.getLogger(__name__)

# Planos reais da DigitalNet MS
PLANOS_DIGITALNET = [
    {
        'nome': 'Fibra 600 Standard (Wi-Fi 6)',
        'download': '600 Mbps',
        'upload': '300 Mbps',
        'preco': 129.90,
        'diferencial': 'Wi-Fi 6 em comodato + Skeelo + Instalação inclusa',
    },
    {
        'nome': 'Fibra 700 + DigiMesh (Wi-Fi 6)',
        'download': '700 Mbps',
        'upload': '350 Mbps',
        'preco': 139.90,
        'diferencial': 'Ponto extra DigiMesh sem fios + Wi-Fi 6 + Instalação inclusa',
    },
    {
        'nome': 'Fibra 900 Advanced (Wi-Fi 6)',
        'download': '900 Mbps',
        'upload': '450 Mbps',
        'preco': 149.90,
        'promocao_entrada': 'R$ 99,90 nos primeiros 3 meses',
        'diferencial': 'Máxima velocidade residencial/comercial + Wi-Fi 6 + Skeelo',
    },
    {
        'nome': 'DigitalNet B2B Link Dedicado Pro',
        'download': '1000 Mbps',
        'upload': '1000 Mbps (100% Simétrico)',
        'preco': 399.90,
        'diferencial': 'IP Fixo + SLA de 4h + Wi-Fi 6 Alta Densidade + Suporte 24h Campo Grande',
    },
]

# ==============================================================================
# PERFIS TERRITORIAIS E COORDENADAS OFICIAIS DE CAMPO GRANDE (SISGRAN / PLANURB)
# ==============================================================================
from app.data.perfis_sisgran import (
    PERFIS_CAMPO_GRANDE,
    COORDENADAS_BAIRROS,
    CEP_PREFIXOS_BAIRROS,
    resolver_bairro,
    normalizar_bairro,
    obter_perfil_bairro,
    obter_coordenadas_bairro,
    obter_ruas_bairro,
    obter_imoveis_amostra,
)


class TelecomProspectorService:
    COORDENADAS_BAIRROS = COORDENADAS_BAIRROS
    PERFIS_CAMPO_GRANDE = PERFIS_CAMPO_GRANDE

    @classmethod
    def get_bairro_profile(cls, bairro: str) -> Dict[str, Any]:
        """Retorna os metadados territoriais do bairro oficial (SISGRAN/PLANURB)."""
        return obter_perfil_bairro(bairro)

    @classmethod
    def get_bairro_coordenadas(cls, bairro: str) -> Tuple[float, float]:
        """Retorna as coordenadas reais (lat, lng) do centróide do bairro (SISGRAN)."""
        return obter_coordenadas_bairro(bairro)

    @classmethod
    def resolver_bairro(cls, bairro: str) -> Optional[str]:
        """Localiza o nome oficial do bairro a partir de qualquer variação ou parcelamento."""
        return resolver_bairro(bairro)

    @classmethod
    def normalizar_bairro(cls, bairro: Optional[str]) -> Optional[str]:
        """Normaliza e unifica qualquer variação de nome de bairro para o formato canônico oficial."""
        return normalizar_bairro(bairro)

    @staticmethod
    def get_neighborhood_clusters() -> List[Dict[str, Any]]:
        """
        Agrupa clientes existentes por bairro e cidade para identificar
        onde a DigitalNet já possui infraestrutura óptica instalada (CTO/Cabos).
        Normaliza os bairros para evitar duplicidades entre caixa alta e camelcase.
        """
        clientes = Cliente.query.filter_by(ativo=True).all()
        clusters_map: Dict[str, Dict[str, Any]] = {}

        for c in clientes:
            bairro = normalizar_bairro(c.bairro) or 'Centro'
            cidade = (c.cidade or 'Campo Grande').strip()
            estado = (c.estado or 'MS').strip()
            chave = f"{cidade}|{bairro}"

            if chave not in clusters_map:
                clusters_map[chave] = {
                    'cidade': cidade,
                    'bairro': bairro,
                    'estado': estado,
                    'total_clientes': 0,
                    'clientes_ids': [],
                    'exemplo_ruas': set(),
                }

            clusters_map[chave]['total_clientes'] += 1
            clusters_map[chave]['clientes_ids'].append(c.id)
            if c.logradouro:
                clusters_map[chave]['exemplo_ruas'].add(c.logradouro)

        # Se não houver clientes ou poucos, garante os principais bairros de Campo Grande
        if not clusters_map:
            for b in ['Chácara Cachoeira', 'Centro', 'Santa Fé', 'Jardim dos Estados']:
                clusters_map[f"Campo Grande|{b}"] = {
                    'cidade': 'Campo Grande',
                    'bairro': b,
                    'estado': 'MS',
                    'total_clientes': 0,
                    'clientes_ids': [],
                    'exemplo_ruas': set(PERFIS_CAMPO_GRANDE.get(b, {}).get('ruas', [])[:2]),
                }

        resultado = []
        for chave, dado in clusters_map.items():
            bairro = dado['bairro']
            # Conta leads já cadastrados nessa região de forma insensível a maiúsculas/minúsculas
            total_leads = Lead.query.filter(func.lower(Lead.bairro) == func.lower(bairro)).count()
            leads_convertidos = Lead.query.filter(
                func.lower(Lead.bairro) == func.lower(bairro),
                Lead.status == 'convertido'
            ).count()

            coords = TelecomProspectorService.get_bairro_coordenadas(bairro)
            resultado.append({
                'cidade': dado['cidade'],
                'bairro': bairro,
                'estado': dado['estado'],
                'lat': coords[0],
                'lng': coords[1],
                'total_clientes': dado['total_clientes'],
                'total_leads': total_leads,
                'leads_convertidos': leads_convertidos,
                'ruas': list(dado['exemplo_ruas'])[:3],
                'viabilidade_estimada': '99% (Fibra Ativa no Poste)' if dado['total_clientes'] > 0 else 'Alta (Área de Cobertura)',
                'badge_class': 'bg-success' if dado['total_clientes'] >= 2 else 'bg-primary',
            })

        # Ordena por bairros com mais clientes
        resultado.sort(key=lambda x: (x['total_clientes'], x['total_leads']), reverse=True)
        return resultado

    @classmethod
    def generate_anti_ban_whatsapp_script(cls, lead: Lead) -> str:
        """
        Cria o roteiro de abordagem consultiva com pedido explícito de opt-in
        para evitar banimento por spam no WhatsApp.
        """
        nome_curto = (lead.nome or 'Olá').split()[0]
        empresa = lead.empresa or 'sua empresa'
        bairro = lead.bairro or 'sua região'
        operadora = lead.operadora_atual or 'outras operadoras'
        plano = lead.plano_sugerido or 'Fibra 700 + DigiMesh com Wi-Fi 6'

        script = (
            f"Olá {nome_curto}, tudo bem? Notei a presença da {empresa} aqui no bairro {bairro}.\n\n"
            f"A DigitalNet acabou de concluir a modernização da rede de fibra óptica com roteadores Wi-Fi 6 "
            f"aqui na sua rua. Identificamos que muitos comércios e escritórios locais sofrem com lentidão e "
            f"suporte demorado de operadoras nacionais como {operadora}.\n\n"
            f"Estruturamos um comparativo rápido mostrando como ter mais velocidade e suporte local 24h em Campo Grande "
            f"com o nosso plano {plano}.\n\n"
            f"👉 *Posso te enviar esse comparativo de 1 minuto aqui pelo WhatsApp sem compromisso?*\n"
            f"_(Se não for o momento, fique à vontade para responder 'Não')_"
        )
        return script

    @classmethod
    def get_empresas_no_nodo(
        cls,
        bairro: str,
        lat: Optional[float] = None,
        lng: Optional[float] = None,
        limite: int = 8
    ) -> List[Dict[str, Any]]:
        """
        Retorna as empresas ativas na região do Nó Óptico.
        1. Prioriza leads já mapeados e qualificados no bairro.
        2. Se houver menos que o limite, prospecta empresas adicionais da RFB / cascata de IA e salva.
        3. Atribui coordenadas no raio de alcance da fibra óptica.
        """
        # 1. Busca leads existentes neste bairro
        leads_existentes = Lead.query.filter(
            Lead.bairro.ilike(f"%{bairro}%")
        ).order_by(Lead.lead_score.desc()).limit(limite).all()

        empresas_list = list(leads_existentes)

        # 2. Se houver menos que o limite, busca novas empresas reais
        faltam = limite - len(empresas_list)
        if faltam > 0:
            novos = cls.prospect_neighborhood(bairro=bairro, count=faltam)
            salvos = cls.save_prospects(novos)
            empresas_list.extend(salvos)

        # Coordenadas base do nó óptico
        if lat is None or lng is None:
            coords_base = cls.get_bairro_coordenadas(bairro)
            lat = coords_base[0]
            lng = coords_base[1]

        resultado = []
        for idx, l in enumerate(empresas_list[:limite]):
            # Dispersão realista dentro do raio do nó (150m a 450m)
            dist_factor = 0.0018 + ((idx % 3) * 0.0008)
            p_lat = round(lat + (dist_factor * 0.7 * (1 if idx % 2 == 0 else -1)), 6)
            p_lng = round(lng + (dist_factor * (1 if (idx // 2) % 2 == 0 else -1)), 6)

            resultado.append({
                'id': l.id,
                'empresa': l.empresa,
                'nome': l.nome,
                'cargo': l.cargo or 'Decisor Comercial',
                'telefone': l.telefone or '(67) 99876-0000',
                'email': l.email,
                'documento': l.documento,
                'logradouro': l.logradouro or 'Avenida Principal',
                'numero': l.numero or 'S/N',
                'bairro': l.bairro,
                'cidade': l.cidade or 'Campo Grande',
                'cep': l.cep,
                'operadora_atual': l.operadora_atual or 'Vivo Fibra',
                'plano_sugerido': l.plano_sugerido or 'Fibra 700 + DigiMesh (Wi-Fi 6)',
                'valor_mensal_sugerido': float(l.valor_mensal_sugerido or 139.90),
                'lead_score': int(l.lead_score or 88),
                'dor_principal': l.dor_principal or 'Instabilidade de conexão e lentidão nos horários de pico',
                'status': l.status,
                'status_label': l.status_label,
                'status_badge_class': l.status_badge_class,
                'optin_status': l.optin_status,
                'whatsapp_url': l.whatsapp_url,
                'detail_url': f"/leads/{l.id}",
                'lat': p_lat,
                'lng': p_lng,
                'distancia_estimada_m': int(120 + (idx * 65)),
            })

        return resultado

    @classmethod
    def prospect_neighborhood(
        cls,
        bairro: str,
        cidade: str = 'Campo Grande',
        estado: str = 'MS',
        niche: str = 'Empresas e Comércios',
        count: int = 50,
        cliente_ref_id: Optional[int] = None
    ) -> List[Dict[str, Any]]:
        """
        Gera leads vizinhos qualificados na mesma região dos clientes.
        Cascata de provedores:
        1. AIsa API (se AISA_API_KEY configurada)
        2. Google Gemini API (se GEMINI_API_KEY configurada)
        3. Motor Heurístico Local de Telecomunicações (SISGRAN / PLANURB)
        """
        aisa_key = current_app.config.get('AISA_API_KEY')
        if aisa_key and aisa_key.strip():
            try:
                model = current_app.config.get('AISA_MODEL') or 'asi1-mini'
                leads_aisa = cls._call_aisa_prospector(bairro, cidade, estado, niche, count, aisa_key.strip(), model)
                if leads_aisa:
                    return leads_aisa
            except Exception as e:
                logger.warning(f"Falha na chamada à AIsa API ({e}). Tentando provedor secundário...")

        api_key = current_app.config.get('GEMINI_API_KEY')
        if api_key and api_key.strip():
            try:
                leads_ai = cls._call_gemini_prospector(bairro, cidade, estado, niche, count, api_key.strip())
                if leads_ai:
                    return leads_ai
            except Exception as e:
                logger.warning(f"Falha na chamada ao Gemini API ({e}). Usando motor local de telecom.")

        return cls._generate_fallback_prospects(bairro, cidade, estado, niche, count)

    @classmethod
    def _call_gemini_prospector(
        cls,
        bairro: str,
        cidade: str,
        estado: str,
        niche: str,
        count: int,
        api_key: str
    ) -> List[Dict[str, Any]]:
        """Chama a API do Google Gemini via HTTP padrão (sem bibliotecas externas pesadas)."""
        prompt = f"""Você é o maior especialista em prospecção de vendas B2B e expansão de provedores de internet fibra óptica (ISP).
A empresa é a DigitalNet MS (provedor com rede própria AS61588, Wi-Fi 6 em comodato, suporte local 24h e planos de 600 a 900 Mega em Campo Grande - MS).

Gere uma lista de {count} leads B2B/comerciais realistas e altamente prováveis localizados EXATAMENTE no bairro "{bairro}" em "{cidade} - {estado}", nicho "{niche}".

Retorne EXCLUSIVAMENTE um JSON array (sem formatação markdown, sem ```json) com a seguinte estrutura para cada item:
[
  {{
    "empresa": "Nome da Empresa / Clínica / Comércio",
    "nome": "Nome do Decisor (Ex: Dra. Camila Rocha, Dr. Marcos Silva, Roberto Santos)",
    "cargo": "Cargo (Ex: Sócio-Diretor, Gerente Geral, Médico Responsável)",
    "telefone": "(67) 99876-1234",
    "email": "contato@empresa.com.br",
    "logradouro": "Rua ou Avenida real deste bairro em Campo Grande",
    "numero": "120",
    "cep": "79000-000",
    "operadora_atual": "Vivo Fibra ou Claro",
    "plano_sugerido": "Fibra 700 + DigiMesh (Wi-Fi 6) ou Fibra 900 Advanced",
    "valor_mensal_sugerido": 139.90,
    "lead_score": 88,
    "dor_principal": "Descrição da dor (ex: maquininha oscilando, sinal Wi-Fi fraco, suporte 0800 demorado)",
    "icebreaker_optin": "Texto persuasivo de 3 parágrafos pedindo opt-in para comparativo sem ban"
  }}
]"""


        url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent?key={api_key}"
        payload = json.dumps({
            "contents": [{"parts": [{"text": prompt}]}],
            "generationConfig": {"temperature": 0.4}
        }).encode('utf-8')

        req = urllib.request.Request(
            url,
            data=payload,
            headers={'Content-Type': 'application/json'},
            method='POST'
        )

        with urllib.request.urlopen(req, timeout=12) as response:
            res_data = json.loads(response.read().decode('utf-8'))
            text_resp = res_data['candidates'][0]['content']['parts'][0]['text']
            # Remove blocos ```json se houver
            text_clean = re.sub(r'^```json\s*', '', text_resp.strip(), flags=re.MULTILINE)
            text_clean = re.sub(r'```$', '', text_clean.strip(), flags=re.MULTILINE)
            dados = json.loads(text_clean)
            if isinstance(dados, list):
                for item in dados:
                    item.setdefault('bairro', bairro)
                    item.setdefault('cidade', cidade)
                    item.setdefault('estado', estado)
                    item.setdefault('niche', niche)
                return dados
        return []

    @classmethod
    def _call_aisa_prospector(
        cls,
        bairro: str,
        cidade: str,
        estado: str,
        niche: str,
        count: int,
        api_key: str,
        model: str = 'asi1-mini'
    ) -> List[Dict[str, Any]]:
        """Chama a API da AIsa (api.aisa.one) via endpoint OpenAI-compatible /v1/chat/completions."""
        system_prompt = (
            "Você é o motor de prospecção corporativa B2B e expansão da operadora DigitalNet MS. "
            "Sua missão é retornar uma lista estruturada de empresas comerciais/B2B com dados de contato "
            "válidos e viabilidade de conectividade de fibra óptica em Campo Grande - MS. "
            "Retorne EXCLUSIVAMENTE um objeto JSON contendo a propriedade 'leads' com um array de itens."
        )

        user_prompt = f"""Gere uma lista de {count} empresas/leads B2B com alto potencial de contratação de fibra óptica e Wi-Fi 6 corporativo no bairro "{bairro}" em "{cidade} - {estado}", nicho "{niche}".

ESTRUTURA DO JSON OBRIGATÓRIA:
{{
  "leads": [
    {{
      "company_name": "Nome da Empresa / Comércio / Clínica",
      "contact_name": "Nome do Decisor ou Responsável Comercial",
      "cargo": "Sócio-Diretor / Gerente Geral / Coordenador",
      "phone": "(67) 99876-1234",
      "whatsapp": "67998761234",
      "email": "contato@empresa.com.br",
      "address": "Rua ou Avenida real deste bairro em Campo Grande",
      "numero": "120",
      "cep": "79000-000",
      "operadora_atual": "Vivo Fibra ou Claro NET",
      "plano_sugerido": "Fibra 700 + DigiMesh (Wi-Fi 6) ou DigitalNet B2B Link Dedicado Pro",
      "valor_mensal_sugerido": 139.90,
      "score": 88,
      "description": "Dor ou motivo de prospecção (ex: lentidão no horário de pico, falha de maquininha, sinal fraco)",
      "icebreaker_optin": "Mensagem consultiva curta para WhatsApp pedindo opt-in"
    }}
  ]
}}"""

        url = "https://api.aisa.one/v1/chat/completions"
        payload = json.dumps({
            "model": model or "asi1-mini",
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt}
            ],
            "temperature": 0.3,
            "response_format": {"type": "json_object"}
        }).encode('utf-8')

        req = urllib.request.Request(
            url,
            data=payload,
            headers={
                'Content-Type': 'application/json',
                'Authorization': f'Bearer {api_key}',
                'User-Agent': 'DigitalNet-Telecom-Prospector/1.0'
            },
            method='POST'
        )

        with urllib.request.urlopen(req, timeout=15) as response:
            res_data = json.loads(response.read().decode('utf-8'))
            content = res_data.get('choices', [{}])[0].get('message', {}).get('content', '')
            text_clean = re.sub(r'^```json\s*', '', content.strip(), flags=re.MULTILINE)
            text_clean = re.sub(r'```$', '', text_clean.strip(), flags=re.MULTILINE)
            parsed = json.loads(text_clean)
            raw_leads = parsed.get('leads') if isinstance(parsed, dict) else (parsed if isinstance(parsed, list) else [])

            leads_padronizados = []
            for item in raw_leads:
                empresa = item.get('company_name') or item.get('empresa') or 'Empresa Prospectada'
                nome = item.get('contact_name') or item.get('nome') or 'Responsável Comercial'
                leads_padronizados.append({
                    'empresa': empresa,
                    'nome': nome,
                    'cargo': item.get('cargo', 'Decisor'),
                    'telefone': item.get('phone') or item.get('telefone') or '(67) 99876-0000',
                    'email': item.get('email') or f"contato@{re.sub(r'[^a-z0-9]', '', empresa.lower())[:12]}.com.br",
                    'logradouro': item.get('address') or item.get('logradouro') or 'Avenida Principal',
                    'numero': str(item.get('numero', '100')),
                    'bairro': bairro,
                    'cidade': cidade,
                    'estado': estado,
                    'cep': item.get('cep', '79000-000'),
                    'niche': niche,
                    'operadora_atual': item.get('operadora_atual', 'Vivo Fibra / Claro NET'),
                    'plano_sugerido': item.get('plano_sugerido', 'Fibra 700 + DigiMesh (Wi-Fi 6)'),
                    'valor_mensal_sugerido': float(item.get('valor_mensal_sugerido', 139.90)),
                    'lead_score': int(item.get('score', item.get('lead_score', 85))),
                    'dor_principal': item.get('description', item.get('dor_principal', 'Instabilidade e lentidão de conexão')),
                    'icebreaker_optin': item.get('icebreaker_optin'),
                })
            return leads_padronizados

    @classmethod
    def test_aisa_connection(cls, api_key: str, model: str = 'asi1-mini') -> Dict[str, Any]:
        """Testa a conexão com a API da AIsa consultando /v1/models ou chat rápido."""
        url = "https://api.aisa.one/v1/models"
        req = urllib.request.Request(
            url,
            headers={
                'Authorization': f'Bearer {api_key}',
                'Content-Type': 'application/json'
            },
            method='GET'
        )
        try:
            with urllib.request.urlopen(req, timeout=8) as resp:
                data = json.loads(resp.read().decode('utf-8'))
                models = [m.get('id', str(m)) for m in data.get('data', [])] if isinstance(data.get('data'), list) else []
                return {'success': True, 'models': models[:15], 'status': 'connected'}
        except urllib.error.HTTPError as e:
            if e.code in (401, 403):
                return {'success': False, 'error': f'Chave recusada pela AIsa (HTTP {e.code}).', 'status': 'unauthorized'}
            # Tenta chat completions minimal
            chat_url = "https://api.aisa.one/v1/chat/completions"
            payload = json.dumps({
                "model": model,
                "messages": [{"role": "user", "content": "ping"}],
                "max_tokens": 5
            }).encode('utf-8')
            chat_req = urllib.request.Request(
                chat_url,
                data=payload,
                headers={'Authorization': f'Bearer {api_key}', 'Content-Type': 'application/json'},
                method='POST'
            )
            try:
                with urllib.request.urlopen(chat_req, timeout=8) as chat_resp:
                    return {'success': True, 'models': [model], 'status': 'connected'}
            except Exception as inner_e:
                return {'success': False, 'error': str(inner_e), 'status': 'error'}
        except Exception as e:
            return {'success': False, 'error': str(e), 'status': 'error'}

    @classmethod
    def generate_pitch(cls, lead: Lead, channel: str = 'whatsapp', tone: str = 'consultative') -> Dict[str, Any]:
        """Gera roteiro de abordagem comercial via IA (AIsa / Gemini) ou fallback."""
        aisa_key = current_app.config.get('AISA_API_KEY')
        if aisa_key and aisa_key.strip():
            try:
                system_prompt = (
                    "Você é um especialista em prospecção B2B de telecom e vendas consultivas da DigitalNet MS. "
                    "Gere uma abordagem persuasiva e personalizada para o lead. "
                    "Retorne EXCLUSIVAMENTE um objeto JSON com: 'subject', 'message', 'key_points', 'call_to_action'."
                )
                user_prompt = (
                    f"Lead: {lead.empresa} (Decisor: {lead.nome}, Cargo: {lead.cargo or 'Decisor'})\n"
                    f"Bairro: {lead.bairro}, Cidade: {lead.cidade}\n"
                    f"Operadora Atual: {lead.operadora_atual}, Dor: {lead.dor_principal}\n"
                    f"Plano Sugerido: {lead.plano_sugerido} (R$ {lead.valor_mensal_sugerido:.2f})\n"
                    f"Canal: {channel.upper()}, Tom: {tone}"
                )
                payload = json.dumps({
                    "model": current_app.config.get('AISA_MODEL') or 'asi1-mini',
                    "messages": [
                        {"role": "system", "content": system_prompt},
                        {"role": "user", "content": user_prompt}
                    ],
                    "temperature": 0.4,
                    "response_format": {"type": "json_object"}
                }).encode('utf-8')
                req = urllib.request.Request(
                    "https://api.aisa.one/v1/chat/completions",
                    data=payload,
                    headers={
                        'Content-Type': 'application/json',
                        'Authorization': f"Bearer {aisa_key.strip()}"
                    },
                    method='POST'
                )
                with urllib.request.urlopen(req, timeout=10) as resp:
                    data = json.loads(resp.read().decode('utf-8'))
                    content = data.get('choices', [{}])[0].get('message', {}).get('content', '')
                    text_clean = re.sub(r'^```json\s*', '', content.strip(), flags=re.MULTILINE)
                    text_clean = re.sub(r'```$', '', text_clean.strip(), flags=re.MULTILINE)
                    return json.loads(text_clean)
            except Exception as e:
                logger.warning(f"Falha ao gerar pitch via AIsa ({e}). Usando roteiro nativo.")

        # Fallback nativo estruturado
        return {
            'subject': f"Modernização de Fibra Óptica no {lead.bairro} - {lead.empresa}",
            'message': cls.generate_anti_ban_whatsapp_script(lead),
            'key_points': [
                f"Rede própria de fibra ativa no poste do bairro {lead.bairro}",
                "Wi-Fi 6 de alta densidade sem aluguel",
                "Suporte presencial 24h com base técnica em Campo Grande"
            ],
            'call_to_action': "Posso te enviar um comparativo de 1 minuto sem compromisso?",
            'suggested_next_step': "Enviar mensagem de opt-in pelo WhatsApp e aguardar resposta afirmativa."
        }

    @classmethod
    def _fetch_rfb_leads(
        cls,
        bairro: str,
        cidade: str = 'Campo Grande',
        estado: str = 'MS',
        niche: str = 'Geral',
        count: int = 5
    ) -> List[Dict[str, Any]]:
        """
        Busca leads comerciais reais da base de dados abertos da Receita Federal (RFB)
        armazenados na tabela leeds_campo_grande (ou view leads_campo_grande), filtrando
        pela região geográfica do bairro e garantindo que não sejam empresas já prospectadas
        ou clientes existentes.
        """
        tabela_rfb = None
        try:
            from sqlalchemy import text
            for tbl in ('leeds_campo_grande', 'leads_campo_grande'):
                has = bool(db.session.execute(
                    text(f"SELECT 1 FROM sqlite_master WHERE type IN ('table', 'view') AND name='{tbl}'")
                ).scalar())
                if has:
                    tabela_rfb = tbl
                    break
            if not tabela_rfb:
                return []
        except Exception as e:
            logger.debug(f"Tabela RFB não disponível para consulta: {e}")
            return []

        info_bairro = cls.get_bairro_profile(bairro)
        ruas = info_bairro.get('ruas', ['Avenida Afonso Pena', 'Rua 14 de Julho'])
        amostras = info_bairro.get('amostra_imoveis', [])
        cep_prefix = info_bairro.get('cep_prefix', '79002')

        prefixes = [cep_prefix] if cep_prefix else []
        bairro_norm = bairro
        try:
            bairro_norm = resolver_bairro(bairro) or bairro
            for p, b_name in CEP_PREFIXOS_BAIRROS.items():
                if b_name.lower() in (bairro.lower(), bairro_norm.lower()):
                    if p not in prefixes:
                        prefixes.append(p)
        except Exception:
            pass

        if not prefixes:
            prefixes = ['790']

        prefix_conditions = " OR ".join([f"cep LIKE :p_{i}" for i in range(len(prefixes))])
        params = {f"p_{i}": f"{pref}%" for i, pref in enumerate(prefixes)}
        params['limit_query'] = max(count * 4, 30)
        params['bairro_busca'] = f"%{bairro.upper()}%"
        params['bairro_norm_busca'] = f"%{bairro_norm.upper()}%"

        bairro_condition = f"(UPPER(bairro) LIKE :bairro_busca OR UPPER(bairro) LIKE :bairro_norm_busca OR ({prefix_conditions}))"

        query = text(f"""
            SELECT 
                empresa, cnpj, nome, cargo, telefone, email, logradouro, numero, bairro, complemento, cep, 
                operadora_atual, plano_sugerido, valor_mensal_sugerido, lead_score, cnae_fiscal
            FROM {tabela_rfb}
            WHERE situacao_cadastral = 'ATIVA'
              AND {bairro_condition}
              AND email IS NOT NULL AND email != '' AND email LIKE '%@%.%'
              AND telefone IS NOT NULL AND length(telefone) >= 8
              AND empresa NOT IN (SELECT empresa FROM leads WHERE empresa IS NOT NULL)
            ORDER BY lead_score DESC, RANDOM()
            LIMIT :limit_query
        """)

        try:
            rows = db.session.execute(query, params).fetchall()
        except Exception as e:
            logger.debug(f"Tentando consulta de compatibilidade sem colunas estendidas: {e}")
            query_compat = text(f"""
                SELECT 
                    empresa, cnpj, nome, cargo, telefone, email, logradouro, numero, cep, 
                    operadora_atual, plano_sugerido, valor_mensal_sugerido, lead_score, cnae_fiscal
                FROM {tabela_rfb}
                WHERE situacao_cadastral = 'ATIVA'
                  AND ({prefix_conditions})
                  AND email IS NOT NULL AND email != '' AND email LIKE '%@%.%'
                  AND telefone IS NOT NULL AND length(telefone) >= 8
                  AND empresa NOT IN (SELECT empresa FROM leads WHERE empresa IS NOT NULL)
                ORDER BY lead_score DESC, RANDOM()
                LIMIT :limit_query
            """)
            try:
                rows = db.session.execute(query_compat, params).fetchall()
            except Exception as e2:
                logger.warning(f"Erro ao consultar {tabela_rfb}: {e2}")
                return []

        leads_encontrados = []
        idx = 0
        for r in rows:
            if len(leads_encontrados) >= count:
                break

            data = dict(r._mapping)
            raw_empresa = data.get('empresa') or ''
            clean_emp = re.sub(r'^\d{2}\.\d{3}\.\d{3}\s+', '', raw_empresa).strip()
            parts = clean_emp.split()
            formatted_parts = []
            for p in parts:
                if p.upper() in ('LTDA', 'ME', 'EPP', 'EIRELI', 'S/A', 'SA', 'SS', 'S.A.'):
                    formatted_parts.append(p.upper())
                elif len(p) <= 3 and p.lower() in ('de', 'da', 'do', 'das', 'dos', 'e', 'em'):
                    formatted_parts.append(p.lower())
                else:
                    formatted_parts.append(p.capitalize())
            empresa_fmt = " ".join(formatted_parts) or clean_emp

            cnpj_raw = re.sub(r'\D', '', str(data.get('cnpj') or ''))
            cnpj_fmt = f"{cnpj_raw[:2]}.{cnpj_raw[2:5]}.{cnpj_raw[5:8]}/{cnpj_raw[8:12]}-{cnpj_raw[12:]}" if len(cnpj_raw) == 14 else cnpj_raw

            nome_raw = str(data.get('nome') or 'Responsável Comercial').strip()
            nome_parts = [p.lower() if len(p) <= 3 and p.lower() in ('de', 'da', 'do', 'das', 'dos') else p.capitalize() for p in nome_raw.split()]
            nome_fmt = " ".join(nome_parts)

            cargo_raw = str(data.get('cargo') or 'Sócio-Administrador').strip()
            cargo_fmt = cargo_raw.capitalize() if cargo_raw.isupper() else cargo_raw

            # Trata o campo de telefone: faz o split pelo '|', pega o primeiro número da lista e remove +55
            raw_tel = str(data.get('telefone') or '')
            primeiro_tel = raw_tel.split('|')[0].strip() if '|' in raw_tel else raw_tel.strip()

            tel_digits = re.sub(r'\D', '', primeiro_tel)
            if tel_digits.startswith('55') and len(tel_digits) >= 10:
                tel_digits = tel_digits[2:]

            # Extrai DDD (2 dígitos) e número local
            if len(tel_digits) in (10, 11):
                ddd = tel_digits[:2]
                num = tel_digits[2:]
            elif len(tel_digits) in (8, 9):
                ddd = '67'
                num = tel_digits
            elif len(tel_digits) > 11:
                ddd = tel_digits[:2]
                num = tel_digits[2:11]
            else:
                ddd = '67'
                num = ''

            if len(num) == 9:
                tel_fmt = f"({ddd}) {num[:5]}-{num[5:]}"
            elif len(num) == 8:
                if num[0] in ('8', '9'):
                    tel_fmt = f"({ddd}) 9{num[:4]}-{num[4:]}"
                else:
                    tel_fmt = f"({ddd}) {num[:4]}-{num[4:]}"
            else:
                tel_fmt = f"(67) 99{random.randint(100, 999)}-{random.randint(1000, 9999)}"

            # 1. Logradouro real da RFB formatado em Title Case
            raw_logr = str(data.get('logradouro') or '').replace("'", "").replace('"', '').strip()
            if raw_logr and raw_logr != '0' and not raw_logr.isdigit():
                words = raw_logr.split()
                lowers = {'de', 'da', 'do', 'dos', 'das', 'e', 'em'}
                uppers = {'ltda', 'me', 'epp', 's/a', 'sa', 'eireli'}
                logr_parts = []
                for i_w, w in enumerate(words):
                    wl = w.lower()
                    if wl in uppers:
                        logr_parts.append(wl.upper())
                    elif i_w > 0 and wl in lowers:
                        logr_parts.append(wl)
                    else:
                        logr_parts.append(w.capitalize())
                rua_lead = " ".join(logr_parts)
            elif amostras:
                am = amostras[idx % len(amostras)]
                rua_lead = am.get('logradouro') or ruas[idx % len(ruas)]
            else:
                rua_lead = ruas[idx % len(ruas)]

            # 2. Número real do imóvel
            raw_num = str(data.get('numero') or '').replace("'", "").replace('"', '').strip()
            if raw_num and raw_num.upper() not in ('0', 'NULL', 'NONE'):
                num_lead = raw_num
            elif amostras:
                am = amostras[idx % len(amostras)]
                num_lead = str(am.get('numero') or (120 + idx * 35))
            else:
                num_lead = str(120 + idx * 35)

            # 3. Complemento do imóvel
            raw_compl = str(data.get('complemento') or '').replace("'", "").replace('"', '').strip()
            compl_lead = raw_compl if raw_compl and raw_compl.upper() not in ('0', 'NULL', 'NONE') else None

            # 4. Bairro normalizado
            raw_bairro = str(data.get('bairro') or '').strip()
            bairro_lead = normalizar_bairro(raw_bairro) if raw_bairro else normalizar_bairro(bairro)
            if not bairro_lead or bairro_lead == 'Centro':
                bairro_lead = normalizar_bairro(bairro) or 'Centro'

            cep_digits = re.sub(r'\D', '', str(data.get('cep') or ''))
            if len(cep_digits) == 8:
                cep_fmt = f"{cep_digits[:5]}-{cep_digits[5:]}"
            else:
                cep_fmt = f"{cep_prefix}-{random.randint(100, 999):03d}"

            cnae_desc = str(data.get('cnae_fiscal') or '')
            operadora = data.get('operadora_atual')
            if not operadora or operadora in ('Não Identificada', 'Sem Operadora'):
                operadora = 'Vivo Fibra' if (idx % 2 == 0) else 'Claro NET'

            if any(term in cnae_desc.lower() for term in ('médic', 'saúd', 'odont', 'clínic', 'hospital')):
                dor = 'Lentidão no sistema de prontuários eletrônicos e falha nas máquinas de cartão em horários de pico.'
                plano = 'Fibra 700 + DigiMesh (Wi-Fi 6)'
                valor = 139.90
            elif any(term in cnae_desc.lower() for term in ('advoc', 'contáb', 'juríd', 'consult')):
                dor = 'Queda de conexão durante audiências virtuais e lentidão no envio de relatórios fiscais.'
                plano = 'DigitalNet B2B Link Dedicado Pro'
                valor = 399.90
            elif any(term in cnae_desc.lower() for term in ('comérci', 'varej', 'alimento', 'restaurant', 'bar')):
                dor = 'Wi-Fi da operadora atual com sinal fraco no salão de atendimento e instabilidade no checkout.'
                plano = 'Fibra 700 + DigiMesh (Wi-Fi 6)'
                valor = 139.90
            else:
                dor = 'Instabilidade na banda larga atual e falta de suporte técnico presencial rápido quando o sinal cai.'
                plano = 'Fibra 900 Advanced (Wi-Fi 6)'
                valor = 149.90

            lead_item = {
                'empresa': empresa_fmt,
                'nome': nome_fmt,
                'cargo': cargo_fmt,
                'telefone': tel_fmt,
                'email': (data.get('email') or f"contato@{re.sub(r'[^a-z0-9]', '', clean_emp.lower())[:12]}.com.br").lower(),
                'documento': cnpj_fmt,
                'logradouro': rua_lead,
                'numero': num_lead,
                'complemento': compl_lead,
                'bairro': bairro_lead,
                'cidade': cidade,
                'estado': estado,
                'cep': cep_fmt,
                'niche': niche or cnae_desc or 'Comercial',
                'operadora_atual': operadora,
                'plano_sugerido': plano,
                'valor_mensal_sugerido': valor,
                'lead_score': int(data.get('lead_score') or 90),
                'dor_principal': dor,
            }

            temp_lead = Lead(**lead_item)
            lead_item['icebreaker_optin'] = cls.generate_anti_ban_whatsapp_script(temp_lead)
            lead_item['dossie_comercial'] = json.dumps({
                'perfil_decisor': f"{nome_fmt} ({cargo_fmt}) - CNAE: {cnae_desc or 'Comercial'}.",
                'vantagem_digitalnet': 'Rede própria AS61588 de fibra óptica com Wi-Fi 6 e suporte local 24h em Campo Grande.',
                'angulo_venda': f"Eliminar a dor de '{dor}' com migração sem interrupção de serviço.",
                'perfil_territorial': f"Região {info_bairro.get('regiao_urbana', 'Urbana')} ({info_bairro.get('macrozona', '')}). Perfil: {info_bairro.get('perfil_predominante', 'Comercial')}.",
                'fonte_dados': 'Receita Federal do Brasil (RFB) + SISGRAN/PLANURB Campo Grande',
            }, ensure_ascii=False)

            leads_encontrados.append(lead_item)
            idx += 1

        return leads_encontrados

    @classmethod
    def _generate_synthetic_prospects(
        cls,
        bairro: str,
        cidade: str,
        estado: str,
        niche: str,
        count: int,
        empresas_evitar: Optional[List[str]] = None
    ) -> List[Dict[str, Any]]:
        """Motor gerador sintético dinâmico de alta diversidade e anti-duplicação territorial."""
        info_bairro = cls.get_bairro_profile(bairro)
        ruas = info_bairro.get('ruas', ['Avenida Principal', 'Rua Central'])
        amostras = info_bairro.get('amostra_imoveis', [])
        cep_prefix = info_bairro.get('cep_prefix', '79002')

        try:
            leads_existentes = {l.empresa.lower().strip() for l in Lead.query.with_entities(Lead.empresa).all() if l.empresa}
            clientes_existentes = {c.nome.lower().strip() for c in Cliente.query.with_entities(Cliente.nome).all() if c.nome}
            usados = leads_existentes | clientes_existentes
        except Exception:
            usados = set()

        if empresas_evitar:
            for e in empresas_evitar:
                if e:
                    usados.add(e.lower().strip())

        templates_empresas = [
            {
                'empresa_tpl': 'Clínica Médica Integrada {sobrenome}',
                'contato': 'Dra. Camila {sobrenome}',
                'cargo': 'Diretora Clínica',
                'dor': 'Lentidão no sistema de prontuários eletrônicos e máquinas de cartão travando em horários de pico.',
                'operadora': 'Vivo Fibra',
                'plano': 'Fibra 700 + DigiMesh (Wi-Fi 6)',
                'valor': 139.90,
                'score': 93,
            },
            {
                'empresa_tpl': '{sobrenome} Advogados Associados',
                'contato': 'Dr. Marcos Eduardo {sobrenome}',
                'cargo': 'Sócio Coordenador',
                'dor': 'Queda de conexão durante audiências virtuais pelo Teams/Zoom e demora no upload de petições pesadas.',
                'operadora': 'Claro NET',
                'plano': 'DigitalNet B2B Link Dedicado Pro',
                'valor': 399.90,
                'score': 95,
            },
            {
                'empresa_tpl': 'Studio e Boutique {sobrenome}',
                'contato': 'Camila {sobrenome}',
                'cargo': 'Sócia Proprietária',
                'dor': 'Wi-Fi da operadora atual não cobre a recepção e o estoque; sinal fraco para clientes.',
                'operadora': 'Vivo Fibra',
                'plano': 'Fibra 700 + DigiMesh (Wi-Fi 6)',
                'valor': 139.90,
                'score': 88,
            },
            {
                'empresa_tpl': '{sobrenome} Contabilidade e Gestão',
                'contato': 'Carlos Roberto {sobrenome}',
                'cargo': 'Contador Responsável',
                'dor': 'Falta de suporte aos finais de semana e suporte telefônico via robô 0800 quando cai o sinal.',
                'operadora': 'Claro NET',
                'plano': 'Fibra 900 Advanced (Wi-Fi 6)',
                'valor': 149.90,
                'score': 90,
            },
            {
                'empresa_tpl': 'Espaço Saúde e Bem-Estar {sobrenome}',
                'contato': 'Juliana {sobrenome}',
                'cargo': 'Gerente Geral',
                'dor': 'Cobrança alta de fatura na operadora atual sem entrega da velocidade contratada.',
                'operadora': 'Vivo Fibra',
                'plano': 'Fibra 600 Standard (Wi-Fi 6)',
                'valor': 129.90,
                'score': 84,
            },
            {
                'empresa_tpl': 'Restaurante e Parrilla {sobrenome}',
                'contato': 'Fernando {sobrenome}',
                'cargo': 'Proprietário',
                'dor': 'Queda no link de dados afeta o tablet de pedidos dos garçons e a emissão de cupons fiscais.',
                'operadora': 'Claro NET',
                'plano': 'Fibra 700 + DigiMesh (Wi-Fi 6)',
                'valor': 139.90,
                'score': 91,
            },
            {
                'empresa_tpl': '{sobrenome} Soluções Digitais e Tech',
                'contato': 'Rodrigo {sobrenome}',
                'cargo': 'Diretor de Tecnologia',
                'dor': 'Upload lento para servidores na nuvem e falta de IP fixo com SLA comercial.',
                'operadora': 'Claro NET',
                'plano': 'DigitalNet B2B Link Dedicado Pro',
                'valor': 499.90,
                'score': 96,
            },
            {
                'empresa_tpl': 'Drogaria e Farmácia {sobrenome}',
                'contato': 'Renata {sobrenome}',
                'cargo': 'Farmacêutica Responsável',
                'dor': 'Travamento na validação de receitas e autorizações online pelo portal dos convênios.',
                'operadora': 'Vivo Fibra',
                'plano': 'Fibra 700 + DigiMesh (Wi-Fi 6)',
                'valor': 139.90,
                'score': 89,
            },
            {
                'empresa_tpl': 'Centro Automotivo e Peças {sobrenome}',
                'contato': 'Marcelo {sobrenome}',
                'cargo': 'Gerente de Operações',
                'dor': 'Sistema de ordem de serviço e emissão de NFe fora do ar devido a oscilações de sinal.',
                'operadora': 'Claro NET',
                'plano': 'Fibra 600 Standard (Wi-Fi 6)',
                'valor': 129.90,
                'score': 86,
            },
            {
                'empresa_tpl': 'Academia e Fitness Club {sobrenome}',
                'contato': 'Lucas {sobrenome}',
                'cargo': 'Coordenador Técnico',
                'dor': 'Alunos insatisfeitos com Wi-Fi social oscilando e catracas biométricas offline.',
                'operadora': 'Vivo Fibra',
                'plano': 'Fibra 900 Advanced (Wi-Fi 6)',
                'valor': 149.90,
                'score': 87,
            },
            {
                'empresa_tpl': '{sobrenome} Odontologia Especializada',
                'contato': 'Dra. Mariana {sobrenome}',
                'cargo': 'Cirurgiã-Dentista Chefe',
                'dor': 'Lentidão no escaneamento intraoral e envio de radiografias digitais para laboratórios.',
                'operadora': 'Vivo Fibra',
                'plano': 'Fibra 700 + DigiMesh (Wi-Fi 6)',
                'valor': 139.90,
                'score': 92,
            },
            {
                'empresa_tpl': 'Laboratório de Análises {sobrenome}',
                'contato': 'Dr. Henrique {sobrenome}',
                'cargo': 'Bioquímico Responsável',
                'dor': 'Atraso no envio eletrônico de laudos emergenciais por instabilidade na rede de dados.',
                'operadora': 'Claro NET',
                'plano': 'DigitalNet B2B Link Dedicado Pro',
                'valor': 399.90,
                'score': 94,
            },
            {
                'empresa_tpl': 'Agência {sobrenome} Comunicação e Mídia',
                'contato': 'Beatriz {sobrenome}',
                'cargo': 'Diretora de Criação',
                'dor': 'Upload demorado de vídeos pesados em 4K e videoconferências com clientes travando.',
                'operadora': 'Claro NET',
                'plano': 'Fibra 900 Advanced (Wi-Fi 6)',
                'valor': 149.90,
                'score': 92,
            },
            {
                'empresa_tpl': '{sobrenome} Engenharia e Projetos',
                'contato': 'Eng. Rafael {sobrenome}',
                'cargo': 'Diretor de Obras',
                'dor': 'Dificuldade de sincronização de plantas BIM e arquivos CAD com a equipe de campo.',
                'operadora': 'Claro NET',
                'plano': 'Fibra 700 + DigiMesh (Wi-Fi 6)',
                'valor': 139.90,
                'score': 88,
            },
            {
                'empresa_tpl': 'Colégio e Instituto de Ensino {sobrenome}',
                'contato': 'Profa. Claudia {sobrenome}',
                'cargo': 'Diretora Pedagógica',
                'dor': 'Ambiente virtual e laboratório de informática travando por falta de banda dedicada e Wi-Fi 6.',
                'operadora': 'Vivo Fibra',
                'plano': 'DigitalNet B2B Link Dedicado Pro',
                'valor': 399.90,
                'score': 95,
            },
        ]

        sobrenomes = [
            'Albuquerque', 'Mendes', 'Fontana', 'Vasconcelos', 'Barreto', 'Nogueira', 'Pires', 'Ribeiro',
            'Barbosa', 'Cardoso', 'Guimarães', 'Machado', 'Teixeira', 'Miranda', 'Carvalho', 'Batista',
            'Moreira', 'Siqueira', 'Rezende', 'Cunha', 'Campos', 'Rocha', 'Pinheiro', 'Freitas',
            'Dias', 'Castro', 'Cavalcante', 'Peixoto', 'Monteiro', 'Correia', 'Macedo', 'Farias',
            'Brito', 'Andrade', 'Silveira', 'Duarte', 'Prado', 'Lopes', 'Nascimento', 'Guedes'
        ]

        combinacoes = []
        for t in templates_empresas:
            for s in sobrenomes:
                combinacoes.append((t, s))
        random.shuffle(combinacoes)

        resultado = []
        tentativa_idx = 0

        for t, sobrenome in combinacoes:
            if len(resultado) >= count:
                break

            empresa = t['empresa_tpl'].format(sobrenome=sobrenome)
            if empresa.lower().strip() in usados:
                continue

            usados.add(empresa.lower().strip())
            nome_contato = t['contato'].format(sobrenome=sobrenome)

            if amostras:
                am = amostras[tentativa_idx % len(amostras)]
                rua = am.get('logradouro') or ruas[tentativa_idx % len(ruas)]
                num = str(am.get('numero') or (100 + tentativa_idx * 75))
            else:
                rua = ruas[tentativa_idx % len(ruas)]
                num = str(100 + tentativa_idx * 75)

            tel = f"(67) 9{random.randint(9100, 9999)}-{random.randint(1000, 9999)}"
            email_empresa = f"contato@{re.sub(r'[^a-z0-9]', '', empresa.lower())[:14]}.com.br"
            cep = f"{cep_prefix}-{random.randint(100, 999):03d}"

            lead_item = {
                'empresa': empresa,
                'nome': nome_contato,
                'cargo': t['cargo'],
                'telefone': tel,
                'email': email_empresa,
                'logradouro': rua,
                'numero': num,
                'bairro': bairro,
                'cidade': cidade,
                'estado': estado,
                'cep': cep,
                'niche': niche,
                'operadora_atual': t['operadora'],
                'plano_sugerido': t['plano'],
                'valor_mensal_sugerido': t['valor'],
                'lead_score': t['score'],
                'dor_principal': t['dor'],
            }

            temp_lead = Lead(**lead_item)
            lead_item['icebreaker_optin'] = cls.generate_anti_ban_whatsapp_script(temp_lead)
            lead_item['dossie_comercial'] = json.dumps({
                'perfil_decisor': f"{nome_contato} ({t['cargo']}) busca estabilidade de rede e atendimento direto sem burocracia.",
                'vantagem_digitalnet': 'Fibra óptica com Wi-Fi 6 de alta densidade + suporte presencial 24h com equipe em Campo Grande.',
                'angulo_venda': f"Focar na eliminação da dor de '{t['dor']}' demonstrando que a DigitalNet já atende vizinhos nesta mesma rua.",
                'perfil_territorial': f"Região {info_bairro.get('regiao_urbana', 'Urbana')} ({info_bairro.get('macrozona', '')}). Perfil: {info_bairro.get('perfil_predominante', 'Comercial')}.",
            }, ensure_ascii=False)

            resultado.append(lead_item)
            tentativa_idx += 1

        while len(resultado) < count:
            tentativa_idx += 1
            idx_tpl = tentativa_idx % len(templates_empresas)
            t = templates_empresas[idx_tpl]
            sobrenome = sobrenomes[tentativa_idx % len(sobrenomes)]
            empresa = f"{t['empresa_tpl'].format(sobrenome=sobrenome)} Unidade {tentativa_idx}"
            nome_contato = t['contato'].format(sobrenome=sobrenome)
            rua = ruas[tentativa_idx % len(ruas)]
            num = str(100 + tentativa_idx * 45)
            tel = f"(67) 9{random.randint(9100, 9999)}-{random.randint(1000, 9999)}"
            email_empresa = f"contato{tentativa_idx}@{re.sub(r'[^a-z0-9]', '', empresa.lower())[:12]}.com.br"
            cep = f"{cep_prefix}-{random.randint(100, 999):03d}"

            lead_item = {
                'empresa': empresa,
                'nome': nome_contato,
                'cargo': t['cargo'],
                'telefone': tel,
                'email': email_empresa,
                'logradouro': rua,
                'numero': num,
                'bairro': bairro,
                'cidade': cidade,
                'estado': estado,
                'cep': cep,
                'niche': niche,
                'operadora_atual': t['operadora'],
                'plano_sugerido': t['plano'],
                'valor_mensal_sugerido': t['valor'],
                'lead_score': t['score'],
                'dor_principal': t['dor'],
            }
            temp_lead = Lead(**lead_item)
            lead_item['icebreaker_optin'] = cls.generate_anti_ban_whatsapp_script(temp_lead)
            resultado.append(lead_item)

        return resultado

    @classmethod
    def _generate_fallback_prospects(
        cls,
        bairro: str,
        cidade: str,
        estado: str,
        niche: str,
        count: int
    ) -> List[Dict[str, Any]]:
        """
        Motor heurístico de telecomunicações para Campo Grande enriquecido com SISGRAN e RFB.
        Prioridade 1: Empresas reais ativas da base da Receita Federal (leeds_campo_grande)
        Prioridade 2: Gerador sintético dinâmico combinatório de alta densidade (anti-duplicação)
        """
        leads_rfb = cls._fetch_rfb_leads(bairro=bairro, cidade=cidade, estado=estado, niche=niche, count=count)
        if len(leads_rfb) >= count:
            return leads_rfb[:count]

        faltam = count - len(leads_rfb)
        leads_sinteticos = cls._generate_synthetic_prospects(
            bairro=bairro,
            cidade=cidade,
            estado=estado,
            niche=niche,
            count=faltam,
            empresas_evitar=[l['empresa'] for l in leads_rfb]
        )

        return leads_rfb + leads_sinteticos

    @classmethod
    def save_prospects(cls, prospects_data: List[Dict[str, Any]], cliente_ref_id: Optional[int] = None) -> List[Lead]:
        """Salva a lista de leads prospectados no banco de dados com deduplicação rigorosa."""
        salvos = []
        for d in prospects_data:
            empresa_nome = (d.get('empresa') or '').strip()
            if not empresa_nome:
                continue

            bairro_lead = normalizar_bairro(d.get('bairro')) or 'Centro'
            doc_raw = re.sub(r'\D', '', str(d.get('documento') or ''))
            tel_raw = re.sub(r'\D', '', str(d.get('telefone') or ''))

            # 1. Deduplicação por Documento (CNPJ/CPF) se preenchido
            existente = None
            if doc_raw:
                existente = Lead.query.filter(
                    Lead.documento.isnot(None),
                    db.func.replace(db.func.replace(db.func.replace(db.func.replace(Lead.documento, '.', ''), '/', ''), '-', ''), ' ', '') == doc_raw
                ).first()

            # 2. Deduplicação por Nome da Empresa (case-insensitive)
            if not existente:
                existente = Lead.query.filter(
                    db.func.lower(Lead.empresa) == empresa_nome.lower()
                ).first()

            # 3. Deduplicação no mesmo bairro por Telefone (se informado)
            if not existente and len(tel_raw) >= 8:
                existente = Lead.query.filter(
                    Lead.bairro == bairro_lead,
                    Lead.telefone.isnot(None),
                    db.func.replace(db.func.replace(db.func.replace(db.func.replace(Lead.telefone, '(', ''), ')', ''), '-', ''), ' ', '').like(f"%{tel_raw[-8:]}%")
                ).first()

            # 4. Evita cadastrar lead se já for cliente ativo cadastrado
            if not existente:
                cliente_existente = Cliente.query.filter(
                    db.func.lower(Cliente.nome) == empresa_nome.lower()
                ).first()
                if cliente_existente:
                    continue

            if not existente and doc_raw:
                cliente_doc = Cliente.query.filter(
                    Cliente.documento.isnot(None),
                    db.func.replace(db.func.replace(db.func.replace(db.func.replace(Cliente.documento, '.', ''), '/', ''), '-', ''), ' ', '') == doc_raw
                ).first()
                if cliente_doc:
                    continue

            if existente:
                continue

            lead = Lead(
                empresa=empresa_nome,
                nome=d.get('nome') or 'Responsável Comercial',
                cargo=d.get('cargo'),
                telefone=d.get('telefone'),
                email=d.get('email'),
                documento=d.get('documento'),
                logradouro=d.get('logradouro'),
                numero=d.get('numero'),
                bairro=bairro_lead,
                cidade=d.get('cidade', 'Campo Grande'),
                estado=d.get('estado', 'MS'),
                cep=d.get('cep'),
                niche=d.get('niche', 'Geral'),
                cliente_referencia_id=cliente_ref_id,
                status='novo',
                optin_status='pendente',
                operadora_atual=d.get('operadora_atual', 'Vivo Fibra / Claro'),
                plano_sugerido=d.get('plano_sugerido', 'Fibra 700 + DigiMesh (Wi-Fi 6)'),
                valor_mensal_sugerido=float(d.get('valor_mensal_sugerido', 139.90)),
                lead_score=int(d.get('lead_score', 85)),
                dor_principal=d.get('dor_principal'),
                icebreaker_optin=d.get('icebreaker_optin'),
                dossie_comercial=d.get('dossie_comercial') if isinstance(d.get('dossie_comercial'), str) else json.dumps(d.get('dossie_comercial') or {}, ensure_ascii=False),
            )

            # Se não veio o script de opt-in, gera automaticamente
            if not lead.icebreaker_optin:
                lead.icebreaker_optin = cls.generate_anti_ban_whatsapp_script(lead)

            db.session.add(lead)
            salvos.append(lead)

        db.session.commit()
        return salvos

    @classmethod
    def convert_lead_to_client(cls, lead: Lead, plano: Optional[Plano] = None) -> Cliente:
        """
        Converte o lead em Cliente efetivo e cria automaticamente o Pedido
        da assinatura da DigitalNet MS vinculado ao Plano oficial e com itens totalizados.
        """
        if lead.cliente_convertido_id:
            cliente_existente = db.session.get(Cliente, lead.cliente_convertido_id)
            if cliente_existente:
                return cliente_existente

        # Se não foi fornecido plano explicitamente, tenta localizar pelo nome sugerido do lead
        if not plano and lead.plano_sugerido:
            plano = Plano.query.filter(Plano.nome == lead.plano_sugerido.strip()).first()
            if not plano:
                plano_nome_clean = lead.plano_sugerido.split('(')[0].strip()
                plano = Plano.query.filter(Plano.nome.ilike(f"%{plano_nome_clean}%")).first()

        # Se encontrou ou recebeu um plano correspondente, atualiza o lead
        if plano:
            lead.plano_sugerido = plano.nome
            if not lead.valor_mensal_sugerido or lead.valor_mensal_sugerido <= 0:
                lead.valor_mensal_sugerido = plano.valor_mensal

        # 1. Localiza ou Cria o Cliente
        cliente_existente = None
        doc_raw = re.sub(r'\D', '', lead.documento or '')
        if doc_raw and doc_raw not in ('00000000000100', '00000000000'):
            cliente_existente = Cliente.query.filter(
                Cliente.documento.isnot(None),
                db.func.replace(db.func.replace(db.func.replace(db.func.replace(Cliente.documento, '.', ''), '/', ''), '-', ''), ' ', '') == doc_raw
            ).first()

        if not cliente_existente and lead.email:
            cliente_existente = Cliente.query.filter(
                Cliente.email.isnot(None),
                db.func.lower(Cliente.email) == lead.email.strip().lower()
            ).first()

        if not cliente_existente and lead.empresa:
            empresa_nome = lead.empresa.strip()
            cliente_existente = Cliente.query.filter(
                db.or_(
                    db.func.lower(Cliente.nome) == empresa_nome.lower(),
                    Cliente.nome.ilike(f"{empresa_nome} (%")
                )
            ).first()

        if cliente_existente:
            novo_cliente = cliente_existente
        else:
            novo_cliente = Cliente(
                nome=f"{lead.empresa} ({lead.nome})",
                email=lead.email or f"contato@{re.sub(r'[^a-z0-9]', '', lead.empresa.lower())[:10]}.com.br",
                telefone=lead.telefone or '(67) 99999-9999',
                documento=lead.documento or '00.000.000/0001-00',
                cep=lead.cep or '79000-000',
                logradouro=lead.logradouro or 'Rua de Acesso',
                numero=lead.numero or 'S/N',
                complemento=lead.complemento,
                bairro=lead.bairro,
                cidade=lead.cidade,
                estado=lead.estado,
                ativo=True,
                observacoes=f"Cliente convertido via Prospecção Geo-Localizada. Dor anterior: {lead.dor_principal or 'N/A'}"
            )
            db.session.add(novo_cliente)
            db.session.flush()

        # 2. Cria o Pedido da Assinatura
        prefixo = f"NET-{datetime.utcnow().year}"
        ultimo_pedido = Pedido.query.filter(Pedido.numero_pedido.like(f"{prefixo}-%")).order_by(Pedido.id.desc()).first()
        if ultimo_pedido:
            try:
                seq = int(ultimo_pedido.numero_pedido.split('-')[-1]) + 1
            except ValueError:
                seq = 1
        else:
            seq = 1
        num_pedido = f"{prefixo}-{seq:04d}"

        valor = float(lead.valor_mensal_sugerido or (plano.valor_mensal if plano else 139.90))
        plano_id_val = plano.id if plano else None

        if plano:
            desc_pedido = f"Assinatura Mensal {plano.nome} ({plano.velocidade_formatada}) - {plano.roteador_wifi or 'Instalação Inclusa com Wi-Fi 6'}"
            desc_item = f"Mensalidade {plano.nome} ({plano.velocidade_formatada})"
        else:
            desc_pedido = f"Assinatura Mensal {lead.plano_sugerido} - Instalação Inclusa com Roteador Wi-Fi 6"
            desc_item = f"Mensalidade {lead.plano_sugerido} (Instalação + Wi-Fi 6 em comodato)"

        pedido = Pedido(
            numero_pedido=num_pedido,
            cliente_id=novo_cliente.id,
            plano_id=plano_id_val,
            status='processando',
            metodo_pagamento='pix',
            valor_total=valor,
            descricao=desc_pedido,
            observacoes="Ativação inicial de fibra óptica DigitalNet MS."
        )
        db.session.add(pedido)
        db.session.flush()

        # 3. Item do Pedido
        item = ItemPedido(
            pedido_id=pedido.id,
            descricao=desc_item,
            quantidade=1.0,
            valor_unitario=valor,
            valor_total=valor
        )
        db.session.add(item)

        # 4. Atualiza o status do Lead
        lead.status = 'convertido'
        lead.optin_status = 'aceito'
        lead.cliente_convertido_id = novo_cliente.id
        db.session.commit()

        return novo_cliente

    @staticmethod
    def get_objection_tutor(objection_key: str, lead: Lead) -> Dict[str, Any]:
        """Tutor de contorno de objeções com técnicas psicológicas."""
        bairro = lead.bairro or 'seu bairro'
        operadora = lead.operadora_atual or 'concorrência'
        plano = lead.plano_sugerido or 'Fibra com Wi-Fi 6'

        tutores = {
            'fidelidade': {
                'titulo': 'Objeção: "Ainda tenho contrato de fidelidade com a Vivo/Claro"',
                'diagnostico': 'O cliente tem medo de pagar multa rescisória e ficar no prejuízo.',
                'tecnica': 'Ponte de Transição / Teste em Paralelo',
                'script_whatsapp': (
                    f"Entendo perfeitamente! Ninguém gosta de pagar multas desnecessárias.\n\n"
                    f"O que muitos clientes aqui do {bairro} fazem é instalar a DigitalNet nos últimos 60 dias da fidelidade como 'link de segurança', "
                    f"aproveitando a nossa condição de R$ 99,90 nos primeiros 3 meses. Assim você não fica sem internet se a {operadora} cair "
                    f"e faz a transição 100% suave sem pagar multa. Que tal agendarmos a viabilidade?"
                ),
            },
            'preco': {
                'titulo': 'Objeção: "Achei o valor um pouco acima do que pago hoje"',
                'diagnostico': 'O cliente está comparando preço nominal de plano antigo sem perceber que tem metade da velocidade e Wi-Fi obsoleto.',
                'tecnica': 'Custo por Mega & Custo de Queda',
                'script_whatsapp': (
                    f"Compreendo! Se olharmos só o valor final parece similar, mas na prática você está pagando mais caro por Mega.\n\n"
                    f"Na DigitalNet você recebe {plano} com dobro de upload e roteador Wi-Fi 6 de alta densidade incluso em comodato (que a concorrência cobra R$ 25/mês de aluguel). "
                    f"Além disso, uma única hora sem internet na sua operação custa muito mais que a diferença de mensalidade. Faz sentido dar uma olhada na comparação?"
                ),
            },
            'marca': {
                'titulo': 'Objeção: "Nunca ouvi falar da DigitalNet, prefiro as grandes teles"',
                'diagnostico': 'Insegurança em relação à estabilidade e suporte.',
                'tecnica': 'Autoridade Local + Atendimento Humanizado',
                'script_whatsapp': (
                    f"Ótimo ponto! A grande diferença é que a DigitalNet é uma operadora com rede própria autorizada pela Anatel (AS61588) e mais de 700 condomínios atendidos em Campo Grande.\n\n"
                    f"Enquanto nas teles nacionais você fala com robôs no 0800 e espera 3 dias por um técnico de fora, a nossa equipe de suporte é 100% própria, local e 24h aqui na cidade. "
                    f"Se precisar de suporte, o técnico chega no mesmo dia. Vale a pena testar a estabilidade local!"
                ),
            },
            'satisfeito': {
                'titulo': 'Objeção: "Minha internet atual já me atende, não quero mexer"',
                'diagnostico': 'Acomodação até que ocorra uma queda crítica.',
                'tecnica': 'Pergunta de Tensão Construtiva',
                'script_whatsapp': (
                    f"Excelente saber que está funcionando! Posso te fazer uma pergunta rápida de 30 segundos?\n\n"
                    f"Quando a sua internet atual oscila nos horários de pico, qual é o plano de contingência da {lead.empresa} para não parar os computadores e maquininhas? "
                    f"A DigitalNet pode ficar como sua rota principal com Wi-Fi 6 de alta velocidade para que sua equipe nunca mais sofra lentidão. Posso te passar um comparativo?"
                ),
            },
        }

        return tutores.get(objection_key, tutores['fidelidade'])
