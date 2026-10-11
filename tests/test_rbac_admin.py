import unittest
from app import create_app
from app.config import Config
from app.extensions import db
from app.models.user import (
    User,
    Grupo,
    PERFIL_ADMIN,
    PERFIL_LIDER,
    PERFIL_AGENTE,
)
from app.models.cliente import Cliente
from app.models.pedido import Pedido


class TestConfig(Config):
    TESTING = True
    SQLALCHEMY_DATABASE_URI = 'sqlite:///:memory:'
    WTF_CSRF_ENABLED = False


class RbacAdminTestCase(unittest.TestCase):
    def setUp(self):
        self.app = create_app(TestConfig)
        self.client = self.app.test_client()
        self.app_context = self.app.app_context()
        self.app_context.push()
        db.create_all()

        # 1. Cria Grupos Iniciais
        self.grupo_admin = Grupo(nome='Administração Master', papel=PERFIL_ADMIN, descricao='Grupo de Admins')
        self.grupo_lider = Grupo(nome='Liderança Operacional', papel=PERFIL_LIDER, descricao='Grupo de Líderes')
        self.grupo_agente = Grupo(nome='Agentes de Campo', papel=PERFIL_AGENTE, descricao='Grupo de Agentes')
        db.session.add_all([self.grupo_admin, self.grupo_lider, self.grupo_agente])
        db.session.flush()

        # 2. Usuário Administrador
        self.user_admin = User(
            nome='Administrador Sistema',
            username='admin_test',
            email='admin@digitalnetms.com.br',
            perfil=PERFIL_ADMIN,
            ativo=True
        )
        self.user_admin.set_password('AdminPass123')
        self.user_admin.grupos.append(self.grupo_admin)

        # 3. Usuário Líder Técnico
        self.user_lider = User(
            nome='Líder Técnico Silva',
            username='lider_test',
            email='lider@digitalnetms.com.br',
            perfil=PERFIL_LIDER,
            ativo=True
        )
        self.user_lider.set_password('LiderPass123')
        self.user_lider.grupos.append(self.grupo_lider)

        # 4. Usuário Agente
        self.user_agente = User(
            nome='Agente Comercial Pereira',
            username='agente_test',
            email='agente@digitalnetms.com.br',
            perfil=PERFIL_AGENTE,
            ativo=True
        )
        self.user_agente.set_password('AgentePass123')
        self.user_agente.grupos.append(self.grupo_agente)

        db.session.add_all([self.user_admin, self.user_lider, self.user_agente])
        db.session.commit()

    def tearDown(self):
        db.session.remove()
        db.drop_all()
        self.app_context.pop()

    def login(self, username, password):
        return self.client.post('/auth/login', data={
            'login': username,
            'password': password
        }, follow_redirects=True)

    def logout(self):
        return self.client.get('/auth/logout', follow_redirects=True)

    # ==========================================================================
    # TESTES DE MODELO & HERANÇA DE PERFIS / GRUPOS
    # ==========================================================================

    def test_user_properties_and_roles(self):
        self.assertTrue(self.user_admin.is_admin)
        self.assertTrue(self.user_admin.is_lider_tecnico)
        self.assertTrue(self.user_admin.is_agente)
        self.assertEqual(self.user_admin.perfil_nome, 'Administrador')

        self.assertFalse(self.user_lider.is_admin)
        self.assertTrue(self.user_lider.is_lider_tecnico)
        self.assertTrue(self.user_lider.is_agente)
        self.assertEqual(self.user_lider.perfil_nome, 'Líder Técnico')

        self.assertFalse(self.user_agente.is_admin)
        self.assertFalse(self.user_agente.is_lider_tecnico)
        self.assertTrue(self.user_agente.is_agente)
        self.assertEqual(self.user_agente.perfil_nome, 'Agente')

    def test_perfil_heranca_por_grupo(self):
        """Usuário com perfil base agente que entra em grupo de líder herda papel."""
        user_hibrido = User(
            nome='Operador Promovido',
            username='hibrido',
            email='hibrido@digitalnetms.com.br',
            perfil=PERFIL_AGENTE,
            ativo=True
        )
        user_hibrido.set_password('Pass123')
        user_hibrido.grupos.append(self.grupo_lider)
        db.session.add(user_hibrido)
        db.session.commit()

        self.assertTrue(user_hibrido.is_lider_tecnico)
        self.assertFalse(user_hibrido.is_admin)

    # ==========================================================================
    # TESTES DE CONTROLE DE ACESSO (RBAC) EM ROTAS
    # ==========================================================================

    def test_agente_bloqueado_em_rotas_admin(self):
        """Agente não pode acessar o painel de usuários nem de grupos."""
        self.login('agente_test', 'AgentePass123')

        res_users = self.client.get('/admin/usuarios')
        self.assertEqual(res_users.status_code, 403)
        self.assertIn(b'403', res_users.data)

        res_groups = self.client.get('/admin/grupos')
        self.assertEqual(res_groups.status_code, 403)

    def test_lider_bloqueado_em_rotas_admin(self):
        """Líder Técnico não pode acessar o painel de administração de usuários."""
        self.login('lider_test', 'LiderPass123')

        res_users = self.client.get('/admin/usuarios')
        self.assertEqual(res_users.status_code, 403)

        res_groups = self.client.get('/admin/grupos')
        self.assertEqual(res_groups.status_code, 403)

    def test_admin_acessa_painel_admin(self):
        """Administrador acessa /admin/usuarios e /admin/grupos com sucesso."""
        self.login('admin_test', 'AdminPass123')

        res_users = self.client.get('/admin/usuarios')
        self.assertEqual(res_users.status_code, 200)
        self.assertIn('Painel de Usuários do Sistema'.encode('utf-8'), res_users.data)
        self.assertIn(b'admin_test', res_users.data)

        res_groups = self.client.get('/admin/grupos')
        self.assertEqual(res_groups.status_code, 200)
        self.assertIn('Grupos de Acesso'.encode('utf-8'), res_groups.data)

    def test_agente_nao_pode_excluir_cliente_ou_pedido(self):
        """Agente não tem permissão para excluir clientes ou pedidos."""
        c = Cliente(nome='Cliente Teste Exclusao', email='excluir@digitalnetms.com.br')
        db.session.add(c)
        db.session.commit()

        # Loga como agente e tenta excluir
        self.login('agente_test', 'AgentePass123')
        res_del = self.client.post(f'/clientes/{c.id}/excluir')
        self.assertEqual(res_del.status_code, 403)
        # Cliente continua existindo no banco
        self.assertIsNotNone(db.session.get(Cliente, c.id))

    def test_lider_pode_excluir_cliente_e_pedido(self):
        """Líder Técnico tem permissão para excluir clientes e pedidos."""
        c = Cliente(nome='Cliente Para Excluir Lider', email='excluir_lider@digitalnetms.com.br')
        db.session.add(c)
        db.session.commit()

        self.login('lider_test', 'LiderPass123')
        res_del = self.client.post(f'/clientes/{c.id}/excluir', follow_redirects=True)
        self.assertEqual(res_del.status_code, 200)
        self.assertIsNone(db.session.get(Cliente, c.id))

    # ==========================================================================
    # TESTES DE CRUD DE USUÁRIOS NO PAINEL ADMIN
    # ==========================================================================

    def test_admin_cria_novo_usuario_com_perfil_e_grupo(self):
        """Administrador cadastra novo usuário com perfil Líder Técnico e grupo."""
        self.login('admin_test', 'AdminPass123')

        res = self.client.post('/admin/usuarios/novo', data={
            'nome': 'Novo Operador Cadastrado',
            'username': 'novolider',
            'email': 'novolider@digitalnetms.com.br',
            'perfil': PERFIL_LIDER,
            'grupos': [self.grupo_lider.id],
            'password': 'SenhaForte#123',
            'confirm_password': 'SenhaForte#123',
            'ativo': 'y'
        }, follow_redirects=True)

        self.assertEqual(res.status_code, 200)
        self.assertIn('cadastrado com sucesso'.encode('utf-8'), res.data)

        novo_user = User.query.filter_by(username='novolider').first()
        self.assertIsNotNone(novo_user)
        self.assertEqual(novo_user.perfil, PERFIL_LIDER)
        self.assertTrue(novo_user.is_lider_tecnico)
        self.assertIn(self.grupo_lider, novo_user.grupos)

        # Testa login com o novo usuário criado
        self.logout()
        res_login = self.login('novolider', 'SenhaForte#123')
        self.assertEqual(res_login.status_code, 200)
        self.assertIn(b'Painel de Controle', res_login.data)

    def test_admin_edita_usuario_e_redefine_senha(self):
        """Administrador edita informações e redefine senha de um usuário."""
        self.login('admin_test', 'AdminPass123')

        res_edit = self.client.post(f'/admin/usuarios/{self.user_agente.id}/editar', data={
            'nome': 'Agente Comercial Atualizado',
            'username': 'agente_atualizado',
            'email': 'agente_atualizado@digitalnetms.com.br',
            'perfil': PERFIL_LIDER,  # promovido para líder
            'grupos': [self.grupo_lider.id],
            'password': 'NovaSenha#2026',
            'confirm_password': 'NovaSenha#2026',
            'ativo': 'y'
        }, follow_redirects=True)

        self.assertEqual(res_edit.status_code, 200)
        self.assertIn('atualizado com sucesso'.encode('utf-8'), res_edit.data)

        user_atualizado = db.session.get(User, self.user_agente.id)
        self.assertEqual(user_atualizado.username, 'agente_atualizado')
        self.assertEqual(user_atualizado.perfil, PERFIL_LIDER)
        self.assertTrue(user_atualizado.check_password('NovaSenha#2026'))

    def test_admin_protecao_auto_desativacao_e_auto_exclusao(self):
        """Admin não pode desativar nem excluir a própria conta logada."""
        self.login('admin_test', 'AdminPass123')

        # 1. Tentativa de desativar a própria conta via toggle-status
        res_toggle = self.client.post(f'/admin/usuarios/{self.user_admin.id}/toggle-status', follow_redirects=True)
        self.assertEqual(res_toggle.status_code, 200)
        self.assertIn('não pode alterar o status da sua própria conta'.encode('utf-8'), res_toggle.data)
        self.assertTrue(self.user_admin.ativo)

        # 2. Tentativa de excluir a própria conta
        res_del = self.client.post(f'/admin/usuarios/{self.user_admin.id}/excluir', follow_redirects=True)
        self.assertEqual(res_del.status_code, 200)
        self.assertIn('não pode excluir sua própria conta'.encode('utf-8'), res_del.data)
        self.assertIsNotNone(db.session.get(User, self.user_admin.id))

    def test_admin_protecao_ultimo_admin(self):
        """Não permite excluir nem revogar o perfil do único administrador ativo."""
        self.login('admin_test', 'AdminPass123')

        # Tentar editar o perfil de si mesmo quando for o único admin ativo
        res_edit = self.client.post(f'/admin/usuarios/{self.user_admin.id}/editar', data={
            'nome': self.user_admin.nome,
            'username': self.user_admin.username,
            'email': self.user_admin.email,
            'perfil': PERFIL_AGENTE,  # Tenta rebaixar para agente
            'ativo': 'y'
        }, follow_redirects=True)

        self.assertEqual(res_edit.status_code, 200)
        self.assertIn('não pode revogar seu perfil de Administrador'.encode('utf-8'), res_edit.data)
        admin_rec = db.session.get(User, self.user_admin.id)
        self.assertEqual(admin_rec.perfil, PERFIL_ADMIN)

    def test_admin_exclui_usuario_comum(self):
        """Admin pode excluir usuário não-admin com sucesso."""
        self.login('admin_test', 'AdminPass123')

        target_id = self.user_agente.id
        res_del = self.client.post(f'/admin/usuarios/{target_id}/excluir', follow_redirects=True)
        self.assertEqual(res_del.status_code, 200)
        self.assertIn('excluído com sucesso'.encode('utf-8'), res_del.data)
        self.assertIsNone(db.session.get(User, target_id))

    # ==========================================================================
    # TESTES DE CRUD DE GRUPOS DE ACESSO
    # ==========================================================================

    def test_admin_cria_e_edita_grupo(self):
        """Criação, edição e exclusão de grupos de acesso."""
        self.login('admin_test', 'AdminPass123')

        # 1. Criar novo grupo
        res_novo = self.client.post('/admin/grupos/novo', data={
            'nome': 'NOC & Monitoramento 24h',
            'papel': PERFIL_LIDER,
            'descricao': 'Equipe de plantão técnico do Data Center',
            'membros': [self.user_lider.id]
        }, follow_redirects=True)
        self.assertEqual(res_novo.status_code, 200)
        self.assertIn('criado com sucesso'.encode('utf-8'), res_novo.data)

        grupo = Grupo.query.filter_by(nome='NOC & Monitoramento 24h').first()
        self.assertIsNotNone(grupo)
        self.assertEqual(grupo.papel, PERFIL_LIDER)
        self.assertIn(self.user_lider, grupo.usuarios)

        # 2. Editar grupo
        res_edit = self.client.post(f'/admin/grupos/{grupo.id}/editar', data={
            'nome': 'NOC & Engenharia de Telecom',
            'papel': PERFIL_ADMIN,
            'descricao': 'Engenharia de rede com acesso total',
            'membros': [self.user_lider.id, self.user_admin.id]
        }, follow_redirects=True)
        self.assertEqual(res_edit.status_code, 200)
        self.assertIn('atualizado com sucesso'.encode('utf-8'), res_edit.data)

        grupo_editado = db.session.get(Grupo, grupo.id)
        self.assertEqual(grupo_editado.nome, 'NOC & Engenharia de Telecom')
        self.assertEqual(grupo_editado.papel, PERFIL_ADMIN)
        self.assertEqual(len(grupo_editado.usuarios), 2)

        # 3. Excluir grupo
        res_del = self.client.post(f'/admin/grupos/{grupo.id}/excluir', follow_redirects=True)
        self.assertEqual(res_del.status_code, 200)
        self.assertIn('excluído com sucesso'.encode('utf-8'), res_del.data)
        self.assertIsNone(db.session.get(Grupo, grupo.id))

        # Os usuários vinculados continuam existindo
        self.assertIsNotNone(db.session.get(User, self.user_lider.id))
        self.assertIsNotNone(db.session.get(User, self.user_admin.id))


if __name__ == '__main__':
    unittest.main()
