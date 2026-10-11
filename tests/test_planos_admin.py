import unittest
from app import create_app
from app.config import Config
from app.extensions import db
from app.models.user import User, Grupo, PERFIL_ADMIN, PERFIL_LIDER, PERFIL_AGENTE
from app.models.plano import Plano, TIPO_PF, TIPO_PJ


class TestConfig(Config):
    TESTING = True
    SQLALCHEMY_DATABASE_URI = 'sqlite:///:memory:'
    WTF_CSRF_ENABLED = False


class PlanosAdminTestCase(unittest.TestCase):
    def setUp(self):
        self.app = create_app(TestConfig)
        self.client = self.app.test_client()
        self.app_context = self.app.app_context()
        self.app_context.push()
        db.create_all()

        # Usuários para teste de permissão
        self.user_admin = User(
            nome='Admin Planos',
            username='admin_planos',
            email='admin.planos@digitalnetms.com.br',
            perfil=PERFIL_ADMIN,
            ativo=True
        )
        self.user_admin.set_password('Admin#2026')

        self.user_lider = User(
            nome='Líder Técnico',
            username='lider_planos',
            email='lider.planos@digitalnetms.com.br',
            perfil=PERFIL_LIDER,
            ativo=True
        )
        self.user_lider.set_password('Lider#2026')

        self.user_agente = User(
            nome='Agente Comercial',
            username='agente_planos',
            email='agente.planos@digitalnetms.com.br',
            perfil=PERFIL_AGENTE,
            ativo=True
        )
        self.user_agente.set_password('Agente#2026')

        db.session.add_all([self.user_admin, self.user_lider, self.user_agente])
        db.session.commit()

    def tearDown(self):
        db.session.remove()
        db.drop_all()
        self.app_context.pop()

    def _login(self, username, password):
        return self.client.post('/auth/login', data={
            'login': username,
            'password': password
        }, follow_redirects=True)

    def test_planos_acesso_negado_anonimo(self):
        """Usuário anônimo é redirecionado para a tela de login."""
        response = self.client.get('/admin/planos')
        self.assertEqual(response.status_code, 302)
        self.assertIn('/auth/login', response.headers.get('Location', ''))

    def test_planos_acesso_negado_agente_e_lider(self):
        """Agente e Líder Técnico recebem 403 Forbidden ao tentar gerenciar planos."""
        self._login('agente_planos', 'Agente#2026')
        resp_agente = self.client.get('/admin/planos')
        self.assertEqual(resp_agente.status_code, 403)

        self._login('lider_planos', 'Lider#2026')
        resp_lider = self.client.get('/admin/planos')
        self.assertEqual(resp_lider.status_code, 403)

    def test_planos_acesso_permitido_admin(self):
        """Administrador tem acesso completo ao catálogo de planos."""
        self._login('admin_planos', 'Admin#2026')
        response = self.client.get('/admin/planos')
        self.assertEqual(response.status_code, 200)
        self.assertIn('Catálogo de Planos de Banda Larga'.encode('utf-8'), response.data)

    def test_seed_planos_oficiais(self):
        """Verifica a carga dos 6 planos residenciais (PF) e 3 corporativos (PJ)."""
        total = Plano.seed_planos_iniciais()
        self.assertEqual(total, 9)

        planos_pf = Plano.query.filter_by(tipo=TIPO_PF).all()
        planos_pj = Plano.query.filter_by(tipo=TIPO_PJ).all()

        self.assertEqual(len(planos_pf), 6)
        self.assertEqual(len(planos_pj), 3)

        # Checa plano residencial representativo
        p700_mesh = Plano.query.filter_by(nome='Fibra 700 + DigiMesh').first()
        self.assertIsNotNone(p700_mesh)
        self.assertEqual(p700_mesh.velocidade_download, 700)
        self.assertEqual(p700_mesh.velocidade_upload, 350)
        self.assertEqual(p700_mesh.valor_mensal, 129.90)
        self.assertIn('DigiMesh', p700_mesh.roteador_wifi)

        # Checa plano corporativo representativo
        elite = Plano.query.filter_by(nome='DigiCorp Elite').first()
        self.assertIsNotNone(elite)
        self.assertEqual(elite.velocidade_download, 900)
        self.assertEqual(elite.valor_mensal, 399.90)
        self.assertEqual(elite.sla_horas, 12)
        self.assertTrue(elite.pabx_virtual)
        self.assertTrue(elite.ip_fixo)

    def test_criar_novo_plano_pf(self):
        """Testa o formulário de criação de um novo plano PF."""
        self._login('admin_planos', 'Admin#2026')

        dados = {
            'nome': 'Fibra 800 Gamer Pro',
            'tipo': TIPO_PF,
            'velocidade_download': 800,
            'velocidade_upload': 400,
            'valor_mensal': '139.90',
            'valor_cheio': '149.90',
            'fidelidade_meses': 12,
            'roteador_wifi': 'Roteador Wi-Fi 6 Gaming Tri-Band',
            'aplicativos_inclusos': 'Twitch Prime + Skeelo',
            'beneficios': 'Baixa latência otimizada para rotas de jogos em SP/IX.br',
            'descricao': 'Jogadores competitivos e streamers',
            'ativo': True,
            'destaque': True,
        }

        response = self.client.post('/admin/planos/novo', data=dados, follow_redirects=True)
        self.assertEqual(response.status_code, 200)

        plano = Plano.query.filter_by(nome='Fibra 800 Gamer Pro').first()
        self.assertIsNotNone(plano)
        self.assertEqual(plano.tipo, TIPO_PF)
        self.assertEqual(plano.velocidade_download, 800)
        self.assertEqual(plano.valor_mensal, 139.90)
        self.assertTrue(plano.destaque)

    def test_criar_novo_plano_pj(self):
        """Testa o formulário de criação de um novo plano corporativo PJ."""
        self._login('admin_planos', 'Admin#2026')

        dados = {
            'nome': 'DigiCorp Enterprise 1G',
            'tipo': TIPO_PJ,
            'velocidade_download': 1000,
            'velocidade_upload': 1000,
            'valor_mensal': '990.00',
            'valor_cheio': '1190.00',
            'fidelidade_meses': 24,
            'roteador_wifi': '4 roteadores Wi-Fi 6 Mesh Enterprise',
            'sla_horas': 4,
            'linhas_simultaneas': 8,
            'pabx_virtual': True,
            'ip_fixo': True,
            'beneficios': 'Banda 100% simétrica com SLA de 4 horas',
            'descricao': 'Data centers e grandes empresas',
            'ativo': True,
            'destaque': False,
        }

        response = self.client.post('/admin/planos/novo', data=dados, follow_redirects=True)
        self.assertEqual(response.status_code, 200)

        plano = Plano.query.filter_by(nome='DigiCorp Enterprise 1G').first()
        self.assertIsNotNone(plano)
        self.assertEqual(plano.tipo, TIPO_PJ)
        self.assertEqual(plano.sla_horas, 4)
        self.assertEqual(plano.linhas_simultaneas, 8)
        self.assertTrue(plano.pabx_virtual)
        self.assertTrue(plano.ip_fixo)

    def test_editar_plano(self):
        """Testa a edição de um plano existente."""
        self._login('admin_planos', 'Admin#2026')

        plano = Plano(
            nome='Plano Original',
            tipo=TIPO_PF,
            velocidade_download=500,
            velocidade_upload=250,
            valor_mensal=99.90,
            fidelidade_meses=12
        )
        db.session.add(plano)
        db.session.commit()

        dados_editados = {
            'nome': 'Plano Editado Turbo',
            'tipo': TIPO_PF,
            'velocidade_download': 600,
            'velocidade_upload': 300,
            'valor_mensal': '109.90',
            'valor_cheio': '119.90',
            'fidelidade_meses': 12,
            'ativo': True,
            'destaque': True,
        }

        response = self.client.post(f'/admin/planos/{plano.id}/editar', data=dados_editados, follow_redirects=True)
        self.assertEqual(response.status_code, 200)

        plano_atualizado = db.session.get(Plano, plano.id)
        self.assertEqual(plano_atualizado.nome, 'Plano Editado Turbo')
        self.assertEqual(plano_atualizado.velocidade_download, 600)
        self.assertEqual(plano_atualizado.valor_mensal, 109.90)

    def test_toggle_status_plano(self):
        """Testa alternar status (ativo/inativo) de um plano."""
        self._login('admin_planos', 'Admin#2026')

        plano = Plano(
            nome='Plano Teste Status',
            tipo=TIPO_PF,
            velocidade_download=300,
            velocidade_upload=150,
            valor_mensal=89.90,
            ativo=True
        )
        db.session.add(plano)
        db.session.commit()

        # Desativa
        response = self.client.post(f'/admin/planos/{plano.id}/toggle-status', follow_redirects=True)
        self.assertEqual(response.status_code, 200)
        plano_db = db.session.get(Plano, plano.id)
        self.assertFalse(plano_db.ativo)

        # Reativa
        response = self.client.post(f'/admin/planos/{plano.id}/toggle-status', follow_redirects=True)
        self.assertEqual(response.status_code, 200)
        plano_db = db.session.get(Plano, plano.id)
        self.assertTrue(plano_db.ativo)

    def test_excluir_plano(self):
        """Testa exclusão de um plano."""
        self._login('admin_planos', 'Admin#2026')

        plano = Plano(
            nome='Plano Para Deletar',
            tipo=TIPO_PF,
            velocidade_download=100,
            velocidade_upload=50,
            valor_mensal=59.90
        )
        db.session.add(plano)
        db.session.commit()
        plano_id = plano.id

        response = self.client.post(f'/admin/planos/{plano_id}/excluir', follow_redirects=True)
        self.assertEqual(response.status_code, 200)

        self.assertIsNone(db.session.get(Plano, plano_id))

    def test_validacao_nome_duplicado(self):
        """Impede o cadastro de dois planos com o mesmo nome."""
        self._login('admin_planos', 'Admin#2026')

        plano = Plano(
            nome='Plano Duplicado',
            tipo=TIPO_PF,
            velocidade_download=500,
            velocidade_upload=250,
            valor_mensal=99.90
        )
        db.session.add(plano)
        db.session.commit()

        # Tenta cadastrar outro com mesmo nome
        dados = {
            'nome': 'Plano Duplicado',
            'tipo': TIPO_PJ,
            'velocidade_download': 700,
            'velocidade_upload': 350,
            'valor_mensal': '199.90',
            'fidelidade_meses': 24,
            'ativo': True
        }
        response = self.client.post('/admin/planos/novo', data=dados)
        self.assertEqual(response.status_code, 200)
        self.assertIn('Já existe um plano cadastrado com este nome.'.encode('utf-8'), response.data)

    def test_sincronizar_planos_rota_admin(self):
        """Testa o endpoint de sincronização em lote dos planos oficiais."""
        self._login('admin_planos', 'Admin#2026')

        response = self.client.post('/admin/planos/sincronizar-padrao', follow_redirects=True)
        self.assertEqual(response.status_code, 200)
        self.assertIn('foram sincronizados com sucesso'.encode('utf-8'), response.data)
        self.assertEqual(Plano.query.count(), 9)


    def test_navegacao_entre_modulos_admin(self):
        """Testa se as abas e botões de navegação conectam Usuários, Grupos e Planos."""
        self._login('admin_planos', 'Admin#2026')

        # Página de planos contém links para usuários e grupos
        res_planos = self.client.get('/admin/planos')
        self.assertEqual(res_planos.status_code, 200)
        self.assertIn(b'/admin/usuarios', res_planos.data)
        self.assertIn(b'/admin/grupos', res_planos.data)
        self.assertIn('Planos de Banda Larga'.encode('utf-8'), res_planos.data)

        # Página de usuários contém link para planos
        res_usuarios = self.client.get('/admin/usuarios')
        self.assertEqual(res_usuarios.status_code, 200)
        self.assertIn(b'/admin/planos', res_usuarios.data)

        # Página de grupos contém link para planos
        res_grupos = self.client.get('/admin/grupos')
        self.assertEqual(res_grupos.status_code, 200)
        self.assertIn(b'/admin/planos', res_grupos.data)


if __name__ == '__main__':
    unittest.main()
