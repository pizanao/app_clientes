from datetime import datetime
import pytest
from app.models.cliente import Cliente
from app.models.pedido import Pedido
from app.models.plano import Plano
from app.models.user import (
    User,
    Grupo,
    PERFIL_ADMIN,
    PERFIL_LIDER,
    PERFIL_AGENTE,
)
from app.routes.auth import is_safe_redirect_url
from app.utils.filters import (
    format_currency,
    format_date,
    format_date_short,
    format_document,
    format_phone,
)


def test_cli_init_db_and_seed_planos(cli_runner, db_session):
    """Testa os comandos CLI flask init-db e flask seed-planos."""
    res_init = cli_runner.invoke(args=['init-db'])
    assert res_init.exit_code == 0
    assert 'inicializado com sucesso' in res_init.output

    res_planos = cli_runner.invoke(args=['seed-planos'])
    assert res_planos.exit_code == 0
    assert Plano.query.count() == 9


def test_cli_create_admin_validation_and_duplicate(cli_runner, db_session):
    """Testa criação de administrador via CLI, validação de senha curta e duplicidade."""
    # Senha com menos de 8 caracteres deve falhar com BadParameter
    res_short = cli_runner.invoke(
        args=['create-admin', '--username', 'adm_curto', '--email', 'c@t.local', '--password', '12345']
    )
    assert res_short.exit_code != 0
    assert User.query.filter_by(username='adm_curto').first() is None

    # Criação válida
    res_ok = cli_runner.invoke(
        args=['create-admin', '--username', 'adm_novo', '--email', 'novo@adm.local', '--password', 'SenhaForte123']
    )
    assert res_ok.exit_code == 0
    criado = User.query.filter_by(username='adm_novo').first()
    assert criado is not None
    assert criado.perfil == PERFIL_ADMIN

    # Tentativa duplicada deve avisar sem quebrar
    res_dup = cli_runner.invoke(
        args=['create-admin', '--username', 'adm_novo', '--email', 'novo@adm.local', '--password', 'SenhaForte123']
    )
    assert res_dup.exit_code == 0
    assert 'já existe' in res_dup.output


def test_cli_seed_idempotency(cli_runner, db_session):
    """Valida execução e idempotência do comando flask seed."""
    res1 = cli_runner.invoke(args=['seed'])
    assert res1.exit_code == 0
    assert 'Seed finalizado' in res1.output

    count_users = User.query.count()
    count_planos = Plano.query.count()
    count_clientes = Cliente.query.count()

    # Segunda execução não deve duplicar registros nem falhar
    res2 = cli_runner.invoke(args=['seed'])
    assert res2.exit_code == 0
    assert User.query.count() == count_users
    assert Plano.query.count() == count_planos
    assert Cliente.query.count() == count_clientes


@pytest.mark.parametrize('val,expected', [
    (None, 'R$ 0,00'),
    (0, 'R$ 0,00'),
    (139.9, 'R$ 139,90'),
    (1234.56, 'R$ 1.234,56'),
    ('invalido', 'invalido'),
])
def test_filter_format_currency(val, expected):
    """Testa formatação monetária BRL no filtro format_currency."""
    assert format_currency(val) == expected


@pytest.mark.parametrize('doc,expected', [
    (None, '-'),
    ('', '-'),
    ('12345678901', '123.456.789-01'),
    ('12345678000199', '12.345.678/0001-99'),
    ('DOC-LIVRE', 'DOC-LIVRE'),
])
def test_filter_format_document(doc, expected):
    """Testa formatação de CPF e CNPJ no filtro format_document."""
    assert format_document(doc) == expected


@pytest.mark.parametrize('phone,expected', [
    (None, '-'),
    ('67991234567', '(67) 99123-4567'),
    ('6733214567', '(67) 3321-4567'),
    ('0800-123', '0800-123'),
])
def test_filter_format_phone(phone, expected):
    """Testa formatação de telefone fixo e móvel no filtro format_phone."""
    assert format_phone(phone) == expected


def test_filter_format_date():
    """Testa formatação de datas completas e curtas."""
    dt = datetime(2026, 10, 16, 14, 30)
    assert format_date(dt) == '16/10/2026 14:30'
    assert format_date_short(dt) == '16/10/2026'
    assert format_date(None) == '-'
    assert format_date_short(None) == '-'


@pytest.mark.parametrize('target_url,is_safe', [
    ('/clientes', True),
    ('/pedidos?page=2', True),
    ('https://evil.example.com/phishing', False),
    ('//evil.example.com/phishing', False),
    ('javascript:alert(1)', False),
    ('http://outro-dominio.com/login', False),
])
def test_is_safe_redirect_url_open_redirect_protection(app, target_url, is_safe):
    """Garante proteção contra Open Redirect no parâmetro next do login."""
    with app.test_request_context('/auth/login', base_url='http://localhost:5000'):
        assert is_safe_redirect_url(target_url) is is_safe


def test_inactive_user_cannot_access_protected_routes(client, db_session, rbac_users):
    """Usuário marcado como inativo não consegue autenticar no sistema."""
    agente = rbac_users['agente']
    agente.ativo = False
    db_session.commit()

    res = client.post(
        '/auth/login',
        data={'login': agente.username, 'password': 'Senha@123'},
        follow_redirects=True
    )
    assert res.status_code == 200
    # Continua na tela de login sem sessão ativa
    res_protegido = client.get('/clientes/')
    assert res_protegido.status_code == 302
    assert '/auth/login' in res_protegido.headers.get('Location', '')


def test_rbac_group_inheritance_for_lider_and_admin(client, db_session, rbac_users):
    """Valida herança de papel via grupos de acesso para @lider_required e @admin_required."""
    agente = rbac_users['agente']
    grupo_lider = rbac_users['grupo_lider']

    # 1. Agente comum tem acesso negado (403) no painel admin
    client.post('/auth/login', data={'login': agente.username, 'password': 'Senha@123'}, follow_redirects=True)
    res_admin = client.get('/admin/usuarios')
    assert res_admin.status_code == 403

    # 2. Agente adicionado a grupo de líder herda papel de líder técnico
    agente.grupos.append(grupo_lider)
    db_session.commit()
    assert agente.is_lider_tecnico is True
    # Mas ainda não é admin
    assert agente.is_admin is False
    res_admin_ainda_negado = client.get('/admin/usuarios')
    assert res_admin_ainda_negado.status_code == 403

    # 3. Agente adicionado a grupo de administração herda papel de admin
    grupo_admin = Grupo(nome='Grupo Diretoria Admin', papel=PERFIL_ADMIN)
    db_session.add(grupo_admin)
    agente.grupos.append(grupo_admin)
    db_session.commit()
    assert agente.is_admin is True

    res_admin_permitido = client.get('/admin/usuarios')
    assert res_admin_permitido.status_code == 200


def test_cliente_bairro_normalization_on_create_and_edit(admin_client, db_session):
    """Garante normalização de bairro tanto na criação quanto na edição de clientes."""
    # 1. Criação com bairro em maiúsculas sem acento
    res_create = admin_client.post('/clientes/novo', data={
        'nome': 'Clínica Santa Fé Odontologia',
        'email': 'contato@santafeodonto.com.br',
        'telefone': '(67) 99111-2233',
        'documento': '12.345.678/0001-99',
        'cep': '79021-000',
        'logradouro': 'Rua Ceará',
        'numero': '1200',
        'bairro': 'SANTA FE',
        'cidade': 'Campo Grande',
        'estado': 'MS',
        'ativo': 'y',
    }, follow_redirects=True)
    assert res_create.status_code == 200

    cliente = Cliente.query.filter_by(email='contato@santafeodonto.com.br').first()
    assert cliente is not None
    assert cliente.bairro == 'Santa Fé'

    # 2. Edição alterando para outro bairro com variação
    res_edit = admin_client.post(f'/clientes/{cliente.id}/editar', data={
        'nome': cliente.nome,
        'email': cliente.email,
        'telefone': cliente.telefone,
        'documento': cliente.documento,
        'cep': '79040-010',
        'logradouro': 'Rua Raul Pires Barbosa',
        'numero': '800',
        'bairro': 'CHACARA CACHOEIRA',
        'cidade': 'Campo Grande',
        'estado': 'MS',
        'ativo': 'y',
    }, follow_redirects=True)
    assert res_edit.status_code == 200

    db_session.refresh(cliente)
    assert cliente.bairro == 'Chácara Cachoeira'


def test_pedido_boundary_1_item_and_10_items_total(admin_client, db_session):
    """
    Testa criação de pedido com limite mínimo (1 item) e limite máximo (10 itens),
    validando cálculo exato do total em centavos.
    """
    cliente = Cliente(
        nome='Hospital dos Olhos MS',
        email='financeiro@hospitalolhos.com.br',
        telefone='(67) 3322-9988',
        documento='33.444.555/0001-66',
        cep='79020-200',
        logradouro='Avenida Afonso Pena',
        numero='3000',
        bairro='Centro',
        cidade='Campo Grande',
        estado='MS',
        ativo=True,
    )
    db_session.add(cliente)
    db_session.commit()

    # 1. Pedido no limite mínimo: exatamente 1 item
    res_1 = admin_client.post('/pedidos/novo', data={
        'cliente_id': str(cliente.id),
        'status': 'concluido',
        'descricao': 'Assinatura Fibra',
        'itens-0-descricao': 'Mensalidade Fibra 700 + DigiMesh',
        'itens-0-quantidade': '1',
        'itens-0-valor_unitario': '139.90',
    }, follow_redirects=True)
    assert res_1.status_code == 200

    ped1 = Pedido.query.filter_by(cliente_id=cliente.id).order_by(Pedido.id.desc()).first()
    assert ped1 is not None
    assert len(ped1.itens) == 1
    assert abs(ped1.total - 139.90) < 0.01

    # 2. Pedido no limite máximo: exatamente 10 itens
    form_10 = {
        'cliente_id': str(cliente.id),
        'status': 'concluido',
        'descricao': 'Pedido Corporativo 10 itens',
    }
    for i in range(10):
        form_10[f'itens-{i}-descricao'] = f'Ponto de Rede #{i + 1}'
        form_10[f'itens-{i}-quantidade'] = '2'
        form_10[f'itens-{i}-valor_unitario'] = '50.25'

    res_10 = admin_client.post('/pedidos/novo', data=form_10, follow_redirects=True)
    assert res_10.status_code == 200

    ped2 = Pedido.query.filter_by(cliente_id=cliente.id).order_by(Pedido.id.desc()).first()
    assert ped2 is not None
    assert len(ped2.itens) == 10
    # 10 * (2 * 50.25) = 1005.00
    assert abs(ped2.total - 1005.00) < 0.01


def test_pedido_rejection_no_items_and_invalid_values(admin_client, db_session):
    """Garante rejeição de pedidos sem itens ou com valores/quantidades inválidos."""
    cliente = Cliente(
        nome='Posto Pantanal Ltda',
        email='contato@postopantanal.com.br',
        telefone='(67) 3344-5566',
        documento='44.555.666/0001-77',
        cep='79002-000',
        logradouro='Avenida Calógeras',
        numero='500',
        bairro='Centro',
        cidade='Campo Grande',
        estado='MS',
        ativo=True,
    )
    db_session.add(cliente)
    db_session.commit()

    pedidos_antes = Pedido.query.count()

    # 1. Sem itens válidos
    res_sem_itens = admin_client.post('/pedidos/novo', data={
        'cliente_id': str(cliente.id),
        'status': 'pendente',
    }, follow_redirects=True)
    assert res_sem_itens.status_code == 200
    assert 'pelo menos 1 item' in res_sem_itens.get_data(as_text=True)
    assert Pedido.query.count() == pedidos_antes

    # 2. Item com quantidade negativa ou zero
    res_qtd_invalida = admin_client.post('/pedidos/novo', data={
        'cliente_id': str(cliente.id),
        'status': 'pendente',
        'itens-0-descricao': 'Item Inválido',
        'itens-0-quantidade': '0',
        'itens-0-valor_unitario': '100.00',
    }, follow_redirects=True)
    assert res_qtd_invalida.status_code == 200
    assert 'quantidade deve ser maior que zero' in res_qtd_invalida.get_data(as_text=True)
    assert Pedido.query.count() == pedidos_antes

    # 3. Item com valor unitário zero ou negativo
    res_valor_invalido = admin_client.post('/pedidos/novo', data={
        'cliente_id': str(cliente.id),
        'status': 'pendente',
        'itens-0-descricao': 'Item Inválido',
        'itens-0-quantidade': '1',
        'itens-0-valor_unitario': '-50.00',
    }, follow_redirects=True)
    assert res_valor_invalido.status_code == 200
    assert 'valor unitário deve ser maior que zero' in res_valor_invalido.get_data(as_text=True)
    assert Pedido.query.count() == pedidos_antes

    # 4. Mais de 10 itens (11 itens)
    form_11 = {
        'cliente_id': str(cliente.id),
        'status': 'pendente',
    }
    for i in range(11):
        form_11[f'itens-{i}-descricao'] = f'Item #{i + 1}'
        form_11[f'itens-{i}-quantidade'] = '1'
        form_11[f'itens-{i}-valor_unitario'] = '10.00'

    res_11 = admin_client.post('/pedidos/novo', data=form_11, follow_redirects=True)
    assert res_11.status_code == 200
    assert 'no máximo 10 itens' in res_11.get_data(as_text=True)
    assert Pedido.query.count() == pedidos_antes
