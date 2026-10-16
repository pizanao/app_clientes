import os
import unittest
from unittest import mock
from app import create_app
from app.config import Config, DEV_SECRET_KEY
from app.extensions import db
from app.models.user import User, PERFIL_ADMIN, PERFIL_AGENTE
from app.models.cliente import Cliente
from app.models.pedido import Pedido
from app.models.lead import Lead
from app.models.plano import Plano, TIPO_PF, TIPO_PJ
from app.routes.auth import is_safe_redirect_url


class TestConfig(Config):
    TESTING = True
    SQLALCHEMY_DATABASE_URI = 'sqlite:///:memory:'
    WTF_CSRF_ENABLED = False


class AppTestCase(unittest.TestCase):
    def setUp(self):
        self.app = create_app(TestConfig)
        self.client = self.app.test_client()
        self.app_context = self.app.app_context()
        self.app_context.push()
        db.create_all()

        # Create a test admin user
        user = User(nome='Tester Admin', username='tester', email='tester@test.com', perfil=PERFIL_ADMIN)
        user.set_password('password123')
        db.session.add(user)
        db.session.commit()

    def tearDown(self):
        db.session.remove()
        db.drop_all()
        self.app_context.pop()

    def login(self, username='tester', password='password123'):
        return self.client.post('/auth/login', data={
            'login': username,
            'password': password
        }, follow_redirects=True)

    def logout(self):
        return self.client.get('/auth/logout', follow_redirects=True)

    # --- AUTH TESTS ---
    def test_login_success_and_logout(self):
        res = self.login()
        self.assertEqual(res.status_code, 200)
        self.assertIn(b'Painel de Controle', res.data)

        res_logout = self.logout()
        self.assertEqual(res_logout.status_code, 200)
        self.assertIn(b'Acessar Sistema', res_logout.data)

    def test_login_invalid_password(self):
        res = self.login(password='wrongpass')
        self.assertEqual(res.status_code, 200)
        self.assertIn(b'incorretos', res.data)

    def test_register_new_user(self):
        res = self.client.post('/auth/register', data={
            'nome': 'Novo Usuario Teste',
            'username': 'novousuario',
            'email': 'novo@teste.com',
            'password': 'secretpassword',
            'confirm_password': 'secretpassword'
        }, follow_redirects=True)
        self.assertEqual(res.status_code, 200)
        self.assertIn(b'Conta criada com sucesso', res.data)

        # Verify login with new user
        res_login = self.login(username='novousuario', password='secretpassword')
        self.assertEqual(res_login.status_code, 200)
        self.assertIn(b'Painel de Controle', res_login.data)

        # Validação de segurança RBAC: novos usuários registrados devem ser agentes e não admin
        novo_user = User.query.filter_by(username='novousuario').first()
        self.assertIsNotNone(novo_user)
        self.assertEqual(novo_user.perfil, PERFIL_AGENTE)
        self.assertFalse(novo_user.is_admin)

    # --- CLIENTES CRUD TESTS ---
    def test_cliente_crud(self):
        self.login()

        # 1. Create client
        res = self.client.post('/clientes/novo', data={
            'nome': 'Empresa Alpha Tech Ltda',
            'email': 'alpha@tech.com',
            'telefone': '(67) 98888-7777',
            'documento': '11.222.333/0001-44',
            'cep': '79040-010',
            'logradouro': 'Rua Ceará',
            'numero': '10',
            'bairro': 'CHÁCARA CACHOEIRA',
            'cidade': 'Campo Grande',
            'estado': 'MS',
            'ativo': 'y',
            'observacoes': 'Cliente prioritário'
        }, follow_redirects=True)
        self.assertEqual(res.status_code, 200)
        self.assertIn(b'Empresa Alpha Tech Ltda', res.data)

        cliente = Cliente.query.filter_by(email='alpha@tech.com').first()
        self.assertIsNotNone(cliente)
        self.assertEqual(cliente.cidade, 'Campo Grande')
        self.assertEqual(cliente.estado, 'MS')
        self.assertEqual(cliente.bairro, 'Chácara Cachoeira')

        # 2. View details
        res_detail = self.client.get(f'/clientes/{cliente.id}')
        self.assertEqual(res_detail.status_code, 200)
        self.assertIn(b'Empresa Alpha Tech Ltda', res_detail.data)

        # 3. Edit client
        res_edit = self.client.post(f'/clientes/{cliente.id}/editar', data={
            'nome': 'Empresa Alpha Tech Modificada',
            'email': 'alpha_editada@tech.com',
            'telefone': '(67) 99999-0000',
            'bairro': 'vilasboas',
            'cidade': 'Campo Grande',
            'estado': 'MS',
            'ativo': 'y'
        }, follow_redirects=True)
        self.assertEqual(res_edit.status_code, 200)
        self.assertIn(b'Empresa Alpha Tech Modificada', res_edit.data)
        cliente_editado = db.session.get(Cliente, cliente.id)
        self.assertEqual(cliente_editado.bairro, 'Vilas Boas')

        # 4. Delete client
        res_del = self.client.post(f'/clientes/{cliente.id}/excluir', follow_redirects=True)
        self.assertEqual(res_del.status_code, 200)
        self.assertIsNone(db.session.get(Cliente, cliente.id))

    def test_cliente_validacao_estado_ms(self):
        self.login()
        # Tentativa de cadastro com estado diferente de MS deve ser rejeitada
        res = self.client.post('/clientes/novo', data={
            'nome': 'Empresa Fora do Estado',
            'email': 'fora@sp.com',
            'telefone': '(11) 98888-7777',
            'documento': '11.222.333/0001-44',
            'cep': '01001-000',
            'logradouro': 'Praça da Sé',
            'numero': '10',
            'bairro': 'Sé',
            'cidade': 'São Paulo',
            'estado': 'SP',
            'ativo': 'y'
        }, follow_redirects=True)
        self.assertEqual(res.status_code, 200)
        self.assertIn('O Leads Prospector atende exclusivamente no estado de Mato Grosso do Sul (MS).'.encode('utf-8'), res.data)
        self.assertIsNone(Cliente.query.filter_by(email='fora@sp.com').first())

    # --- PEDIDOS CRUD TESTS ---
    def test_pedido_crud(self):
        self.login()

        # Create client first
        c = Cliente(nome='Cliente Para Pedidos', email='pedido@cliente.com')
        db.session.add(c)
        db.session.commit()

        # 1. Create order
        res_create = self.client.post('/pedidos/novo', data={
            'cliente_id': c.id,
            'numero_pedido': 'PED-2026-9999',
            'data_pedido': '2026-10-07T14:30',
            'status': 'pendente',
            'metodo_pagamento': 'pix',
            'valor_total': '1500.50',
            'descricao': 'Consultoria e implantação de sistema',
            'observacoes': 'Pagamento após entrega'
        }, follow_redirects=True)
        self.assertEqual(res_create.status_code, 200)
        self.assertIn(b'PED-2026-9999', res_create.data)

        pedido = Pedido.query.filter_by(numero_pedido='PED-2026-9999').first()
        self.assertIsNotNone(pedido)
        self.assertEqual(pedido.valor_total, 1500.50)

        # 2. View order details
        res_detail = self.client.get(f'/pedidos/{pedido.id}')
        self.assertEqual(res_detail.status_code, 200)
        self.assertIn(b'PED-2026-9999', res_detail.data)

        # 3. Edit order
        res_edit = self.client.post(f'/pedidos/{pedido.id}/editar', data={
            'cliente_id': c.id,
            'numero_pedido': 'PED-2026-9999',
            'data_pedido': '2026-10-07T14:30',
            'status': 'concluido',
            'metodo_pagamento': 'cartao_credito',
            'valor_total': '1800.00',
            'descricao': 'Consultoria expandida e treinamento'
        }, follow_redirects=True)
        self.assertEqual(res_edit.status_code, 200)
        self.assertIn(b'Conclu', res_edit.data)

        pedido_atualizado = db.session.get(Pedido, pedido.id)
        self.assertEqual(pedido_atualizado.status, 'concluido')
        self.assertEqual(pedido_atualizado.valor_total, 1800.00)

        # 4. Delete order
        res_del = self.client.post(f'/pedidos/{pedido.id}/excluir', follow_redirects=True)
        self.assertEqual(res_del.status_code, 200)
        self.assertIsNone(db.session.get(Pedido, pedido.id))

    def test_pedido_com_multiplos_itens_e_totalizacao(self):
        """Testa criação e totalização automática de pedido com múltiplos itens."""
        self.login()

        c = Cliente(nome='Cliente Itens Teste', email='itens@cliente.com')
        db.session.add(c)
        db.session.commit()

        # Cadastrar pedido com 3 itens:
        # Item 1: 2x 150.00 = 300.00
        # Item 2: 3x 50.00  = 150.00
        # Item 3: 1x 25.50  = 25.50
        # Total esperado: 475.50
        res = self.client.post('/pedidos/novo', data={
            'cliente_id': c.id,
            'numero_pedido': 'PED-2026-ITENS1',
            'data_pedido': '2026-10-07T10:00',
            'status': 'pendente',
            'metodo_pagamento': 'pix',
            'itens-0-descricao': 'Monitor LED 24 polegadas',
            'itens-0-quantidade': '2',
            'itens-0-valor_unitario': '150.00',
            'itens-1-descricao': 'Teclado Mecânico RGB',
            'itens-1-quantidade': '3',
            'itens-1-valor_unitario': '50.00',
            'itens-2-descricao': 'Mousepad Gamer Extra Grande',
            'itens-2-quantidade': '1',
            'itens-2-valor_unitario': '25.50',
        }, follow_redirects=True)
        self.assertEqual(res.status_code, 200)
        self.assertIn(b'PED-2026-ITENS1', res.data)

        pedido = Pedido.query.filter_by(numero_pedido='PED-2026-ITENS1').first()
        self.assertIsNotNone(pedido)
        self.assertEqual(len(pedido.itens), 3)
        self.assertEqual(pedido.valor_total, 475.50)

        # Verificar cada item
        self.assertEqual(pedido.itens[0].descricao, 'Monitor LED 24 polegadas')
        self.assertEqual(pedido.itens[0].quantidade, 2.0)
        self.assertEqual(pedido.itens[0].valor_unitario, 150.00)
        self.assertEqual(pedido.itens[0].valor_total, 300.00)

        self.assertEqual(pedido.itens[1].descricao, 'Teclado Mecânico RGB')
        self.assertEqual(pedido.itens[1].quantidade, 3.0)
        self.assertEqual(pedido.itens[1].valor_unitario, 50.00)
        self.assertEqual(pedido.itens[1].valor_total, 150.00)

        self.assertEqual(pedido.itens[2].descricao, 'Mousepad Gamer Extra Grande')
        self.assertEqual(pedido.itens[2].quantidade, 1.0)
        self.assertEqual(pedido.itens[2].valor_unitario, 25.50)
        self.assertEqual(pedido.itens[2].valor_total, 25.50)

        # Detalhe do pedido deve exibir os itens e valores
        res_detalhe = self.client.get(f'/pedidos/{pedido.id}')
        self.assertEqual(res_detalhe.status_code, 200)
        self.assertIn(b'Monitor LED 24 polegadas', res_detalhe.data)
        self.assertIn(b'Teclado Mec', res_detalhe.data)
        self.assertIn(b'Mousepad Gamer Extra Grande', res_detalhe.data)
        self.assertIn(b'475,50', res_detalhe.data)

        # Edição do pedido: remover 1 item e atualizar quantidades
        res_edit = self.client.post(f'/pedidos/{pedido.id}/editar', data={
            'cliente_id': c.id,
            'numero_pedido': 'PED-2026-ITENS1',
            'data_pedido': '2026-10-07T10:00',
            'status': 'concluido',
            'metodo_pagamento': 'pix',
            'itens-0-descricao': 'Monitor LED 24 polegadas Atualizado',
            'itens-0-quantidade': '1',
            'itens-0-valor_unitario': '200.00',
            'itens-1-descricao': 'Mousepad Gamer Extra Grande',
            'itens-1-quantidade': '2',
            'itens-1-valor_unitario': '30.00',
        }, follow_redirects=True)
        self.assertEqual(res_edit.status_code, 200)

        pedido_atualizado = db.session.get(Pedido, pedido.id)
        self.assertEqual(len(pedido_atualizado.itens), 2)
        # 1x 200.00 + 2x 30.00 = 260.00
        self.assertEqual(pedido_atualizado.valor_total, 260.00)

    def test_pedido_validacao_minimo_um_item(self):
        """Testa que pedido sem itens é rejeitado pela validação."""
        self.login()
        c = Cliente(nome='Cliente Min Item', email='min@cliente.com')
        db.session.add(c)
        db.session.commit()

        res = self.client.post('/pedidos/novo', data={
            'cliente_id': c.id,
            'numero_pedido': 'PED-2026-ZERO',
            'data_pedido': '2026-10-07T10:00',
            'status': 'pendente',
            'metodo_pagamento': 'pix',
            # Sem itens informados
        }, follow_redirects=True)

        self.assertEqual(res.status_code, 200)
        self.assertIn('O pedido deve conter pelo menos 1 item.'.encode('utf-8'), res.data)
        self.assertIsNone(Pedido.query.filter_by(numero_pedido='PED-2026-ZERO').first())

    def test_pedido_validacao_maximo_dez_itens(self):
        """Testa que pedido com mais de 10 itens (11 itens) é rejeitado."""
        self.login()
        c = Cliente(nome='Cliente Max Item', email='max@cliente.com')
        db.session.add(c)
        db.session.commit()

        # Enviar 11 itens
        data = {
            'cliente_id': c.id,
            'numero_pedido': 'PED-2026-MAX11',
            'data_pedido': '2026-10-07T10:00',
            'status': 'pendente',
            'metodo_pagamento': 'pix',
        }
        for i in range(11):
            data[f'itens-{i}-descricao'] = f'Item Teste {i + 1}'
            data[f'itens-{i}-quantidade'] = '1'
            data[f'itens-{i}-valor_unitario'] = '10.00'

        res = self.client.post('/pedidos/novo', data=data, follow_redirects=True)
        self.assertEqual(res.status_code, 200)
        self.assertIn('máximo 10 itens'.encode('utf-8'), res.data)
        self.assertIsNone(Pedido.query.filter_by(numero_pedido='PED-2026-MAX11').first())

    def test_pedido_validacao_campos_invalidos_item(self):
        """Testa validação de valores negativos ou zerados nos itens."""
        self.login()
        c = Cliente(nome='Cliente Invalido', email='invalido@cliente.com')
        db.session.add(c)
        db.session.commit()

        # Quantidade zerada
        res = self.client.post('/pedidos/novo', data={
            'cliente_id': c.id,
            'numero_pedido': 'PED-2026-INV1',
            'data_pedido': '2026-10-07T10:00',
            'status': 'pendente',
            'metodo_pagamento': 'pix',
            'itens-0-descricao': 'Produto Inválido',
            'itens-0-quantidade': '0',
            'itens-0-valor_unitario': '50.00',
        }, follow_redirects=True)
        self.assertEqual(res.status_code, 200)
        self.assertIn('quantidade deve ser maior que zero'.encode('utf-8'), res.data)
        self.assertIsNone(Pedido.query.filter_by(numero_pedido='PED-2026-INV1').first())

        # Valor unitário negativo
        res2 = self.client.post('/pedidos/novo', data={
            'cliente_id': c.id,
            'numero_pedido': 'PED-2026-INV2',
            'data_pedido': '2026-10-07T10:00',
            'status': 'pendente',
            'metodo_pagamento': 'pix',
            'itens-0-descricao': 'Produto Inválido',
            'itens-0-quantidade': '1',
            'itens-0-valor_unitario': '-10.00',
        }, follow_redirects=True)
        self.assertEqual(res2.status_code, 200)
        self.assertIn('valor unitário deve ser maior que zero'.encode('utf-8'), res2.data)
        self.assertIsNone(Pedido.query.filter_by(numero_pedido='PED-2026-INV2').first())

    # --- SEGURANÇA: REDIRECIONAMENTO APÓS LOGIN ---
    def test_is_safe_redirect_url(self):
        for url in ['/clientes/', '/pedidos/1?x=1', '/dashboard']:
            self.assertTrue(is_safe_redirect_url(url), url)
        for url in [None, '', '//evil.com', '/\\evil.com', '\\\\evil.com',
                    'https://evil.com', 'http:/evil.com', 'javascript:alert(1)', 'clientes']:
            self.assertFalse(is_safe_redirect_url(url), url)

    def test_login_bloqueia_open_redirect(self):
        res = self.client.post('/auth/login?next=//evil.com/phish', data={
            'login': 'tester', 'password': 'password123'
        })
        self.assertEqual(res.status_code, 302)
        self.assertNotIn('evil.com', res.headers['Location'])
        self.assertTrue(res.headers['Location'].endswith('/dashboard'))

    def test_login_respeita_next_interno(self):
        res = self.client.post('/auth/login?next=/clientes/', data={
            'login': 'tester', 'password': 'password123'
        })
        self.assertEqual(res.status_code, 302)
        self.assertTrue(res.headers['Location'].endswith('/clientes/'))

    # --- DASHBOARD ---
    def test_dashboard_ticket_medio_ignora_cancelados(self):
        self.login()
        c = Cliente(nome='Cliente Ticket', email='ticket@cliente.com')
        db.session.add(c)
        db.session.flush()
        db.session.add_all([
            Pedido(numero_pedido='PED-T-1', cliente_id=c.id, status='concluido', valor_total=100.0),
            Pedido(numero_pedido='PED-T-2', cliente_id=c.id, status='pendente', valor_total=300.0),
            Pedido(numero_pedido='PED-T-3', cliente_id=c.id, status='cancelado', valor_total=1000.0),
        ])
        db.session.commit()

        res = self.client.get('/dashboard')
        self.assertEqual(res.status_code, 200)
        # (100 + 300) / 2 pedidos válidos = 200,00 (antes era 400 / 3 = 133,33)
        self.assertIn('Ticket Médio: <strong>R$ 200,00</strong>'.encode('utf-8'), res.data)

    def test_dashboard_indicadores_atendimento_e_monitoramento(self):
        """Testa o carregamento de todos os novos indicadores operacionais, funil de leads e mix de planos."""
        self.login()

        # 1. Cria planos oficiais
        plano_pf = Plano(
            nome='Fibra 700 Teste Dash',
            tipo=TIPO_PF,
            velocidade_download=700,
            velocidade_upload=350,
            valor_mensal=139.90,
            roteador_wifi='Wi-Fi 6 em comodato'
        )
        plano_pj = Plano(
            nome='DigiCorp Teste Dash',
            tipo=TIPO_PJ,
            velocidade_download=900,
            velocidade_upload=450,
            valor_mensal=399.90,
            sla_horas=12,
            roteador_wifi='2 repetidores Wi-Fi 6'
        )
        db.session.add_all([plano_pf, plano_pj])

        # 2. Cria cliente com bairro específico de Campo Grande
        cliente = Cliente(
            nome='Hospital Santa Marina',
            email='contato@santamarina.com.br',
            bairro='Chácara Cachoeira',
            cidade='Campo Grande',
            estado='MS',
            ativo=True
        )
        db.session.add(cliente)
        db.session.flush()

        # 3. Cria pedidos vinculados com planos
        p1 = Pedido(
            numero_pedido='PED-DASH-01',
            cliente_id=cliente.id,
            plano_id=plano_pj.id,
            status='processando',
            valor_total=399.90
        )
        p2 = Pedido(
            numero_pedido='PED-DASH-02',
            cliente_id=cliente.id,
            plano_id=plano_pf.id,
            status='pendente',
            valor_total=139.90
        )
        db.session.add_all([p1, p2])

        # 4. Cria leads para testar funil e taxa de opt-in
        l1 = Lead(
            nome='Dr. Roberto',
            empresa='Clínica Olhos MS',
            bairro='Chácara Cachoeira',
            operadora_atual='Vivo Fibra',
            plano_sugerido='Fibra 700 Teste Dash',
            valor_mensal_sugerido=139.90,
            status='optin_aceito',
            optin_status='aceito',
            lead_score=95
        )
        l2 = Lead(
            nome='Dra. Camila',
            empresa='Consultório Sorrir',
            bairro='Centro',
            operadora_atual='Claro NET',
            plano_sugerido='DigiCorp Teste Dash',
            valor_mensal_sugerido=399.90,
            status='novo',
            optin_status='pendente',
            lead_score=80
        )
        db.session.add_all([l1, l2])
        db.session.commit()

        # 5. Executa requisição GET ao dashboard
        res = self.client.get('/dashboard')
        self.assertEqual(res.status_code, 200)

        html = res.get_data(as_text=True)
        # Verifica se os títulos dos blocos estão presentes
        self.assertIn('Painel de Atendimento & Monitoramento', html)
        self.assertIn('MRR Estimado (Recorrente)', html)
        self.assertIn('Ordens Técnicas Abertas', html)
        self.assertIn('Opt-in WhatsApp (Anti-Ban)', html)
        self.assertIn('Fila de Atendimento & Abordagem Rápida', html)
        self.assertIn('Fila de Despacho Técnico & Ativações', html)
        self.assertIn('Top Bairros com Maior Ativação', html)
        self.assertIn('Mix de Assinaturas & Planos Contratados', html)

        # Verifica dados específicos populados
        self.assertIn('Clínica Olhos MS', html)
        self.assertIn('Hospital Santa Marina', html)
        self.assertIn('Chácara Cachoeira', html)
        self.assertIn('PED-DASH-01', html)
        self.assertIn('Vivo Fibra', html)
        self.assertIn('SLA 12h', html)

    # --- CLI ---
    def test_seed_nao_usa_senha_fixa(self):
        runner = self.app.test_cli_runner()
        with mock.patch.dict(os.environ, {'SEED_ADMIN_PASSWORD': 'SenhaSeed*2026'}):
            result = runner.invoke(args=['seed'])
        self.assertEqual(result.exit_code, 0, result.output)
        self.assertNotIn('SenhaSeed*2026', result.output)
        admin = User.query.filter_by(username='admin').first()
        self.assertTrue(admin.check_password('SenhaSeed*2026'))
        self.assertFalse(admin.check_password('admin123'))

    def test_create_admin_nao_exibe_senha(self):
        runner = self.app.test_cli_runner()
        result = runner.invoke(args=['create-admin', '--username', 'chefe',
                                     '--email', 'chefe@x.com', '--password', 'SuperSenha123'])
        self.assertEqual(result.exit_code, 0, result.output)
        self.assertNotIn('SuperSenha123', result.output)
        self.assertTrue(User.query.filter_by(username='chefe').first().check_password('SuperSenha123'))

        curta = runner.invoke(args=['create-admin', '--username', 'x', '--email', 'x@x.com', '--password', '123'])
        self.assertNotEqual(curta.exit_code, 0)

    def test_sidebar_compacta_e_alternancia_tema(self):
        self.login()
        res = self.client.get('/dashboard')
        self.assertEqual(res.status_code, 200)
        html = res.get_data(as_text=True)

        # 1. Alternância de tema claro/escuro
        self.assertIn('data-bs-theme', html)
        self.assertIn('id="themeToggle"', html)
        self.assertIn('id="themeIcon"', html)
        self.assertIn('id="dropdownThemeToggle"', html)

        # 2. Estrutura para sidebar compacta apenas com ícones
        self.assertIn('class="brand-text"', html)
        self.assertIn('class="user-info text-truncate"', html)
        self.assertIn('title="Dashboard"', html)
        self.assertIn('title="Radar de Leads"', html)
        self.assertIn('title="Clientes"', html)
        self.assertIn('title="Pedidos & Instalação"', html)


class SecretKeyConfigTestCase(unittest.TestCase):
    """Garante que a aplicação não sobe em produção com a SECRET_KEY de desenvolvimento."""

    def _config(self, secret, testing=False):
        return type('Cfg', (TestConfig,), {'SECRET_KEY': secret, 'TESTING': testing})

    def test_producao_com_chave_padrao_falha(self):
        with mock.patch.dict(os.environ, {'FLASK_DEBUG': '0'}):
            with self.assertRaises(RuntimeError):
                create_app(self._config(DEV_SECRET_KEY))
            with self.assertRaises(RuntimeError):
                create_app(self._config(''))

    def test_producao_com_chave_propria_funciona(self):
        with mock.patch.dict(os.environ, {'FLASK_DEBUG': '0'}):
            app = create_app(self._config('chave-de-producao-forte-e-unica'))
        self.assertFalse(app.debug)

    def test_debug_aceita_chave_padrao(self):
        with mock.patch.dict(os.environ, {'FLASK_DEBUG': '1'}):
            app = create_app(self._config(DEV_SECRET_KEY))
        self.assertTrue(app.debug)


if __name__ == '__main__':
    unittest.main()
