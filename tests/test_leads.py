import html
import json
import unittest
from app import create_app
from app.config import Config
from app.extensions import db
from app.models.user import User
from app.models.cliente import Cliente
from app.models.pedido import Pedido, ItemPedido
from app.models.lead import Lead
from app.models.plano import Plano
from app.services.prospector import TelecomProspectorService


class TestConfig(Config):
    TESTING = True
    SQLALCHEMY_DATABASE_URI = 'sqlite:///:memory:'
    WTF_CSRF_ENABLED = False


class LeadsTestCase(unittest.TestCase):
    def setUp(self):
        self.app = create_app(TestConfig)
        self.client = self.app.test_client()
        self.app_context = self.app.app_context()
        self.app_context.push()
        db.create_all()

        # Seed initial plans
        Plano.seed_planos_iniciais()

        # Create a test user
        user = User(nome='Vendedor Telecom', username='vendedor', email='vendedor@digitalnet.local')
        user.set_password('senha12345')
        db.session.add(user)

        # Create sample active client in Chácara Cachoeira, Campo Grande
        cliente = Cliente(
            nome='Consultório Dr. Marcelo',
            email='marcelo@consultorio.com.br',
            telefone='(67) 99111-2233',
            cep='79040-010',
            logradouro='Rua Raul Pires Barbosa',
            numero='100',
            bairro='Chácara Cachoeira',
            cidade='Campo Grande',
            estado='MS',
            ativo=True
        )
        db.session.add(cliente)
        db.session.commit()
        self.cliente_id = cliente.id

    def tearDown(self):
        db.session.remove()
        db.drop_all()
        self.app_context.pop()

    def login(self):
        return self.client.post('/auth/login', data={
            'login': 'vendedor',
            'password': 'senha12345'
        }, follow_redirects=True)

    def test_neighborhood_clusters_detection(self):
        clusters = TelecomProspectorService.get_neighborhood_clusters()
        self.assertGreater(len(clusters), 0)
        # Should have detected Chácara Cachoeira as having active clients
        chacara = next((c for c in clusters if c['bairro'] == 'Chácara Cachoeira'), None)
        self.assertIsNotNone(chacara)
        self.assertEqual(chacara['total_clientes'], 1)

    def test_prospect_neighborhood_and_anti_ban_generation(self):
        prospects = TelecomProspectorService.prospect_neighborhood(
            bairro='Chácara Cachoeira',
            cidade='Campo Grande',
            estado='MS',
            count=3
        )
        self.assertEqual(len(prospects), 3)

        salvos = TelecomProspectorService.save_prospects(prospects, cliente_ref_id=self.cliente_id)
        self.assertEqual(len(salvos), 3)

        lead = salvos[0]
        self.assertIn('Chácara Cachoeira', lead.bairro)
        self.assertIsNotNone(lead.icebreaker_optin)
        # Anti-ban rules check:
        # 1) Mentions neighborhood
        self.assertIn('Chácara Cachoeira', lead.icebreaker_optin)
        # 2) Contains opt-in question
        self.assertTrue('Posso te enviar' in lead.icebreaker_optin or 'opt-in' in lead.icebreaker_optin.lower())
        # 3) WhatsApp URL ready
        self.assertTrue(lead.whatsapp_url.startswith('https://wa.me/'))

    def test_no_duplicate_leads_on_consecutive_prospecting(self):
        # Primeira rodada de prospecção na Chácara Cachoeira
        p1 = TelecomProspectorService.prospect_neighborhood(
            bairro='Chácara Cachoeira',
            cidade='Campo Grande',
            count=3
        )
        salvos_1 = TelecomProspectorService.save_prospects(p1, cliente_ref_id=self.cliente_id)
        self.assertEqual(len(salvos_1), 3)

        # Segunda rodada consecutiva no mesmo bairro
        p2 = TelecomProspectorService.prospect_neighborhood(
            bairro='Chácara Cachoeira',
            cidade='Campo Grande',
            count=3
        )
        salvos_2 = TelecomProspectorService.save_prospects(p2, cliente_ref_id=self.cliente_id)
        self.assertEqual(len(salvos_2), 3)

        # Garante que não houve empresas repetidas
        empresas_1 = {l.empresa.lower() for l in salvos_1}
        empresas_2 = {l.empresa.lower() for l in salvos_2}
        self.assertEqual(len(empresas_1.intersection(empresas_2)), 0)

        # Terceira rodada em outro bairro (Centro)
        p3 = TelecomProspectorService.prospect_neighborhood(
            bairro='Centro',
            cidade='Campo Grande',
            count=3
        )
        salvos_3 = TelecomProspectorService.save_prospects(p3, cliente_ref_id=self.cliente_id)
        self.assertEqual(len(salvos_3), 3)
        empresas_3 = {l.empresa.lower() for l in salvos_3}
        self.assertEqual(len(empresas_1.intersection(empresas_3)), 0)
        self.assertEqual(len(empresas_2.intersection(empresas_3)), 0)

        # Tentativa de salvar os mesmos dados novamente não deve duplicar nenhum registro
        salvos_duplicados = TelecomProspectorService.save_prospects(p1, cliente_ref_id=self.cliente_id)
        self.assertEqual(len(salvos_duplicados), 0)

    def test_convert_lead_to_client_and_order(self):
        lead = Lead(
            nome='Dra. Vanessa Mendes',
            empresa='Clínica Odonto Prime',
            cargo='Diretora Clínica',
            telefone='(67) 99888-7766',
            email='contato@odontoprime.com.br',
            logradouro='Rua Raul Pires Barbosa',
            numero='550',
            bairro='Chácara Cachoeira',
            cidade='Campo Grande',
            estado='MS',
            cep='79040-010',
            plano_sugerido='Fibra 700 + DigiMesh (Wi-Fi 6)',
            valor_mensal_sugerido=139.90,
            status='novo',
            optin_status='pendente'
        )
        db.session.add(lead)
        db.session.commit()

        # Convert to client
        cliente = TelecomProspectorService.convert_lead_to_client(lead)
        self.assertIsNotNone(cliente.id)
        self.assertEqual(lead.status, 'convertido')
        self.assertEqual(lead.optin_status, 'aceito')
        self.assertEqual(lead.cliente_convertido_id, cliente.id)

        # Check created order
        pedido = Pedido.query.filter_by(cliente_id=cliente.id).first()
        self.assertIsNotNone(pedido)
        self.assertEqual(pedido.valor_total, 139.90)
        self.assertEqual(len(pedido.itens), 1)
        self.assertIn('Fibra 700 + DigiMesh', pedido.itens[0].descricao)
        # Verifica vínculo automático ao modelo Plano
        self.assertIsNotNone(pedido.plano_id)
        self.assertEqual(pedido.plano.nome, 'Fibra 700 + DigiMesh')

    def test_convert_lead_with_explicit_plano_and_web_route(self):
        plano_dedicado = Plano.query.filter_by(nome='DigiCorp Elite').first()
        self.assertIsNotNone(plano_dedicado)

        lead = Lead(
            nome='Dr. Carlos Silveira',
            empresa='Hospital Regional Especialidades',
            cargo='Superintendente de TI',
            telefone='(67) 99777-6655',
            email='ti@hospitalregional.med.br',
            logradouro='Avenida Afonso Pena',
            numero='1800',
            bairro='Centro',
            cidade='Campo Grande',
            estado='MS',
            cep='79002-070',
            plano_sugerido='Plano Desconhecido Inicial',
            valor_mensal_sugerido=plano_dedicado.valor_mensal,
            status='novo',
            optin_status='pendente'
        )
        db.session.add(lead)
        db.session.commit()

        # 1. Conversão direta no serviço com plano explícito
        cliente = TelecomProspectorService.convert_lead_to_client(lead, plano=plano_dedicado)
        self.assertIsNotNone(cliente.id)
        pedido = Pedido.query.filter_by(cliente_id=cliente.id).first()
        self.assertIsNotNone(pedido)
        self.assertEqual(pedido.plano_id, plano_dedicado.id)
        self.assertEqual(pedido.plano.nome, 'DigiCorp Elite')
        self.assertIn(pedido, plano_dedicado.pedidos)
        self.assertEqual(pedido.valor_total, plano_dedicado.valor_mensal)
        self.assertIn('DigiCorp Elite', pedido.itens[0].descricao)

        # 2. Conversão via rota HTTP POST com plano_id selecionado pelo vendedor
        self.login()
        lead2 = Lead(
            nome='Luciana Prado',
            empresa='Escola Construtiva',
            telefone='(67) 99123-4567',
            bairro='Santa Fé',
            cidade='Campo Grande',
            estado='MS',
            status='optin_aceito',
            optin_status='aceito'
        )
        db.session.add(lead2)
        db.session.commit()

        plano_fibra_900 = Plano.query.filter_by(nome='Fibra 900 Advanced').first()
        self.assertIsNotNone(plano_fibra_900)

        res_conv = self.client.post(f'/leads/{lead2.id}/converter', data={
            'plano_id': str(plano_fibra_900.id),
            'valor_mensal_sugerido': '149.90'
        }, follow_redirects=False)

        # Deve redirecionar para a página do cliente criado
        self.assertEqual(res_conv.status_code, 302)
        self.assertIn('/clientes/', res_conv.headers['Location'])

        lead2_atualizado = db.session.get(Lead, lead2.id)
        self.assertEqual(lead2_atualizado.status, 'convertido')
        pedido2 = Pedido.query.filter_by(cliente_id=lead2_atualizado.cliente_convertido_id).first()
        self.assertIsNotNone(pedido2)
        self.assertEqual(pedido2.plano_id, plano_fibra_900.id)
        self.assertEqual(pedido2.plano.nome, 'Fibra 900 Advanced')
        self.assertEqual(pedido2.valor_total, 149.90)

    def test_leads_web_routes(self):
        self.login()

        # GET /leads/
        res = self.client.get('/leads/')
        self.assertEqual(res.status_code, 200)
        self.assertIn('Radar de Prospecção', res.get_data(as_text=True))
        self.assertIn('Chácara Cachoeira', res.get_data(as_text=True))
        # Verifica que o mapa possui suporte a fullscreen e nó de fibra
        self.assertIn('id="cardMapaCalor"', res.get_data(as_text=True))
        self.assertIn('btnToggleFullscreenMap', res.get_data(as_text=True))
        self.assertIn('toggleFullscreenMapa', res.get_data(as_text=True))
        self.assertIn('carregarEmpresasDoNodo', res.get_data(as_text=True))
        self.assertIn('offcanvasNodoEmpresas', res.get_data(as_text=True))
        # Verifica que o mapa não possui mais a URL do Carto que causava a marca d'água de API Key
        self.assertNotIn('cartocdn.com', res.get_data(as_text=True))

        # Testa injeção da chave do Mapbox
        self.app.config['MAPBOX_API_KEY'] = 'pk.test_mapbox_secret_123'
        res_with_key = self.client.get('/leads/')
        self.assertEqual(res_with_key.status_code, 200)
        self.assertIn('pk.test_mapbox_secret_123', res_with_key.get_data(as_text=True))
        self.assertIn('Mapbox Ativo', res_with_key.get_data(as_text=True))

        # POST /leads/prospectar
        res_post = self.client.post('/leads/prospectar', data={
            'bairro': 'Santa Fé',
            'cidade': 'Campo Grande',
            'count': '2'
        }, follow_redirects=True)
        self.assertEqual(res_post.status_code, 200)
        self.assertIn('Santa Fé', res_post.get_data(as_text=True))

        # Check detail page
        lead = Lead.query.first()
        self.assertIsNotNone(lead)
        res_detail = self.client.get(f'/leads/{lead.id}')
        self.assertEqual(res_detail.status_code, 200)
        self.assertIn(lead.empresa, html.unescape(res_detail.get_data(as_text=True)))
        self.assertIn('Abordagem WhatsApp com Opt-in Anti-Ban', res_detail.get_data(as_text=True))

        # POST /leads/<id>/status
        res_status = self.client.post(f'/leads/{lead.id}/status', data={
            'status': 'optin_aceito',
            'optin_status': 'aceito'
        }, follow_redirects=True)
        self.assertEqual(res_status.status_code, 200)
        updated_lead = db.session.get(Lead, lead.id)
        self.assertEqual(updated_lead.optin_status, 'aceito')

    def test_leads_api_endpoints(self):
        self.login()

        # GET /leads/api/clusters
        res = self.client.get('/leads/api/clusters')
        self.assertEqual(res.status_code, 200)
        data = res.get_json()
        self.assertTrue(data['success'])
        self.assertIsInstance(data['clusters'], list)

        # POST /leads/api/prospectar
        res_prospect = self.client.post('/leads/api/prospectar', json={
            'bairro': 'Centro',
            'cidade': 'Campo Grande',
            'count': 2
        })
        self.assertEqual(res_prospect.status_code, 200)
        data_p = res_prospect.get_json()
        self.assertTrue(data_p['success'])
        self.assertGreaterEqual(data_p['count'], 1)

        # GET /leads/api/nodo/<bairro>/empresas
        res_nodo = self.client.get('/leads/api/nodo/Chácara%20Cachoeira/empresas?lat=-20.455&lng=-54.582&limite=3')
        self.assertEqual(res_nodo.status_code, 200)
        data_nodo = res_nodo.get_json()
        self.assertTrue(data_nodo['success'])
        self.assertEqual(data_nodo['bairro'], 'Chácara Cachoeira')
        self.assertIsInstance(data_nodo['empresas'], list)
        self.assertGreaterEqual(len(data_nodo['empresas']), 1)
        primeira_emp = data_nodo['empresas'][0]
        self.assertIn('empresa', primeira_emp)
        self.assertIn('lead_score', primeira_emp)
        self.assertIn('lat', primeira_emp)
        self.assertIn('lng', primeira_emp)
        self.assertIn('whatsapp_url', primeira_emp)

    def test_leads_api_geojson_layers(self):
        # Deve exigir login
        res_anon = self.client.get('/leads/api/geojson/bairros')
        self.assertIn(res_anon.status_code, (302, 401))

        self.login()

        # Camada de Bairros
        res_bairros = self.client.get('/leads/api/geojson/bairros')
        self.assertEqual(res_bairros.status_code, 200)
        geo_bairros = res_bairros.get_json()
        self.assertEqual(geo_bairros.get('type'), 'FeatureCollection')
        self.assertGreater(len(geo_bairros.get('features', [])), 0)
        self.assertIn('bairro', geo_bairros['features'][0]['properties'])

        # Camada de Macrozonas
        res_macro = self.client.get('/leads/api/geojson/macrozonas')
        self.assertEqual(res_macro.status_code, 200)
        geo_macro = res_macro.get_json()
        self.assertEqual(geo_macro.get('type'), 'FeatureCollection')
        self.assertGreater(len(geo_macro.get('features', [])), 0)

        # Camada de Parcelamentos
        res_parc = self.client.get('/leads/api/geojson/parcelamentos')
        self.assertEqual(res_parc.status_code, 200)
        geo_parc = res_parc.get_json()
        self.assertEqual(geo_parc.get('type'), 'FeatureCollection')
        self.assertGreater(len(geo_parc.get('features', [])), 0)

        # Camada inexistente deve retornar 404
        res_404 = self.client.get('/leads/api/geojson/camada_inexistente')
        self.assertEqual(res_404.status_code, 404)

    def test_perfis_campo_grande_sisgran_enrichment(self):
        from app.services.prospector import PERFIS_CAMPO_GRANDE, COORDENADAS_BAIRROS

        # Deve conter todos os 74 bairros oficiais do SISGRAN
        self.assertGreaterEqual(len(COORDENADAS_BAIRROS), 74)
        self.assertGreaterEqual(len(PERFIS_CAMPO_GRANDE), 74)

        # Bairros de diferentes regiões urbanas devem estar presentes com metadados do SISGRAN
        amambai = TelecomProspectorService.get_bairro_profile('Amambaí')
        self.assertEqual(amambai['regiao_urbana'].upper(), 'CENTRO')
        self.assertIn('MZ 1', amambai['macrozona'])
        self.assertIsInstance(amambai['parcelamentos'], list)

        aero_rancho = TelecomProspectorService.get_bairro_profile('aero rancho')
        self.assertEqual(aero_rancho['regiao_urbana'].upper(), 'ANHANDUIZINHO')
        self.assertIn('MZ 2', aero_rancho['macrozona'])
        self.assertGreater(len(aero_rancho['parcelamentos']), 0)

        # Resolução de coordenadas deve funcionar com acento ou sem acento
        coords_com_acento = TelecomProspectorService.get_bairro_coordenadas('Chácara Cachoeira')
        coords_sem_acento = TelecomProspectorService.get_bairro_coordenadas('chacara cachoeira')
        self.assertEqual(coords_com_acento, coords_sem_acento)
        self.assertAlmostEqual(coords_com_acento[0], -20.4578, delta=0.01)

        # Resolução por nome de parcelamento/vila contida no bairro
        perfil_por_vila = TelecomProspectorService.get_bairro_profile('Vila Nogueira')
        self.assertEqual(perfil_por_vila['nome_oficial'], 'CENTENÁRIO')

    def test_aisa_api_endpoints_and_pitch(self):
        self.login()

        # Status da AIsa
        res_status = self.client.get('/leads/api/aisa/status')
        self.assertEqual(res_status.status_code, 200)
        data_status = res_status.get_json()
        self.assertTrue(data_status['success'])
        self.assertIn('active_provider', data_status)
        self.assertIn('aisa_model', data_status)

        # Validação sem lead_id deve retornar 400
        res_pitch_invalido = self.client.post('/leads/api/aisa/pitch', json={})
        self.assertEqual(res_pitch_invalido.status_code, 400)

        # Geração de pitch consultivo para lead real
        lead = Lead(
            nome='Dr. Carlos Santana',
            empresa='Clínica Oftalmo Campo Grande',
            cargo='Diretor Clínico',
            telefone='(67) 99222-3344',
            bairro='Centro',
            cidade='Campo Grande',
            estado='MS',
            dor_principal='Queda frequente de link nas cirurgias e consultas',
            plano_sugerido='DigitalNet B2B Link Dedicado Pro',
            valor_mensal_sugerido=399.90
        )
        db.session.add(lead)
        db.session.commit()

        res_pitch = self.client.post('/leads/api/aisa/pitch', json={'lead_id': lead.id, 'channel': 'whatsapp'})
        self.assertEqual(res_pitch.status_code, 200)
        pitch_json = res_pitch.get_json()
        self.assertTrue(pitch_json['success'])
        self.assertIn('pitch', pitch_json)
        self.assertIn('message', pitch_json['pitch'])

    def test_aisa_prospector_mocked(self):
        from unittest.mock import patch, MagicMock
        import io

        mock_aisa_response = {
            'choices': [{
                'message': {
                    'content': json.dumps({
                        'leads': [{
                            'company_name': 'Hospital de Olhos MS',
                            'contact_name': 'Dr. Eduardo Fontes',
                            'cargo': 'Diretor Técnico',
                            'phone': '(67) 99888-1122',
                            'email': 'contato@olhosms.com.br',
                            'address': 'Rua Rui Barbosa',
                            'numero': '300',
                            'cep': '79002-000',
                            'operadora_atual': 'Vivo Fibra',
                            'plano_sugerido': 'DigitalNet B2B Link Dedicado Pro',
                            'valor_mensal_sugerido': 399.90,
                            'score': 96,
                            'description': 'Necessidade de link redundante e baixa latência.',
                            'icebreaker_optin': 'Olá Dr. Eduardo, podemos enviar um comparativo de fibra dedicada?'
                        }]
                    })
                }
            }]
        }

        mock_resp = MagicMock()
        mock_resp.read.return_value = json.dumps(mock_aisa_response).encode('utf-8')
        mock_resp.__enter__.return_value = mock_resp
        mock_resp.__exit__.return_value = False

        with patch('urllib.request.urlopen', return_value=mock_resp):
            with patch.dict(self.app.config, {'AISA_API_KEY': 'test-aisa-key-123'}):
                leads = TelecomProspectorService.prospect_neighborhood(
                    bairro='Centro',
                    cidade='Campo Grande',
                    count=1
                )
                self.assertEqual(len(leads), 1)
                self.assertEqual(leads[0]['empresa'], 'Hospital de Olhos MS')
                self.assertEqual(leads[0]['cargo'], 'Diretor Técnico')
                self.assertEqual(leads[0]['lead_score'], 96)

