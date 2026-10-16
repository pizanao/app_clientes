import json
import urllib.error
from unittest.mock import MagicMock

import pytest

from app.models.cliente import Cliente
from app.models.lead import Lead
from app.models.pedido import Pedido
from app.services.prospector import TelecomProspectorService


def _make_mock_http_response(payload: dict):
    """Return a context-managed HTTP response with a JSON payload."""
    mock_resp = MagicMock()
    mock_resp.read.return_value = json.dumps(payload).encode('utf-8')
    mock_resp.__enter__.return_value = mock_resp
    mock_resp.__exit__.return_value = False
    return mock_resp


def test_cascade_aisa_primary_success(app, monkeypatch):
    """A successful AIsa response is normalized and returned before other providers."""
    monkeypatch.setitem(app.config, 'AISA_API_KEY', 'aisa-valid-key')
    monkeypatch.setitem(app.config, 'GEMINI_API_KEY', '')
    payload = {
        'choices': [{
            'message': {
                'content': json.dumps({
                    'leads': [{
                        'company_name': 'DataCenter Pantanal Tech',
                        'contact_name': 'Eng. Lucas Prado',
                        'cargo': 'CTO',
                        'phone': '(67) 99111-2233',
                        'email': 'lucas@pantanaltech.com.br',
                        'address': 'Avenida Afonso Pena',
                        'numero': '4100',
                        'cep': '79020-000',
                        'operadora_atual': 'Vivo Fibra',
                        'plano_sugerido': 'Fibra B2B Link Dedicado Pro',
                        'valor_mensal_sugerido': 399.90,
                        'score': 98,
                        'description': 'Demanda de link dedicado redundante.',
                        'icebreaker_optin': 'Olá Lucas, podemos avaliar a redundância óptica?',
                    }]
                })
            }
        }]
    }
    monkeypatch.setattr(
        'urllib.request.urlopen',
        lambda req, timeout=25: _make_mock_http_response(payload),
    )

    leads = TelecomProspectorService.prospect_neighborhood(
        bairro='Jardim dos Estados', cidade='Campo Grande', count=1,
    )

    assert len(leads) == 1
    assert leads[0]['empresa'] == 'DataCenter Pantanal Tech'
    assert leads[0]['lead_score'] == 98
    assert leads[0]['bairro'] == 'Jardim dos Estados'


def test_cascade_failover_aisa_to_gemini(app, monkeypatch):
    """An AIsa HTTP failure falls through to the normalized Gemini result."""
    monkeypatch.setitem(app.config, 'AISA_API_KEY', 'aisa-failing-key')
    monkeypatch.setitem(app.config, 'GEMINI_API_KEY', 'gemini-valid-key')
    gemini_payload = {
        'candidates': [{
            'content': {
                'parts': [{
                    'text': json.dumps([{
                        'empresa': 'Laboratório BioExame MS',
                        'nome': 'Dra. Helena Costa',
                        'cargo': 'Diretora Técnica',
                        'telefone': '(67) 99333-4455',
                        'email': 'helena@bioexame.com.br',
                        'logradouro': 'Rua 15 de Novembro',
                        'numero': '890',
                        'cep': '79002-140',
                        'operadora_atual': 'Claro Fibra',
                        'plano_sugerido': 'Fibra B2B Link Dedicado Pro',
                        'valor_mensal_sugerido': 399.90,
                        'lead_score': 94,
                        'dor_principal': 'Lentidão no envio de laudos por imagem.',
                        'icebreaker_optin': 'Olá Dra. Helena, tudo bem?',
                    }])
                }]
            }
        }]
    }

    def fake_urlopen(req, timeout=20):
        url = req.full_url if hasattr(req, 'full_url') else str(req)
        if 'aisa.one' in url:
            raise urllib.error.HTTPError(url, 500, 'Internal Server Error', {}, None)
        return _make_mock_http_response(gemini_payload)

    monkeypatch.setattr('urllib.request.urlopen', fake_urlopen)
    leads = TelecomProspectorService.prospect_neighborhood(
        bairro='Centro', cidade='Campo Grande', count=1,
    )

    assert len(leads) == 1
    assert leads[0]['empresa'] == 'Laboratório BioExame MS'
    assert leads[0]['lead_score'] == 94


def test_cascade_failover_to_rfb_and_synthetic_complement(app, rfb_memory_seeded, monkeypatch):
    """RFB leads precede three synthetic complements when the requested count is five."""
    monkeypatch.setitem(app.config, 'AISA_API_KEY', '')
    monkeypatch.setitem(app.config, 'GEMINI_API_KEY', '')

    leads = TelecomProspectorService.prospect_neighborhood(
        bairro='Chácara Cachoeira', cidade='Campo Grande', count=5,
    )

    assert len(leads) == 5
    rfb_empresas = {
        'clinica medica pantanal ltda',
        'contabilidade exata ms ltda',
    }
    rfb_leads = [lead for lead in leads if lead['empresa'].casefold() in rfb_empresas]
    assert len(rfb_leads) == 2
    assert len([lead for lead in leads if lead not in rfb_leads]) == 3

    lead_clinica = next(lead for lead in rfb_leads if 'Clinica Medica Pantanal' in lead['empresa'])
    assert lead_clinica['telefone'] == '(67) 99123-4567'
    assert Lead(**lead_clinica).telefone_e164 == '+5567991234567'
    assert lead_clinica['logradouro'] == 'Raul Pires Barbosa'
    assert lead_clinica['numero'] == '1240'
    assert lead_clinica['complemento'] == 'SALA 02'


def test_save_prospects_global_deduplication(db_session):
    """Existing customers and case-insensitive duplicates do not become new leads."""
    db_session.add(Cliente(
        nome='Empresa Ja Cliente Ltda',
        email='cliente@existente.com',
        telefone='(67) 3322-1100',
        bairro='Centro',
        cidade='Campo Grande',
        estado='MS',
    ))
    db_session.commit()

    salvos = TelecomProspectorService.save_prospects([
        {'empresa': 'Empresa Ja Cliente Ltda', 'nome': 'Contato 1', 'telefone': '(67) 3322-1100', 'bairro': 'Centro'},
        {'empresa': 'Nova Oportunidade Optica Ltda', 'nome': 'Contato 2', 'telefone': '(67) 99111-2222', 'bairro': 'Centro'},
        {'empresa': 'nova oportunidade optica ltda', 'nome': 'Contato 2 Dup', 'telefone': '(67) 99111-2222', 'bairro': 'Centro'},
    ])

    assert len(salvos) == 1
    assert salvos[0].empresa == 'Nova Oportunidade Optica Ltda'


@pytest.mark.parametrize(('obj_key', 'termo_esperado'), [
    ('fidelidade', 'multa'),
    ('preco', 'custo'),
    ('ti_interna', 'fidelidade'),
])
def test_objection_tutors_return_actionable_copy(db_session, obj_key, termo_esperado):
    """Each recognized objection, plus the fallback, returns sales copy with its key argument."""
    lead = Lead(
        nome='Roberto Silva', empresa='Silva & Filhos Ltda', telefone='(67) 99123-4567',
        bairro='Centro', operadora_atual='Vivo Fibra',
        plano_sugerido='Fibra B2B Link Dedicado Pro', valor_mensal_sugerido=399.90,
    )

    tutor = TelecomProspectorService.get_objection_tutor(obj_key, lead)

    assert {'titulo', 'diagnostico', 'tecnica', 'script_whatsapp'} <= tutor.keys()
    texto_completo = ' '.join(tutor.values()).lower()
    assert termo_esperado in texto_completo


def test_anti_ban_script_requests_opt_in_and_offers_decline(db_session):
    """The native WhatsApp script personalizes the lead and explicitly requests consent."""
    lead = Lead(
        nome='Marina Souza', empresa='Studio Aurora', bairro='Centro',
        operadora_atual='Claro Fibra', plano_sugerido='Fibra 900 Advanced (Wi-Fi 6)',
    )

    script = TelecomProspectorService.generate_anti_ban_whatsapp_script(lead)

    assert 'Olá Marina' in script
    assert 'Studio Aurora' in script
    assert 'Posso te enviar' in script
    assert "responder 'Não'" in script


@pytest.mark.parametrize(('channel', 'tone'), [
    ('whatsapp', 'consultative'),
    ('whatsapp', 'direct'),
    ('whatsapp', 'urgent'),
    ('email', 'consultative'),
    ('email', 'direct'),
    ('email', 'urgent'),
])
def test_generate_pitch_returns_structured_native_pitch_for_each_channel_and_tone(app, db_session, channel, tone):
    """All supported pitch selections retain a personalized native opt-in fallback."""
    lead = Lead(
        nome='Marina Souza', empresa='Studio Aurora', bairro='Centro', cidade='Campo Grande',
        operadora_atual='Claro Fibra', plano_sugerido='Fibra 900 Advanced (Wi-Fi 6)',
        valor_mensal_sugerido=149.90,
    )

    pitch = TelecomProspectorService.generate_pitch(lead, channel=channel, tone=tone)

    assert {'subject', 'message', 'key_points', 'call_to_action', 'suggested_next_step'} <= pitch.keys()
    assert pitch['subject'] == 'Modernização de Fibra Óptica no Centro - Studio Aurora'
    assert 'Olá Marina' in pitch['message']
    assert pitch['call_to_action'].startswith('Posso te enviar')


def test_convert_lead_to_client_and_reuse_existing(db_session, sample_planos):
    """A second lead for the same company and email reuses its customer and adds an order."""
    lead1 = Lead(
        nome='Dr. Fernando Lima', empresa='Clínica OrtoMS Ltda', cargo='Diretor',
        telefone='(67) 99222-3344', email='contato@ortoms.com.br',
        logradouro='Rua Euclides da Cunha', numero='500', cep='79020-230',
        bairro='Jardim dos Estados', cidade='Campo Grande', estado='MS',
        plano_sugerido=sample_planos['pj'].nome, valor_mensal_sugerido=sample_planos['pj'].valor_mensal,
    )
    db_session.add(lead1)
    db_session.commit()

    cliente1 = TelecomProspectorService.convert_lead_to_client(lead1, plano=sample_planos['pj'])

    assert lead1.status == 'convertido'
    assert lead1.cliente_convertido_id == cliente1.id
    pedidos_cliente1 = Pedido.query.filter_by(cliente_id=cliente1.id).all()
    assert len(pedidos_cliente1) == 1
    assert pedidos_cliente1[0].plano_id == sample_planos['pj'].id
    assert abs(pedidos_cliente1[0].valor_total - 399.90) < 0.01

    lead2 = Lead(
        nome='Dr. Fernando Lima', empresa='Clínica OrtoMS Ltda', telefone='(67) 99222-3344',
        email='contato@ortoms.com.br', bairro='Jardim dos Estados',
        plano_sugerido=sample_planos['pf'].nome, valor_mensal_sugerido=sample_planos['pf'].valor_mensal,
    )
    db_session.add(lead2)
    db_session.commit()

    cliente2 = TelecomProspectorService.convert_lead_to_client(lead2, plano=sample_planos['pf'])

    assert cliente2.id == cliente1.id
    assert Pedido.query.filter_by(cliente_id=cliente1.id).count() == 2
