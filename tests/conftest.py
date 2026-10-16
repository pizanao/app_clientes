import pytest
from sqlalchemy import text

from app import create_app
from app.config import Config
from app.extensions import db
from app.models.plano import Plano, TIPO_PF, TIPO_PJ
from app.models.user import (
    PERFIL_ADMIN,
    PERFIL_AGENTE,
    PERFIL_LIDER,
    Grupo,
    User,
)


class PytestConfig(Config):
    TESTING = True
    SQLALCHEMY_DATABASE_URI = 'sqlite:///:memory:'
    WTF_CSRF_ENABLED = False
    AISA_API_KEY = ''
    GEMINI_API_KEY = ''


@pytest.fixture
def app():
    """Cria uma instância isolada da aplicação Flask com SQLite em memória."""
    flask_app = create_app(PytestConfig)
    ctx = flask_app.app_context()
    ctx.push()
    db.create_all()
    yield flask_app
    db.session.remove()
    db.drop_all()
    ctx.pop()


@pytest.fixture
def db_session(app):
    """Retorna a sessão ativa do SQLAlchemy vinculada ao banco em memória."""
    return db.session


@pytest.fixture
def client(app):
    """Retorna o cliente HTTP de testes do Flask."""
    return app.test_client()


@pytest.fixture
def cli_runner(app):
    """Retorna o executor de comandos CLI do Flask."""
    return app.test_cli_runner()


@pytest.fixture
def rbac_users(db_session):
    """Cria e retorna usuários e grupos para os 3 perfis hierárquicos RBAC."""
    grupo_lider = Grupo(
        nome='Grupo Lideranca',
        papel=PERFIL_LIDER,
        descricao='Grupo de líderes técnicos',
    )
    grupo_comercial = Grupo(
        nome='Grupo Comercial',
        papel=PERFIL_AGENTE,
        descricao='Grupo de agentes comerciais',
    )
    db_session.add_all([grupo_lider, grupo_comercial])

    admin = User(
        nome='Admin Pytest',
        username='admin_pytest',
        email='admin@pytest.local',
        perfil=PERFIL_ADMIN,
        ativo=True,
    )
    admin.set_password('Senha@123')

    lider = User(
        nome='Lider Pytest',
        username='lider_pytest',
        email='lider@pytest.local',
        perfil=PERFIL_LIDER,
        ativo=True,
    )
    lider.set_password('Senha@123')
    lider.grupos.append(grupo_lider)

    agente = User(
        nome='Agente Pytest',
        username='agente_pytest',
        email='agente@pytest.local',
        perfil=PERFIL_AGENTE,
        ativo=True,
    )
    agente.set_password('Senha@123')
    agente.grupos.append(grupo_comercial)

    db_session.add_all([admin, lider, agente])
    db_session.commit()

    return {
        'admin': admin,
        'lider': lider,
        'agente': agente,
        'grupo_lider': grupo_lider,
        'grupo_comercial': grupo_comercial,
    }


@pytest.fixture
def admin_client(client, rbac_users):
    """Retorna um test_client autenticado com perfil Administrador."""
    client.post(
        '/auth/login',
        data={'login': rbac_users['admin'].username, 'password': 'Senha@123'},
        follow_redirects=True,
    )
    return client


@pytest.fixture
def lider_client(client, rbac_users):
    """Retorna um test_client autenticado com perfil Líder Técnico."""
    client.post(
        '/auth/login',
        data={'login': rbac_users['lider'].username, 'password': 'Senha@123'},
        follow_redirects=True,
    )
    return client


@pytest.fixture
def agente_client(client, rbac_users):
    """Retorna um test_client autenticado com perfil Agente Comercial."""
    client.post(
        '/auth/login',
        data={'login': rbac_users['agente'].username, 'password': 'Senha@123'},
        follow_redirects=True,
    )
    return client


@pytest.fixture
def sample_planos(db_session):
    """Popula planos PF e PJ básicos para testes de conversão e pedidos."""
    plano_pf = Plano(
        nome='Fibra 700 + DigiMesh (Wi-Fi 6)',
        tipo=TIPO_PF,
        velocidade_download=700,
        velocidade_upload=350,
        valor_mensal=139.90,
        beneficios='Instalação grátis\nWi-Fi 6 incluso',
        destaque=True,
        ativo=True,
    )
    plano_pj = Plano(
        nome='Fibra B2B Link Dedicado Pro',
        tipo=TIPO_PJ,
        velocidade_download=1000,
        velocidade_upload=1000,
        valor_mensal=399.90,
        beneficios='SLA 4h\nIP Fixo incluso',
        destaque=True,
        ativo=True,
    )
    db_session.add_all([plano_pf, plano_pj])
    db_session.commit()
    return {'pf': plano_pf, 'pj': plano_pj}


@pytest.fixture
def rfb_memory_seeded(db_session):
    """Cria a tabela e view RFB na conexão SQLite :memory: dos testes."""
    db_session.execute(text("""
        CREATE TABLE IF NOT EXISTS "leeds_campo_grande" (
            empresa TEXT,
            cnpj TEXT PRIMARY KEY,
            nome TEXT,
            cargo TEXT,
            telefone TEXT,
            email TEXT,
            logradouro TEXT,
            numero TEXT,
            bairro TEXT,
            complemento TEXT,
            cep TEXT,
            operadora_atual TEXT,
            plano_sugerido TEXT,
            valor_mensal_sugerido REAL,
            lead_score INTEGER,
            cnae_fiscal TEXT,
            motivo_situacao TEXT,
            municipio_nome TEXT,
            situacao_cadastral TEXT
        );
    """))
    db_session.execute(text(
        'CREATE VIEW IF NOT EXISTS leads_campo_grande AS SELECT * FROM leeds_campo_grande;'
    ))

    registros = [
        (
            'CLINICA MEDICA PANTANAL LTDA', '12345678000190',
            'DR ROBERTO ALMEIDA', 'Sócio-Administrador',
            '+5567991234567 | +556733210000', 'CONTATO@CLINICAPANTANAL.COM.BR',
            'RAUL PIRES BARBOSA', '1240', 'CHACARA CACHOEIRA', 'SALA 02', '79040150',
            'Vivo Fibra', 'Fibra B2B Link Dedicado Pro', 399.9, 95,
            'Atividade médica ambulatorial com recursos para realização de procedimentos cirúrgicos',
            'SEM MOTIVO', 'CAMPO GRANDE', 'ATIVA',
        ),
        (
            'CONTABILIDADE EXATA MS LTDA', '23456789000181',
            'MARCOS VINICIUS SOUZA', 'Sócio-Administrador',
            '+556798234567 | +55', 'FISCAL@EXATAMS.COM.BR',
            'JERIBA', '455', 'CHACARA CACHOEIRA', '', '79040220',
            'Claro / Embratel', 'Fibra 700 + DigiMesh (Wi-Fi 6)', 139.9, 91,
            'Atividades de contabilidade',
            'SEM MOTIVO', 'CAMPO GRANDE', 'ATIVA',
        ),
        (
            'ADVOCACIA CENTRAL ASSOCIADOS', '34567890000172',
            'DRA PATRICIA NOGUEIRA', 'Titular',
            '+556733824455 | +55000000000000', 'CONTATO@CENTRALADV.COM.BR',
            'AFONSO PENA', '2500', 'CENTRO', 'CONJ 801', '79002074',
            'Vivo Fibra', 'Fibra B2B Link Dedicado Pro', 399.9, 93,
            'Serviços advocatícios',
            'SEM MOTIVO', 'CAMPO GRANDE', 'ATIVA',
        ),
        (
            'SUPERMERCADO ESTRELA DO SUL LTDA', '45678901000163',
            'CARLOS EDUARDO MENDES', 'Diretor Comercial',
            '+556799876543 | +55', 'COMPRAS@ESTRELASUL.COM.BR',
            'MATO GROSSO', '1800', 'JARDIM DOS ESTADOS', 'LOJA A', '79020200',
            'Oi Fibra', 'Fibra B2B Link Dedicado Pro', 399.9, 90,
            'Comércio varejista de mercadorias em geral, com predominância de produtos alimentícios - supermercados',
            'SEM MOTIVO', 'CAMPO GRANDE', 'ATIVA',
        ),
        (
            'TECNOLOGIA CAMPO GRANDE LTDA', '56789012000154',
            'ANA PAULA FERREIRA', 'Sócia-Administradora',
            '+5567995554433 | +556733221100', 'CONTATO@TECNOCG.COM.BR',
            'VIA PARK', '700', 'VILA ALTA', 'SALA 12', '79051000',
            'Vivo Fibra', 'Fibra B2B Link Dedicado Pro', 399.9, 89,
            'Desenvolvimento de programas de computador sob encomenda',
            'SEM MOTIVO', 'CAMPO GRANDE', 'ATIVA',
        ),
    ]

    for reg in registros:
        db_session.execute(
            text("""
                INSERT INTO leeds_campo_grande VALUES (
                    :p0, :p1, :p2, :p3, :p4, :p5, :p6, :p7, :p8, :p9,
                    :p10, :p11, :p12, :p13, :p14, :p15, :p16, :p17, :p18
                )
            """),
            {f'p{i}': value for i, value in enumerate(reg)},
        )

    db_session.commit()
    return len(registros)
