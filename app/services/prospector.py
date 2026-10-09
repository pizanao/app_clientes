from datetime import datetime
import json
import logging
import os
import random
import re
import urllib.parse
import urllib.request
from typing import Dict, List, Any, Optional
from flask import current_app
from app.extensions import db
from app.models.cliente import Cliente
from app.models.lead import Lead
from app.models.pedido import Pedido, ItemPedido

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

# Ruas e perfis de empresas em Campo Grande - MS para Fallback
PERFIS_CAMPO_GRANDE = {
    'Chácara Cachoeira': {
        'ruas': ['Rua Raul Pires Barbosa', 'Rua Afonso Pena', 'Rua Jeribá', 'Rua Dr. Paulo Machado'],
        'cep_prefix': '79040',
        'nichos': ['Clínicas Médicas & Odontológicas', 'Escritórios de Advocacia', 'Coworkings & Startups', 'Consultórios'],
    },
    'Centro': {
        'ruas': ['Rua 14 de Julho', 'Avenida Calógeras', 'Rua Dom Aquino', 'Rua Barão do Rio Branco'],
        'cep_prefix': '79002',
        'nichos': ['Comércio & Varejo', 'Escritórios de Contabilidade', 'Imobiliárias', 'Restaurantes & Lanchonetes'],
    },
    'Santa Fé': {
        'ruas': ['Rua Ceará', 'Rua Abrão Júlio Rahe', 'Rua Alagoas', 'Rua Goiás'],
        'cep_prefix': '79021',
        'nichos': ['Clínicas de Estética', 'Escritórios Corporativos', 'Agências de Marketing', 'Boutiques'],
    },
    'Jardim dos Estados': {
        'ruas': ['Rua Euclides da Cunha', 'Rua Rio Grande do Sul', 'Rua Bahia', 'Avenida Mato Grosso'],
        'cep_prefix': '79020',
        'nichos': ['Escritórios Executivos', 'Restaurantes Gastronômicos', 'Centros Médicos', 'Empresas de TI'],
    },
    'Tiradentes': {
        'ruas': ['Avenida Marquês de Pombal', 'Rua José Nogueira Vieira', 'Avenida Três Barras'],
        'cep_prefix': '79041',
        'nichos': ['Supermercados & Farmácias', 'Auto Centers', 'Academias', 'Escolas & Cursos'],
    },
    'Vilas Boas': {
        'ruas': ['Avenida Bom Pastor', 'Rua Domingos Jorge Velho', 'Rua Cel. Salustiano'],
        'cep_prefix': '79051',
        'nichos': ['Gastronomia & Restaurantes', 'Lojas de Conveniência', 'Pet Shops & Veterinárias'],
    },
}

# Coordenadas geográficas reais dos bairros de Campo Grande - MS para o Mapa de Calor
COORDENADAS_BAIRROS = {
    'Chácara Cachoeira': (-20.4578, -54.5824),
    'Centro': (-20.4628, -54.6156),
    'Santa Fé': (-20.4485, -54.5952),
    'Jardim dos Estados': (-20.4552, -54.6063),
    'Tiradentes': (-20.4682, -54.5615),
    'Vilas Boas': (-20.4851, -54.5889),
    'Bela Vista': (-20.4720, -54.5900),
    'Copacabana': (-20.4900, -54.6300),
}


class TelecomProspectorService:
    COORDENADAS_BAIRROS = COORDENADAS_BAIRROS

    @staticmethod
    def get_neighborhood_clusters() -> List[Dict[str, Any]]:
        """
        Agrupa clientes existentes por bairro e cidade para identificar
        onde a DigitalNet já possui infraestrutura óptica instalada (CTO/Cabos).
        """
        clientes = Cliente.query.filter_by(ativo=True).all()
        clusters_map: Dict[str, Dict[str, Any]] = {}

        for c in clientes:
            bairro = (c.bairro or 'Centro').strip()
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
            # Conta leads já cadastrados nessa região
            total_leads = Lead.query.filter_by(bairro=bairro).count()
            leads_convertidos = Lead.query.filter_by(bairro=bairro, status='convertido').count()

            coords = COORDENADAS_BAIRROS.get(bairro, (-20.4697, -54.6201))
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
    def prospect_neighborhood(
        cls,
        bairro: str,
        cidade: str = 'Campo Grande',
        estado: str = 'MS',
        niche: str = 'Empresas e Comércios',
        count: int = 5,
        cliente_ref_id: Optional[int] = None
    ) -> List[Dict[str, Any]]:
        """
        Gera leads vizinhos qualificados na mesma região dos clientes.
        Tenta chamar o Google Gemini se GEMINI_API_KEY estiver configurado;
        caso contrário, usa o motor heurístico local hiper-realista.
        """
        api_key = current_app.config.get('GEMINI_API_KEY')
        if api_key:
            try:
                leads_ai = cls._call_gemini_prospector(bairro, cidade, estado, niche, count, api_key)
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

        url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key={api_key}"
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
                return dados
        return []

    @classmethod
    def _generate_fallback_prospects(
        cls,
        bairro: str,
        cidade: str,
        estado: str,
        niche: str,
        count: int
    ) -> List[Dict[str, Any]]:
        """Motor heurístico de telecomunicações para Campo Grande."""
        info_bairro = PERFIS_CAMPO_GRANDE.get(bairro, {
            'ruas': ['Avenida Principal', 'Rua Central', 'Rua das Palmeiras'],
            'cep_prefix': '79000',
            'nichos': ['Comércio & Serviços', 'Consultórios', 'Escritórios'],
        })

        ruas = info_bairro['ruas']
        cep_prefix = info_bairro['cep_prefix']

        templates_empresas = [
            {
                'empresa_tpl': 'Clínica Integrada {sobrenome}',
                'contato': 'Dra. Patricia {sobrenome}',
                'cargo': 'Diretora Clínica',
                'dor': 'Lentidão no sistema de agendamento online e máquinas de cartão travando em horários de pico.',
                'operadora': 'Vivo Fibra',
                'plano': 'Fibra 700 + DigiMesh (Wi-Fi 6)',
                'valor': 139.90,
                'score': 92,
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
                'empresa_tpl': 'Studio & Boutique {sobrenome}',
                'contato': 'Camila {sobrenome}',
                'cargo': 'Sócia Proprietária',
                'dor': 'Wi-Fi da operadora atual não cobre a recepção e o estoque; sinal fraco para clientes.',
                'operadora': 'Vivo Fibra',
                'plano': 'Fibra 700 + DigiMesh (Wi-Fi 6)',
                'valor': 139.90,
                'score': 88,
            },
            {
                'empresa_tpl': '{sobrenome} Contabilidade & Gestão',
                'contato': 'Carlos Roberto {sobrenome}',
                'cargo': 'Contador Responsável',
                'dor': 'Falta de suporte aos finais de semana e suporte telefônico via robô 0800 quando cai o sinal.',
                'operadora': 'Claro NET',
                'plano': 'Fibra 900 Advanced (Wi-Fi 6)',
                'valor': 149.90,
                'score': 90,
            },
            {
                'empresa_tpl': 'Espaço Saúde & Bem-Estar {sobrenome}',
                'contato': 'Juliana {sobrenome}',
                'cargo': 'Gerente Geral',
                'dor': 'Cobrança alta de fatura na fatura atual sem entrega da velocidade contratada.',
                'operadora': 'Vivo Fibra',
                'plano': 'Fibra 600 Standard (Wi-Fi 6)',
                'valor': 129.90,
                'score': 84,
            },
            {
                'empresa_tpl': 'Restaurante & Café {sobrenome}',
                'contato': 'Fernando {sobrenome}',
                'cargo': 'Proprietário',
                'dor': 'Queda no link de dados afeta o tablet de pedidos dos garçons e a emissão de cupons fiscais.',
                'operadora': 'Claro NET',
                'plano': 'Fibra 700 + DigiMesh (Wi-Fi 6)',
                'valor': 139.90,
                'score': 91,
            },
        ]

        sobrenomes = ['Albuquerque', 'Mendes', 'Fontana', 'Vasconcelos', 'Barreto', 'Nogueira', 'Pires', 'Ribeiro']
        resultado = []

        for i in range(min(count, len(templates_empresas))):
            t = templates_empresas[i]
            sobrenome = sobrenomes[i % len(sobrenomes)]
            empresa = t['empresa_tpl'].format(sobrenome=sobrenome)
            nome_contato = t['contato'].format(sobrenome=sobrenome)
            rua = ruas[i % len(ruas)]
            num = str(100 + i * 85)
            tel = f"(67) 9{random.randint(9100, 9999)}-{random.randint(1000, 9999)}"
            email_empresa = f"contato@{re.sub(r'[^a-z0-9]', '', empresa.lower())[:14]}.com.br"
            cep = f"{cep_prefix}-{random.randint(100, 999):03d}"

            # Cria lead estruturado
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

            # Monta script de opt-in
            temp_lead = Lead(**lead_item)
            lead_item['icebreaker_optin'] = cls.generate_anti_ban_whatsapp_script(temp_lead)
            lead_item['dossie_comercial'] = json.dumps({
                'perfil_decisor': f"{nome_contato} ({t['cargo']}) busca estabilidade de rede e atendimento direto sem burocracia.",
                'vantagem_digitalnet': 'Fibra óptica com Wi-Fi 6 de alta densidade + suporte presencial 24h com equipe em Campo Grande.',
                'angulo_venda': f"Focar na eliminação da dor de '{t['dor']}' demonstrando que a DigitalNet já atende vizinhos nesta mesma rua.",
            }, ensure_ascii=False)

            resultado.append(lead_item)

        return resultado

    @classmethod
    def save_prospects(cls, prospects_data: List[Dict[str, Any]], cliente_ref_id: Optional[int] = None) -> List[Lead]:
        """Salva a lista de leads prospectados no banco de dados."""
        salvos = []
        for d in prospects_data:
            # Evita duplicidade exata de empresa + bairro
            existente = Lead.query.filter_by(
                empresa=d['empresa'],
                bairro=d.get('bairro', 'Campo Grande')
            ).first()

            if existente:
                continue

            lead = Lead(
                empresa=d['empresa'],
                nome=d['nome'],
                cargo=d.get('cargo'),
                telefone=d.get('telefone'),
                email=d.get('email'),
                logradouro=d.get('logradouro'),
                numero=d.get('numero'),
                bairro=d.get('bairro', 'Centro'),
                cidade=d.get('cidade', 'Campo Grande'),
                estado=d.get('estado', 'MS'),
                cep=d.get('cep'),
                niche=d.get('niche', 'Geral'),
                cliente_referencia_id=cliente_ref_id,
                status='novo',
                optin_status='pendente',
                operadora_atual=d.get('operadora_atual', 'Vivo Fibra / Claro'),
                plano_sugerido=d.get('plano_sugerido', 'Fibra 700 + DigiMesh'),
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
    def convert_lead_to_client(cls, lead: Lead) -> Cliente:
        """
        Converte o lead em Cliente efetivo e cria automaticamente o Pedido
        da assinatura da DigitalNet MS com itens totalizados.
        """
        if lead.cliente_convertido_id:
            cliente_existente = Cliente.query.get(lead.cliente_convertido_id)
            if cliente_existente:
                return cliente_existente

        # 1. Cria o Cliente
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

        valor = float(lead.valor_mensal_sugerido or 139.90)
        pedido = Pedido(
            numero_pedido=num_pedido,
            cliente_id=novo_cliente.id,
            status='processando',
            metodo_pagamento='pix',
            valor_total=valor,
            descricao=f"Assinatura Mensal {lead.plano_sugerido} - Instalação Inclusa com Roteador Wi-Fi 6",
            observacoes="Ativação inicial de fibra óptica DigitalNet MS."
        )
        db.session.add(pedido)
        db.session.flush()

        # 3. Item do Pedido
        item = ItemPedido(
            pedido_id=pedido.id,
            descricao=f"Mensalidade {lead.plano_sugerido} (Instalação + Wi-Fi 6 em comodato)",
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
