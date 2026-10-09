import unittest
from app import create_app
from app.config import Config
from app.extensions import db
from app.models.user import User
from app.models.cliente import Cliente
from app.models.pedido import Pedido, ItemPedido
from app.models.lead import Lead
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

    def test_leads_web_routes(self):
        self.login()

        # GET /leads/
        res = self.client.get('/leads/')
        self.assertEqual(res.status_code, 200)
        self.assertIn('Radar de Prospecção', res.get_data(as_text=True))
        self.assertIn('Chácara Cachoeira', res.get_data(as_text=True))

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
        self.assertIn(lead.empresa, res_detail.get_data(as_text=True))
        self.assertIn('Abordagem WhatsApp com Opt-in Anti-Ban', res_detail.get_data(as_text=True))

        # POST /leads/<id>/status
        res_status = self.client.post(f'/leads/{lead.id}/status', data={
            'status': 'optin_aceito',
            'optin_status': 'aceito'
        }, follow_redirects=True)
        self.assertEqual(res_status.status_code, 200)
        updated_lead = Lead.query.get(lead.id)
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
