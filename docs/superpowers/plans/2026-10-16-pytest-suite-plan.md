# Pytest Modular Suite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implementar uma suíte modular de novos testes automatizados com `pytest` (`tests/conftest.py` + 3 módulos especializados independentes) preservando os 60 testes `unittest` existentes e habilitando execução paralela via Subagent-Driven Development.

**Architecture:** Uma camada fundacional (`pytest.ini` + `tests/conftest.py`) fornece fixtures isoladas em memória (`app`, `db_session`, `client`, `cli_runner`, perfis RBAC e tabela RFB `leeds_campo_grande` in-memory). Três módulos independentes (`test_pytest_prospector.py`, `test_pytest_geo_rfb.py`, `test_pytest_cli_security.py`) cobrem cada domínio sem qualquer sobreposição de arquivos, permitindo que 3 subagentes trabalhem sem conflitos de merge.

**Tech Stack:** Python 3.11+, Pytest 8.3+, Flask 3.1, Flask-SQLAlchemy 3.1, SQLite3 (R*Tree + `:memory:`), Unittest.mock.

**Spec:** `docs/superpowers/specs/2026-10-16-pytest-suite-design.md`

## Global Constraints

- **Preservação Integral do Legado (`unittest`):** Os 4 arquivos existentes (`tests/test_app.py`, `tests/test_leads.py`, `tests/test_planos_admin.py` e `tests/test_rbac_admin.py`, totalizando 60 testes) devem permanecer intactos e funcionando tanto via `pytest` quanto via `.venv/bin/python -m unittest discover -s tests -v`.
- **Isolamento de Conexão SQLite `:memory:` (Regra 4 do `AGENTS.md`):** Nenhuma fixture ou teste com SQLite `:memory:` deve invocar `inspect(db.engine)` diretamente, pois isso aloca conexões separadas no pool e isola a transação em memória. Todas as criações e consultas de tabelas dinâmicas (como `leeds_campo_grande`) devem usar `db.session.execute(text(...))`.
- **Zero Conflito entre Subagentes:** Após a Tarefa 1 (`requirements.txt`, `pytest.ini` e `tests/conftest.py`), as Tarefas 2, 3 e 4 operam cada uma em um único arquivo exclusivo (`tests/test_pytest_*.py`).
- **Atualização do `setup.sh`:** Na Tarefa 5, `scripts/gerar_setup.py` deve ser executado e validado com `--check` para que o instalador autônomo reflita os novos arquivos.

## Review Focus

- **Conexão isolada em SQLite `:memory:` ao testar a cascata RFB (`leeds_campo_grande`):** Criar a tabela via `db.session.execute(text(...))` e commitar na mesma sessão antes de chamar `TelecomProspectorService.prospect_neighborhood`, garantindo que o serviço enxergue os registros em memória (testado na Tarefa 2).
- **Idempotência de restauração geoespacial (`restaurar_imoveis.py`):** Quando `geo_imoveis` já possui `> 20.000` registros e `force=False`, `restaurar_dump` deve abortar a sobrescrita imediatamente preservando os dados existentes (testado na Tarefa 3).
- **Falha de rede durante download de dump (`.tmp` órfão):** Quando `urllib.request.urlopen` lança erro de rede em `baixar_dump`, o arquivo parcial `.tmp` deve ser removido do disco (testado na Tarefa 3).
- **Prevenção de Open Redirect no login (`is_safe_redirect_url`):** URLs com protocolo externo (`https://evil.com`) ou esquema relativo (`//evil.com`) no parâmetro `next` devem ser rejeitadas pelo validador de redirecionamento (testado na Tarefa 4).
- **Senha curta no comando CLI `flask create-admin`:** Senhas com menos de 8 caracteres devem falhar com `BadParameter` sem criar o usuário no banco (testado na Tarefa 4).

---

### Task 1: Pytest Infrastructure & Shared Fixtures (`conftest.py`)

**Files:**
- Modify: `requirements.txt:1-24`
- Create: `pytest.ini`
- Create: `tests/conftest.py`

**Interfaces:**
- Consumes: `app.create_app`, `app.config.Config`, `app.extensions.db`, `app.models.user.{User, Grupo, PERFIL_ADMIN, PERFIL_LIDER, PERFIL_AGENTE}`, `app.models.plano.{Plano, TIPO_PF, TIPO_PJ}`
- Produces:
  - `pytest` instalado em `.venv/bin/pytest`
  - Fixtures em `tests/conftest.py`:
    - `app() -> Flask`
    - `db_session(app) -> scoped_session`
    - `client(app) -> FlaskClient`
    - `cli_runner(app) -> FlaskCliRunner`
    - `rbac_users(db_session) -> dict[str, User | Grupo]` (chaves: `'admin'`, `'lider'`, `'agente'`, `'grupo_lider'`, `'grupo_comercial'`)
    - `admin_client(client, rbac_users) -> FlaskClient`
    - `lider_client(client, rbac_users) -> FlaskClient`
    - `agente_client(client, rbac_users) -> FlaskClient`
    - `sample_planos(db_session) -> dict[str, Plano]` (chaves: `'pf'`, `'pj'`)
    - `rfb_memory_seeded(db_session) -> int` (cria `leeds_campo_grande` e view `leads_campo_grande` com 4 empresas e retorna `4`)

- [ ] **Step 1: Add `pytest` to `requirements.txt` and install in `.venv`**

Atualize `requirements.txt` adicionando `pytest==8.3.5` em ordem alfabética:

```text
alembic==1.20.0
blinker==1.9.0
cachelib==0.17.0
click==8.5.0
dnspython==2.8.0
email-validator==2.3.0
Flask==3.1.3
Flask-Login==0.6.3
Flask-Migrate==4.1.0
Flask-Session==0.8.0
Flask-SQLAlchemy==3.1.1
Flask-WTF==1.3.0
idna==3.20
itsdangerous==2.2.0
Jinja2==3.1.6
Mako==1.4.3
MarkupSafe==3.0.4
msgspec==0.22.0
pytest==8.3.5
python-dotenv==1.2.4
SQLAlchemy==2.1.4
typing_extensions==4.16.0
Werkzeug==3.1.9
WTForms==3.2.2
```

Run: `.venv/bin/pip install pytest==8.3.5`
Expected: `Successfully installed ... pytest-8.3.5`

- [ ] **Step 2: Create `pytest.ini`**

Crie `pytest.ini` na raiz do projeto:

```ini
[pytest]
testpaths = tests
python_files = test_*.py
python_classes = Test* *TestCase
python_functions = test_*
addopts = -v --tb=short
filterwarnings =
    ignore::ResourceWarning
    ignore::DeprecationWarning
```

- [ ] **Step 3: Create `tests/conftest.py` with shared fixtures**

Crie `tests/conftest.py`:

```python
import pytest
from sqlalchemy import text
from app import create_app
from app.config import Config
from app.extensions import db
from app.models.user import User, Grupo, PERFIL_ADMIN, PERFIL_LIDER, PERFIL_AGENTE
from app.models.plano import Plano, TIPO_PF, TIPO_PJ


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
        descricao='Grupo de líderes técnicos'
    )
    grupo_comercial = Grupo(
        nome='Grupo Comercial',
        papel=PERFIL_AGENTE,
        descricao='Grupo de agentes comerciais'
    )
    db_session.add_all([grupo_lider, grupo_comercial])

    admin = User(
        nome='Admin Pytest',
        username='admin_pytest',
        email='admin@pytest.local',
        perfil=PERFIL_ADMIN,
        ativo=True
    )
    admin.set_password('Senha@123')

    lider = User(
        nome='Lider Pytest',
        username='lider_pytest',
        email='lider@pytest.local',
        perfil=PERFIL_LIDER,
        ativo=True
    )
    lider.set_password('Senha@123')
    lider.grupos.append(grupo_lider)

    agente = User(
        nome='Agente Pytest',
        username='agente_pytest',
        email='agente@pytest.local',
        perfil=PERFIL_AGENTE,
        ativo=True
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
        follow_redirects=True
    )
    return client


@pytest.fixture
def lider_client(client, rbac_users):
    """Retorna um test_client autenticado com perfil Líder Técnico."""
    client.post(
        '/auth/login',
        data={'login': rbac_users['lider'].username, 'password': 'Senha@123'},
        follow_redirects=True
    )
    return client


@pytest.fixture
def agente_client(client, rbac_users):
    """Retorna um test_client autenticado com perfil Agente Comercial."""
    client.post(
        '/auth/login',
        data={'login': rbac_users['agente'].username, 'password': 'Senha@123'},
        follow_redirects=True
    )
    return client


@pytest.fixture
def sample_planos(db_session):
    """Popula planos PF e PJ básicos para testes de conversão e pedidos."""
    plano_pf = Plano(
        nome='DigitalNet Fibra 700 + DigiMesh (Wi-Fi 6)',
        tipo=TIPO_PF,
        subtitulo='700 Mega Residencial',
        velocidade_download=700,
        velocidade_upload=350,
        tecnologia='Wi-Fi 6',
        valor_mensal=139.90,
        beneficios='Instalação grátis\nWi-Fi 6 incluso',
        destaque=True,
        ativo=True,
        ordem=1
    )
    plano_pj = Plano(
        nome='DigitalNet B2B Link Dedicado Pro',
        tipo=TIPO_PJ,
        subtitulo='1 Gbps Simétrico Corporativo',
        velocidade_download=1000,
        velocidade_upload=1000,
        tecnologia='Fibra Dedicada + IP Fixo',
        valor_mensal=399.90,
        beneficios='SLA 4h\nIP Fixo incluso',
        destaque=True,
        ativo=True,
        ordem=2
    )
    db_session.add_all([plano_pf, plano_pj])
    db_session.commit()
    return {'pf': plano_pf, 'pj': plano_pj}


@pytest.fixture
def rfb_memory_seeded(db_session):
    """
    Cria a tabela leeds_campo_grande e a view leads_campo_grande na mesma
    conexão SQLite :memory: com 4 empresas reais de Campo Grande - MS.
    """
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
        "CREATE VIEW IF NOT EXISTS leads_campo_grande AS SELECT * FROM leeds_campo_grande;"
    ))

    registros = [
        (
            'CLINICA MEDICA PANTANAL LTDA', '12345678000190',
            'DR ROBERTO ALMEIDA', 'Sócio-Administrador',
            '+5567991234567 | +556733210000', 'CONTATO@CLINICAPANTANAL.COM.BR',
            'RAUL PIRES BARBOSA', '1240', 'CHACARA CACHOEIRA', 'SALA 02', '79040150',
            'Vivo Fibra', 'DigitalNet B2B Link Dedicado Pro', 399.9, 95,
            'Atividade médica ambulatorial com recursos para realização de procedimentos cirúrgicos',
            'SEM MOTIVO', 'CAMPO GRANDE', 'ATIVA'
        ),
        (
            'CONTABILIDADE EXATA MS LTDA', '23456789000181',
            'MARCOS VINICIUS SOUZA', 'Sócio-Administrador',
            '+556798234567 | +55', 'FISCAL@EXATAMS.COM.BR',
            'JERIBA', '455', 'CHACARA CACHOEIRA', '', '79040220',
            'Claro / Embratel', 'DigitalNet Fibra 700 + DigiMesh (Wi-Fi 6)', 139.9, 91,
            'Atividades de contabilidade',
            'SEM MOTIVO', 'CAMPO GRANDE', 'ATIVA'
        ),
        (
            'ADVOCACIA CENTRAL ASSOCIADOS', '34567890000172',
            'DRA PATRICIA NOGUEIRA', 'Titular',
            '+556733824455 | +55000000000000', 'CONTATO@CENTRALADV.COM.BR',
            'AFONSO PENA', '2500', 'CENTRO', 'CONJ 801', '79002074',
            'Vivo Fibra', 'DigitalNet B2B Link Dedicado Pro', 399.9, 93,
            'Serviços advocatícios',
            'SEM MOTIVO', 'CAMPO GRANDE', 'ATIVA'
        ),
        (
            'SUPERMERCADO ESTRELA DO SUL LTDA', '45678901000163',
            'CARLOS EDUARDO MENDES', 'Diretor Comercial',
            '+556799876543 | +55', 'COMPRAS@ESTRELASUL.COM.BR',
            'MATO GROSSO', '1800', 'JARDIM DOS ESTADOS', 'LOJA A', '79020200',
            'Oi Fibra', 'DigitalNet B2B Link Dedicado Pro', 399.9, 90,
            'Comércio varejista de mercadorias em geral, com predominância de produtos alimentícios - supermercados',
            'SEM MOTIVO', 'CAMPO GRANDE', 'ATIVA'
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
            {f'p{i}': v for i, v in enumerate(reg)}
        )

    db_session.commit()
    return len(registros)
```

- [ ] **Step 4: Run `pytest` to verify the 60 existing `unittest` tests pass under `pytest`**

Run: `.venv/bin/pytest`
Expected: `60 passed`

- [ ] **Step 5: Commit Task 1**

```bash
git add requirements.txt pytest.ini tests/conftest.py
git commit -m "test(pytest): configurar pytest.ini e fixtures compartilhadas em conftest.py"
```

---

### Task 2: Prospector & AI/RFB Cascade Suite (`tests/test_pytest_prospector.py`)

**Files:**
- Create: `tests/test_pytest_prospector.py`

**Interfaces:**
- Consumes:
  - Fixtures from `tests/conftest.py`: `app`, `db_session`, `sample_planos`, `rfb_memory_seeded`
  - `app.services.prospector.TelecomProspectorService`
  - `app.models.lead.Lead`, `app.models.cliente.Cliente`, `app.models.pedido.Pedido`
- Produces:
  - Self-contained pytest test suite in `tests/test_pytest_prospector.py` (12 test functions including parameterized tests)

- [ ] **Step 1: Create `tests/test_pytest_prospector.py` with tests for the AI/RFB/Synthetic cascade, deduplication, objection tutors, and 1-click conversion**

Crie `tests/test_pytest_prospector.py`:

```python
import json
import urllib.error
from unittest.mock import MagicMock
import pytest
from app.models.cliente import Cliente
from app.models.lead import Lead
from app.models.pedido import Pedido
from app.services.prospector import TelecomProspectorService


def _make_mock_http_response(payload: dict):
    mock_resp = MagicMock()
    mock_resp.read.return_value = json.dumps(payload).encode('utf-8')
    mock_resp.__enter__.return_value = mock_resp
    mock_resp.__exit__.return_value = False
    return mock_resp


def test_cascade_aisa_primary_success(app, monkeypatch):
    """Quando AISA_API_KEY está ativa e retorna HTTP 200, utiliza os leads da AIsa."""
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
                        'plano_sugerido': 'DigitalNet B2B Link Dedicado Pro',
                        'valor_mensal_sugerido': 399.90,
                        'score': 98,
                        'description': 'Demanda de link dedicado redundante.',
                        'icebreaker_optin': 'Olá Lucas, podemos avaliar a redundância óptica?'
                    }]
                })
            }
        }]
    }

    monkeypatch.setattr(
        'urllib.request.urlopen',
        lambda req, timeout=25: _make_mock_http_response(payload)
    )

    leads = TelecomProspectorService.prospect_neighborhood(
        bairro='Jardim dos Estados',
        cidade='Campo Grande',
        count=1
    )
    assert len(leads) == 1
    assert leads[0]['empresa'] == 'DataCenter Pantanal Tech'
    assert leads[0]['lead_score'] == 98
    assert leads[0]['bairro'] == 'Jardim dos Estados'


def test_cascade_failover_aisa_to_gemini(app, monkeypatch):
    """Quando AIsa falha (HTTPError 500), faz failover automático para Gemini API."""
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
                        'plano_sugerido': 'DigitalNet B2B Link Dedicado Pro',
                        'valor_mensal_sugerido': 399.90,
                        'lead_score': 94,
                        'dor_principal': 'Lentidão no envio de laudos por imagem.',
                        'icebreaker_optin': 'Olá Dra. Helena, tudo bem?'
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
        bairro='Centro',
        cidade='Campo Grande',
        count=1
    )
    assert len(leads) == 1
    assert leads[0]['empresa'] == 'Laboratório BioExame MS'
    assert leads[0]['lead_score'] == 94


def test_cascade_failover_to_rfb_and_synthetic_complement(app, rfb_memory_seeded, monkeypatch):
    """
    Sem chaves de IA, busca prioritariamente na tabela leeds_campo_grande (RFB),
    trata o telefone com pipe '|' e complementa com leads sintéticos até atingir count.
    """
    monkeypatch.setitem(app.config, 'AISA_API_KEY', '')
    monkeypatch.setitem(app.config, 'GEMINI_API_KEY', '')

    # Existem 2 empresas de CHACARA CACHOEIRA na fixture rfb_memory_seeded; pedimos count=4
    leads = TelecomProspectorService.prospect_neighborhood(
        bairro='Chácara Cachoeira',
        cidade='Campo Grande',
        count=4
    )
    assert len(leads) == 4

    empresas_nomes = [l['empresa'].upper() for l in leads]
    assert any('CLINICA MEDICA PANTANAL' in e for e in empresas_nomes)
    assert any('CONTABILIDADE EXATA MS' in e for e in empresas_nomes)

    # Verifica formatação do telefone da clínica (primeiro número antes do '|')
    lead_clinica = next(l for l in leads if 'CLINICA MEDICA PANTANAL' in l['empresa'].upper())
    assert lead_clinica['telefone'] == '(67) 99123-4567'
    assert 'SALA 02' in lead_clinica['logradouro'] or lead_clinica['numero'] == '1240'


def test_save_prospects_global_deduplication(db_session):
    """Garante que save_prospects ignora empresas já salvas em Lead ou Cliente."""
    cliente_existente = Cliente(
        nome='Empresa Ja Cliente Ltda',
        email='cliente@existente.com',
        telefone='(67) 3322-1100',
        bairro='Centro',
        cidade='Campo Grande',
        estado='MS'
    )
    db_session.add(cliente_existente)
    db_session.commit()

    lote = [
        {
            'empresa': 'Empresa Ja Cliente Ltda',
            'nome': 'Contato 1',
            'telefone': '(67) 3322-1100',
            'bairro': 'Centro',
        },
        {
            'empresa': 'Nova Oportunidade Optica Ltda',
            'nome': 'Contato 2',
            'telefone': '(67) 99111-2222',
            'bairro': 'Centro',
        },
        {
            'empresa': 'nova oportunidade optica ltda',  # duplicado no mesmo lote (case-insensitive)
            'nome': 'Contato 2 Dup',
            'telefone': '(67) 99111-2222',
            'bairro': 'Centro',
        },
    ]

    salvos = TelecomProspectorService.save_prospects(lote)
    assert len(salvos) == 1
    assert salvos[0].empresa == 'Nova Oportunidade Optica Ltda'


@pytest.mark.parametrize('obj_key,termo_esperado', [
    ('fidelidade', 'multa'),
    ('preco', 'custo'),
    ('ti_interna', 'IP'),
    ('chave_inexistente', 'fidelidade'),
])
def test_objection_tutors_parametrized(db_session, obj_key, termo_esperado):
    """Valida todas as chaves de quebra de objeção no dossiê comercial."""
    lead = Lead(
        nome='Roberto Silva',
        empresa='Silva & Filhos Ltda',
        telefone='(67) 99123-4567',
        bairro='Centro',
        operadora_atual='Vivo Fibra',
        plano_sugerido='DigitalNet B2B Link Dedicado Pro',
        valor_mensal_sugerido=399.90
    )
    tutor = TelecomProspectorService.get_objection_tutor(obj_key, lead)
    assert isinstance(tutor, dict)
    assert 'titulo' in tutor
    assert 'resposta_whatsapp' in tutor
    assert 'argumento_tecnico' in tutor
    texto_completo = f"{tutor['titulo']} {tutor['resposta_whatsapp']} {tutor['argumento_tecnico']}".lower()
    assert termo_esperado.lower() in texto_completo


def test_convert_lead_to_client_and_reuse_existing(db_session, sample_planos):
    """Testa conversão 1-clique de Lead em Cliente + Pedido e reaproveitamento de Cliente."""
    lead1 = Lead(
        nome='Dr. Fernando Lima',
        empresa='Clínica OrtoMS Ltda',
        cargo='Diretor',
        telefone='(67) 99222-3344',
        email='contato@ortoms.com.br',
        logradouro='Rua Euclides da Cunha',
        numero='500',
        cep='79020-230',
        bairro='Jardim dos Estados',
        cidade='Campo Grande',
        estado='MS',
        plano_sugerido=sample_planos['pj'].nome,
        valor_mensal_sugerido=sample_planos['pj'].valor_mensal
    )
    db_session.add(lead1)
    db_session.commit()

    cliente1 = TelecomProspectorService.convert_lead_to_client(lead1, plano=sample_planos['pj'])
    assert cliente1.id is not None
    assert lead1.status == 'convertido'
    assert lead1.cliente_convertido_id == cliente1.id

    pedidos_cliente1 = Pedido.query.filter_by(cliente_id=cliente1.id).all()
    assert len(pedidos_cliente1) == 1
    assert pedidos_cliente1[0].plano_id == sample_planos['pj'].id
    assert abs(pedidos_cliente1[0].total - 399.90) < 0.01

    # Segundo lead para a mesma empresa/e-mail deve reutilizar o cliente existente
    lead2 = Lead(
        nome='Dr. Fernando Lima',
        empresa='Clínica OrtoMS Ltda',
        telefone='(67) 99222-3344',
        email='contato@ortoms.com.br',
        bairro='Jardim dos Estados',
        plano_sugerido=sample_planos['pf'].nome,
        valor_mensal_sugerido=sample_planos['pf'].valor_mensal
    )
    db_session.add(lead2)
    db_session.commit()

    cliente2 = TelecomProspectorService.convert_lead_to_client(lead2, plano=sample_planos['pf'])
    assert cliente2.id == cliente1.id
    assert Pedido.query.filter_by(cliente_id=cliente1.id).count() == 2
```

- [ ] **Step 2: Run `pytest tests/test_pytest_prospector.py`**

Run: `.venv/bin/pytest tests/test_pytest_prospector.py -v`
Expected: `9 passed` (6 functions + 3 extra parametrize cases)

- [ ] **Step 3: Commit Task 2**

```bash
git add tests/test_pytest_prospector.py
git commit -m "test(prospector): adicionar suite pytest para cascata IA/RFB, objecoes e conversao"
```

---

### Task 3: Geospatial & RFB Pipelines Suite (`tests/test_pytest_geo_rfb.py`)

**Files:**
- Create: `tests/test_pytest_geo_rfb.py`

**Interfaces:**
- Consumes:
  - `scripts.carregar_geojson_sqlite.{utm21s_to_wgs84, extract_coordinates_and_bounds, FieldStats, GeoJsonTable}`
  - `scripts.restaurar_imoveis.{restaurar_dump, gerar_dump, verificar_tabela_existente, baixar_dump, CREATE_TABLE_GEO_IMOVEIS_SQL, INDEXES_GEO_IMOVEIS_SQL}`
  - `scripts.restaurar_rfb.{restaurar_dump as restaurar_rfb_dump, verificar_tabela_existente as verificar_rfb_existente}`
  - `scripts.enriquecer_clientes_rfb.{format_telefone, format_cep}`
- Produces:
  - Self-contained pytest suite in `tests/test_pytest_geo_rfb.py` using `tmp_path` and `monkeypatch`

- [ ] **Step 1: Create `tests/test_pytest_geo_rfb.py`**

Crie `tests/test_pytest_geo_rfb.py`:

```python
import gzip
import io
import json
import sqlite3
import urllib.error
from unittest.mock import MagicMock
import pytest

from scripts.carregar_geojson_sqlite import (
    FieldStats,
    GeoJsonTable,
    extract_coordinates_and_bounds,
    utm21s_to_wgs84,
)
from scripts.enriquecer_clientes_rfb import format_cep, format_telefone
import scripts.restaurar_imoveis as mod_imoveis
import scripts.restaurar_rfb as mod_rfb


@pytest.mark.parametrize('easting,northing,expected_lon,expected_lat', [
    (744866.7916, 7737103.7295, -54.652909, -20.448769),
    (750000.0, 7735000.0, -54.603452, -20.467008),
])
def test_utm21s_to_wgs84_parametrized(easting, northing, expected_lon, expected_lat):
    """Testa precisão geodésica da conversão UTM Zona 21S (EPSG:31981) para WGS84 (EPSG:4326)."""
    lon, lat = utm21s_to_wgs84(easting, northing)
    assert abs(lon - expected_lon) < 1e-4
    assert abs(lat - expected_lat) < 1e-4


@pytest.mark.parametrize('sample_values,expected_type', [
    ([1, 2, 100], 'INTEGER'),
    (['10', '25', '300'], 'INTEGER'),
    (['04160902071', '00017'], 'TEXT'),  # preserva zeros à esquerda
    ([10, 25.5, 100], 'REAL'),
    (['RESIDENCIAL', 'COMERCIAL'], 'TEXT'),
    ([None, None], 'TEXT'),
])
def test_field_stats_type_inference(sample_values, expected_type):
    """Verifica inferência de tipos SQLite em FieldStats para números, zeros à esquerda e nulos."""
    st = FieldStats('campo_teste')
    for val in sample_values:
        st.record_value(val)
    assert st.infer_sqlite_type() == expected_type


def test_geojson_table_analyze_and_ddl_generation(tmp_path):
    """Testa análise de arquivo GeoJSON em EPSG:31981 e geração de DDL com R*Tree."""
    geojson_file = tmp_path / 'lotes_teste.geojson'
    sample_data = {
        'type': 'FeatureCollection',
        'crs': {'type': 'name', 'properties': {'name': 'urn:ogc:def:crs:EPSG::31981'}},
        'features': [
            {
                'type': 'Feature',
                'geometry': {
                    'type': 'MultiPolygon',
                    'coordinates': [[[[744866.79, 7737103.72], [744877.07, 7737097.54], [744866.79, 7737103.72]]]]
                },
                'properties': {
                    'gid': 1,
                    'codlote': '04160902071',
                    'nomebairro': 'SANTO AMARO',
                    'ruaimo': 'JERUSALEM',
                    'arealote': 432.0,
                }
            }
        ]
    }
    geojson_file.write_text(json.dumps(sample_data), encoding='utf-8')

    gt = GeoJsonTable(str(geojson_file), 'geo_lotes_teste')
    gt.analyze()

    assert len(gt.features) == 1
    assert gt.geometry_type == 'MultiPolygon'
    assert -55.0 < gt.bbox[0] < -54.0
    assert -21.0 < gt.bbox[1] < -20.0
    assert gt.fields['codlote'].infer_sqlite_type() == 'TEXT'
    assert gt.fields['arealote'].infer_sqlite_type() == 'REAL'

    ddl = '\n'.join(gt.generate_ddl())
    assert 'CREATE TABLE IF NOT EXISTS "geo_lotes_teste"' in ddl
    assert 'CREATE VIRTUAL TABLE IF NOT EXISTS "geo_lotes_teste_rtree" USING rtree' in ddl
    assert 'idx_geo_lotes_teste_nomebairro' in ddl


def test_restaurar_imoveis_csv_gz_and_idempotency(tmp_path):
    """Testa restauração de geo_imoveis via .csv.gz e proteção contra sobrescrita sem --force."""
    db_file = tmp_path / 'imoveis.db'
    csv_gz = tmp_path / 'geo_imoveis.csv.gz'

    csv_content = (
        'gid,codlote,ruaimo,nrporta,nomebairro,usoimovel,arealote,areaedific,'
        'geometry_geojson,geometry_type,min_lng,min_lat,max_lng,max_lat,centroid_lat,centroid_lng\n'
        '1,04160902071,AFONSO PENA,1500,CENTRO,COMERCIAL,500.0,320.0,'
        '"{""type"":""MultiPolygon"",""coordinates"":[]}",MultiPolygon,-54.62,-20.46,-54.61,-20.45,-20.455,-54.615\n'
    )
    with gzip.open(csv_gz, 'wt', encoding='utf-8') as f:
        f.write(csv_content)

    mod_imoveis.restaurar_dump(csv_gz, db_file, force=True)

    con = sqlite3.connect(str(db_file))
    assert mod_imoveis.verificar_tabela_existente(con) == 1
    cur = con.cursor()
    cur.execute('SELECT COUNT(*) FROM geo_imoveis_rtree')
    assert cur.fetchone()[0] == 1
    con.close()


def test_restaurar_imoveis_skips_when_already_populated(tmp_path, monkeypatch):
    """Quando geo_imoveis já possui > 20.000 registros e force=False, não recria a tabela."""
    db_file = tmp_path / 'imoveis_cheio.db'
    con = sqlite3.connect(str(db_file))
    con.execute(mod_imoveis.CREATE_TABLE_GEO_IMOVEIS_SQL)
    con.commit()
    con.close()

    monkeypatch.setattr(mod_imoveis, 'verificar_tabela_existente', lambda conn: 462744)

    chamou_sql = {'called': False}
    monkeypatch.setattr(mod_imoveis, '_restaurar_sql', lambda conn, p: chamou_sql.update(called=True))

    dummy_gz = tmp_path / 'dummy.sql.gz'
    dummy_gz.write_bytes(b'dummy')

    mod_imoveis.restaurar_dump(dummy_gz, db_file, force=False)
    assert chamou_sql['called'] is False


def test_baixar_dump_cleans_up_tmp_on_network_failure(tmp_path, monkeypatch):
    """Se o download do dump falhar no meio, o arquivo temporário .tmp deve ser removido."""
    destino = tmp_path / 'geo_imoveis.sql.gz'

    def broken_urlopen(req, timeout=120):
        raise urllib.error.URLError('Connection reset by peer')

    monkeypatch.setattr('urllib.request.urlopen', broken_urlopen)

    with pytest.raises(RuntimeError, match='Falha ao baixar dump'):
        mod_imoveis.baixar_dump('https://example.com/geo_imoveis.sql.gz', destino)

    assert not destino.exists()
    assert not destino.with_suffix('.tmp').exists()


def test_restaurar_rfb_sql_gz_and_view_creation(tmp_path):
    """Testa restauração de leeds_campo_grande via .sql.gz e criação da VIEW leads_campo_grande."""
    db_file = tmp_path / 'rfb_test.db'
    sql_gz = tmp_path / 'leeds_campo_grande.sql.gz'

    sql_script = """
    CREATE TABLE "leeds_campo_grande" (
        empresa text,
        cnpj text primary key,
        nome text,
        cargo text,
        telefone text,
        email text,
        logradouro text,
        numero text,
        bairro text,
        complemento text,
        cep text
    );
    INSERT INTO "leeds_campo_grande" VALUES (
        'PADARIA PAO QUENTE LTDA', '11222333000144', 'JOSE SILVA', 'Sócio-Administrador',
        '+5567991112233 | +55', 'CONTATO@PAOQUENTE.COM', 'CEARA', '900',
        'SANTA FE', 'LOJA 1', '79021000'
    );
    """
    with gzip.open(sql_gz, 'wt', encoding='utf-8') as f:
        f.write(sql_script)

    mod_rfb.restaurar_dump(sql_gz, db_file, force=True)

    con = sqlite3.connect(str(db_file))
    assert mod_rfb.verificar_tabela_existente(con) == 1
    cur = con.cursor()
    cur.execute("SELECT empresa, bairro, complemento FROM leads_campo_grande WHERE cnpj = '11222333000144'")
    row = cur.fetchone()
    assert row == ('PADARIA PAO QUENTE LTDA', 'SANTA FE', 'LOJA 1')
    con.close()


@pytest.mark.parametrize('raw_cep,expected_cep', [
    ('79040010', '79040-010'),
    ('79002-072', '79002-072'),
    ('', '79002-000'),
    (None, '79002-000'),
])
def test_enriquecer_format_cep(raw_cep, expected_cep):
    """Verifica normalização e fallback de CEP em enriquecer_clientes_rfb.py."""
    assert format_cep(raw_cep, '79002') == expected_cep
```

- [ ] **Step 2: Run `pytest tests/test_pytest_geo_rfb.py`**

Run: `.venv/bin/pytest tests/test_pytest_geo_rfb.py -v`
Expected: `17 passed`

- [ ] **Step 3: Commit Task 3**

```bash
git add tests/test_pytest_geo_rfb.py
git commit -m "test(geo-rfb): adicionar suite pytest para reprojecao WGS84, R*Tree e restauracao de dumps"
```

---

### Task 4: Flask CLI, Jinja Filters, Security & Pedidos Edge-Cases Suite (`tests/test_pytest_cli_security.py`)

**Files:**
- Create: `tests/test_pytest_cli_security.py`

**Interfaces:**
- Consumes:
  - Fixtures from `tests/conftest.py`: `app`, `db_session`, `client`, `cli_runner`, `rbac_users`, `admin_client`, `agente_client`
  - `app.utils.filters.{format_currency, format_date, format_date_short, format_document, format_phone}`
  - `app.routes.auth.is_safe_redirect_url`
  - `app.models.user.{User, Grupo, PERFIL_ADMIN}`
  - `app.models.cliente.Cliente`, `app.models.pedido.Pedido`
- Produces:
  - Self-contained pytest suite in `tests/test_pytest_cli_security.py`

- [ ] **Step 1: Create `tests/test_pytest_cli_security.py`**

Crie `tests/test_pytest_cli_security.py`:

```python
from datetime import datetime
import pytest
from app.models.cliente import Cliente
from app.models.pedido import Pedido
from app.models.plano import Plano
from app.models.user import User, PERFIL_ADMIN
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
    # Senha com menos de 8 caracteres deve falhar
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


@pytest.mark.parametrize('target_url,is_safe', [
    ('/clientes', True),
    ('/pedidos?page=2', True),
    ('https://evil.example.com/phishing', False),
    ('//evil.example.com/phishing', False),
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


def test_pedido_boundary_10_items_and_bairro_normalization(admin_client, db_session):
    """
    Testa normalização de bairro no cadastro de cliente e criação de pedido
    no limite máximo de 10 itens com soma exata.
    """
    res_cli = admin_client.post('/clientes/novo', data={
        'nome': 'Condomínio Parque das Nações',
        'email': 'sindico@parquenacoes.com.br',
        'telefone': '(67) 99888-1122',
        'documento': '11.222.333/0001-44',
        'cep': '79040-010',
        'logradouro': 'Avenida Afonso Pena',
        'numero': '5500',
        'bairro': 'CHÁCARA CACHOEIRA',
        'cidade': 'Campo Grande',
        'estado': 'MS',
    }, follow_redirects=True)
    assert res_cli.status_code == 200

    cliente = Cliente.query.filter_by(email='sindico@parquenacoes.com.br').first()
    assert cliente is not None
    assert cliente.bairro == 'Chácara Cachoeira'

    # Monta pedido com exatamente 10 itens (limite máximo permitido)
    form_data = {
        'cliente_id': str(cliente.id),
        'status': 'aprovado',
        'observacoes': 'Pedido corporativo com 10 itens',
    }
    for i in range(10):
        form_data[f'itens-{i}-descricao'] = f'Ponto Adicional Mesh #{i + 1}'
        form_data[f'itens-{i}-quantidade'] = '2'
        form_data[f'itens-{i}-preco_unitario'] = '50.25'

    res_ped = admin_client.post('/pedidos/novo', data=form_data, follow_redirects=True)
    assert res_ped.status_code == 200

    pedido = Pedido.query.filter_by(cliente_id=cliente.id).first()
    assert pedido is not None
    assert len(pedido.itens) == 10
    # 10 itens * (2 * 50.25) = 1005.00
    assert abs(pedido.total - 1005.00) < 0.01
```

- [ ] **Step 2: Run `pytest tests/test_pytest_cli_security.py`**

Run: `.venv/bin/pytest tests/test_pytest_cli_security.py -v`
Expected: `24 passed`

- [ ] **Step 3: Commit Task 4**

```bash
git add tests/test_pytest_cli_security.py
git commit -m "test(cli-security): adicionar suite pytest para Flask CLI, filtros Jinja, seguranca e pedidos"
```

---

### Task 5: Full Integration, `unittest` Coexistence Verification & `setup.sh` Sync

**Files:**
- Modify: `scripts/gerar_setup.py:187-195`
- Modify: `setup.sh`

**Interfaces:**
- Consumes: All test files in `tests/`, `scripts/gerar_setup.py`
- Produces: Synchronized `setup.sh` passing `python scripts/gerar_setup.py --check` and full test runs passing under both `pytest` and `unittest`.

- [ ] **Step 1: Update `test.sh` template in `scripts/gerar_setup.py` to run `pytest` (which runs both `unittest` and `pytest` suites)**

Em `scripts/gerar_setup.py`, atualize o bloco `test.sh` (linhas 187-195) para executar `pytest` (com fallback para `unittest`):

```python
cat > test.sh <<'OMNI_EOF'
#!/usr/bin/env bash
# Executa a suíte completa de testes automatizados (unittest + pytest) no Linux
set -e
source .venv/bin/activate
echo "Executando suíte de testes automatizados (pytest + unittest)..."
python3 -m pytest -v
OMNI_EOF
```

- [ ] **Step 2: Regenerate `setup.sh` and verify `--check`**

Run: `.venv/bin/python scripts/gerar_setup.py && .venv/bin/python scripts/gerar_setup.py --check`
Expected: `setup.sh está atualizado.`

- [ ] **Step 3: Run both `pytest` and `unittest` full suites to verify 100% pass rate**

Run: `.venv/bin/pytest && .venv/bin/python -m unittest discover -s tests -v`
Expected:
- `pytest`: `110 passed` (60 legacy `unittest` + 50 new `pytest` test cases)
- `unittest`: `Ran 60 tests ... OK`

- [ ] **Step 4: Commit Task 5**

```bash
git add scripts/gerar_setup.py setup.sh
git commit -m "chore(setup): sincronizar setup.sh com a nova suite de testes pytest"
```
