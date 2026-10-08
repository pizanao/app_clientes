#!/usr/bin/env bash
# ==============================================================================
# Script de Criação e Configuração Automatizada - OmniGestão (Linux)
# ==============================================================================
# ARQUIVO GERADO AUTOMATICAMENTE por scripts/gerar_setup.py — não edite à mão.
# Para atualizar após mudanças no código: python scripts/gerar_setup.py
#
# Este script cria toda a estrutura de diretórios e todos os arquivos fonte,
# gera um .env com SECRET_KEY aleatória, instala as dependências Python em
# ambiente virtual (.venv), aplica as migrações do banco de dados, popula com
# dados de teste (seed) e executa os testes automatizados.
#
# Uso em uma pasta vazia:
#   chmod +x setup.sh
#   ./setup.sh
#
# Variáveis opcionais:
#   SEED_ADMIN_PASSWORD=MinhaSenha ./setup.sh   # senha do usuário "admin"
#   (se omitida, uma senha aleatória é gerada e exibida ao final do seed)
# ==============================================================================

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}===================================================================${NC}"
echo -e "${BLUE}    Iniciando a instalação e recriação do projeto OmniGestão       ${NC}"
echo -e "${BLUE}===================================================================${NC}"

# 1. Verificação de pré-requisitos no Linux
echo -e "\n${YELLOW}[1/6] Verificando pré-requisitos do sistema...${NC}"

if ! command -v python3 &> /dev/null; then
    echo -e "${RED}ERRO: python3 não foi encontrado. Instale com:${NC}"
    echo "  sudo apt update && sudo apt install -y python3 python3-venv python3-pip"
    exit 1
fi

if ! python3 -c "import venv" &> /dev/null; then
    echo -e "${RED}ERRO: o módulo venv não está disponível. Instale com:${NC}"
    echo "  sudo apt install -y python3-venv"
    exit 1
fi

echo -e "${GREEN}✓ Python 3 encontrado: $(python3 --version)${NC}"

# 2. Criação da estrutura de pastas
echo -e "\n${YELLOW}[2/6] Criando a estrutura de diretórios...${NC}"
mkdir -p \
    'app' \
    'app/forms' \
    'app/models' \
    'app/routes' \
    'app/static/css' \
    'app/static/js' \
    'app/templates' \
    'app/templates/auth' \
    'app/templates/clientes' \
    'app/templates/dashboard' \
    'app/templates/errors' \
    'app/templates/pedidos' \
    'app/utils' \
    'instance' \
    'migrations' \
    'migrations/versions' \
    'tests'
echo -e "${GREEN}✓ Estrutura de pastas criada com sucesso.${NC}"

# 3. Criação dos arquivos do projeto
echo -e "\n${YELLOW}[3/6] Criando 44 arquivos de código-fonte...${NC}"

# --- .env.example ---
cat > '.env.example' <<'OMNI_EOF'
FLASK_APP=wsgi.py
# 1 = desenvolvimento. Em produção use 0 e defina uma SECRET_KEY própria
# (a aplicação se recusa a iniciar sem ela fora do modo debug).
FLASK_DEBUG=1
# Gere com: python -c "import secrets; print(secrets.token_hex(32))"
SECRET_KEY=sua-chave-secreta-muito-segura-aqui
DATABASE_URL=sqlite:///app_clientes.db
# Senha do usuário "admin" criado pelo "flask seed".
# Se omitida, uma senha aleatória é gerada e exibida uma única vez.
# SEED_ADMIN_PASSWORD=
OMNI_EOF

# --- .gitignore ---
cat > '.gitignore' <<'OMNI_EOF'
# Python
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
build/
develop-eggs/
dist/
downloads/
eggs/
.eggs/
lib/
lib64/
parts/
sdist/
var/
wheels/
share/python-wheels/
*.egg-info/
.installed.cfg
*.egg

# Virtual Environment
.venv/
env/
venv/
ENV/

# Database & Sessions
instance/
*.db
*.sqlite3

# Environment
.env
.env.local

# IDE
.vscode/
.idea/
*.sublime-project
*.sublime-workspace
run.sh
seed.sh
test.sh
OMNI_EOF

# --- app/__init__.py ---
cat > 'app/__init__.py' <<'OMNI_EOF'
import os
from flask import Flask, render_template
from app.config import Config, DEV_SECRET_KEY
from app.extensions import db, migrate, login_manager, sess
from app.utils.filters import init_filters


def create_app(config_class=Config):
    app = Flask(__name__)
    app.config.from_object(config_class)

    # Fora de debug/teste, exige uma SECRET_KEY própria: com a chave padrão
    # qualquer pessoa conseguiria forjar cookies de sessão/"lembrar de mim".
    if not (app.debug or app.testing) and app.config.get('SECRET_KEY') in (None, '', DEV_SECRET_KEY):
        raise RuntimeError(
            'SECRET_KEY não configurada para produção. Defina a variável de ambiente '
            'SECRET_KEY (ex.: python -c "import secrets; print(secrets.token_hex(32))") '
            'ou use FLASK_DEBUG=1 em desenvolvimento.'
        )

    # Initialize Flask extensions
    db.init_app(app)
    migrate.init_app(app, db)
    login_manager.init_app(app)
    sess.init_app(app)

    # Register custom Jinja filters
    init_filters(app)

    # Register blueprints
    from app.routes.auth import auth_bp
    from app.routes.main import main_bp
    from app.routes.clientes import clientes_bp
    from app.routes.pedidos import pedidos_bp

    app.register_blueprint(auth_bp)
    app.register_blueprint(main_bp)
    app.register_blueprint(clientes_bp)
    app.register_blueprint(pedidos_bp)

    # Register CLI commands
    from app.cli import register_cli_commands
    register_cli_commands(app)

    # Error handlers
    @app.errorhandler(404)
    def not_found_error(error):
        return render_template('errors/404.html'), 404

    @app.errorhandler(500)
    def internal_error(error):
        db.session.rollback()
        return render_template('errors/500.html'), 500

    return app
OMNI_EOF

# --- app/cli.py ---
cat > 'app/cli.py' <<'OMNI_EOF'
import os
import secrets
import click
from datetime import datetime, timedelta
from flask.cli import with_appcontext
from app.extensions import db
from app.models.user import User
from app.models.cliente import Cliente
from app.models.pedido import Pedido, ItemPedido


def register_cli_commands(app):

    @app.cli.command('init-db')
    @with_appcontext
    def init_db_command():
        """Cria as tabelas do banco de dados diretamente."""
        db.create_all()
        click.echo('Banco de dados inicializado com sucesso!')

    @app.cli.command('create-admin')
    @click.option('--username', default='admin', help='Nome de usuário do admin.')
    @click.option('--email', default='admin@sistema.local', help='E-mail do admin.')
    @click.password_option('--password', help='Senha do admin (solicitada de forma oculta se omitida).')
    @with_appcontext
    def create_admin_command(username, email, password):
        """Cria um usuário administrador inicial."""
        if len(password) < 8:
            raise click.BadParameter('A senha deve ter pelo menos 8 caracteres.', param_hint='--password')

        user = User.query.filter((User.username == username) | (User.email == email)).first()
        if user:
            click.echo(f'Usuário {username} ou e-mail {email} já existe.')
            return

        admin = User(
            nome='Administrador do Sistema',
            username=username,
            email=email,
            ativo=True
        )
        admin.set_password(password)
        db.session.add(admin)
        db.session.commit()
        click.echo(f'Administrador "{username}" criado com sucesso!')

    @app.cli.command('seed')
    @with_appcontext
    def seed_command():
        """Popula o banco com usuário admin e dados fictícios de exemplo."""
        db.create_all()

        # Admin user
        admin = User.query.filter_by(username='admin').first()
        if not admin:
            # Sem senha fixa no código: usa SEED_ADMIN_PASSWORD ou gera uma aleatória
            senha_admin = os.environ.get('SEED_ADMIN_PASSWORD') or secrets.token_urlsafe(9)
            admin = User(
                nome='Administrador Master',
                username='admin',
                email='admin@exemplo.com',
                ativo=True
            )
            admin.set_password(senha_admin)
            db.session.add(admin)
            if os.environ.get('SEED_ADMIN_PASSWORD'):
                click.echo('Criado usuário "admin" com a senha definida em SEED_ADMIN_PASSWORD.')
            else:
                click.echo(f'Criado usuário "admin" com senha gerada: {senha_admin}')
                click.echo('Anote esta senha agora: ela não será exibida novamente.')

        # Sample clients
        if Cliente.query.count() == 0:
            clientes_exemplo = [
                Cliente(
                    nome='TechNova Soluções Digitais Ltda',
                    email='contato@technova.com.br',
                    telefone='(11) 98765-4321',
                    documento='12.345.678/0001-90',
                    cep='01310-100',
                    logradouro='Avenida Paulista',
                    numero='1000',
                    complemento='Conjunto 502',
                    bairro='Bela Vista',
                    cidade='São Paulo',
                    estado='SP',
                    ativo=True,
                    observacoes='Cliente corporativo, faturamento mensal.'
                ),
                Cliente(
                    nome='Mariana Albuquerque Silva',
                    email='mariana.albuquerque@gmail.com',
                    telefone='(21) 99876-5432',
                    documento='123.456.789-00',
                    cep='22041-001',
                    logradouro='Rua Barata Ribeiro',
                    numero='340',
                    complemento='Apto 402',
                    bairro='Copacabana',
                    cidade='Rio de Janeiro',
                    estado='RJ',
                    ativo=True,
                    observacoes='Cliente VIP desde 2024.'
                ),
                Cliente(
                    nome='Carlos Eduardo Mendes',
                    email='carlos.mendes@outlook.com',
                    telefone='(31) 98452-1122',
                    documento='987.654.321-99',
                    cep='30130-110',
                    logradouro='Avenida Afonso Pena',
                    numero='1500',
                    complemento='',
                    bairro='Centro',
                    cidade='Belo Horizonte',
                    estado='MG',
                    ativo=True,
                    observacoes='Prefere pagamentos via PIX.'
                ),
                Cliente(
                    nome='Distribuidora Sul Brasil',
                    email='compras@sulbrasil.com.br',
                    telefone='(41) 3222-8899',
                    documento='98.765.432/0001-11',
                    cep='80020-310',
                    logradouro='Rua XV de Novembro',
                    numero='780',
                    complemento='Loja 3',
                    bairro='Centro',
                    cidade='Curitiba',
                    estado='PR',
                    ativo=True,
                    observacoes='Pedido mínimo de 10 unidades.'
                ),
                Cliente(
                    nome='Juliana Prado Costa',
                    email='juliana.prado@yahoo.com.br',
                    telefone='(71) 99123-4567',
                    documento='333.444.555-66',
                    cep='40140-110',
                    logradouro='Avenida Oceânica',
                    numero='420',
                    complemento='Bloco B',
                    bairro='Barra',
                    cidade='Salvador',
                    estado='BA',
                    ativo=False,
                    observacoes='Cadastro temporariamente inativo a pedido do cliente.'
                ),
            ]
            db.session.add_all(clientes_exemplo)
            db.session.flush()

            # Sample orders with items
            pedidos_exemplo = [
                Pedido(
                    numero_pedido='PED-2026-0001',
                    cliente_id=clientes_exemplo[0].id,
                    data_pedido=datetime.utcnow() - timedelta(days=5),
                    status='concluido',
                    metodo_pagamento='pix',
                    valor_total=4850.00,
                    descricao='Desenvolvimento de módulo de relatórios e consultoria técnica especializada (40h).',
                    observacoes='Pago à vista via PIX com desconto de 5%.'
                ),
                Pedido(
                    numero_pedido='PED-2026-0002',
                    cliente_id=clientes_exemplo[1].id,
                    data_pedido=datetime.utcnow() - timedelta(days=3),
                    status='concluido',
                    metodo_pagamento='cartao_credito',
                    valor_total=1299.90,
                    descricao='Assinatura de plano anual Premium + Suporte prioritário 24/7.',
                    observacoes='Parcelado em 3x no cartão de crédito.'
                ),
                Pedido(
                    numero_pedido='PED-2026-0003',
                    cliente_id=clientes_exemplo[2].id,
                    data_pedido=datetime.utcnow() - timedelta(days=2),
                    status='processando',
                    metodo_pagamento='boleto',
                    valor_total=890.00,
                    descricao='Kit de equipamentos de automação e licença de software de gestão.',
                    observacoes='Aguardando compensação bancária do boleto emitido.'
                ),
                Pedido(
                    numero_pedido='PED-2026-0004',
                    cliente_id=clientes_exemplo[3].id,
                    data_pedido=datetime.utcnow() - timedelta(days=1),
                    status='pendente',
                    metodo_pagamento='pix',
                    valor_total=6420.50,
                    descricao='Lote de suprimentos de informática (cabos de rede Cat6, switches 8 portas gigabit).',
                    observacoes='Orçamento aprovado. Enviada chave PIX para faturamento.'
                ),
                Pedido(
                    numero_pedido='PED-2026-0005',
                    cliente_id=clientes_exemplo[0].id,
                    data_pedido=datetime.utcnow(),
                    status='pendente',
                    metodo_pagamento='transferencia',
                    valor_total=2500.00,
                    descricao='Renovação de hospedagem em nuvem e backup corporativo dedicado.',
                    observacoes='Fatura gerada com vencimento em 5 dias.'
                ),
            ]
            db.session.add_all(pedidos_exemplo)
            db.session.flush()

            # Add sample items for each order
            itens_exemplo = [
                # Pedido 1 (Total: 4850.00)
                ItemPedido(pedido_id=pedidos_exemplo[0].id, descricao='Desenvolvimento de módulo de relatórios personalizados', quantidade=1.0, valor_unitario=3500.00, valor_total=3500.00),
                ItemPedido(pedido_id=pedidos_exemplo[0].id, descricao='Consultoria técnica especializada (horas)', quantidade=10.0, valor_unitario=135.00, valor_total=1350.00),

                # Pedido 2 (Total: 1299.90)
                ItemPedido(pedido_id=pedidos_exemplo[1].id, descricao='Assinatura Anual Plano Premium Cloud', quantidade=1.0, valor_unitario=999.90, valor_total=999.90),
                ItemPedido(pedido_id=pedidos_exemplo[1].id, descricao='Pacote Suporte Prioritário 24/7 (trimestral)', quantidade=3.0, valor_unitario=100.00, valor_total=300.00),

                # Pedido 3 (Total: 890.00)
                ItemPedido(pedido_id=pedidos_exemplo[2].id, descricao='Kit de Equipamentos de Automação Comercial', quantidade=1.0, valor_unitario=590.00, valor_total=590.00),
                ItemPedido(pedido_id=pedidos_exemplo[2].id, descricao='Licença Adicional de Terminal OmniGestão', quantidade=1.0, valor_unitario=300.00, valor_total=300.00),

                # Pedido 4 (Total: 6420.50)
                ItemPedido(pedido_id=pedidos_exemplo[3].id, descricao='Cabo de Rede Furukawa Cat6 (Caixa 100m)', quantidade=2.0, valor_unitario=350.00, valor_total=700.00),
                ItemPedido(pedido_id=pedidos_exemplo[3].id, descricao='Switch Gigabit Ethernet 8 Portas TP-Link', quantidade=10.0, valor_unitario=180.00, valor_total=1800.00),
                ItemPedido(pedido_id=pedidos_exemplo[3].id, descricao='Roteador Corporativo Dual Band Wi-Fi 6', quantidade=3.0, valor_unitario=640.00, valor_total=1920.00),
                ItemPedido(pedido_id=pedidos_exemplo[3].id, descricao='Serviço de Conectorização e Certificação de Rede', quantidade=1.0, valor_unitario=2000.50, valor_total=2000.50),

                # Pedido 5 (Total: 2500.00)
                ItemPedido(pedido_id=pedidos_exemplo[4].id, descricao='Hospedagem Dedicada Cloud Server (Mensal)', quantidade=1.0, valor_unitario=1800.00, valor_total=1800.00),
                ItemPedido(pedido_id=pedidos_exemplo[4].id, descricao='Rotina de Backup Corporativo Offsite (500GB)', quantidade=1.0, valor_unitario=700.00, valor_total=700.00),
            ]
            db.session.add_all(itens_exemplo)
            click.echo('Clientes, Pedidos e Itens de exemplo cadastrados com sucesso!')

        db.session.commit()
        click.echo('Processo de Seed finalizado!')
OMNI_EOF

# --- app/config.py ---
cat > 'app/config.py' <<'OMNI_EOF'
import os
from datetime import timedelta

BASE_DIR = os.path.abspath(os.path.dirname(os.path.dirname(__file__)))
INSTANCE_DIR = os.path.join(BASE_DIR, 'instance')
os.makedirs(INSTANCE_DIR, exist_ok=True)

# Chave usada apenas em desenvolvimento/testes. create_app() recusa iniciar
# com ela (ou sem SECRET_KEY) quando a aplicação não está em modo debug/teste.
DEV_SECRET_KEY = 'dev-secret-key-super-secure-change-in-prod-12345'


class Config:
    """Base configuration."""
    SECRET_KEY = os.environ.get('SECRET_KEY') or DEV_SECRET_KEY
    
    # SQLAlchemy
    # No Flask-SQLAlchemy 3+, caminhos relativos SQLite (sqlite:///nome.db) já são resolvidos
    # automaticamente em relação a app.instance_path. Se o usuário fornecer 'sqlite:///instance/nome.db',
    # evita duplicação de pastas ('instance/instance/nome.db') que causa erro de abertura do SQLite.
    _raw_db_url = os.environ.get('DATABASE_URL')
    if not _raw_db_url:
        SQLALCHEMY_DATABASE_URI = f"sqlite:///{os.path.join(INSTANCE_DIR, 'app_clientes.db')}"
    elif _raw_db_url.startswith('sqlite:///instance/'):
        SQLALCHEMY_DATABASE_URI = _raw_db_url.replace('sqlite:///instance/', 'sqlite:///', 1)
    else:
        SQLALCHEMY_DATABASE_URI = _raw_db_url

    SQLALCHEMY_TRACK_MODIFICATIONS = False
    
    # Flask-Session using CacheLib FileSystemCache
    from cachelib.file import FileSystemCache
    SESSION_TYPE = 'cachelib'
    SESSION_CACHELIB = FileSystemCache(cache_dir=os.path.join(INSTANCE_DIR, 'flask_sessions'), threshold=100)
    SESSION_PERMANENT = True
    PERMANENT_SESSION_LIFETIME = timedelta(days=1)
    
    # WTForms CSRF
    WTF_CSRF_ENABLED = True
OMNI_EOF

# --- app/extensions.py ---
cat > 'app/extensions.py' <<'OMNI_EOF'
from flask_sqlalchemy import SQLAlchemy
from flask_migrate import Migrate
from flask_login import LoginManager
from flask_session import Session

db = SQLAlchemy()
migrate = Migrate()
login_manager = LoginManager()
sess = Session()

login_manager.login_view = 'auth.login'
login_manager.login_message = 'Por favor, faça login para acessar esta página.'
login_manager.login_message_category = 'warning'
OMNI_EOF

# --- app/forms/__init__.py ---
cat > 'app/forms/__init__.py' <<'OMNI_EOF'
from app.forms.auth_forms import LoginForm, RegisterForm
from app.forms.cliente_forms import ClienteForm
from app.forms.pedido_forms import PedidoForm

__all__ = ['LoginForm', 'RegisterForm', 'ClienteForm', 'PedidoForm']
OMNI_EOF

# --- app/forms/auth_forms.py ---
cat > 'app/forms/auth_forms.py' <<'OMNI_EOF'
from flask_wtf import FlaskForm
from wtforms import StringField, PasswordField, BooleanField, SubmitField
from wtforms.validators import DataRequired, Email, Length, EqualTo, ValidationError
from app.models.user import User


class LoginForm(FlaskForm):
    login = StringField('Usuário ou E-mail', validators=[
        DataRequired(message='Informe seu usuário ou e-mail.')
    ])
    password = PasswordField('Senha', validators=[
        DataRequired(message='Informe sua senha.')
    ])
    remember = BooleanField('Lembrar de mim')
    submit = SubmitField('Entrar no Sistema')


class RegisterForm(FlaskForm):
    nome = StringField('Nome Completo', validators=[
        DataRequired(message='O nome é obrigatório.'),
        Length(min=3, max=100, message='O nome deve ter entre 3 e 100 caracteres.')
    ])
    username = StringField('Nome de Usuário', validators=[
        DataRequired(message='O nome de usuário é obrigatório.'),
        Length(min=3, max=50, message='O usuário deve ter entre 3 e 50 caracteres.')
    ])
    email = StringField('E-mail', validators=[
        DataRequired(message='O e-mail é obrigatório.'),
        Email(message='Informe um e-mail válido.')
    ])
    password = PasswordField('Senha', validators=[
        DataRequired(message='A senha é obrigatória.'),
        Length(min=6, message='A senha deve ter pelo menos 6 caracteres.')
    ])
    confirm_password = PasswordField('Confirmar Senha', validators=[
        DataRequired(message='Confirme a senha.'),
        EqualTo('password', message='As senhas não coincidem.')
    ])
    submit = SubmitField('Criar Conta')

    def validate_username(self, field):
        if User.query.filter_by(username=field.data.strip()).first():
            raise ValidationError('Este nome de usuário já está em uso.')

    def validate_email(self, field):
        if User.query.filter_by(email=field.data.strip().lower()).first():
            raise ValidationError('Este e-mail já está cadastrado.')
OMNI_EOF

# --- app/forms/cliente_forms.py ---
cat > 'app/forms/cliente_forms.py' <<'OMNI_EOF'
from flask_wtf import FlaskForm
from wtforms import StringField, BooleanField, TextAreaField, SelectField, SubmitField
from wtforms.validators import DataRequired, Email, Length, Optional

ESTADOS_BRASIL = [
    ('', 'Selecione o Estado'),
    ('AC', 'Acre (AC)'),
    ('AL', 'Alagoas (AL)'),
    ('AP', 'Amapá (AP)'),
    ('AM', 'Amazonas (AM)'),
    ('BA', 'Bahia (BA)'),
    ('CE', 'Ceará (CE)'),
    ('DF', 'Distrito Federal (DF)'),
    ('ES', 'Espírito Santo (ES)'),
    ('GO', 'Goiás (GO)'),
    ('MA', 'Maranhão (MA)'),
    ('MT', 'Mato Grosso (MT)'),
    ('MS', 'Mato Grosso do Sul (MS)'),
    ('MG', 'Minas Gerais (MG)'),
    ('PA', 'Pará (PA)'),
    ('PB', 'Paraíba (PB)'),
    ('PR', 'Paraná (PR)'),
    ('PE', 'Pernambuco (PE)'),
    ('PI', 'Piauí (PI)'),
    ('RJ', 'Rio de Janeiro (RJ)'),
    ('RN', 'Rio Grande do Norte (RN)'),
    ('RS', 'Rio Grande do Sul (RS)'),
    ('RO', 'Rondônia (RO)'),
    ('RR', 'Roraima (RR)'),
    ('SC', 'Santa Catarina (SC)'),
    ('SP', 'São Paulo (SP)'),
    ('SE', 'Sergipe (SE)'),
    ('TO', 'Tocantins (TO)'),
]


class ClienteForm(FlaskForm):
    nome = StringField('Nome Completo / Razão Social *', validators=[
        DataRequired(message='O nome do cliente é obrigatório.'),
        Length(min=3, max=120, message='O nome deve ter entre 3 e 120 caracteres.')
    ])
    email = StringField('E-mail *', validators=[
        DataRequired(message='O e-mail é obrigatório.'),
        Email(message='Informe um e-mail válido.')
    ])
    telefone = StringField('Telefone / WhatsApp', validators=[
        Optional(),
        Length(max=30)
    ])
    documento = StringField('CPF ou CNPJ', validators=[
        Optional(),
        Length(max=30)
    ])
    cep = StringField('CEP', validators=[
        Optional(),
        Length(max=15)
    ])
    logradouro = StringField('Logradouro (Rua, Av, etc)', validators=[
        Optional(),
        Length(max=150)
    ])
    numero = StringField('Número', validators=[
        Optional(),
        Length(max=20)
    ])
    complemento = StringField('Complemento (Apto, Sala)', validators=[
        Optional(),
        Length(max=50)
    ])
    bairro = StringField('Bairro', validators=[
        Optional(),
        Length(max=80)
    ])
    cidade = StringField('Cidade', validators=[
        Optional(),
        Length(max=80)
    ])
    estado = SelectField('Estado (UF)', choices=ESTADOS_BRASIL, validators=[
        Optional()
    ])
    ativo = BooleanField('Cliente Ativo', default=True)
    observacoes = TextAreaField('Observações Internas', validators=[
        Optional()
    ])
    submit = SubmitField('Salvar Cliente')
OMNI_EOF

# --- app/forms/pedido_forms.py ---
cat > 'app/forms/pedido_forms.py' <<'OMNI_EOF'
from datetime import datetime
from flask_wtf import FlaskForm
from wtforms import (
    StringField, SelectField, TextAreaField, DecimalField,
    DateTimeLocalField, SubmitField, HiddenField, Form
)
from wtforms.validators import DataRequired, NumberRange, Optional, Length


class ItemPedidoForm(Form):
    """Subformulário para itens individuais do pedido."""
    id = HiddenField('ID')
    descricao = StringField('Descrição do Item *', validators=[
        DataRequired(message='A descrição do item é obrigatória.'),
        Length(min=2, max=255, message='A descrição deve ter entre 2 e 255 caracteres.')
    ])
    quantidade = DecimalField('Quantidade *', places=2, validators=[
        DataRequired(message='Informe a quantidade do item.'),
        NumberRange(min=0.01, message='A quantidade deve ser maior que zero.')
    ])
    valor_unitario = DecimalField('Valor Unitário (R$) *', places=2, validators=[
        DataRequired(message='Informe o valor unitário do item.'),
        NumberRange(min=0.01, message='O valor unitário deve ser maior que zero.')
    ])
    valor_total = DecimalField('Valor Total (R$)', places=2, validators=[
        Optional()
    ])


class PedidoForm(FlaskForm):
    cliente_id = SelectField('Cliente *', coerce=int, validators=[
        DataRequired(message='Selecione um cliente.')
    ])
    numero_pedido = StringField('Número do Pedido *', validators=[
        DataRequired(message='O número do pedido é obrigatório.'),
        Length(max=30)
    ])
    data_pedido = DateTimeLocalField('Data e Hora do Pedido *', format='%Y-%m-%dT%H:%M', default=datetime.utcnow, validators=[
        DataRequired(message='Informe a data do pedido.')
    ])
    status = SelectField('Status do Pedido *', choices=[
        ('pendente', 'Pendente'),
        ('processando', 'Em Processamento'),
        ('concluido', 'Concluído'),
        ('cancelado', 'Cancelado')
    ], default='pendente', validators=[
        DataRequired(message='Selecione o status do pedido.')
    ])
    metodo_pagamento = SelectField('Método de Pagamento *', choices=[
        ('pix', 'PIX'),
        ('cartao_credito', 'Cartão de Crédito'),
        ('cartao_debito', 'Cartão de Débito'),
        ('boleto', 'Boleto Bancário'),
        ('transferencia', 'Transferência / TED'),
        ('dinheiro', 'Dinheiro em Espécie')
    ], default='pix', validators=[
        DataRequired(message='Selecione o método de pagamento.')
    ])
    valor_total = DecimalField('Valor Total (R$)', places=2, validators=[
        Optional()
    ])
    descricao = TextAreaField('Resumo Geral / Descrição do Pedido', validators=[
        Optional()
    ])
    observacoes = TextAreaField('Observações Adicionais', validators=[
        Optional()
    ])
    submit = SubmitField('Salvar Pedido')

OMNI_EOF

# --- app/models/__init__.py ---
cat > 'app/models/__init__.py' <<'OMNI_EOF'
from app.models.user import User
from app.models.cliente import Cliente
from app.models.pedido import Pedido, ItemPedido

__all__ = ['User', 'Cliente', 'Pedido', 'ItemPedido']

OMNI_EOF

# --- app/models/cliente.py ---
cat > 'app/models/cliente.py' <<'OMNI_EOF'
from datetime import datetime
from app.extensions import db


class Cliente(db.Model):
    __tablename__ = 'clientes'

    id = db.Column(db.Integer, primary_key=True)
    nome = db.Column(db.String(120), nullable=False, index=True)
    email = db.Column(db.String(120), nullable=False, index=True)
    telefone = db.Column(db.String(30), nullable=True)
    documento = db.Column(db.String(30), nullable=True, index=True)  # CPF or CNPJ
    cep = db.Column(db.String(15), nullable=True)
    logradouro = db.Column(db.String(150), nullable=True)
    numero = db.Column(db.String(20), nullable=True)
    complemento = db.Column(db.String(50), nullable=True)
    bairro = db.Column(db.String(80), nullable=True)
    cidade = db.Column(db.String(80), nullable=True)
    estado = db.Column(db.String(2), nullable=True)  # UF
    ativo = db.Column(db.Boolean, default=True, nullable=False)
    observacoes = db.Column(db.Text, nullable=True)
    
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    # Relationship to Pedidos
    pedidos = db.relationship(
        'Pedido',
        backref='cliente',
        lazy=True,
        cascade='all, delete-orphan',
        order_by='desc(Pedido.data_pedido)'
    )

    @property
    def total_pedidos(self) -> int:
        return len(self.pedidos)

    @property
    def valor_total_gasto(self) -> float:
        return sum(p.valor_total for p in self.pedidos if p.status != 'cancelado')

    @property
    def endereco_completo(self) -> str:
        partes = []
        if self.logradouro:
            partes.append(f"{self.logradouro}, {self.numero or 'S/N'}")
        if self.bairro:
            partes.append(self.bairro)
        if self.cidade and self.estado:
            partes.append(f"{self.cidade}/{self.estado}")
        elif self.cidade:
            partes.append(self.cidade)
        if self.cep:
            partes.append(f"CEP: {self.cep}")
        return " - ".join(partes) if partes else "Endereço não informado"

    def __repr__(self):
        return f'<Cliente {self.nome}>'
OMNI_EOF

# --- app/models/pedido.py ---
cat > 'app/models/pedido.py' <<'OMNI_EOF'
from datetime import datetime
from app.extensions import db


class ItemPedido(db.Model):
    __tablename__ = 'itens_pedido'

    id = db.Column(db.Integer, primary_key=True)
    pedido_id = db.Column(db.Integer, db.ForeignKey('pedidos.id', ondelete='CASCADE'), nullable=False, index=True)
    descricao = db.Column(db.String(255), nullable=False)
    quantidade = db.Column(db.Float, nullable=False, default=1.0)
    valor_unitario = db.Column(db.Float, nullable=False, default=0.0)
    valor_total = db.Column(db.Float, nullable=False, default=0.0)
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)

    def calcular_total(self) -> float:
        """Calcula e atualiza o valor total do item (Qtd * Vlr Unitario)."""
        qtd = float(self.quantidade or 0.0)
        unit = float(self.valor_unitario or 0.0)
        self.valor_total = round(qtd * unit, 2)
        return self.valor_total

    def __repr__(self):
        return f'<ItemPedido #{self.id}: {self.descricao} ({self.quantidade} x R$ {self.valor_unitario:.2f})>'


class Pedido(db.Model):
    __tablename__ = 'pedidos'

    id = db.Column(db.Integer, primary_key=True)
    numero_pedido = db.Column(db.String(30), unique=True, nullable=False, index=True)
    cliente_id = db.Column(db.Integer, db.ForeignKey('clientes.id', ondelete='CASCADE'), nullable=False, index=True)
    data_pedido = db.Column(db.DateTime, default=datetime.utcnow, nullable=False, index=True)
    status = db.Column(db.String(25), default='pendente', nullable=False, index=True)
    metodo_pagamento = db.Column(db.String(30), default='pix', nullable=False)
    valor_total = db.Column(db.Float, default=0.0, nullable=False)
    descricao = db.Column(db.Text, nullable=True)
    observacoes = db.Column(db.Text, nullable=True)

    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    # Relacionamento 1:N com Itens do Pedido (1 a 10 itens por pedido)
    itens = db.relationship(
        'ItemPedido',
        backref='pedido',
        lazy='joined',
        cascade='all, delete-orphan',
        order_by='ItemPedido.id.asc()'
    )

    STATUS_CHOICES = {
        'pendente': ('Pendente', 'bg-warning text-dark'),
        'processando': ('Em Processamento', 'bg-info text-white'),
        'concluido': ('Concluído', 'bg-success text-white'),
        'cancelado': ('Cancelado', 'bg-danger text-white'),
    }

    METODOS_PAGAMENTO = {
        'pix': 'PIX',
        'cartao_credito': 'Cartão de Crédito',
        'cartao_debito': 'Cartão de Débito',
        'boleto': 'Boleto Bancário',
        'transferencia': 'Transferência / TED',
        'dinheiro': 'Dinheiro em Espécie',
    }

    @property
    def status_label(self) -> str:
        return self.STATUS_CHOICES.get(self.status, (self.status, 'bg-secondary'))[0]

    @property
    def status_badge_class(self) -> str:
        return self.STATUS_CHOICES.get(self.status, (self.status, 'bg-secondary'))[1]

    @property
    def metodo_pagamento_label(self) -> str:
        return self.METODOS_PAGAMENTO.get(self.metodo_pagamento, self.metodo_pagamento)

    @property
    def total_itens(self) -> int:
        return len(self.itens)

    @property
    def resumo_itens(self) -> str:
        if self.itens:
            return ", ".join(item.descricao for item in self.itens)
        return self.descricao or "Sem itens cadastrados"

    def recalcular_total(self) -> float:
        """Totaliza o valor do pedido com base nos itens cadastrados."""
        total = sum(item.calcular_total() for item in self.itens)
        self.valor_total = round(total, 2)
        return self.valor_total

    def __repr__(self):
        return f'<Pedido {self.numero_pedido} - Cliente {self.cliente_id}>'

OMNI_EOF

# --- app/models/user.py ---
cat > 'app/models/user.py' <<'OMNI_EOF'
from datetime import datetime
from flask_login import UserMixin
from werkzeug.security import generate_password_hash, check_password_hash
from app.extensions import db, login_manager


class User(UserMixin, db.Model):
    __tablename__ = 'usuarios'

    id = db.Column(db.Integer, primary_key=True)
    nome = db.Column(db.String(100), nullable=False)
    username = db.Column(db.String(50), unique=True, nullable=False, index=True)
    email = db.Column(db.String(120), unique=True, nullable=False, index=True)
    password_hash = db.Column(db.String(255), nullable=False)
    ativo = db.Column(db.Boolean, default=True, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)

    def set_password(self, password: str):
        self.password_hash = generate_password_hash(password)

    def check_password(self, password: str) -> bool:
        return check_password_hash(self.password_hash, password)

    def __repr__(self):
        return f'<User {self.username}>'


@login_manager.user_loader
def load_user(user_id):
    return db.session.get(User, int(user_id))
OMNI_EOF

# --- app/routes/__init__.py ---
cat > 'app/routes/__init__.py' <<'OMNI_EOF'
from app.routes.auth import auth_bp
from app.routes.main import main_bp
from app.routes.clientes import clientes_bp
from app.routes.pedidos import pedidos_bp

__all__ = ['auth_bp', 'main_bp', 'clientes_bp', 'pedidos_bp']
OMNI_EOF

# --- app/routes/auth.py ---
cat > 'app/routes/auth.py' <<'OMNI_EOF'
from urllib.parse import urlsplit
from flask import Blueprint, render_template, redirect, url_for, flash, request
from flask_login import login_user, logout_user, login_required, current_user
from app.extensions import db
from app.models.user import User
from app.forms.auth_forms import LoginForm, RegisterForm

auth_bp = Blueprint('auth', __name__, url_prefix='/auth')


def is_safe_redirect_url(target):
    """
    Aceita apenas caminhos relativos ao próprio site (ex.: '/clientes/1').
    Rejeita URLs absolutas e variantes como '//host' ou '/\\host', que os
    navegadores interpretam como endereço externo (open redirect).
    """
    if not target:
        return False
    normalized = target.strip().replace('\\', '/')
    if not normalized.startswith('/') or normalized.startswith('//'):
        return False
    parts = urlsplit(normalized)
    return not parts.scheme and not parts.netloc


@auth_bp.route('/login', methods=['GET', 'POST'])
def login():
    if current_user.is_authenticated:
        return redirect(url_for('main.dashboard'))

    form = LoginForm()
    if form.validate_on_submit():
        login_input = form.login.data.strip()
        # Find by username or email
        user = User.query.filter(
            (User.username == login_input) | (User.email == login_input.lower())
        ).first()

        if user and user.check_password(form.password.data):
            if not user.ativo:
                flash('Sua conta está desativada. Entre em contato com o suporte.', 'danger')
                return render_template('auth/login.html', form=form)

            login_user(user, remember=form.remember.data)
            flash(f'Bem-vindo(a) de volta, {user.nome}!', 'success')
            next_page = request.args.get('next')
            if not is_safe_redirect_url(next_page):
                next_page = url_for('main.dashboard')
            return redirect(next_page)
        else:
            flash('Usuário/E-mail ou senha incorretos.', 'danger')

    return render_template('auth/login.html', form=form)


@auth_bp.route('/register', methods=['GET', 'POST'])
def register():
    if current_user.is_authenticated:
        return redirect(url_for('main.dashboard'))

    form = RegisterForm()
    if form.validate_on_submit():
        user = User(
            nome=form.nome.data.strip(),
            username=form.username.data.strip(),
            email=form.email.data.strip().lower()
        )
        user.set_password(form.password.data)
        
        db.session.add(user)
        db.session.commit()

        flash('Conta criada com sucesso! Faça login para continuar.', 'success')
        return redirect(url_for('auth.login'))

    return render_template('auth/register.html', form=form)


@auth_bp.route('/logout')
@login_required
def logout():
    logout_user()
    flash('Você saiu do sistema com segurança.', 'info')
    return redirect(url_for('auth.login'))
OMNI_EOF

# --- app/routes/clientes.py ---
cat > 'app/routes/clientes.py' <<'OMNI_EOF'
from flask import Blueprint, render_template, redirect, url_for, flash, request
from flask_login import login_required
from sqlalchemy import or_
from app.extensions import db
from app.models.cliente import Cliente
from app.models.pedido import Pedido
from app.forms.cliente_forms import ClienteForm

clientes_bp = Blueprint('clientes', __name__, url_prefix='/clientes')


@clientes_bp.route('/')
@login_required
def index():
    search = request.args.get('q', '').strip()
    status_filter = request.args.get('status', 'todos')
    
    query = Cliente.query

    if search:
        search_term = f"%{search}%"
        query = query.filter(
            or_(
                Cliente.nome.ilike(search_term),
                Cliente.email.ilike(search_term),
                Cliente.documento.ilike(search_term),
                Cliente.telefone.ilike(search_term),
                Cliente.cidade.ilike(search_term)
            )
        )

    if status_filter == 'ativo':
        query = query.filter(Cliente.ativo == True)
    elif status_filter == 'inativo':
        query = query.filter(Cliente.ativo == False)

    clientes = query.order_by(Cliente.nome.asc()).all()
    
    return render_template(
        'clientes/index.html',
        clientes=clientes,
        search=search,
        status_filter=status_filter,
        total_encontrados=len(clientes)
    )


@clientes_bp.route('/novo', methods=['GET', 'POST'])
@login_required
def novo():
    form = ClienteForm()
    if form.validate_on_submit():
        cliente = Cliente(
            nome=form.nome.data.strip(),
            email=form.email.data.strip().lower(),
            telefone=form.telefone.data.strip() if form.telefone.data else None,
            documento=form.documento.data.strip() if form.documento.data else None,
            cep=form.cep.data.strip() if form.cep.data else None,
            logradouro=form.logradouro.data.strip() if form.logradouro.data else None,
            numero=form.numero.data.strip() if form.numero.data else None,
            complemento=form.complemento.data.strip() if form.complemento.data else None,
            bairro=form.bairro.data.strip() if form.bairro.data else None,
            cidade=form.cidade.data.strip() if form.cidade.data else None,
            estado=form.estado.data if form.estado.data else None,
            ativo=form.ativo.data,
            observacoes=form.observacoes.data.strip() if form.observacoes.data else None
        )
        db.session.add(cliente)
        db.session.commit()
        flash(f'Cliente "{cliente.nome}" cadastrado com sucesso!', 'success')
        return redirect(url_for('clientes.detalhe', id=cliente.id))

    return render_template('clientes/form.html', form=form, titulo='Novo Cliente', acao='Cadastrar')


@clientes_bp.route('/<int:id>')
@login_required
def detalhe(id):
    cliente = db.session.get(Cliente, id)
    if not cliente:
        flash('Cliente não encontrado.', 'danger')
        return redirect(url_for('clientes.index'))

    # Statistics for this client
    pedidos = cliente.pedidos
    pedidos_concluidos = [p for p in pedidos if p.status == 'concluido']
    total_gasto = sum(p.valor_total for p in pedidos if p.status != 'cancelado')

    return render_template(
        'clientes/detail.html',
        cliente=cliente,
        pedidos=pedidos,
        pedidos_concluidos=pedidos_concluidos,
        total_gasto=total_gasto
    )


@clientes_bp.route('/<int:id>/editar', methods=['GET', 'POST'])
@login_required
def editar(id):
    cliente = db.session.get(Cliente, id)
    if not cliente:
        flash('Cliente não encontrado.', 'danger')
        return redirect(url_for('clientes.index'))

    form = ClienteForm(obj=cliente)
    if form.validate_on_submit():
        cliente.nome = form.nome.data.strip()
        cliente.email = form.email.data.strip().lower()
        cliente.telefone = form.telefone.data.strip() if form.telefone.data else None
        cliente.documento = form.documento.data.strip() if form.documento.data else None
        cliente.cep = form.cep.data.strip() if form.cep.data else None
        cliente.logradouro = form.logradouro.data.strip() if form.logradouro.data else None
        cliente.numero = form.numero.data.strip() if form.numero.data else None
        cliente.complemento = form.complemento.data.strip() if form.complemento.data else None
        cliente.bairro = form.bairro.data.strip() if form.bairro.data else None
        cliente.cidade = form.cidade.data.strip() if form.cidade.data else None
        cliente.estado = form.estado.data if form.estado.data else None
        cliente.ativo = form.ativo.data
        cliente.observacoes = form.observacoes.data.strip() if form.observacoes.data else None

        db.session.commit()
        flash(f'Cliente "{cliente.nome}" atualizado com sucesso!', 'success')
        return redirect(url_for('clientes.detalhe', id=cliente.id))

    return render_template('clientes/form.html', form=form, cliente=cliente, titulo='Editar Cliente', acao='Salvar Alterações')


@clientes_bp.route('/<int:id>/excluir', methods=['POST'])
@login_required
def excluir(id):
    cliente = db.session.get(Cliente, id)
    if not cliente:
        flash('Cliente não encontrado.', 'danger')
        return redirect(url_for('clientes.index'))

    nome = cliente.nome
    total_pedidos = len(cliente.pedidos)
    db.session.delete(cliente)
    db.session.commit()

    if total_pedidos > 0:
        flash(f'Cliente "{nome}" e seus {total_pedidos} pedidos vinculados foram excluídos com sucesso.', 'info')
    else:
        flash(f'Cliente "{nome}" excluído com sucesso.', 'info')

    return redirect(url_for('clientes.index'))
OMNI_EOF

# --- app/routes/main.py ---
cat > 'app/routes/main.py' <<'OMNI_EOF'
from flask import Blueprint, render_template, redirect, url_for
from flask_login import login_required, current_user
from sqlalchemy import func
from app.extensions import db
from app.models.cliente import Cliente
from app.models.pedido import Pedido

main_bp = Blueprint('main', __name__)


@main_bp.route('/')
def index():
    if current_user.is_authenticated:
        return redirect(url_for('main.dashboard'))
    return redirect(url_for('auth.login'))


@main_bp.route('/dashboard')
@login_required
def dashboard():
    # Metrics
    total_clientes = Cliente.query.count()
    clientes_ativos = Cliente.query.filter_by(ativo=True).count()
    total_pedidos = Pedido.query.count()

    # Pedidos counts by status
    pedidos_pendentes = Pedido.query.filter_by(status='pendente').count()
    pedidos_processando = Pedido.query.filter_by(status='processando').count()
    pedidos_concluidos = Pedido.query.filter_by(status='concluido').count()
    pedidos_cancelados = Pedido.query.filter_by(status='cancelado').count()

    # Revenue
    faturamento_total = db.session.query(
        func.coalesce(func.sum(Pedido.valor_total), 0.0)
    ).filter(Pedido.status != 'cancelado').scalar() or 0.0

    faturamento_concluido = db.session.query(
        func.coalesce(func.sum(Pedido.valor_total), 0.0)
    ).filter(Pedido.status == 'concluido').scalar() or 0.0

    # O faturamento ignora pedidos cancelados, então o divisor também deve ignorá-los
    pedidos_validos = total_pedidos - pedidos_cancelados
    ticket_medio = (faturamento_total / pedidos_validos) if pedidos_validos > 0 else 0.0

    # Recent items
    ultimos_clientes = Cliente.query.order_by(Cliente.created_at.desc()).limit(5).all()
    ultimos_pedidos = Pedido.query.order_by(Pedido.data_pedido.desc()).limit(5).all()

    return render_template(
        'dashboard/index.html',
        total_clientes=total_clientes,
        clientes_ativos=clientes_ativos,
        total_pedidos=total_pedidos,
        pedidos_pendentes=pedidos_pendentes,
        pedidos_processando=pedidos_processando,
        pedidos_concluidos=pedidos_concluidos,
        pedidos_cancelados=pedidos_cancelados,
        faturamento_total=faturamento_total,
        faturamento_concluido=faturamento_concluido,
        ticket_medio=ticket_medio,
        ultimos_clientes=ultimos_clientes,
        ultimos_pedidos=ultimos_pedidos
    )
OMNI_EOF

# --- app/routes/pedidos.py ---
cat > 'app/routes/pedidos.py' <<'OMNI_EOF'
from datetime import datetime
from flask import Blueprint, render_template, redirect, url_for, flash, request
from flask_login import login_required
from sqlalchemy import or_
from app.extensions import db
from app.models.cliente import Cliente
from app.models.pedido import Pedido, ItemPedido
from app.forms.pedido_forms import PedidoForm

pedidos_bp = Blueprint('pedidos', __name__, url_prefix='/pedidos')


def gerar_numero_pedido():
    """Generates an automatic order code: PED-YYYY-XXXX."""
    ano_atual = datetime.utcnow().year
    ultimo_pedido = Pedido.query.filter(
        Pedido.numero_pedido.like(f"PED-{ano_atual}-%")
    ).order_by(Pedido.id.desc()).first()

    if ultimo_pedido:
        try:
            ultimo_num = int(ultimo_pedido.numero_pedido.split('-')[-1])
            proximo = ultimo_num + 1
        except (ValueError, IndexError):
            proximo = Pedido.query.count() + 1
    else:
        proximo = 1

    return f"PED-{ano_atual}-{proximo:04d}"


def processar_itens_post(request_form):
    """
    Processa e valida os itens submetidos no formulário.
    Regras de negócio:
    - Pelo menos 1 item e no máximo 10 itens por pedido
    - Descrição não vazia
    - Quantidade > 0
    - Valor unitário > 0
    - Valor total do item = round(quantidade * valor_unitario, 2)
    - Valor total do pedido = soma dos valores totais dos itens

    Retorna: (itens_data, lista_de_erros, valor_total_pedido)
    """
    indices = set()
    for key in request_form.keys():
        if key.startswith('itens-') and '-' in key[6:]:
            part = key[6:].split('-')[0]
            if part.isdigit():
                indices.add(int(part))

    itens_data = []
    erros = []

    # Se não houver campos itens-* mas houver descricao e valor_total (compatibilidade legada)
    if not indices:
        desc_legado = (request_form.get('descricao') or '').strip()
        val_legado_str = (request_form.get('valor_total') or '').replace(',', '.').strip()
        if desc_legado and val_legado_str:
            try:
                val_legado = float(val_legado_str)
                if val_legado > 0:
                    item_legado = {
                        'id': '',
                        'descricao': desc_legado,
                        'quantidade': 1.0,
                        'valor_unitario': val_legado,
                        'valor_total': val_legado
                    }
                    return [item_legado], [], val_legado
            except ValueError:
                pass

        erros.append('O pedido deve conter pelo menos 1 item.')
        return itens_data, erros, 0.0

    sorted_indices = sorted(list(indices))

    for idx in sorted_indices:
        desc = (request_form.get(f'itens-{idx}-descricao') or '').strip()
        qtd_raw = (request_form.get(f'itens-{idx}-quantidade') or '').replace(',', '.').strip()
        unit_raw = (request_form.get(f'itens-{idx}-valor_unitario') or '').replace(',', '.').strip()
        item_id = (request_form.get(f'itens-{idx}-id') or '').strip()

        # Se a linha estiver inteiramente em branco e houver outras preenchidas, podemos ignorar
        if not desc and not qtd_raw and not unit_raw:
            continue

        item_pos = len(itens_data) + 1

        if not desc:
            erros.append(f'Item #{item_pos}: A descrição do item é obrigatória.')

        try:
            qtd = float(qtd_raw)
            if qtd <= 0:
                erros.append(f'Item #{item_pos}: A quantidade deve ser maior que zero.')
        except (ValueError, TypeError):
            erros.append(f'Item #{item_pos}: Quantidade inválida.')
            qtd = 0.0

        try:
            unit = float(unit_raw)
            if unit <= 0:
                erros.append(f'Item #{item_pos}: O valor unitário deve ser maior que zero.')
        except (ValueError, TypeError):
            erros.append(f'Item #{item_pos}: Valor unitário inválido.')
            unit = 0.0

        total_item = round(qtd * unit, 2)

        itens_data.append({
            'id': item_id,
            'descricao': desc,
            'quantidade': qtd,
            'valor_unitario': unit,
            'valor_total': total_item
        })

    # Validação do limite de 1 a 10 itens
    if len(itens_data) < 1:
        erros.append('O pedido deve conter pelo menos 1 item.')
    elif len(itens_data) > 10:
        erros.append(f'O pedido pode conter no máximo 10 itens (atualmente possui {len(itens_data)}).')

    total_pedido = round(sum(it['valor_total'] for it in itens_data), 2)
    return itens_data, erros, total_pedido


@pedidos_bp.route('/')
@login_required
def index():
    search = request.args.get('q', '').strip()
    status_filter = request.args.get('status', 'todos')
    cliente_filter = request.args.get('cliente_id', type=int)

    query = Pedido.query.join(Cliente)

    if search:
        search_term = f"%{search}%"
        query = query.outerjoin(ItemPedido).filter(
            or_(
                Pedido.numero_pedido.ilike(search_term),
                Pedido.descricao.ilike(search_term),
                ItemPedido.descricao.ilike(search_term),
                Cliente.nome.ilike(search_term)
            )
        ).distinct()

    if status_filter and status_filter != 'todos':
        query = query.filter(Pedido.status == status_filter)

    if cliente_filter:
        query = query.filter(Pedido.cliente_id == cliente_filter)

    pedidos = query.order_by(Pedido.data_pedido.desc()).all()
    clientes = Cliente.query.order_by(Cliente.nome.asc()).all()

    total_valor = sum(p.valor_total for p in pedidos if p.status != 'cancelado')

    return render_template(
        'pedidos/index.html',
        pedidos=pedidos,
        clientes=clientes,
        search=search,
        status_filter=status_filter,
        cliente_filter=cliente_filter,
        total_valor=total_valor,
        total_encontrados=len(pedidos)
    )


@pedidos_bp.route('/novo', methods=['GET', 'POST'])
@login_required
def novo():
    clientes = Cliente.query.filter_by(ativo=True).order_by(Cliente.nome.asc()).all()
    if not clientes:
        flash('É necessário cadastrar ao menos um cliente ativo antes de criar um pedido.', 'warning')
        return redirect(url_for('clientes.novo'))

    form = PedidoForm()
    form.cliente_id.choices = [(c.id, f"{c.nome} ({c.documento or c.email})") for c in clientes]

    # Pre-select client if passed via URL
    preselected_cliente_id = request.args.get('cliente_id', type=int)
    if request.method == 'GET':
        if preselected_cliente_id and any(c.id == preselected_cliente_id for c in clientes):
            form.cliente_id.data = preselected_cliente_id
        form.numero_pedido.data = gerar_numero_pedido()
        form.data_pedido.data = datetime.now()
        initial_itens = [{'id': '', 'descricao': '', 'quantidade': 1, 'valor_unitario': '', 'valor_total': 0.0}]
        return render_template('pedidos/form.html', form=form, itens=initial_itens, titulo='Novo Pedido', acao='Cadastrar')

    if request.method == 'POST':
        itens_data, itens_erros, valor_total_itens = processar_itens_post(request.form)

        # Check if order number already exists
        existente = Pedido.query.filter_by(numero_pedido=form.numero_pedido.data.strip().upper()).first()
        if existente:
            flash(f'O número de pedido "{form.numero_pedido.data}" já existe. Geramos outro para você.', 'warning')
            form.numero_pedido.data = gerar_numero_pedido()
            return render_template(
                'pedidos/form.html',
                form=form,
                itens=itens_data or [{'id': '', 'descricao': '', 'quantidade': 1, 'valor_unitario': '', 'valor_total': 0.0}],
                titulo='Novo Pedido',
                acao='Cadastrar'
            )

        if itens_erros:
            for erro in itens_erros:
                flash(erro, 'danger')
            return render_template(
                'pedidos/form.html',
                form=form,
                itens=itens_data or [{'id': '', 'descricao': '', 'quantidade': 1, 'valor_unitario': '', 'valor_total': 0.0}],
                titulo='Novo Pedido',
                acao='Cadastrar'
            )

        if form.validate_on_submit():
            # Build general description if empty
            descricao_pedido = form.descricao.data.strip() if form.descricao.data else ""
            if not descricao_pedido and itens_data:
                descricao_pedido = ", ".join(f"{it['quantidade']:g}x {it['descricao']}" for it in itens_data)

            pedido = Pedido(
                cliente_id=form.cliente_id.data,
                numero_pedido=form.numero_pedido.data.strip().upper(),
                data_pedido=form.data_pedido.data,
                status=form.status.data,
                metodo_pagamento=form.metodo_pagamento.data,
                valor_total=valor_total_itens,
                descricao=descricao_pedido,
                observacoes=form.observacoes.data.strip() if form.observacoes.data else None
            )
            db.session.add(pedido)
            db.session.flush()

            # Add items
            for it in itens_data:
                item_obj = ItemPedido(
                    pedido_id=pedido.id,
                    descricao=it['descricao'],
                    quantidade=it['quantidade'],
                    valor_unitario=it['valor_unitario'],
                    valor_total=it['valor_total']
                )
                db.session.add(item_obj)

            db.session.commit()

            flash(f'Pedido #{pedido.numero_pedido} criado com sucesso!', 'success')
            return redirect(url_for('pedidos.detalhe', id=pedido.id))

    return render_template(
        'pedidos/form.html',
        form=form,
        itens=itens_data if 'itens_data' in locals() else [{'id': '', 'descricao': '', 'quantidade': 1, 'valor_unitario': '', 'valor_total': 0.0}],
        titulo='Novo Pedido',
        acao='Cadastrar'
    )


@pedidos_bp.route('/<int:id>')
@login_required
def detalhe(id):
    pedido = db.session.get(Pedido, id)
    if not pedido:
        flash('Pedido não encontrado.', 'danger')
        return redirect(url_for('pedidos.index'))

    return render_template('pedidos/detail.html', pedido=pedido)


@pedidos_bp.route('/<int:id>/editar', methods=['GET', 'POST'])
@login_required
def editar(id):
    pedido = db.session.get(Pedido, id)
    if not pedido:
        flash('Pedido não encontrado.', 'danger')
        return redirect(url_for('pedidos.index'))

    clientes = Cliente.query.order_by(Cliente.nome.asc()).all()
    form = PedidoForm(obj=pedido)
    form.cliente_id.choices = [(c.id, f"{c.nome} ({c.documento or c.email})") for c in clientes]

    if request.method == 'GET':
        itens_data = [
            {
                'id': item.id,
                'descricao': item.descricao,
                'quantidade': item.quantidade,
                'valor_unitario': item.valor_unitario,
                'valor_total': item.valor_total
            }
            for item in pedido.itens
        ]
        if not itens_data:
            itens_data = [{
                'id': '',
                'descricao': pedido.descricao or 'Item do Pedido',
                'quantidade': 1,
                'valor_unitario': pedido.valor_total,
                'valor_total': pedido.valor_total
            }]
        return render_template('pedidos/form.html', form=form, pedido=pedido, itens=itens_data, titulo='Editar Pedido', acao='Salvar Alterações')

    if request.method == 'POST':
        itens_data, itens_erros, valor_total_itens = processar_itens_post(request.form)

        # Check unique order number if modified
        num_novo = form.numero_pedido.data.strip().upper()
        if num_novo != pedido.numero_pedido:
            existente = Pedido.query.filter_by(numero_pedido=num_novo).first()
            if existente:
                flash(f'Já existe outro pedido com o número {num_novo}.', 'danger')
                return render_template(
                    'pedidos/form.html',
                    form=form,
                    pedido=pedido,
                    itens=itens_data,
                    titulo='Editar Pedido',
                    acao='Salvar Alterações'
                )

        if itens_erros:
            for erro in itens_erros:
                flash(erro, 'danger')
            return render_template(
                'pedidos/form.html',
                form=form,
                pedido=pedido,
                itens=itens_data,
                titulo='Editar Pedido',
                acao='Salvar Alterações'
            )

        if form.validate_on_submit():
            pedido.cliente_id = form.cliente_id.data
            pedido.numero_pedido = num_novo
            pedido.data_pedido = form.data_pedido.data
            pedido.status = form.status.data
            pedido.metodo_pagamento = form.metodo_pagamento.data
            pedido.valor_total = valor_total_itens
            if form.descricao.data and form.descricao.data.strip():
                pedido.descricao = form.descricao.data.strip()
            elif not pedido.descricao and itens_data:
                pedido.descricao = ", ".join(f"{it['quantidade']:g}x {it['descricao']}" for it in itens_data)
            pedido.observacoes = form.observacoes.data.strip() if form.observacoes.data else None

            # Remove existing items and add updated
            ItemPedido.query.filter_by(pedido_id=pedido.id).delete()
            for it in itens_data:
                item_obj = ItemPedido(
                    pedido_id=pedido.id,
                    descricao=it['descricao'],
                    quantidade=it['quantidade'],
                    valor_unitario=it['valor_unitario'],
                    valor_total=it['valor_total']
                )
                db.session.add(item_obj)

            db.session.commit()
            flash(f'Pedido #{pedido.numero_pedido} atualizado com sucesso!', 'success')
            return redirect(url_for('pedidos.detalhe', id=pedido.id))

    return render_template(
        'pedidos/form.html',
        form=form,
        pedido=pedido,
        itens=itens_data if 'itens_data' in locals() else [],
        titulo='Editar Pedido',
        acao='Salvar Alterações'
    )


@pedidos_bp.route('/<int:id>/excluir', methods=['POST'])
@login_required
def excluir(id):
    pedido = db.session.get(Pedido, id)
    if not pedido:
        flash('Pedido não encontrado.', 'danger')
        return redirect(url_for('pedidos.index'))

    num = pedido.numero_pedido
    db.session.delete(pedido)
    db.session.commit()

    flash(f'Pedido #{num} excluído com sucesso.', 'info')
    return redirect(url_for('pedidos.index'))

OMNI_EOF

# --- app/static/css/style.css ---
cat > 'app/static/css/style.css' <<'OMNI_EOF'
/* ==========================================================================
   APP CLIENTES - MODERN DESIGN SYSTEM
   ========================================================================== */

:root {
  --primary: #4263a3;
  --primary-hover: #19449c;
  --primary-light: #eef2ff;
  --primary-border: #c7d2fe;

  --secondary: #64748b;
  --secondary-light: #f1f5f9;

  --success: #10b981;
  --success-light: #ecfdf5;
  --success-text: #065f46;

  --warning: #f59e0b;
  --warning-light: #fffbeb;
  --warning-text: #92400e;

  --danger: #ef4444;
  --danger-light: #fef2f2;
  --danger-text: #991b1b;

  --info: #06b6d4;
  --info-light: #ecfeff;
  --info-text: #155e75;

  --sidebar-bg: #0f172a;
  --sidebar-text: #94a3b8;
  --sidebar-hover: #1e293b;
  --sidebar-active: #4263a3;

  --bg-main: #f8fafc;
  --card-bg: #ffffff;
  --card-border: #e2e8f0;
  --card-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.05), 0 2px 4px -2px rgba(0, 0, 0, 0.05);
  --card-shadow-hover: 0 10px 15px -3px rgba(0, 0, 0, 0.08), 0 4px 6px -4px rgba(0, 0, 0, 0.04);

  --font-family: 'Plus Jakarta Sans', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  --radius-sm: 8px;
  --radius-md: 12px;
  --radius-lg: 16px;
  --radius-xl: 20px;
}

body {
  font-family: var(--font-family);
  background-color: var(--bg-main);
  color: #1e293b;
  min-height: 100vh;
  margin: 0;
  padding: 0;
  -webkit-font-smoothing: antialiased;
}

/* ==========================================================================
   LAYOUT STRUCTURE (Sidebar + Content)
   ========================================================================== */

.app-wrapper {
  display: flex;
  min-height: 100vh;
  width: 100%;
}

.sidebar {
  width: 270px;
  background-color: var(--sidebar-bg);
  color: #f8fafc;
  flex-shrink: 0;
  display: flex;
  flex-direction: column;
  transition: all 0.3s ease;
  z-index: 1040;
}

.sidebar-header {
  padding: 1.5rem 1.5rem 1rem;
  border-bottom: 1px solid rgba(255, 255, 255, 0.08);
}

.brand-logo {
  display: flex;
  align-items: center;
  gap: 12px;
  text-decoration: none;
  color: #ffffff;
  font-weight: 700;
  font-size: 1.25rem;
}

.brand-icon {
  width: 40px;
  height: 40px;
  background: linear-gradient(135deg, #4263a3, #19449c);
  border-radius: var(--radius-md);
  display: flex;
  align-items: center;
  justify-content: center;
  color: #ffffff;
  font-size: 1.3rem;
  box-shadow: 0 4px 12px rgb(25 68 156);
}

.sidebar-nav {
  padding: 1.25rem 0.75rem;
  flex: 1;
  overflow-y: auto;
}

.nav-section-title {
  font-size: 0.75rem;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: #64748b;
  font-weight: 700;
  padding: 0.75rem 1rem 0.4rem;
}

.sidebar-link {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 0.75rem 1rem;
  border-radius: var(--radius-sm);
  color: var(--sidebar-text);
  text-decoration: none;
  font-weight: 500;
  font-size: 0.925rem;
  transition: all 0.2s ease;
  margin-bottom: 4px;
}

.sidebar-link i {
  font-size: 1.15rem;
  transition: transform 0.2s ease;
}

.sidebar-link:hover {
  background-color: var(--sidebar-hover);
  color: #ffffff;
}

.sidebar-link:hover i {
  transform: translateX(2px);
}

.sidebar-link.active {
  background: linear-gradient(135deg, rgba(24, 102, 241, 0.2), rgba(24, 70, 229, 0.25));
  color: #ffffff;
  border-left: 3px solid #19449c;
  font-weight: 600;
}

.sidebar-footer {
  padding: 1.25rem;
  border-top: 1px solid rgba(255, 255, 255, 0.08);
  background: rgba(0, 0, 0, 0.15);
}

.user-badge {
  display: flex;
  align-items: center;
  gap: 12px;
}

.user-avatar {
  width: 40px;
  height: 40px;
  background: linear-gradient(135deg, #10b981, #059669);
  color: #ffffff;
  font-weight: 700;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 1rem;
  flex-shrink: 0;
}

.main-content {
  flex: 1;
  display: flex;
  flex-direction: column;
  min-width: 0;
  background-color: var(--bg-main);
}

.top-navbar {
  background: #ffffff;
  border-bottom: 1px solid var(--card-border);
  padding: 0.85rem 1.75rem;
  display: flex;
  align-items: center;
  justify-content: space-between;
  position: sticky;
  top: 0;
  z-index: 1030;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.02);
}

.page-container {
  padding: 2rem 2.25rem;
  flex: 1;
}

/* ==========================================================================
   CARDS & CONTAINERS
   ========================================================================== */

.card-custom {
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: var(--radius-lg);
  box-shadow: var(--card-shadow);
  transition: transform 0.2s ease, box-shadow 0.2s ease;
  overflow: hidden;
}

.card-custom:hover {
  box-shadow: var(--card-shadow-hover);
}

.card-stat {
  position: relative;
  overflow: hidden;
  border: 1px solid var(--card-border);
  border-radius: var(--radius-lg);
  padding: 1.5rem;
  background: #ffffff;
  box-shadow: var(--card-shadow);
  transition: all 0.25s ease;
}

.card-stat:hover {
  transform: translateY(-3px);
  box-shadow: var(--card-shadow-hover);
}

.stat-icon {
  width: 52px;
  height: 52px;
  border-radius: var(--radius-md);
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 1.5rem;
  flex-shrink: 0;
}

.stat-icon.primary { background: #eef2ff; color: #19449c; }
.stat-icon.success { background: #ecfdf5; color: #10b981; }
.stat-icon.warning { background: #fffbeb; color: #f59e0b; }
.stat-icon.info { background: #ecfeff; color: #06b6d4; }
.stat-icon.danger { background: #fef2f2; color: #ef4444; }

.stat-title {
  color: #64748b;
  font-size: 0.85rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.03em;
  margin-bottom: 0.25rem;
}

.stat-value {
  color: #0f172a;
  font-size: 1.85rem;
  font-weight: 800;
  line-height: 1.2;
}

/* ==========================================================================
   TABLES & BADGES
   ========================================================================== */

.table-custom {
  width: 100%;
  margin-bottom: 0;
  border-collapse: separate;
  border-spacing: 0;
}

.table-custom th {
  background-color: #f8fafc;
  color: #475569;
  font-weight: 600;
  font-size: 0.8rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  padding: 0.95rem 1.25rem;
  border-bottom: 1px solid var(--card-border);
  white-space: nowrap;
}

.table-custom td {
  padding: 1rem 1.25rem;
  vertical-align: middle;
  border-bottom: 1px solid #f1f5f9;
  color: #334155;
  font-size: 0.925rem;
}

.table-custom tbody tr {
  transition: background-color 0.15s ease;
}

.table-custom tbody tr:hover {
  background-color: #f8fafc;
}

/* Status Badges */
.badge-status {
  padding: 0.35rem 0.75rem;
  font-size: 0.75rem;
  font-weight: 600;
  border-radius: 9999px;
  display: inline-flex;
  align-items: center;
  gap: 6px;
}

.badge-status::before {
  content: "";
  display: inline-block;
  width: 6px;
  height: 6px;
  border-radius: 50%;
}

.badge-status.badge-concluido {
  background-color: #d1fae5;
  color: #065f46;
}
.badge-status.badge-concluido::before { background-color: #10b981; }

.badge-status.badge-pendente {
  background-color: #fef3c7;
  color: #92400e;
}
.badge-status.badge-pendente::before { background-color: #f59e0b; }

.badge-status.badge-processando {
  background-color: #e0f2fe;
  color: #0369a1;
}
.badge-status.badge-processando::before { background-color: #0284c7; }

.badge-status.badge-cancelado {
  background-color: #fee2e2;
  color: #991b1b;
}
.badge-status.badge-cancelado::before { background-color: #ef4444; }

.badge-status.badge-ativo {
  background-color: #dcfce7;
  color: #166534;
}
.badge-status.badge-ativo::before { background-color: #22c55e; }

.badge-status.badge-inativo {
  background-color: #f1f5f9;
  color: #64748b;
}
.badge-status.badge-inativo::before { background-color: #94a3b8; }

/* ==========================================================================
   BUTTONS & FORMS
   ========================================================================== */

.btn-primary-custom {
  background: linear-gradient(135deg, #4263a3, #19449c);
  color: #ffffff;
  border: none;
  font-weight: 600;
  padding: 0.6rem 1.25rem;
  border-radius: var(--radius-sm);
  box-shadow: 0 2px 4px rgba(79, 70, 229, 0.2);
  transition: all 0.2s ease;
  display: inline-flex;
  align-items: center;
  gap: 8px;
}

.btn-primary-custom:hover {
  background: linear-gradient(135deg, #19449c, #0d0d42);
  color: #ffffff;
  transform: translateY(-1px);
  box-shadow: 0 4px 8px rgb(25 68 156);
}

.btn-light-custom {
  background-color: #ffffff;
  border: 1px solid var(--card-border);
  color: #334155;
  font-weight: 500;
  padding: 0.6rem 1.15rem;
  border-radius: var(--radius-sm);
  transition: all 0.2s ease;
}

.btn-light-custom:hover {
  background-color: #f8fafc;
  border-color: #cbd5e1;
  color: #0f172a;
}

.form-control, .form-select {
  border: 1px solid #cbd5e1;
  border-radius: var(--radius-sm);
  padding: 0.65rem 0.95rem;
  font-size: 0.95rem;
  transition: border-color 0.15s ease, box-shadow 0.15s ease;
}

.form-control:focus, .form-select:focus {
  border-color: var(--primary);
  box-shadow: 0 0 0 3px rgba(79, 70, 229, 0.15);
}

.form-label {
  font-weight: 600;
  font-size: 0.875rem;
  color: #334155;
  margin-bottom: 0.35rem;
}

/* ==========================================================================
   AUTH PAGES (Login & Register)
   ========================================================================== */

.auth-wrapper {
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  background: linear-gradient(135deg, #0f172a 0%, #0d0d42 50%, #19449c 100%);
  padding: 2rem 1rem;
}

.auth-card {
  width: 100%;
  max-width: 480px;
  background: #ffffff;
  border-radius: var(--radius-xl);
  box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.35);
  padding: 2.5rem 2.25rem;
  position: relative;
  overflow: hidden;
}

.auth-card::before {
  content: "";
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  height: 6px;
  background: linear-gradient(90deg, #19449c, #06b6d4, #10b981);
}

/* ==========================================================================
   ALERTS & TOASTS
   ========================================================================== */

.alert-custom {
  border: none;
  border-radius: var(--radius-md);
  padding: 1rem 1.25rem;
  display: flex;
  align-items: center;
  gap: 12px;
  box-shadow: 0 2px 5px rgba(0, 0, 0, 0.05);
  margin-bottom: 1.25rem;
}

/* Responsive adjustments */
@media (max-width: 991.98px) {
  .sidebar {
    position: fixed;
    top: 0;
    bottom: 0;
    left: -270px;
  }
  .sidebar.show {
    left: 0;
  }
  .sidebar-backdrop {
    display: none;
    position: fixed;
    inset: 0;
    background: rgba(15, 23, 42, 0.6);
    backdrop-filter: blur(2px);
    z-index: 1035;
  }
  .sidebar-backdrop.show {
    display: block;
  }
  .page-container {
    padding: 1.25rem 1rem;
  }
}
OMNI_EOF

# --- app/static/js/main.js ---
cat > 'app/static/js/main.js' <<'OMNI_EOF'
document.addEventListener('DOMContentLoaded', function () {
  // 1. Sidebar Toggle on Mobile
  const sidebarToggle = document.getElementById('sidebarToggle');
  const sidebar = document.getElementById('sidebar');
  const sidebarBackdrop = document.getElementById('sidebarBackdrop');

  if (sidebarToggle && sidebar && sidebarBackdrop) {
    sidebarToggle.addEventListener('click', function () {
      sidebar.classList.toggle('show');
      sidebarBackdrop.classList.toggle('show');
    });

    sidebarBackdrop.addEventListener('click', function () {
      sidebar.classList.remove('show');
      sidebarBackdrop.classList.remove('show');
    });
  }

  // 2. Auto-dismiss flash alerts after 6 seconds
  const alerts = document.querySelectorAll('.alert-dismissible');
  alerts.forEach(function (alert) {
    setTimeout(function () {
      const bsAlert = bootstrap.Alert.getOrCreateInstance(alert);
      if (bsAlert) {
        bsAlert.close();
      }
    }, 6000);
  });

  // 3. Generic Delete Confirmation Modal Handler
  const deleteModal = document.getElementById('deleteConfirmModal');
  if (deleteModal) {
    deleteModal.addEventListener('show.bs.modal', function (event) {
      const button = event.relatedTarget;
      if (!button) return;

      const actionUrl = button.getAttribute('data-action');
      const itemName = button.getAttribute('data-name') || 'este registro';
      const itemType = button.getAttribute('data-type') || 'item';

      const form = deleteModal.querySelector('#deleteConfirmForm');
      const textSpan = deleteModal.querySelector('#deleteItemName');
      const typeSpan = deleteModal.querySelector('#deleteItemType');

      if (form && actionUrl) form.action = actionUrl;
      if (textSpan) textSpan.textContent = itemName;
      if (typeSpan) typeSpan.textContent = itemType;
    });
  }

  // 4. Input Masks (CPF/CNPJ, Telefone, CEP)
  const docInput = document.getElementById('documento');
  if (docInput) {
    docInput.addEventListener('input', function (e) {
      let v = e.target.value.replace(/\D/g, '');
      if (v.length <= 11) {
        // CPF: 000.000.000-00
        v = v.replace(/(\d{3})(\d)/, '$1.$2');
        v = v.replace(/(\d{3})(\d)/, '$1.$2');
        v = v.replace(/(\d{3})(\d{1,2})$/, '$1-$2');
      } else {
        // CNPJ: 00.000.000/0000-00
        v = v.substring(0, 14);
        v = v.replace(/^(\d{2})(\d)/, '$1.$2');
        v = v.replace(/^(\d{2})\.(\d{3})(\d)/, '$1.$2');
        v = v.replace(/\.(\d{3})(\d)/, '.$1/$2');
        v = v.replace(/(\d{4})(\d)/, '$1-$2');
      }
      e.target.value = v;
    });
  }

  const phoneInput = document.getElementById('telefone');
  if (phoneInput) {
    phoneInput.addEventListener('input', function (e) {
      let v = e.target.value.replace(/\D/g, '').substring(0, 11);
      if (v.length > 10) {
        // (11) 98765-4321
        v = v.replace(/^(\d{2})(\d{5})(\d{4})$/, '($1) $2-$3');
      } else if (v.length > 5) {
        // (11) 8765-4321
        v = v.replace(/^(\d{2})(\d{4})(\d{0,4})$/, '($1) $2-$3');
      } else if (v.length > 2) {
        v = v.replace(/^(\d{2})(\d{0,5})$/, '($1) $2');
      }
      e.target.value = v;
    });
  }

  const cepInput = document.getElementById('cep');
  if (cepInput) {
    cepInput.addEventListener('input', function (e) {
      let v = e.target.value.replace(/\D/g, '').substring(0, 8);
      if (v.length > 5) {
        v = v.replace(/^(\d{5})(\d{1,3})$/, '$1-$2');
      }
      e.target.value = v;
    });

    // Optional: Auto-fill ViaCEP
    cepInput.addEventListener('blur', function () {
      const cep = this.value.replace(/\D/g, '');
      if (cep.length === 8) {
        fetch(`https://viacep.com.br/ws/${cep}/json/`)
          .then(res => res.json())
          .then(data => {
            if (!data.erro) {
              const logradouro = document.getElementById('logradouro');
              const bairro = document.getElementById('bairro');
              const cidade = document.getElementById('cidade');
              const estado = document.getElementById('estado');

              if (logradouro && !logradouro.value) logradouro.value = data.logradouro;
              if (bairro && !bairro.value) bairro.value = data.bairro;
              if (cidade && !cidade.value) cidade.value = data.localidade;
              if (estado && !estado.value) estado.value = data.uf;

              const numInput = document.getElementById('numero');
              if (numInput) numInput.focus();
            }
          })
          .catch(() => {});
      }
    });
  }

  // 5. Initialize Bootstrap tooltips
  const tooltipTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="tooltip"]'));
  tooltipTriggerList.map(function (tooltipTriggerEl) {
    return new bootstrap.Tooltip(tooltipTriggerEl);
  });
});
OMNI_EOF

# --- app/templates/auth/login.html ---
cat > 'app/templates/auth/login.html' <<'OMNI_EOF'
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Login - OmniGestão</title>
  
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&display=swap" rel="stylesheet">
  
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css">
  <link rel="stylesheet" href="{{ url_for('static', filename='css/style.css') }}">
</head>
<body>

  <div class="auth-wrapper">
    <div class="auth-card">
      <div class="text-center mb-4">
        <div class="brand-icon mx-auto mb-3" style="width: 54px; height: 54px; font-size: 1.7rem;">
          <i class="bi bi-layers-fill"></i>
        </div>
        <h3 class="fw-bold text-dark mb-1">Acessar Sistema</h3>
        <p class="text-muted small">Gerenciamento completo de Clientes & Pedidos</p>
      </div>

      <!-- FLASH MESSAGES -->
      {% with messages = get_flashed_messages(with_categories=true) %}
        {% if messages %}
          {% for category, message in messages %}
            <div class="alert alert-{{ category if category != 'message' else 'info' }} alert-dismissible fade show small py-2 mb-3" role="alert">
              {{ message }}
              <button type="button" class="btn-close btn-close-sm" data-bs-dismiss="alert" aria-label="Fechar"></button>
            </div>
          {% endfor %}
        {% endif %}
      {% endwith %}

      <form method="POST" action="{{ url_for('auth.login', next=request.args.get('next')) }}">
        {{ form.hidden_tag() }}

        <div class="mb-3">
          <label for="login" class="form-label">Usuário ou E-mail</label>
          <div class="input-group">
            <span class="input-group-text bg-light text-muted border-end-0">
              <i class="bi bi-person"></i>
            </span>
            {{ form.login(class="form-control border-start-0" + (" is-invalid" if form.login.errors else ""), placeholder="admin ou seu@email.com", autofocus=true) }}
          </div>
          {% for error in form.login.errors %}
            <div class="text-danger small mt-1">{{ error }}</div>
          {% endfor %}
        </div>

        <div class="mb-3">
          <div class="d-flex justify-content-between align-items-center">
            <label for="password" class="form-label">Senha</label>
          </div>
          <div class="input-group">
            <span class="input-group-text bg-light text-muted border-end-0">
              <i class="bi bi-lock"></i>
            </span>
            {{ form.password(class="form-control border-start-0" + (" is-invalid" if form.password.errors else ""), placeholder="••••••••") }}
          </div>
          {% for error in form.password.errors %}
            <div class="text-danger small mt-1">{{ error }}</div>
          {% endfor %}
        </div>

        <div class="mb-4 form-check">
          {{ form.remember(class="form-check-input", id="remember") }}
          <label class="form-check-label text-muted small" for="remember">Lembrar-se neste dispositivo</label>
        </div>

        <button type="submit" class="btn btn-primary-custom w-100 justify-content-center py-2 mb-3">
          <i class="bi bi-box-arrow-in-right"></i> Entrar na Plataforma
        </button>

        <div class="text-center pt-2 border-top">
          <span class="text-muted small">Não possui uma conta? </span>
          <a href="{{ url_for('auth.register') }}" class="small fw-semibold text-primary text-decoration-none">
            Cadastre-se gratuitamente
          </a>
        </div>
      </form>
    </div>
  </div>

  <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>
OMNI_EOF

# --- app/templates/auth/register.html ---
cat > 'app/templates/auth/register.html' <<'OMNI_EOF'
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Cadastrar Usuário - OmniGestão</title>
  
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&display=swap" rel="stylesheet">
  
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css">
  <link rel="stylesheet" href="{{ url_for('static', filename='css/style.css') }}">
</head>
<body>

  <div class="auth-wrapper">
    <div class="auth-card" style="max-width: 520px;">
      <div class="text-center mb-4">
        <div class="brand-icon mx-auto mb-3" style="width: 54px; height: 54px; font-size: 1.7rem;">
          <i class="bi bi-person-plus-fill"></i>
        </div>
        <h3 class="fw-bold text-dark mb-1">Criar Nova Conta</h3>
        <p class="text-muted small">Cadastre-se para acessar o painel de gestão</p>
      </div>

      <!-- FLASH MESSAGES -->
      {% with messages = get_flashed_messages(with_categories=true) %}
        {% if messages %}
          {% for category, message in messages %}
            <div class="alert alert-{{ category if category != 'message' else 'info' }} alert-dismissible fade show small py-2 mb-3" role="alert">
              {{ message }}
              <button type="button" class="btn-close btn-close-sm" data-bs-dismiss="alert" aria-label="Fechar"></button>
            </div>
          {% endfor %}
        {% endif %}
      {% endwith %}

      <form method="POST" action="{{ url_for('auth.register') }}">
        {{ form.hidden_tag() }}

        <div class="mb-3">
          <label for="nome" class="form-label">Nome Completo</label>
          <div class="input-group">
            <span class="input-group-text bg-light text-muted border-end-0">
              <i class="bi bi-person-badge"></i>
            </span>
            {{ form.nome(class="form-control border-start-0" + (" is-invalid" if form.nome.errors else ""), placeholder="Ex: Maria Santos", autofocus=true) }}
          </div>
          {% for error in form.nome.errors %}
            <div class="text-danger small mt-1">{{ error }}</div>
          {% endfor %}
        </div>

        <div class="row">
          <div class="col-md-6 mb-3">
            <label for="username" class="form-label">Nome de Usuário</label>
            <div class="input-group">
              <span class="input-group-text bg-light text-muted border-end-0">@</span>
              {{ form.username(class="form-control border-start-0" + (" is-invalid" if form.username.errors else ""), placeholder="mariasantos") }}
            </div>
            {% for error in form.username.errors %}
              <div class="text-danger small mt-1">{{ error }}</div>
            {% endfor %}
          </div>

          <div class="col-md-6 mb-3">
            <label for="email" class="form-label">E-mail</label>
            <div class="input-group">
              <span class="input-group-text bg-light text-muted border-end-0">
                <i class="bi bi-envelope"></i>
              </span>
              {{ form.email(class="form-control border-start-0" + (" is-invalid" if form.email.errors else ""), placeholder="maria@empresa.com") }}
            </div>
            {% for error in form.email.errors %}
              <div class="text-danger small mt-1">{{ error }}</div>
            {% endfor %}
          </div>
        </div>

        <div class="row">
          <div class="col-md-6 mb-3">
            <label for="password" class="form-label">Senha</label>
            <div class="input-group">
              <span class="input-group-text bg-light text-muted border-end-0">
                <i class="bi bi-lock"></i>
              </span>
              {{ form.password(class="form-control border-start-0" + (" is-invalid" if form.password.errors else ""), placeholder="Mínimo 6 dígitos") }}
            </div>
            {% for error in form.password.errors %}
              <div class="text-danger small mt-1">{{ error }}</div>
            {% endfor %}
          </div>

          <div class="col-md-6 mb-4">
            <label for="confirm_password" class="form-label">Confirmar Senha</label>
            <div class="input-group">
              <span class="input-group-text bg-light text-muted border-end-0">
                <i class="bi bi-shield-check"></i>
              </span>
              {{ form.confirm_password(class="form-control border-start-0" + (" is-invalid" if form.confirm_password.errors else ""), placeholder="Repita a senha") }}
            </div>
            {% for error in form.confirm_password.errors %}
              <div class="text-danger small mt-1">{{ error }}</div>
            {% endfor %}
          </div>
        </div>

        <button type="submit" class="btn btn-primary-custom w-100 justify-content-center py-2 mb-3">
          <i class="bi bi-check-circle"></i> Finalizar Cadastro
        </button>

        <div class="text-center pt-2 border-top">
          <span class="text-muted small">Já possui uma conta? </span>
          <a href="{{ url_for('auth.login') }}" class="small fw-semibold text-primary text-decoration-none">
            Acesse seu login
          </a>
        </div>
      </form>
    </div>
  </div>

  <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>
OMNI_EOF

# --- app/templates/base.html ---
cat > 'app/templates/base.html' <<'OMNI_EOF'
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{% block title %}Gestão de Clientes e Pedidos{% endblock %}</title>

  <!-- Google Fonts: Plus Jakarta Sans -->
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&display=swap" rel="stylesheet">

  <!-- Bootstrap 5.3.3 CSS -->
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">

  <!-- Bootstrap Icons -->
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css">

  <!-- Custom CSS -->
  <link rel="stylesheet" href="{{ url_for('static', filename='css/style.css') }}">
  {% block extra_css %}{% endblock %}
</head>
<body>

  <div class="sidebar-backdrop" id="sidebarBackdrop"></div>

  <div class="app-wrapper">
    <!-- SIDEBAR -->
    <aside class="sidebar" id="sidebar">
      <div class="sidebar-header">
        <a href="{{ url_for('main.dashboard') }}" class="brand-logo">
          <div class="brand-icon">
            <i class="bi bi-layers-fill"></i>
          </div>
          <div>
            <div style="line-height: 1.1;">OmniGestão</div>
            <small style="font-size: 0.7rem; color: #94a3b8; font-weight: 400;">Clientes & Pedidos</small>
          </div>
        </a>
      </div>

      <nav class="sidebar-nav">
        <div class="nav-section-title">Principal</div>
        <a href="{{ url_for('main.dashboard') }}" class="sidebar-link {% if request.endpoint == 'main.dashboard' %}active{% endif %}">
          <i class="bi bi-speedometer2"></i>
          <span>Dashboard</span>
        </a>

        <div class="nav-section-title">Gerenciamento</div>
        <a href="{{ url_for('clientes.index') }}" class="sidebar-link {% if request.blueprint == 'clientes' and request.endpoint != 'clientes.novo' %}active{% endif %}">
          <i class="bi bi-people-fill"></i>
          <span>Clientes</span>
        </a>
        <a href="{{ url_for('pedidos.index') }}" class="sidebar-link {% if request.blueprint == 'pedidos' and request.endpoint != 'pedidos.novo' %}active{% endif %}">
          <i class="bi bi-bag-check-fill"></i>
          <span>Pedidos</span>
        </a>

        <div class="nav-section-title">Ações Rápidas</div>
        <a href="{{ url_for('clientes.novo') }}" class="sidebar-link {% if request.endpoint == 'clientes.novo' %}active{% endif %}">
          <i class="bi bi-person-plus-fill"></i>
          <span>Novo Cliente</span>
        </a>
        <a href="{{ url_for('pedidos.novo') }}" class="sidebar-link {% if request.endpoint == 'pedidos.novo' %}active{% endif %}">
          <i class="bi bi-cart-plus-fill"></i>
          <span>Novo Pedido</span>
        </a>
      </nav>

      <div class="sidebar-footer">
        <div class="user-badge">
          <div class="user-avatar">
            {{ current_user.nome[:2].upper() if current_user.is_authenticated else 'U' }}
          </div>
          <div class="text-truncate" style="flex: 1;">
            <div class="fw-bold text-white text-truncate" style="font-size: 0.9rem;">
              {{ current_user.nome if current_user.is_authenticated else 'Usuário' }}
            </div>
            <div class="text-muted text-truncate" style="font-size: 0.75rem;">
              @{{ current_user.username if current_user.is_authenticated else 'convidado' }}
            </div>
          </div>
          <a href="{{ url_for('auth.logout') }}" class="text-secondary text-decoration-none" title="Sair do sistema" data-bs-toggle="tooltip">
            <i class="bi bi-box-arrow-right fs-5"></i>
          </a>
        </div>
      </div>
    </aside>

    <!-- MAIN CONTENT -->
    <div class="main-content">
      <!-- TOP NAVBAR -->
      <header class="top-navbar">
        <div class="d-flex align-items-center gap-3">
          <button class="btn btn-sm btn-outline-secondary d-lg-none" id="sidebarToggle" type="button" aria-label="Abrir menu">
            <i class="bi bi-list fs-5"></i>
          </button>
          <div class="d-none d-md-block">
            <span class="text-muted small">Sistema Integrado de Gestão</span>
          </div>
        </div>

        <div class="d-flex align-items-center gap-2">
          <a href="{{ url_for('clientes.novo') }}" class="btn btn-sm btn-outline-primary d-none d-sm-inline-flex align-items-center gap-1">
            <i class="bi bi-person-plus"></i> + Cliente
          </a>
          <a href="{{ url_for('pedidos.novo') }}" class="btn btn-sm btn-primary d-none d-sm-inline-flex align-items-center gap-1">
            <i class="bi bi-cart-plus"></i> + Pedido
          </a>
          <div class="vr mx-2 d-none d-sm-block"></div>
          <div class="dropdown">
            <button class="btn btn-light-custom btn-sm dropdown-toggle d-flex align-items-center gap-2" type="button" data-bs-toggle="dropdown">
              <i class="bi bi-person-circle"></i>
              <span class="d-none d-md-inline">{{ current_user.nome }}</span>
            </button>
            <ul class="dropdown-menu dropdown-menu-end shadow-sm border-0">
              <li><h6 class="dropdown-header">Conectado como <strong>{{ current_user.username }}</strong></h6></li>
              <li><a class="dropdown-item" href="{{ url_for('clientes.index') }}"><i class="bi bi-people me-2"></i>Meus Clientes</a></li>
              <li><a class="dropdown-item" href="{{ url_for('pedidos.index') }}"><i class="bi bi-bag-check me-2"></i>Meus Pedidos</a></li>
              <li><hr class="dropdown-divider"></li>
              <li><a class="dropdown-item text-danger" href="{{ url_for('auth.logout') }}"><i class="bi bi-box-arrow-right me-2"></i>Sair da Conta</a></li>
            </ul>
          </div>
        </div>
      </header>

      <!-- FLASH MESSAGES -->
      <main class="page-container">
        {% with messages = get_flashed_messages(with_categories=true) %}
          {% if messages %}
            {% for category, message in messages %}
              <div class="alert alert-{{ category if category != 'message' else 'info' }} alert-dismissible fade show alert-custom" role="alert">
                {% if category == 'success' %}
                  <i class="bi bi-check-circle-fill text-success fs-5"></i>
                {% elif category == 'danger' %}
                  <i class="bi bi-exclamation-triangle-fill text-danger fs-5"></i>
                {% elif category == 'warning' %}
                  <i class="bi bi-exclamation-circle-fill text-warning fs-5"></i>
                {% else %}
                  <i class="bi bi-info-circle-fill text-info fs-5"></i>
                {% endif %}
                <div class="flex-grow-1">{{ message }}</div>
                <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Fechar"></button>
              </div>
            {% endfor %}
          {% endif %}
        {% endwith %}

        {% block content %}{% endblock %}
      </main>
    </div>
  </div>

  <!-- GENERIC DELETE CONFIRMATION MODAL -->
  <div class="modal fade" id="deleteConfirmModal" tabindex="-1" aria-labelledby="deleteModalLabel" aria-hidden="true">
    <div class="modal-dialog modal-dialog-centered">
      <div class="modal-content border-0 shadow">
        <div class="modal-header bg-danger text-white">
          <h5 class="modal-title" id="deleteModalLabel">
            <i class="bi bi-exclamation-octagon-fill me-2"></i>Confirmar Exclusão
          </h5>
          <button type="button" class="btn-close btn-close-white" data-bs-dismiss="modal" aria-label="Fechar"></button>
        </div>
        <div class="modal-body p-4 text-center">
          <div class="mb-3">
            <i class="bi bi-trash3 text-danger" style="font-size: 3rem;"></i>
          </div>
          <h5 class="fw-bold mb-2">Tem certeza que deseja excluir?</h5>
          <p class="text-muted mb-0">
            Você está prestes a excluir <span id="deleteItemType">o registro</span>:
            <strong id="deleteItemName" class="text-dark d-block mt-1"></strong>
          </p>
          <div class="alert alert-warning small text-start mt-3 mb-0">
            <i class="bi bi-info-circle me-1"></i> Esta ação é irreversível e excluirá permanentemente todos os dados associados.
          </div>
        </div>
        <div class="modal-footer bg-light">
          <button type="button" class="btn btn-secondary btn-sm px-3" data-bs-dismiss="modal">Cancelar</button>
          <form id="deleteConfirmForm" method="POST" action="">
            <button type="submit" class="btn btn-danger btn-sm px-4">
              <i class="bi bi-trash me-1"></i> Sim, Excluir
            </button>
          </form>
        </div>
      </div>
    </div>
  </div>

  <!-- Bootstrap 5.3.3 JS Bundle -->
  <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"></script>
  <!-- Custom JS -->
  <script src="{{ url_for('static', filename='js/main.js') }}"></script>
  {% block extra_js %}{% endblock %}
</body>
</html>
OMNI_EOF

# --- app/templates/clientes/detail.html ---
cat > 'app/templates/clientes/detail.html' <<'OMNI_EOF'
{% extends "base.html" %}

{% block title %}{{ cliente.nome }} - Detalhes do Cliente{% endblock %}

{% block content %}
<div class="mb-4">
  <nav aria-label="breadcrumb">
    <ol class="breadcrumb small mb-1">
      <li class="breadcrumb-item"><a href="{{ url_for('clientes.index') }}" class="text-decoration-none">Clientes</a></li>
      <li class="breadcrumb-item active" aria-current="page">{{ cliente.nome }}</li>
    </ol>
  </nav>

  <div class="d-flex flex-column flex-md-row align-items-md-center justify-content-between gap-3">
    <div class="d-flex align-items-center gap-3">
      <div class="rounded-circle bg-primary text-white fw-bold d-flex align-items-center justify-content-center shadow-sm" style="width: 52px; height: 52px; font-size: 1.25rem;">
        {{ cliente.nome[:2].upper() }}
      </div>
      <div>
        <div class="d-flex align-items-center gap-2">
          <h2 class="fw-bold mb-0 text-dark">{{ cliente.nome }}</h2>
          <span class="badge-status {{ 'badge-ativo' if cliente.ativo else 'badge-inativo' }}">
            {{ 'Ativo' if cliente.ativo else 'Inativo' }}
          </span>
        </div>
        <small class="text-muted">Cadastrado em {{ cliente.created_at | datetime_br }}</small>
      </div>
    </div>

    <!-- ACTION BUTTONS -->
    <div class="d-flex flex-wrap gap-2">
      <a href="{{ url_for('pedidos.novo', cliente_id=cliente.id) }}" class="btn btn-primary-custom btn-sm">
        <i class="bi bi-cart-plus"></i> Novo Pedido
      </a>
      <a href="{{ url_for('clientes.editar', id=cliente.id) }}" class="btn btn-light-custom btn-sm">
        <i class="bi bi-pencil"></i> Editar
      </a>
      <button type="button" class="btn btn-outline-danger btn-sm"
              data-bs-toggle="modal"
              data-bs-target="#deleteConfirmModal"
              data-action="{{ url_for('clientes.excluir', id=cliente.id) }}"
              data-name="{{ cliente.nome }}"
              data-type="o cliente">
        <i class="bi bi-trash"></i> Excluir
      </button>
    </div>
  </div>
</div>

<!-- CLIENT DETAILS GRID -->
<div class="row g-4 mb-4">
  <div class="col-lg-4">
    <!-- CONTACT & INFO CARD -->
    <div class="card-custom p-4 bg-white h-100">
      <h6 class="fw-bold text-dark pb-2 mb-3 border-bottom d-flex align-items-center gap-2">
        <i class="bi bi-card-checklist text-primary"></i> Informações do Cliente
      </h6>

      <div class="mb-3">
        <label class="text-muted small d-block">E-mail</label>
        <a href="mailto:{{ cliente.email }}" class="text-dark fw-semibold text-decoration-none">
          <i class="bi bi-envelope me-1 text-primary"></i>{{ cliente.email }}
        </a>
      </div>

      <div class="mb-3">
        <label class="text-muted small d-block">Telefone</label>
        {% if cliente.telefone %}
          <a href="tel:{{ cliente.telefone }}" class="text-dark fw-semibold text-decoration-none">
            <i class="bi bi-telephone me-1 text-success"></i>{{ cliente.telefone | phone_br }}
          </a>
        {% else %}
          <span class="text-muted">Não informado</span>
        {% endif %}
      </div>

      <div class="mb-3">
        <label class="text-muted small d-block">CPF / CNPJ</label>
        <span class="badge bg-light text-dark border font-monospace fs-6">
          {{ cliente.documento | doc_br }}
        </span>
      </div>

      <div class="mb-3">
        <label class="text-muted small d-block">Endereço Completo</label>
        <span class="text-secondary small">
          <i class="bi bi-geo-alt me-1 text-danger"></i>{{ cliente.endereco_completo }}
        </span>
      </div>

      {% if cliente.observacoes %}
        <div class="mt-3 pt-3 border-top">
          <label class="text-muted small d-block mb-1">Observações Internas</label>
          <div class="p-2 bg-light rounded small text-secondary">
            {{ cliente.observacoes }}
          </div>
        </div>
      {% endif %}
    </div>
  </div>

  <div class="col-lg-8">
    <!-- CLIENT METRICS -->
    <div class="row g-3 mb-4">
      <div class="col-sm-4">
        <div class="card-stat">
          <div class="stat-title">Total de Pedidos</div>
          <div class="stat-value text-primary">{{ pedidos | length }}</div>
          <small class="text-muted">Histórico completo</small>
        </div>
      </div>
      <div class="col-sm-4">
        <div class="card-stat">
          <div class="stat-title">Pedidos Concluídos</div>
          <div class="stat-value text-success">{{ pedidos_concluidos | length }}</div>
          <small class="text-muted">Finalizados com sucesso</small>
        </div>
      </div>
      <div class="col-sm-4">
        <div class="card-stat">
          <div class="stat-title">Total Faturado</div>
          <div class="stat-value text-dark">{{ total_gasto | currency }}</div>
          <small class="text-muted">Soma de pedidos válidos</small>
        </div>
      </div>
    </div>

    <!-- CLIENT ORDERS TABLE -->
    <div class="card-custom bg-white">
      <div class="card-header bg-white border-bottom p-3 d-flex align-items-center justify-content-between">
        <h6 class="fw-bold mb-0 text-dark">
          <i class="bi bi-bag-check me-2 text-primary"></i>Pedidos Vinculados ({{ pedidos | length }})
        </h6>
        <a href="{{ url_for('pedidos.novo', cliente_id=cliente.id) }}" class="btn btn-sm btn-outline-primary">
          <i class="bi bi-plus-lg"></i> Adicionar Pedido
        </a>
      </div>

      <div class="table-responsive">
        <table class="table-custom mb-0">
          <thead>
            <tr>
              <th>Nº Pedido</th>
              <th>Data</th>
              <th>Descrição</th>
              <th>Pagamento</th>
              <th>Status</th>
              <th>Valor Total</th>
              <th class="text-end">Ações</th>
            </tr>
          </thead>
          <tbody>
            {% for pedido in pedidos %}
              <tr>
                <td>
                  <a href="{{ url_for('pedidos.detalhe', id=pedido.id) }}" class="fw-bold text-dark text-decoration-none">
                    #{{ pedido.numero_pedido }}
                  </a>
                </td>
                <td class="text-muted small">{{ pedido.data_pedido | date_br }}</td>
                <td>
                  <span class="text-truncate d-inline-block small" style="max-width: 180px;" title="{{ pedido.descricao }}">
                    {{ pedido.descricao }}
                  </span>
                </td>
                <td class="small text-muted">{{ pedido.metodo_pagamento_label }}</td>
                <td>
                  <span class="badge-status badge-{{ pedido.status }}">
                    {{ pedido.status_label }}
                  </span>
                </td>
                <td class="fw-bold">{{ pedido.valor_total | currency }}</td>
                <td class="text-end">
                  <div class="btn-group btn-group-sm">
                    <a href="{{ url_for('pedidos.detalhe', id=pedido.id) }}" class="btn btn-light" title="Ver Detalhes">
                      <i class="bi bi-eye"></i>
                    </a>
                    <a href="{{ url_for('pedidos.editar', id=pedido.id) }}" class="btn btn-light" title="Editar">
                      <i class="bi bi-pencil"></i>
                    </a>
                  </div>
                </td>
              </tr>
            {% else %}
              <tr>
                <td colspan="7" class="text-center py-4 text-muted">
                  <i class="bi bi-cart-x fs-2 d-block mb-2 text-secondary"></i>
                  Este cliente ainda não possui nenhum pedido registrado.
                  <div class="mt-2">
                    <a href="{{ url_for('pedidos.novo', cliente_id=cliente.id) }}" class="btn btn-sm btn-primary">
                      Criar Primeiro Pedido
                    </a>
                  </div>
                </td>
              </tr>
            {% endfor %}
          </tbody>
        </table>
      </div>
    </div>
  </div>
</div>
{% endblock %}
OMNI_EOF

# --- app/templates/clientes/form.html ---
cat > 'app/templates/clientes/form.html' <<'OMNI_EOF'
{% extends "base.html" %}

{% block title %}{{ titulo }} - OmniGestão{% endblock %}

{% block content %}
<div class="mb-4">
  <nav aria-label="breadcrumb">
    <ol class="breadcrumb small mb-1">
      <li class="breadcrumb-item"><a href="{{ url_for('clientes.index') }}" class="text-decoration-none">Clientes</a></li>
      <li class="breadcrumb-item active" aria-current="page">{{ titulo }}</li>
    </ol>
  </nav>
  <div class="d-flex align-items-center justify-content-between">
    <h2 class="fw-bold mb-0 text-dark">{{ titulo }}</h2>
    <a href="{{ url_for('clientes.index') }}" class="btn btn-outline-secondary btn-sm">
      <i class="bi bi-arrow-left"></i> Voltar à Lista
    </a>
  </div>
</div>

<div class="row justify-content-center">
  <div class="col-lg-10">
    <form method="POST" novalidate>
      {{ form.hidden_tag() }}

      <!-- CARD 1: DADOS PRINCIPAIS -->
      <div class="card-custom p-4 mb-4 bg-white">
        <h5 class="fw-bold text-dark mb-3 pb-2 border-bottom d-flex align-items-center gap-2">
          <i class="bi bi-person-lines-fill text-primary"></i> Identificação do Cliente
        </h5>

        <div class="row g-3">
          <div class="col-md-8">
            <label for="nome" class="form-label">{{ form.nome.label.text }}</label>
            {{ form.nome(class="form-control" + (" is-invalid" if form.nome.errors else ""), placeholder="Nome completo ou Razão Social") }}
            {% for error in form.nome.errors %}
              <div class="invalid-feedback">{{ error }}</div>
            {% endfor %}
          </div>

          <div class="col-md-4">
            <label for="documento" class="form-label">{{ form.documento.label.text }}</label>
            {{ form.documento(class="form-control" + (" is-invalid" if form.documento.errors else ""), placeholder="000.000.000-00", id="documento") }}
            {% for error in form.documento.errors %}
              <div class="invalid-feedback">{{ error }}</div>
            {% endfor %}
          </div>

          <div class="col-md-6">
            <label for="email" class="form-label">{{ form.email.label.text }}</label>
            <div class="input-group">
              <span class="input-group-text bg-light text-muted"><i class="bi bi-envelope"></i></span>
              {{ form.email(class="form-control" + (" is-invalid" if form.email.errors else ""), placeholder="cliente@exemplo.com") }}
              {% for error in form.email.errors %}
                <div class="invalid-feedback">{{ error }}</div>
              {% endfor %}
            </div>
          </div>

          <div class="col-md-4">
            <label for="telefone" class="form-label">{{ form.telefone.label.text }}</label>
            <div class="input-group">
              <span class="input-group-text bg-light text-muted"><i class="bi bi-telephone"></i></span>
              {{ form.telefone(class="form-control" + (" is-invalid" if form.telefone.errors else ""), placeholder="(00) 00000-0000", id="telefone") }}
              {% for error in form.telefone.errors %}
                <div class="invalid-feedback">{{ error }}</div>
              {% endfor %}
            </div>
          </div>

          <div class="col-md-2 d-flex align-items-end">
            <div class="form-check form-switch mb-2">
              {{ form.ativo(class="form-check-input", id="ativo", role="switch") }}
              <label class="form-check-label fw-semibold" for="ativo">Ativo</label>
            </div>
          </div>
        </div>
      </div>

      <!-- CARD 2: ENDEREÇO -->
      <div class="card-custom p-4 mb-4 bg-white">
        <h5 class="fw-bold text-dark mb-3 pb-2 border-bottom d-flex align-items-center gap-2">
          <i class="bi bi-geo-alt-fill text-danger"></i> Endereço e Localização
        </h5>

        <div class="row g-3">
          <div class="col-md-3">
            <label for="cep" class="form-label">{{ form.cep.label.text }}</label>
            <div class="input-group">
              {{ form.cep(class="form-control" + (" is-invalid" if form.cep.errors else ""), placeholder="00000-000", id="cep") }}
              <span class="input-group-text bg-light text-muted" title="Busca automática de CEP" data-bs-toggle="tooltip">
                <i class="bi bi-search"></i>
              </span>
            </div>
            <small class="text-muted" style="font-size: 0.75rem;">Preenchimento automático via CEP</small>
            {% for error in form.cep.errors %}
              <div class="invalid-feedback">{{ error }}</div>
            {% endfor %}
          </div>

          <div class="col-md-7">
            <label for="logradouro" class="form-label">{{ form.logradouro.label.text }}</label>
            {{ form.logradouro(class="form-control" + (" is-invalid" if form.logradouro.errors else ""), placeholder="Rua, Avenida, Praça...", id="logradouro") }}
            {% for error in form.logradouro.errors %}
              <div class="invalid-feedback">{{ error }}</div>
            {% endfor %}
          </div>

          <div class="col-md-2">
            <label for="numero" class="form-label">{{ form.numero.label.text }}</label>
            {{ form.numero(class="form-control" + (" is-invalid" if form.numero.errors else ""), placeholder="123", id="numero") }}
            {% for error in form.numero.errors %}
              <div class="invalid-feedback">{{ error }}</div>
            {% endfor %}
          </div>

          <div class="col-md-4">
            <label for="complemento" class="form-label">{{ form.complemento.label.text }}</label>
            {{ form.complemento(class="form-control" + (" is-invalid" if form.complemento.errors else ""), placeholder="Apto 101, Bloco B...", id="complemento") }}
            {% for error in form.complemento.errors %}
              <div class="invalid-feedback">{{ error }}</div>
            {% endfor %}
          </div>

          <div class="col-md-3">
            <label for="bairro" class="form-label">{{ form.bairro.label.text }}</label>
            {{ form.bairro(class="form-control" + (" is-invalid" if form.bairro.errors else ""), placeholder="Centro, Jardins...", id="bairro") }}
            {% for error in form.bairro.errors %}
              <div class="invalid-feedback">{{ error }}</div>
            {% endfor %}
          </div>

          <div class="col-md-3">
            <label for="cidade" class="form-label">{{ form.cidade.label.text }}</label>
            {{ form.cidade(class="form-control" + (" is-invalid" if form.cidade.errors else ""), placeholder="São Paulo, Rio de Janeiro...", id="cidade") }}
            {% for error in form.cidade.errors %}
              <div class="invalid-feedback">{{ error }}</div>
            {% endfor %}
          </div>

          <div class="col-md-2">
            <label for="estado" class="form-label">{{ form.estado.label.text }}</label>
            {{ form.estado(class="form-select" + (" is-invalid" if form.estado.errors else ""), id="estado") }}
            {% for error in form.estado.errors %}
              <div class="invalid-feedback">{{ error }}</div>
            {% endfor %}
          </div>
        </div>
      </div>

      <!-- CARD 3: OBSERVAÇÕES -->
      <div class="card-custom p-4 mb-4 bg-white">
        <h5 class="fw-bold text-dark mb-3 pb-2 border-bottom d-flex align-items-center gap-2">
          <i class="bi bi-chat-left-text-fill text-info"></i> Observações e Notas Internas
        </h5>

        <div class="mb-3">
          {{ form.observacoes(class="form-control" + (" is-invalid" if form.observacoes.errors else ""), rows=3, placeholder="Informações de suporte, dados de faturamento ou detalhes importantes do cliente...") }}
          {% for error in form.observacoes.errors %}
            <div class="invalid-feedback">{{ error }}</div>
          {% endfor %}
        </div>
      </div>

      <!-- SUBMIT BAR -->
      <div class="d-flex align-items-center justify-content-end gap-2 mb-5">
        <a href="{{ url_for('clientes.index') }}" class="btn btn-light-custom px-4">Cancelar</a>
        <button type="submit" class="btn btn-primary-custom px-4">
          <i class="bi bi-check-lg"></i> {{ acao }}
        </button>
      </div>
    </form>
  </div>
</div>
{% endblock %}
OMNI_EOF

# --- app/templates/clientes/index.html ---
cat > 'app/templates/clientes/index.html' <<'OMNI_EOF'
{% extends "base.html" %}

{% block title %}Clientes - OmniGestão{% endblock %}

{% block content %}
<div class="d-flex flex-column flex-md-row align-items-md-center justify-content-between pb-3 mb-4 border-bottom gap-3">
  <div>
    <h2 class="fw-bold mb-1 text-dark">Cadastro de Clientes</h2>
    <p class="text-muted mb-0 small">Gerencie sua carteira de clientes, dados de contato e endereços</p>
  </div>
  <div>
    <a href="{{ url_for('clientes.novo') }}" class="btn btn-primary-custom shadow-sm">
      <i class="bi bi-person-plus-fill"></i> Novo Cliente
    </a>
  </div>
</div>

<!-- SEARCH & FILTER BAR -->
<div class="card-custom p-3 mb-4 bg-white">
  <form method="GET" action="{{ url_for('clientes.index') }}" class="row g-2 align-items-center">
    <div class="col-md-6 col-lg-7">
      <div class="input-group">
        <span class="input-group-text bg-light text-muted border-end-0">
          <i class="bi bi-search"></i>
        </span>
        <input type="text" name="q" class="form-control border-start-0" placeholder="Buscar por nome, e-mail, CPF/CNPJ ou cidade..." value="{{ search }}">
        {% if search %}
          <a href="{{ url_for('clientes.index', status=status_filter) }}" class="btn btn-outline-secondary" title="Limpar busca">
            <i class="bi bi-x-lg"></i>
          </a>
        {% endif %}
      </div>
    </div>

    <div class="col-md-4 col-lg-3">
      <select name="status" class="form-select" onchange="this.form.submit()">
        <option value="todos" {% if status_filter == 'todos' %}selected{% endif %}>Status: Todos</option>
        <option value="ativo" {% if status_filter == 'ativo' %}selected{% endif %}>Apenas Ativos</option>
        <option value="inativo" {% if status_filter == 'inativo' %}selected{% endif %}>Apenas Inativos</option>
      </select>
    </div>

    <div class="col-md-2 col-lg-2">
      <button type="submit" class="btn btn-light-custom w-100">
        <i class="bi bi-funnel"></i> Filtrar
      </button>
    </div>
  </form>
</div>

<!-- CLIENTS TABLE -->
<div class="card-custom">
  <div class="card-header bg-white border-bottom p-3 d-flex align-items-center justify-content-between">
    <span class="text-muted small">
      Exibindo <strong>{{ total_encontrados }}</strong> cliente(s)
    </span>
  </div>

  <div class="table-responsive">
    <table class="table-custom mb-0">
      <thead>
        <tr>
          <th>Cliente / Razão</th>
          <th>CPF / CNPJ</th>
          <th>Contato</th>
          <th>Cidade / UF</th>
          <th>Status</th>
          <th>Pedidos</th>
          <th class="text-end">Ações</th>
        </tr>
      </thead>
      <tbody>
        {% for cliente in clientes %}
          <tr>
            <td>
              <div class="d-flex align-items-center gap-2">
                <div class="rounded-circle bg-light text-primary fw-bold d-flex align-items-center justify-content-center" style="width: 36px; height: 36px; font-size: 0.85rem;">
                  {{ cliente.nome[:2].upper() }}
                </div>
                <div>
                  <a href="{{ url_for('clientes.detalhe', id=cliente.id) }}" class="fw-bold text-dark text-decoration-none">
                    {{ cliente.nome }}
                  </a>
                  <small class="text-muted d-block">{{ cliente.email }}</small>
                </div>
              </div>
            </td>
            <td>
              <span class="badge bg-light text-dark border font-monospace">
                {{ cliente.documento | doc_br }}
              </span>
            </td>
            <td>
              <span class="small text-muted d-block">
                <i class="bi bi-telephone me-1"></i>{{ cliente.telefone | phone_br }}
              </span>
            </td>
            <td>
              {% if cliente.cidade or cliente.estado %}
                <span class="small text-secondary">
                  <i class="bi bi-geo-alt me-1 text-danger"></i>{{ cliente.cidade or '-' }}{% if cliente.estado %}/{{ cliente.estado }}{% endif %}
                </span>
              {% else %}
                <span class="text-muted small">-</span>
              {% endif %}
            </td>
            <td>
              <span class="badge-status {{ 'badge-ativo' if cliente.ativo else 'badge-inativo' }}">
                {{ 'Ativo' if cliente.ativo else 'Inativo' }}
              </span>
            </td>
            <td>
              <a href="{{ url_for('clientes.detalhe', id=cliente.id) }}" class="badge bg-primary-subtle text-primary border-0 text-decoration-none px-2 py-1">
                {{ cliente.pedidos | length }} pedido(s)
              </a>
            </td>
            <td class="text-end">
              <div class="btn-group btn-group-sm">
                <a href="{{ url_for('clientes.detalhe', id=cliente.id) }}" class="btn btn-outline-secondary" title="Ver Detalhes" data-bs-toggle="tooltip">
                  <i class="bi bi-eye"></i>
                </a>
                <a href="{{ url_for('clientes.editar', id=cliente.id) }}" class="btn btn-outline-primary" title="Editar Cliente" data-bs-toggle="tooltip">
                  <i class="bi bi-pencil"></i>
                </a>
                <a href="{{ url_for('pedidos.novo', cliente_id=cliente.id) }}" class="btn btn-outline-success" title="Novo Pedido para este Cliente" data-bs-toggle="tooltip">
                  <i class="bi bi-cart-plus"></i>
                </a>
                <button type="button" class="btn btn-outline-danger" 
                        data-bs-toggle="modal" 
                        data-bs-target="#deleteConfirmModal"
                        data-action="{{ url_for('clientes.excluir', id=cliente.id) }}"
                        data-name="{{ cliente.nome }}"
                        data-type="o cliente">
                  <i class="bi bi-trash"></i>
                </button>
              </div>
            </td>
          </tr>
        {% else %}
          <tr>
            <td colspan="7" class="text-center py-5 text-muted">
              <i class="bi bi-search fs-1 d-block mb-2 text-secondary"></i>
              Nenhum cliente encontrado com os filtros aplicados.
              <div class="mt-3">
                {% if search or status_filter != 'todos' %}
                  <a href="{{ url_for('clientes.index') }}" class="btn btn-sm btn-outline-secondary">Limpar Filtros</a>
                {% else %}
                  <a href="{{ url_for('clientes.novo') }}" class="btn btn-sm btn-primary">Cadastrar Primeiro Cliente</a>
                {% endif %}
              </div>
            </td>
          </tr>
        {% endfor %}
      </tbody>
    </table>
  </div>
</div>
{% endblock %}
OMNI_EOF

# --- app/templates/dashboard/index.html ---
cat > 'app/templates/dashboard/index.html' <<'OMNI_EOF'
{% extends "base.html" %}

{% block title %}Dashboard - OmniGestão{% endblock %}

{% block content %}
<div class="d-flex flex-column flex-md-row align-items-md-center justify-content-between pb-3 mb-4 border-bottom gap-3">
  <div>
    <h2 class="fw-bold mb-1 text-dark">Painel de Controle</h2>
    <p class="text-muted mb-0 small">Visão geral em tempo real de clientes, faturamento e pedidos</p>
  </div>
  <div class="d-flex gap-2">
    <a href="{{ url_for('clientes.novo') }}" class="btn btn-light-custom btn-sm d-flex align-items-center gap-1 shadow-sm">
      <i class="bi bi-person-plus text-primary"></i> Novo Cliente
    </a>
    <a href="{{ url_for('pedidos.novo') }}" class="btn btn-primary-custom btn-sm shadow-sm">
      <i class="bi bi-cart-plus"></i> Novo Pedido
    </a>
  </div>
</div>

<!-- STAT CARDS ROW -->
<div class="row g-3 mb-4">
  <div class="col-sm-6 col-xl-3">
    <div class="card-stat">
      <div class="d-flex align-items-center justify-content-between mb-2">
        <div class="stat-title">Total de Clientes</div>
        <div class="stat-icon primary">
          <i class="bi bi-people"></i>
        </div>
      </div>
      <div class="stat-value">{{ total_clientes }}</div>
      <div class="small text-muted mt-2">
        <span class="text-success fw-semibold"><i class="bi bi-check-circle me-1"></i>{{ clientes_ativos }}</span> ativos no sistema
      </div>
    </div>
  </div>

  <div class="col-sm-6 col-xl-3">
    <div class="card-stat">
      <div class="d-flex align-items-center justify-content-between mb-2">
        <div class="stat-title">Faturamento Total</div>
        <div class="stat-icon success">
          <i class="bi bi-cash-stack"></i>
        </div>
      </div>
      <div class="stat-value text-success">{{ faturamento_total | currency }}</div>
      <div class="small text-muted mt-2">
        <span>Concluído: <strong>{{ faturamento_concluido | currency }}</strong></span>
      </div>
    </div>
  </div>

  <div class="col-sm-6 col-xl-3">
    <div class="card-stat">
      <div class="d-flex align-items-center justify-content-between mb-2">
        <div class="stat-title">Total de Pedidos</div>
        <div class="stat-icon info">
          <i class="bi bi-bag-check"></i>
        </div>
      </div>
      <div class="stat-value">{{ total_pedidos }}</div>
      <div class="small text-muted mt-2">
        <span>Ticket Médio: <strong>{{ ticket_medio | currency }}</strong></span>
      </div>
    </div>
  </div>

  <div class="col-sm-6 col-xl-3">
    <div class="card-stat">
      <div class="d-flex align-items-center justify-content-between mb-2">
        <div class="stat-title">Pedidos Pendentes</div>
        <div class="stat-icon warning">
          <i class="bi bi-hourglass-split"></i>
        </div>
      </div>
      <div class="stat-value text-warning">{{ pedidos_pendentes }}</div>
      <div class="small text-muted mt-2">
        <span class="text-info fw-semibold">{{ pedidos_processando }}</span> em processamento
      </div>
    </div>
  </div>
</div>

<!-- ORDERS BY STATUS SUMMARY PILLS -->
<div class="card-custom p-3 mb-4 bg-white">
  <div class="row text-center g-2 align-items-center">
    <div class="col-6 col-md-3 border-end">
      <div class="text-muted small">Pendentes</div>
      <div class="fs-5 fw-bold text-warning">{{ pedidos_pendentes }}</div>
    </div>
    <div class="col-6 col-md-3 border-end">
      <div class="text-muted small">Em Processamento</div>
      <div class="fs-5 fw-bold text-info">{{ pedidos_processando }}</div>
    </div>
    <div class="col-6 col-md-3 border-end">
      <div class="text-muted small">Concluídos</div>
      <div class="fs-5 fw-bold text-success">{{ pedidos_concluidos }}</div>
    </div>
    <div class="col-6 col-md-3">
      <div class="text-muted small">Cancelados</div>
      <div class="fs-5 fw-bold text-danger">{{ pedidos_cancelados }}</div>
    </div>
  </div>
</div>

<!-- RECENT TABLES ROW -->
<div class="row g-4">
  <!-- RECENT ORDERS -->
  <div class="col-lg-7">
    <div class="card-custom h-100">
      <div class="card-header bg-white border-bottom p-3 d-flex align-items-center justify-content-between">
        <h6 class="fw-bold mb-0 text-dark">
          <i class="bi bi-clock-history me-2 text-primary"></i>Últimos Pedidos
        </h6>
        <a href="{{ url_for('pedidos.index') }}" class="btn btn-sm btn-link text-decoration-none p-0 fw-semibold">
          Ver todos ({{ total_pedidos }}) &rarr;
        </a>
      </div>
      <div class="table-responsive">
        <table class="table-custom mb-0">
          <thead>
            <tr>
              <th>Pedido</th>
              <th>Cliente</th>
              <th>Data</th>
              <th>Valor</th>
              <th>Status</th>
              <th class="text-end">Ação</th>
            </tr>
          </thead>
          <tbody>
            {% for pedido in ultimos_pedidos %}
              <tr>
                <td>
                  <a href="{{ url_for('pedidos.detalhe', id=pedido.id) }}" class="fw-bold text-decoration-none text-dark">
                    #{{ pedido.numero_pedido }}
                  </a>
                </td>
                <td>
                  <a href="{{ url_for('clientes.detalhe', id=pedido.cliente.id) }}" class="text-decoration-none text-dark text-truncate d-inline-block" style="max-width: 140px;">
                    {{ pedido.cliente.nome }}
                  </a>
                </td>
                <td class="text-muted small">{{ pedido.data_pedido | date_br }}</td>
                <td class="fw-bold">{{ pedido.valor_total | currency }}</td>
                <td>
                  <span class="badge-status badge-{{ pedido.status }}">
                    {{ pedido.status_label }}
                  </span>
                </td>
                <td class="text-end">
                  <a href="{{ url_for('pedidos.detalhe', id=pedido.id) }}" class="btn btn-sm btn-light p-1 px-2" title="Visualizar Pedido">
                    <i class="bi bi-eye"></i>
                  </a>
                </td>
              </tr>
            {% else %}
              <tr>
                <td colspan="6" class="text-center py-4 text-muted">
                  <i class="bi bi-inbox fs-2 d-block mb-2 text-secondary"></i>
                  Nenhum pedido registrado ainda.
                  <div class="mt-2">
                    <a href="{{ url_for('pedidos.novo') }}" class="btn btn-sm btn-primary">Cadastrar Primeiro Pedido</a>
                  </div>
                </td>
              </tr>
            {% endfor %}
          </tbody>
        </table>
      </div>
    </div>
  </div>

  <!-- RECENT CLIENTS -->
  <div class="col-lg-5">
    <div class="card-custom h-100">
      <div class="card-header bg-white border-bottom p-3 d-flex align-items-center justify-content-between">
        <h6 class="fw-bold mb-0 text-dark">
          <i class="bi bi-people me-2 text-primary"></i>Clientes Recentes
        </h6>
        <a href="{{ url_for('clientes.index') }}" class="btn btn-sm btn-link text-decoration-none p-0 fw-semibold">
          Ver todos ({{ total_clientes }}) &rarr;
        </a>
      </div>
      <div class="p-0">
        <ul class="list-group list-group-flush">
          {% for cliente in ultimos_clientes %}
            <li class="list-group-item p-3 d-flex align-items-center justify-content-between">
              <div class="d-flex align-items-center gap-3 text-truncate">
                <div class="rounded-circle bg-primary-subtle text-primary d-flex align-items-center justify-content-center fw-bold" style="width: 42px; height: 42px; flex-shrink: 0;">
                  {{ cliente.nome[:2].upper() }}
                </div>
                <div class="text-truncate">
                  <a href="{{ url_for('clientes.detalhe', id=cliente.id) }}" class="fw-bold text-dark text-decoration-none d-block text-truncate">
                    {{ cliente.nome }}
                  </a>
                  <small class="text-muted d-block text-truncate">
                    <i class="bi bi-envelope me-1"></i>{{ cliente.email }}
                  </small>
                </div>
              </div>
              <div class="text-end ps-2 flex-shrink-0">
                <span class="badge-status {{ 'badge-ativo' if cliente.ativo else 'badge-inativo' }} mb-1 d-inline-block">
                  {{ 'Ativo' if cliente.ativo else 'Inativo' }}
                </span>
                <div class="small text-muted">{{ cliente.pedidos | length }} pedidos</div>
              </div>
            </li>
          {% else %}
            <li class="list-group-item text-center py-4 text-muted">
              <i class="bi bi-person-x fs-2 d-block mb-2 text-secondary"></i>
              Nenhum cliente cadastrado ainda.
              <div class="mt-2">
                <a href="{{ url_for('clientes.novo') }}" class="btn btn-sm btn-outline-primary">Cadastrar Cliente</a>
              </div>
            </li>
          {% endfor %}
        </ul>
      </div>
    </div>
  </div>
</div>
{% endblock %}
OMNI_EOF

# --- app/templates/errors/404.html ---
cat > 'app/templates/errors/404.html' <<'OMNI_EOF'
{% extends "base.html" %}

{% block title %}Página não encontrada - 404{% endblock %}

{% block content %}
<div class="text-center py-5">
  <div class="display-1 fw-bold text-primary mb-3">404</div>
  <h3 class="fw-bold mb-2">Ops! Página não encontrada.</h3>
  <p class="text-muted mb-4">A página que você está procurando pode ter sido removida ou está indisponível.</p>
  <a href="{{ url_for('main.dashboard') }}" class="btn btn-primary-custom">
    <i class="bi bi-house"></i> Voltar ao Dashboard
  </a>
</div>
{% endblock %}
OMNI_EOF

# --- app/templates/errors/500.html ---
cat > 'app/templates/errors/500.html' <<'OMNI_EOF'
{% extends "base.html" %}

{% block title %}Erro Interno - 500{% endblock %}

{% block content %}
<div class="text-center py-5">
  <div class="display-1 fw-bold text-danger mb-3">500</div>
  <h3 class="fw-bold mb-2">Erro interno do servidor.</h3>
  <p class="text-muted mb-4">Ocorreu uma falha inesperada durante o processamento. Nossa equipe foi notificada.</p>
  <a href="{{ url_for('main.dashboard') }}" class="btn btn-primary-custom">
    <i class="bi bi-house"></i> Voltar ao Dashboard
  </a>
</div>
{% endblock %}
OMNI_EOF

# --- app/templates/pedidos/detail.html ---
cat > 'app/templates/pedidos/detail.html' <<'OMNI_EOF'
{% extends "base.html" %}

{% block title %}Pedido #{{ pedido.numero_pedido }} - OmniGestão{% endblock %}

{% block extra_css %}
<style>
  @media print {
    .sidebar, .top-navbar, .no-print, .breadcrumb {
      display: none !important;
    }
    .main-content {
      margin: 0 !important;
      padding: 0 !important;
    }
    .page-container {
      padding: 0 !important;
    }
    .card-custom {
      box-shadow: none !important;
      border: 1px solid #ccc !important;
    }
  }
</style>
{% endblock %}

{% block content %}
<div class="mb-4 no-print">
  <nav aria-label="breadcrumb">
    <ol class="breadcrumb small mb-1">
      <li class="breadcrumb-item"><a href="{{ url_for('pedidos.index') }}" class="text-decoration-none">Pedidos</a></li>
      <li class="breadcrumb-item active" aria-current="page">#{{ pedido.numero_pedido }}</li>
    </ol>
  </nav>

  <div class="d-flex flex-column flex-md-row align-items-md-center justify-content-between gap-3">
    <div class="d-flex align-items-center gap-2">
      <h2 class="fw-bold mb-0 text-dark">Pedido #{{ pedido.numero_pedido }}</h2>
      <span class="badge-status badge-{{ pedido.status }}">
        {{ pedido.status_label }}
      </span>
    </div>

    <div class="d-flex flex-wrap gap-2">
      <button onclick="window.print()" class="btn btn-outline-secondary btn-sm">
        <i class="bi bi-printer"></i> Imprimir
      </button>
      <a href="{{ url_for('pedidos.editar', id=pedido.id) }}" class="btn btn-primary-custom btn-sm">
        <i class="bi bi-pencil"></i> Editar Pedido
      </a>
      <button type="button" class="btn btn-outline-danger btn-sm"
              data-bs-toggle="modal"
              data-bs-target="#deleteConfirmModal"
              data-action="{{ url_for('pedidos.excluir', id=pedido.id) }}"
              data-name="Pedido #{{ pedido.numero_pedido }}"
              data-type="o pedido">
        <i class="bi bi-trash"></i> Excluir
      </button>
    </div>
  </div>
</div>

<div class="row justify-content-center">
  <div class="col-lg-10">
    <div class="card-custom p-4 p-md-5 bg-white">
      <!-- INVOICE HEADER -->
      <div class="d-flex flex-column flex-md-row justify-content-between align-items-start pb-4 border-bottom mb-4 gap-3">
        <div>
          <div class="d-flex align-items-center gap-2 mb-2">
            <div class="brand-icon" style="width: 36px; height: 36px; font-size: 1.1rem;">
              <i class="bi bi-layers-fill"></i>
            </div>
            <h4 class="fw-bold mb-0 text-dark">OmniGestão</h4>
          </div>
          <p class="text-muted small mb-0">Comprovante e Detalhes do Pedido Comercial</p>
        </div>

        <div class="text-md-end">
          <div class="badge bg-light text-dark border fs-6 font-monospace mb-1">
            {{ pedido.numero_pedido }}
          </div>
          <div class="text-muted small">
            Emitido em: <strong>{{ pedido.data_pedido | datetime_br }}</strong>
          </div>
          <div class="text-muted small">
            Atualizado em: {{ pedido.updated_at | datetime_br }}
          </div>
        </div>
      </div>

      <!-- INVOICE PARTIES -->
      <div class="row g-4 mb-4">
        <div class="col-md-6 border-end-md">
          <h6 class="text-uppercase text-muted fw-bold small mb-2">Dados do Cliente</h6>
          <h5 class="fw-bold mb-1">
            <a href="{{ url_for('clientes.detalhe', id=pedido.cliente.id) }}" class="text-dark text-decoration-none">
              {{ pedido.cliente.nome }}
            </a>
          </h5>
          <div class="text-muted small mb-1">
            <strong>CPF/CNPJ:</strong> {{ pedido.cliente.documento | doc_br }}
          </div>
          <div class="text-muted small mb-1">
            <strong>E-mail:</strong> {{ pedido.cliente.email }}
          </div>
          <div class="text-muted small mb-1">
            <strong>Telefone:</strong> {{ pedido.cliente.telefone | phone_br }}
          </div>
          <div class="text-muted small mt-2">
            <strong>Endereço:</strong><br>
            {{ pedido.cliente.endereco_completo }}
          </div>
        </div>

        <div class="col-md-6 ps-md-4">
          <h6 class="text-uppercase text-muted fw-bold small mb-2">Pagamento & Situação</h6>
          <div class="mb-2">
            <span class="text-muted small d-block">Status Atual:</span>
            <span class="badge-status badge-{{ pedido.status }} fs-6">
              {{ pedido.status_label }}
            </span>
          </div>
          <div class="mb-2">
            <span class="text-muted small d-block">Forma de Pagamento:</span>
            <strong class="text-dark">{{ pedido.metodo_pagamento_label }}</strong>
          </div>
          <div class="mt-3 p-3 bg-light rounded-3">
            <span class="text-muted small d-block">Valor Total do Pedido:</span>
            <span class="fs-3 fw-bold text-success">{{ pedido.valor_total | currency }}</span>
          </div>
        </div>
      </div>

      <!-- ITEMS TABLE -->
      <div class="mb-4">
        <div class="d-flex align-items-center justify-content-between mb-2">
          <h6 class="text-uppercase text-muted fw-bold small mb-0 d-flex align-items-center gap-2">
            <i class="bi bi-box-seam text-primary"></i> Itens do Pedido ({{ pedido.itens|length if pedido.itens else 0 }})
          </h6>
          <span class="badge bg-light text-muted border small">
            {{ pedido.itens|length }} {{ 'item cadastrado' if (pedido.itens|length == 1) else 'itens cadastrados' }}
          </span>
        </div>

        <div class="table-responsive border rounded-3 overflow-hidden">
          <table class="table table-striped align-middle mb-0">
            <thead class="table-light text-secondary small text-uppercase">
              <tr>
                <th style="width: 50px;" class="text-center">#</th>
                <th>Descrição do Item</th>
                <th style="width: 130px;" class="text-end">Quantidade</th>
                <th style="width: 170px;" class="text-end">Valor Unitário</th>
                <th style="width: 170px;" class="text-end">Valor Total</th>
              </tr>
            </thead>
            <tbody>
              {% for item in pedido.itens %}
                <tr>
                  <td class="text-center text-muted fw-semibold">{{ loop.index }}</td>
                  <td>
                    <span class="fw-semibold text-dark">{{ item.descricao }}</span>
                  </td>
                  <td class="text-end font-monospace">
                    {{ item.quantidade|int if item.quantidade == item.quantidade|int else item.quantidade }}
                  </td>
                  <td class="text-end text-muted">
                    {{ item.valor_unitario | currency }}
                  </td>
                  <td class="text-end fw-bold text-dark">
                    {{ item.valor_total | currency }}
                  </td>
                </tr>
              {% else %}
                <tr>
                  <td colspan="5" class="p-3 text-muted">
                    {{ pedido.descricao or 'Nenhum item discriminado individualmente.' }}
                  </td>
                </tr>
              {% endfor %}
            </tbody>
            <tfoot class="table-light border-top">
              <tr>
                <td colspan="4" class="text-end fw-bold text-dark py-3">
                  <span class="text-muted small me-2">Soma dos Itens:</span>
                  Valor Total do Pedido:
                </td>
                <td class="text-end fw-bold text-success fs-5 py-3">
                  {{ pedido.valor_total | currency }}
                </td>
              </tr>
            </tfoot>
          </table>
        </div>
      </div>

      <!-- GENERAL DESCRIPTION / NOTES -->
      {% if pedido.descricao and pedido.descricao != pedido.resumo_itens %}
        <div class="mb-4">
          <h6 class="text-uppercase text-muted fw-bold small mb-2">Resumo Geral / Descrição do Pedido</h6>
          <div class="p-3 bg-light rounded-3 border">
            <p class="mb-0 text-dark" style="white-space: pre-line;">{{ pedido.descricao }}</p>
          </div>
        </div>
      {% endif %}

      <!-- OBSERVATIONS -->
      {% if pedido.observacoes %}
        <div class="mb-4">
          <h6 class="text-uppercase text-muted fw-bold small mb-2">Observações Adicionais</h6>
          <div class="p-3 bg-white border rounded-3 text-secondary small">
            <p class="mb-0" style="white-space: pre-line;">{{ pedido.observacoes }}</p>
          </div>
        </div>
      {% endif %}

      <!-- FOOTER NOTE -->
      <div class="pt-4 border-top text-center text-muted small">
        <p class="mb-0">Documento gerado automaticamente pelo sistema OmniGestão.</p>
      </div>
    </div>
  </div>
</div>
{% endblock %}
OMNI_EOF

# --- app/templates/pedidos/form.html ---
cat > 'app/templates/pedidos/form.html' <<'OMNI_EOF'
{% extends "base.html" %}

{% block title %}{{ titulo }} - OmniGestão{% endblock %}

{% block content %}
<div class="mb-4">
  <nav aria-label="breadcrumb">
    <ol class="breadcrumb small mb-1">
      <li class="breadcrumb-item"><a href="{{ url_for('pedidos.index') }}" class="text-decoration-none">Pedidos</a></li>
      <li class="breadcrumb-item active" aria-current="page">{{ titulo }}</li>
    </ol>
  </nav>
  <div class="d-flex align-items-center justify-content-between">
    <div>
      <h2 class="fw-bold mb-0 text-dark">{{ titulo }}</h2>
      <p class="text-muted small mb-0">Preencha as informações do pedido e seus itens (mínimo de 1 e máximo de 10 itens).</p>
    </div>
    <a href="{{ url_for('pedidos.index') }}" class="btn btn-outline-secondary btn-sm">
      <i class="bi bi-arrow-left"></i> Voltar à Lista
    </a>
  </div>
</div>

<div class="row justify-content-center">
  <div class="col-lg-11 col-xl-10">
    <form method="POST" id="pedidoForm" novalidate>
      {{ form.hidden_tag() }}

      <!-- DADOS PRINCIPAIS DO PEDIDO -->
      <div class="card-custom p-4 mb-4 bg-white">
        <h5 class="fw-bold text-dark mb-3 pb-2 border-bottom d-flex align-items-center gap-2">
          <i class="bi bi-receipt text-primary"></i> Dados Principais do Pedido
        </h5>

        <div class="row g-3">
          <div class="col-md-6 col-lg-5">
            <label for="cliente_id" class="form-label">{{ form.cliente_id.label.text }}</label>
            {{ form.cliente_id(class="form-select" + (" is-invalid" if form.cliente_id.errors else "")) }}
            {% for error in form.cliente_id.errors %}
              <div class="invalid-feedback">{{ error }}</div>
            {% endfor %}
            <small class="text-muted" style="font-size: 0.75rem;">
              Não encontrou o cliente? <a href="{{ url_for('clientes.novo') }}" target="_blank">Cadastre um novo aqui</a>
            </small>
          </div>

          <div class="col-md-3 col-lg-3">
            <label for="numero_pedido" class="form-label">{{ form.numero_pedido.label.text }}</label>
            {{ form.numero_pedido(class="form-control" + (" is-invalid" if form.numero_pedido.errors else ""), placeholder="PED-2026-0001") }}
            {% for error in form.numero_pedido.errors %}
              <div class="invalid-feedback">{{ error }}</div>
            {% endfor %}
          </div>

          <div class="col-md-3 col-lg-4">
            <label for="data_pedido" class="form-label">{{ form.data_pedido.label.text }}</label>
            {{ form.data_pedido(class="form-control" + (" is-invalid" if form.data_pedido.errors else "")) }}
            {% for error in form.data_pedido.errors %}
              <div class="invalid-feedback">{{ error }}</div>
            {% endfor %}
          </div>

          <div class="col-md-4">
            <label for="status" class="form-label">{{ form.status.label.text }}</label>
            {{ form.status(class="form-select" + (" is-invalid" if form.status.errors else "")) }}
            {% for error in form.status.errors %}
              <div class="invalid-feedback">{{ error }}</div>
            {% endfor %}
          </div>

          <div class="col-md-4">
            <label for="metodo_pagamento" class="form-label">{{ form.metodo_pagamento.label.text }}</label>
            {{ form.metodo_pagamento(class="form-select" + (" is-invalid" if form.metodo_pagamento.errors else "")) }}
            {% for error in form.metodo_pagamento.errors %}
              <div class="invalid-feedback">{{ error }}</div>
            {% endfor %}
          </div>

          <div class="col-md-4">
            <label for="valor_total" class="form-label fw-bold text-dark">
              Valor Total do Pedido (R$)
            </label>
            <div class="input-group">
              <span class="input-group-text bg-light fw-bold text-success">R$</span>
              <input type="text"
                     name="valor_total"
                     id="valor_total"
                     class="form-control bg-light fw-bold text-success fs-6"
                     value="{{ '%.2f'|format(form.valor_total.data) if form.valor_total.data else '0.00' }}"
                     readonly>
            </div>
            <small class="text-muted" style="font-size: 0.75rem;">
              Totalizado automaticamente pela soma dos itens.
            </small>
          </div>
        </div>
      </div>

      <!-- ITENS DO PEDIDO (MÍNIMO 1 E MÁXIMO 10) -->
      <div class="card-custom p-4 mb-4 bg-white">
        <div class="d-flex flex-wrap align-items-center justify-content-between pb-3 mb-3 border-bottom gap-2">
          <div>
            <h5 class="fw-bold text-dark mb-1 d-flex align-items-center gap-2">
              <i class="bi bi-box-seam text-primary"></i> Itens do Pedido *
            </h5>
            <p class="text-muted small mb-0">
              Obrigatório existir pelo menos <strong>1 item</strong> e no máximo <strong>10 itens</strong> por pedido.
            </p>
          </div>

          <div class="d-flex align-items-center gap-2">
            <span id="itemCountBadge" class="badge bg-light text-primary border border-primary-subtle px-3 py-2 fs-6 fw-semibold">
              <i class="bi bi-list-check me-1"></i>
              <span id="itemCountNum">{{ itens|length if itens else 1 }}</span> / 10 itens
            </span>
            <button type="button" id="btnAddItem" class="btn btn-primary-custom btn-sm px-3">
              <i class="bi bi-plus-lg me-1"></i> Adicionar Item
            </button>
          </div>
        </div>

        <div class="table-responsive">
          <table class="table align-middle mb-0" id="itensTable">
            <thead class="table-light text-secondary small text-uppercase">
              <tr>
                <th style="width: 50px;" class="text-center">#</th>
                <th>Descrição do Item *</th>
                <th style="width: 140px;">Quantidade *</th>
                <th style="width: 170px;">Valor Unitário (R$) *</th>
                <th style="width: 180px;">Valor Total do Item (R$)</th>
                <th style="width: 60px;" class="text-center">Ação</th>
              </tr>
            </thead>
            <tbody id="itensTableBody">
              {% for item in itens %}
                <tr class="item-row" data-index="{{ loop.index0 }}">
                  <td class="text-center fw-bold text-muted row-number">{{ loop.index }}</td>
                  <td>
                    {% if item.id %}
                      <input type="hidden" name="itens-{{ loop.index0 }}-id" value="{{ item.id }}">
                    {% endif %}
                    <input type="text"
                           name="itens-{{ loop.index0 }}-descricao"
                           class="form-control item-descricao"
                           placeholder="Ex: Consultoria técnica, Monitor 27'', etc."
                           value="{{ item.descricao }}"
                           required>
                  </td>
                  <td>
                    <input type="number"
                           name="itens-{{ loop.index0 }}-quantidade"
                           class="form-control item-qtd text-end"
                           placeholder="1"
                           step="any"
                           min="0.01"
                           value="{{ item.quantidade if item.quantidade is defined and item.quantidade != '' else 1 }}"
                           required>
                  </td>
                  <td>
                    <div class="input-group">
                      <span class="input-group-text bg-light text-muted small">R$</span>
                      <input type="number"
                             name="itens-{{ loop.index0 }}-valor_unitario"
                             class="form-control item-unit text-end"
                             placeholder="0.00"
                             step="0.01"
                             min="0.01"
                             value="{{ item.valor_unitario if item.valor_unitario is defined and item.valor_unitario != '' else '' }}"
                             required>
                    </div>
                  </td>
                  <td>
                    <div class="input-group">
                      <span class="input-group-text bg-light text-muted small">R$</span>
                      <input type="text"
                             name="itens-{{ loop.index0 }}-valor_total"
                             class="form-control item-total text-end bg-light fw-bold text-dark"
                             value="{{ '%.2f'|format(item.valor_total) if item.valor_total is defined and item.valor_total else '0.00' }}"
                             readonly>
                    </div>
                  </td>
                  <td class="text-center">
                    <button type="button" class="btn btn-outline-danger btn-sm btn-remove-item" title="Remover item">
                      <i class="bi bi-trash"></i>
                    </button>
                  </td>
                </tr>
              {% else %}
                <tr class="item-row" data-index="0">
                  <td class="text-center fw-bold text-muted row-number">1</td>
                  <td>
                    <input type="text"
                           name="itens-0-descricao"
                           class="form-control item-descricao"
                           placeholder="Ex: Consultoria técnica, Monitor 27'', etc."
                           required>
                  </td>
                  <td>
                    <input type="number"
                           name="itens-0-quantidade"
                           class="form-control item-qtd text-end"
                           placeholder="1"
                           step="any"
                           min="0.01"
                           value="1"
                           required>
                  </td>
                  <td>
                    <div class="input-group">
                      <span class="input-group-text bg-light text-muted small">R$</span>
                      <input type="number"
                             name="itens-0-valor_unitario"
                             class="form-control item-unit text-end"
                             placeholder="0.00"
                             step="0.01"
                             min="0.01"
                             required>
                    </div>
                  </td>
                  <td>
                    <div class="input-group">
                      <span class="input-group-text bg-light text-muted small">R$</span>
                      <input type="text"
                             name="itens-0-valor_total"
                             class="form-control item-total text-end bg-light fw-bold text-dark"
                             value="0.00"
                             readonly>
                    </div>
                  </td>
                  <td class="text-center">
                    <button type="button" class="btn btn-outline-danger btn-sm btn-remove-item" title="Remover item">
                      <i class="bi bi-trash"></i>
                    </button>
                  </td>
                </tr>
              {% endfor %}
            </tbody>
            <tfoot class="table-light border-top">
              <tr>
                <td colspan="4" class="text-end fw-bold text-dark py-3">
                  <span class="text-muted me-2 small">Soma de todos os itens:</span>
                  Valor Total do Pedido:
                </td>
                <td class="fw-bold text-success fs-5 py-3">
                  <span id="orderTotalDisplay">R$ 0,00</span>
                </td>
                <td></td>
              </tr>
            </tfoot>
          </table>
        </div>

        <div id="itemLimitAlert" class="alert alert-warning d-none mt-3 mb-0 py-2 small d-flex align-items-center gap-2">
          <i class="bi bi-exclamation-triangle-fill"></i>
          <span>Limite máximo de 10 itens atingido para este pedido. Para adicionar outro item, remova um item existente.</span>
        </div>
      </div>

      <!-- OBSERVAÇÕES E DETALHES GERAIS -->
      <div class="card-custom p-4 mb-4 bg-white">
        <h5 class="fw-bold text-dark mb-3 pb-2 border-bottom d-flex align-items-center gap-2">
          <i class="bi bi-chat-left-text text-secondary"></i> Observações e Resumo Adicional
        </h5>

        <div class="mb-3">
          <label for="descricao" class="form-label">{{ form.descricao.label.text }}</label>
          {{ form.descricao(class="form-control" + (" is-invalid" if form.descricao.errors else ""), rows=2, placeholder="Resumo opcional dos serviços ou produtos contratados (preenchido automaticamente se deixado em branco)...") }}
          {% for error in form.descricao.errors %}
            <div class="invalid-feedback">{{ error }}</div>
          {% endfor %}
        </div>

        <div class="mb-0">
          <label for="observacoes" class="form-label">{{ form.observacoes.label.text }}</label>
          {{ form.observacoes(class="form-control" + (" is-invalid" if form.observacoes.errors else ""), rows=2, placeholder="Observações de entrega, termos de garantia, condições especiais de faturamento...") }}
          {% for error in form.observacoes.errors %}
            <div class="invalid-feedback">{{ error }}</div>
          {% endfor %}
        </div>
      </div>

      <!-- BOTÕES DE AÇÃO -->
      <div class="d-flex align-items-center justify-content-end gap-2 mb-5">
        <a href="{{ url_for('pedidos.index') }}" class="btn btn-light-custom px-4">Cancelar</a>
        <button type="submit" id="btnSubmitPedido" class="btn btn-primary-custom px-4">
          <i class="bi bi-check-lg"></i> {{ acao }}
        </button>
      </div>
    </form>
  </div>
</div>

<!-- TEMPLATE PARA NOVA LINHA DE ITEM -->
<template id="itemRowTemplate">
  <tr class="item-row" data-index="__INDEX__">
    <td class="text-center fw-bold text-muted row-number">__NUM__</td>
    <td>
      <input type="text"
             name="itens-__INDEX__-descricao"
             class="form-control item-descricao"
             placeholder="Ex: Consultoria técnica, Monitor 27'', etc."
             required>
    </td>
    <td>
      <input type="number"
             name="itens-__INDEX__-quantidade"
             class="form-control item-qtd text-end"
             placeholder="1"
             step="any"
             min="0.01"
             value="1"
             required>
    </td>
    <td>
      <div class="input-group">
        <span class="input-group-text bg-light text-muted small">R$</span>
        <input type="number"
               name="itens-__INDEX__-valor_unitario"
               class="form-control item-unit text-end"
               placeholder="0.00"
               step="0.01"
               min="0.01"
               required>
      </div>
    </td>
    <td>
      <div class="input-group">
        <span class="input-group-text bg-light text-muted small">R$</span>
        <input type="text"
               name="itens-__INDEX__-valor_total"
               class="form-control item-total text-end bg-light fw-bold text-dark"
               value="0.00"
               readonly>
      </div>
    </td>
    <td class="text-center">
      <button type="button" class="btn btn-outline-danger btn-sm btn-remove-item" title="Remover item">
        <i class="bi bi-trash"></i>
      </button>
    </td>
  </tr>
</template>
{% endblock %}

{% block extra_js %}
<script>
document.addEventListener('DOMContentLoaded', function () {
  const tableBody = document.getElementById('itensTableBody');
  const btnAddItem = document.getElementById('btnAddItem');
  const itemCountBadge = document.getElementById('itemCountNum');
  const itemLimitAlert = document.getElementById('itemLimitAlert');
  const template = document.getElementById('itemRowTemplate');
  const valorTotalInput = document.getElementById('valor_total');
  const orderTotalDisplay = document.getElementById('orderTotalDisplay');
  const pedidoForm = document.getElementById('pedidoForm');

  const MAX_ITENS = 10;
  const MIN_ITENS = 1;

  function formatBRL(value) {
    return new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(value);
  }

  // Recalcula o subtotal de uma linha (Qtd * Vlr Unitario)
  function recalculateRow(row) {
    const qtdInput = row.querySelector('.item-qtd');
    const unitInput = row.querySelector('.item-unit');
    const totalInput = row.querySelector('.item-total');

    const qtd = parseFloat(qtdInput.value.replace(',', '.')) || 0;
    const unit = parseFloat(unitInput.value.replace(',', '.')) || 0;

    const rowTotal = Math.round((qtd * unit) * 100) / 100;
    totalInput.value = rowTotal.toFixed(2);

    return rowTotal;
  }

  // Recalcula todos os itens e totaliza o pedido
  function recalculateAll() {
    const rows = tableBody.querySelectorAll('.item-row');
    let orderTotal = 0;

    rows.forEach(function (row) {
      orderTotal += recalculateRow(row);
    });

    orderTotal = Math.round(orderTotal * 100) / 100;

    if (valorTotalInput) {
      valorTotalInput.value = orderTotal.toFixed(2);
    }
    if (orderTotalDisplay) {
      orderTotalDisplay.textContent = formatBRL(orderTotal);
    }
  }

  // Reindexa as linhas para manter a integridade dos inputs itens-0-*, itens-1-*, etc.
  function reindexRows() {
    const rows = tableBody.querySelectorAll('.item-row');
    const totalRows = rows.length;

    if (itemCountBadge) {
      itemCountBadge.textContent = totalRows;
    }

    rows.forEach(function (row, idx) {
      row.setAttribute('data-index', idx);
      const rowNumberEl = row.querySelector('.row-number');
      if (rowNumberEl) {
        rowNumberEl.textContent = idx + 1;
      }

      // Atualiza os nomes dos campos para manter a numeração sequencial
      row.querySelectorAll('input').forEach(function (input) {
        const name = input.getAttribute('name');
        if (name && name.startsWith('itens-')) {
          const parts = name.split('-');
          if (parts.length >= 3) {
            input.setAttribute('name', `itens-${idx}-${parts.slice(2).join('-')}`);
          }
        }
      });

      // Se houver apenas 1 item, desabilita o botão de remoção para garantir pelo menos 1 item
      const removeBtn = row.querySelector('.btn-remove-item');
      if (removeBtn) {
        if (totalRows <= MIN_ITENS) {
          removeBtn.setAttribute('disabled', 'disabled');
          removeBtn.setAttribute('title', 'O pedido deve ter pelo menos 1 item.');
          removeBtn.classList.add('disabled');
        } else {
          removeBtn.removeAttribute('disabled');
          removeBtn.setAttribute('title', 'Remover este item');
          removeBtn.classList.remove('disabled');
        }
      }
    });

    // Controla o botão de adicionar item de acordo com o limite de 10
    if (totalRows >= MAX_ITENS) {
      if (btnAddItem) {
        btnAddItem.setAttribute('disabled', 'disabled');
      }
      if (itemLimitAlert) {
        itemLimitAlert.classList.remove('d-none');
      }
    } else {
      if (btnAddItem) {
        btnAddItem.removeAttribute('disabled');
      }
      if (itemLimitAlert) {
        itemLimitAlert.classList.add('d-none');
      }
    }
  }

  // Adicionar novo item
  if (btnAddItem) {
    btnAddItem.addEventListener('click', function () {
      const rows = tableBody.querySelectorAll('.item-row');
      if (rows.length >= MAX_ITENS) {
        alert('Limite máximo de 10 itens por pedido atingido.');
        return;
      }

      const newIndex = rows.length;
      let html = template.innerHTML
        .replace(/__INDEX__/g, newIndex)
        .replace(/__NUM__/g, newIndex + 1);

      const tempDiv = document.createElement('tbody');
      tempDiv.innerHTML = html;
      const newRow = tempDiv.firstElementChild;

      tableBody.appendChild(newRow);

      reindexRows();
      recalculateAll();

      const descInput = newRow.querySelector('.item-descricao');
      if (descInput) {
        descInput.focus();
      }
    });
  }

  // Event Delegation para inputs e remoção de itens
  tableBody.addEventListener('input', function (e) {
    if (e.target.classList.contains('item-qtd') || e.target.classList.contains('item-unit')) {
      recalculateAll();
    }
  });

  tableBody.addEventListener('change', function (e) {
    if (e.target.classList.contains('item-qtd') || e.target.classList.contains('item-unit')) {
      recalculateAll();
    }
  });

  tableBody.addEventListener('click', function (e) {
    const btn = e.target.closest('.btn-remove-item');
    if (!btn) return;

    const rows = tableBody.querySelectorAll('.item-row');
    if (rows.length <= MIN_ITENS) {
      alert('O pedido deve possuir pelo menos 1 item.');
      return;
    }

    const row = btn.closest('.item-row');
    if (row) {
      row.remove();
      reindexRows();
      recalculateAll();
    }
  });

  // Validação no envio do formulário
  if (pedidoForm) {
    pedidoForm.addEventListener('submit', function (e) {
      reindexRows();
      recalculateAll();

      const rows = tableBody.querySelectorAll('.item-row');
      if (rows.length < MIN_ITENS) {
        e.preventDefault();
        alert('O pedido deve conter pelo menos 1 item.');
        return false;
      }

      if (rows.length > MAX_ITENS) {
        e.preventDefault();
        alert('O pedido pode conter no máximo 10 itens.');
        return false;
      }

      // Validar cada linha
      for (let i = 0; i < rows.length; i++) {
        const r = rows[i];
        const desc = r.querySelector('.item-descricao').value.trim();
        const qtd = parseFloat(r.querySelector('.item-qtd').value) || 0;
        const unit = parseFloat(r.querySelector('.item-unit').value) || 0;

        if (!desc) {
          e.preventDefault();
          alert(`Por favor, preencha a descrição do item #${i + 1}.`);
          r.querySelector('.item-descricao').focus();
          return false;
        }

        if (qtd <= 0) {
          e.preventDefault();
          alert(`A quantidade do item #${i + 1} deve ser maior que zero.`);
          r.querySelector('.item-qtd').focus();
          return false;
        }

        if (unit <= 0) {
          e.preventDefault();
          alert(`O valor unitário do item #${i + 1} deve ser maior que zero.`);
          r.querySelector('.item-unit').focus();
          return false;
        }
      }
    });
  }

  // Inicialização no carregamento da página
  reindexRows();
  recalculateAll();
});
</script>
{% endblock %}

OMNI_EOF

# --- app/templates/pedidos/index.html ---
cat > 'app/templates/pedidos/index.html' <<'OMNI_EOF'
{% extends "base.html" %}

{% block title %}Pedidos - OmniGestão{% endblock %}

{% block content %}
<div class="d-flex flex-column flex-md-row align-items-md-center justify-content-between pb-3 mb-4 border-bottom gap-3">
  <div>
    <h2 class="fw-bold mb-1 text-dark">Cadastro de Pedidos</h2>
    <p class="text-muted mb-0 small">Controle de vendas, faturamento e status dos pedidos</p>
  </div>
  <div>
    <a href="{{ url_for('pedidos.novo') }}" class="btn btn-primary-custom shadow-sm">
      <i class="bi bi-cart-plus-fill"></i> Novo Pedido
    </a>
  </div>
</div>

<!-- SEARCH & FILTER BAR -->
<div class="card-custom p-3 mb-4 bg-white">
  <form method="GET" action="{{ url_for('pedidos.index') }}" class="row g-2 align-items-center">
    <div class="col-md-4 col-lg-5">
      <div class="input-group">
        <span class="input-group-text bg-light text-muted border-end-0">
          <i class="bi bi-search"></i>
        </span>
        <input type="text" name="q" class="form-control border-start-0" placeholder="Buscar por nº pedido, itens ou cliente..." value="{{ search }}">
        {% if search %}
          <a href="{{ url_for('pedidos.index', status=status_filter, cliente_id=cliente_filter) }}" class="btn btn-outline-secondary" title="Limpar busca">
            <i class="bi bi-x-lg"></i>
          </a>
        {% endif %}
      </div>
    </div>

    <div class="col-md-3 col-lg-3">
      <select name="status" class="form-select" onchange="this.form.submit()">
        <option value="todos" {% if status_filter == 'todos' %}selected{% endif %}>Status: Todos</option>
        <option value="pendente" {% if status_filter == 'pendente' %}selected{% endif %}>Pendentes</option>
        <option value="processando" {% if status_filter == 'processando' %}selected{% endif %}>Em Processamento</option>
        <option value="concluido" {% if status_filter == 'concluido' %}selected{% endif %}>Concluídos</option>
        <option value="cancelado" {% if status_filter == 'cancelado' %}selected{% endif %}>Cancelados</option>
      </select>
    </div>

    <div class="col-md-3 col-lg-3">
      <select name="cliente_id" class="form-select" onchange="this.form.submit()">
        <option value="">Cliente: Todos</option>
        {% for c in clientes %}
          <option value="{{ c.id }}" {% if cliente_filter == c.id %}selected{% endif %}>{{ c.nome }}</option>
        {% endfor %}
      </select>
    </div>

    <div class="col-md-2 col-lg-1">
      <button type="submit" class="btn btn-light-custom w-100" title="Aplicar filtros">
        <i class="bi bi-funnel"></i>
      </button>
    </div>
  </form>
</div>

<!-- ORDERS STAT SUMMARY BANNER -->
<div class="d-flex align-items-center justify-content-between p-3 mb-3 bg-light rounded-3 border">
  <div class="d-flex align-items-center gap-2">
    <i class="bi bi-receipt-cutoff text-primary fs-5"></i>
    <span class="text-secondary small">
      Total de pedidos filtrados: <strong>{{ total_encontrados }}</strong>
    </span>
  </div>
  <div>
    <span class="text-muted small me-2">Volume Total:</span>
    <span class="fs-6 fw-bold text-success">{{ total_valor | currency }}</span>
  </div>
</div>

<!-- ORDERS TABLE -->
<div class="card-custom">
  <div class="table-responsive">
    <table class="table-custom mb-0">
      <thead>
        <tr>
          <th>Nº Pedido</th>
          <th>Cliente</th>
          <th>Data e Hora</th>
          <th>Método de Pagto</th>
          <th>Valor Total</th>
          <th>Status</th>
          <th class="text-end">Ações</th>
        </tr>
      </thead>
      <tbody>
        {% for pedido in pedidos %}
          <tr>
            <td>
              <a href="{{ url_for('pedidos.detalhe', id=pedido.id) }}" class="fw-bold text-dark text-decoration-none">
                #{{ pedido.numero_pedido }}
              </a>
              <div>
                <span class="badge bg-light text-secondary border" style="font-size: 0.7rem;">
                  <i class="bi bi-box-seam me-1"></i>{{ pedido.itens|length }} {{ 'item' if pedido.itens|length == 1 else 'itens' }}
                </span>
              </div>
            </td>
            <td>
              <div class="d-flex flex-column">
                <a href="{{ url_for('clientes.detalhe', id=pedido.cliente.id) }}" class="text-dark fw-semibold text-decoration-none text-truncate" style="max-width: 220px;">
                  {{ pedido.cliente.nome }}
                </a>
                <small class="text-muted text-truncate" style="max-width: 220px; font-size: 0.75rem;" title="{{ pedido.resumo_itens }}">
                  {{ pedido.resumo_itens }}
                </small>
              </div>
            </td>
            <td class="text-muted small">{{ pedido.data_pedido | datetime_br }}</td>
            <td>
              <span class="badge bg-light text-secondary border">
                {{ pedido.metodo_pagamento_label }}
              </span>
            </td>
            <td class="fw-bold">{{ pedido.valor_total | currency }}</td>
            <td>
              <span class="badge-status badge-{{ pedido.status }}">
                {{ pedido.status_label }}
              </span>
            </td>
            <td class="text-end">
              <div class="btn-group btn-group-sm">
                <a href="{{ url_for('pedidos.detalhe', id=pedido.id) }}" class="btn btn-outline-secondary" title="Ver Detalhes" data-bs-toggle="tooltip">
                  <i class="bi bi-eye"></i>
                </a>
                <a href="{{ url_for('pedidos.editar', id=pedido.id) }}" class="btn btn-outline-primary" title="Editar Pedido" data-bs-toggle="tooltip">
                  <i class="bi bi-pencil"></i>
                </a>
                <button type="button" class="btn btn-outline-danger"
                        data-bs-toggle="modal"
                        data-bs-target="#deleteConfirmModal"
                        data-action="{{ url_for('pedidos.excluir', id=pedido.id) }}"
                        data-name="Pedido #{{ pedido.numero_pedido }}"
                        data-type="o pedido">
                  <i class="bi bi-trash"></i>
                </button>
              </div>
            </td>
          </tr>
        {% else %}
          <tr>
            <td colspan="7" class="text-center py-5 text-muted">
              <i class="bi bi-search fs-1 d-block mb-2 text-secondary"></i>
              Nenhum pedido encontrado com os filtros informados.
              <div class="mt-3">
                {% if search or status_filter != 'todos' or cliente_filter %}
                  <a href="{{ url_for('pedidos.index') }}" class="btn btn-sm btn-outline-secondary">Limpar Filtros</a>
                {% else %}
                  <a href="{{ url_for('pedidos.novo') }}" class="btn btn-sm btn-primary">Cadastrar Primeiro Pedido</a>
                {% endif %}
              </div>
            </td>
          </tr>
        {% endfor %}
      </tbody>
    </table>
  </div>
</div>
{% endblock %}
OMNI_EOF

# --- app/utils/__init__.py ---
cat > 'app/utils/__init__.py' <<'OMNI_EOF'
from app.utils.filters import init_filters

__all__ = ['init_filters']
OMNI_EOF

# --- app/utils/filters.py ---
cat > 'app/utils/filters.py' <<'OMNI_EOF'
def format_currency(value):
    """Formats float/decimal into Brazilian Real (R$ X.XXX,XX)."""
    if value is None:
        return "R$ 0,00"
    try:
        val = float(value)
        return f"R$ {val:,.2f}".replace(',', 'X').replace('.', ',').replace('X', '.')
    except (ValueError, TypeError):
        return str(value)


def format_date(value, fmt='%d/%m/%Y %H:%M'):
    """Formats datetime object to standard Brazilian date format."""
    if not value:
        return "-"
    try:
        return value.strftime(fmt)
    except Exception:
        return str(value)


def format_date_short(value):
    """Formats datetime object to short DD/MM/YYYY."""
    return format_date(value, fmt='%d/%m/%Y')


def format_document(doc):
    """Formats CPF (11 digits) or CNPJ (14 digits) if digits only."""
    if not doc:
        return "-"
    digits = ''.join(filter(str.isdigit, str(doc)))
    if len(digits) == 11:
        return f"{digits[:3]}.{digits[3:6]}.{digits[6:9]}-{digits[9:]}"
    elif len(digits) == 14:
        return f"{digits[:2]}.{digits[2:5]}.{digits[5:8]}/{digits[8:12]}-{digits[12:]}"
    return doc


def format_phone(phone):
    """Formats Brazilian phone numbers."""
    if not phone:
        return "-"
    digits = ''.join(filter(str.isdigit, str(phone)))
    if len(digits) == 11:
        return f"({digits[:2]}) {digits[2:7]}-{digits[7:]}"
    elif len(digits) == 10:
        return f"({digits[:2]}) {digits[2:6]}-{digits[6:]}"
    return phone


def init_filters(app):
    app.jinja_env.filters['currency'] = format_currency
    app.jinja_env.filters['datetime_br'] = format_date
    app.jinja_env.filters['date_br'] = format_date_short
    app.jinja_env.filters['doc_br'] = format_document
    app.jinja_env.filters['phone_br'] = format_phone
OMNI_EOF

# --- migrations/README ---
cat > 'migrations/README' <<'OMNI_EOF'
Single-database configuration for Flask.
OMNI_EOF

# --- migrations/alembic.ini ---
cat > 'migrations/alembic.ini' <<'OMNI_EOF'
# A generic, single database configuration.

[alembic]
# template used to generate migration files
# file_template = %%(rev)s_%%(slug)s

# set to 'true' to run the environment during
# the 'revision' command, regardless of autogenerate
# revision_environment = false


# Logging configuration
[loggers]
keys = root,sqlalchemy,alembic,flask_migrate

[handlers]
keys = console

[formatters]
keys = generic

[logger_root]
level = WARN
handlers = console
qualname =

[logger_sqlalchemy]
level = WARN
handlers =
qualname = sqlalchemy.engine

[logger_alembic]
level = INFO
handlers =
qualname = alembic

[logger_flask_migrate]
level = INFO
handlers =
qualname = flask_migrate

[handler_console]
class = StreamHandler
args = (sys.stderr,)
level = NOTSET
formatter = generic

[formatter_generic]
format = %(levelname)-5.5s [%(name)s] %(message)s
datefmt = %H:%M:%S
OMNI_EOF

# --- migrations/env.py ---
cat > 'migrations/env.py' <<'OMNI_EOF'
import logging
from logging.config import fileConfig

from flask import current_app

from alembic import context

# this is the Alembic Config object, which provides
# access to the values within the .ini file in use.
config = context.config

# Interpret the config file for Python logging.
# This line sets up loggers basically.
fileConfig(config.config_file_name)
logger = logging.getLogger('alembic.env')


def get_engine():
    try:
        # this works with Flask-SQLAlchemy<3 and Alchemical
        return current_app.extensions['migrate'].db.get_engine()
    except (TypeError, AttributeError):
        # this works with Flask-SQLAlchemy>=3
        return current_app.extensions['migrate'].db.engine


def get_engine_url():
    try:
        return get_engine().url.render_as_string(hide_password=False).replace(
            '%', '%%')
    except AttributeError:
        return str(get_engine().url).replace('%', '%%')


# add your model's MetaData object here
# for 'autogenerate' support
# from myapp import mymodel
# target_metadata = mymodel.Base.metadata
config.set_main_option('sqlalchemy.url', get_engine_url())
target_db = current_app.extensions['migrate'].db

# other values from the config, defined by the needs of env.py,
# can be acquired:
# my_important_option = config.get_main_option("my_important_option")
# ... etc.


def get_metadata():
    if hasattr(target_db, 'metadatas'):
        return target_db.metadatas[None]
    return target_db.metadata


def run_migrations_offline():
    """Run migrations in 'offline' mode.

    This configures the context with just a URL
    and not an Engine, though an Engine is acceptable
    here as well.  By skipping the Engine creation
    we don't even need a DBAPI to be available.

    Calls to context.execute() here emit the given string to the
    script output.

    """
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url, target_metadata=get_metadata(), literal_binds=True
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online():
    """Run migrations in 'online' mode.

    In this scenario we need to create an Engine
    and associate a connection with the context.

    """

    # this callback is used to prevent an auto-migration from being generated
    # when there are no changes to the schema
    # reference: http://alembic.zzzcomputing.com/en/latest/cookbook.html
    def process_revision_directives(context, revision, directives):
        if getattr(config.cmd_opts, 'autogenerate', False):
            script = directives[0]
            if script.upgrade_ops.is_empty():
                directives[:] = []
                logger.info('No changes in schema detected.')

    conf_args = current_app.extensions['migrate'].configure_args
    if conf_args.get("process_revision_directives") is None:
        conf_args["process_revision_directives"] = process_revision_directives

    connectable = get_engine()

    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=get_metadata(),
            **conf_args
        )

        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
OMNI_EOF

# --- migrations/script.py.mako ---
cat > 'migrations/script.py.mako' <<'OMNI_EOF'
"""${message}

Revision ID: ${up_revision}
Revises: ${down_revision | comma,n}
Create Date: ${create_date}

"""
from alembic import op
import sqlalchemy as sa
${imports if imports else ""}

# revision identifiers, used by Alembic.
revision = ${repr(up_revision)}
down_revision = ${repr(down_revision)}
branch_labels = ${repr(branch_labels)}
depends_on = ${repr(depends_on)}


def upgrade():
    ${upgrades if upgrades else "pass"}


def downgrade():
    ${downgrades if downgrades else "pass"}
OMNI_EOF

# --- migrations/versions/99d1cc5b3cb2_add_itens_pedido.py ---
cat > 'migrations/versions/99d1cc5b3cb2_add_itens_pedido.py' <<'OMNI_EOF'
"""add_itens_pedido

Revision ID: 99d1cc5b3cb2
Revises: ed09ad0566ba
Create Date: 2026-10-07 19:22:53.126999

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '99d1cc5b3cb2'
down_revision = 'ed09ad0566ba'
branch_labels = None
depends_on = None


def upgrade():
    # ### commands auto generated by Alembic - please adjust! ###
    op.create_table('itens_pedido',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('pedido_id', sa.Integer(), nullable=False),
    sa.Column('descricao', sa.String(length=255), nullable=False),
    sa.Column('quantidade', sa.Float(), nullable=False),
    sa.Column('valor_unitario', sa.Float(), nullable=False),
    sa.Column('valor_total', sa.Float(), nullable=False),
    sa.Column('created_at', sa.DateTime(), nullable=False),
    sa.ForeignKeyConstraint(['pedido_id'], ['pedidos.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id')
    )
    with op.batch_alter_table('itens_pedido', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_itens_pedido_pedido_id'), ['pedido_id'], unique=False)

    with op.batch_alter_table('pedidos', schema=None) as batch_op:
        batch_op.alter_column('descricao',
               existing_type=sa.TEXT(),
               nullable=True)

    # ### end Alembic commands ###


def downgrade():
    # ### commands auto generated by Alembic - please adjust! ###
    with op.batch_alter_table('pedidos', schema=None) as batch_op:
        batch_op.alter_column('descricao',
               existing_type=sa.TEXT(),
               nullable=False)

    with op.batch_alter_table('itens_pedido', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_itens_pedido_pedido_id'))

    op.drop_table('itens_pedido')
    # ### end Alembic commands ###
OMNI_EOF

# --- migrations/versions/ed09ad0566ba_initial_migration_with_users_clients_.py ---
cat > 'migrations/versions/ed09ad0566ba_initial_migration_with_users_clients_.py' <<'OMNI_EOF'
"""Initial migration with users, clients and orders

Revision ID: ed09ad0566ba
Revises: 
Create Date: 2026-10-07 15:36:07.267208

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'ed09ad0566ba'
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    # ### commands auto generated by Alembic - please adjust! ###
    op.create_table('clientes',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('nome', sa.String(length=120), nullable=False),
    sa.Column('email', sa.String(length=120), nullable=False),
    sa.Column('telefone', sa.String(length=30), nullable=True),
    sa.Column('documento', sa.String(length=30), nullable=True),
    sa.Column('cep', sa.String(length=15), nullable=True),
    sa.Column('logradouro', sa.String(length=150), nullable=True),
    sa.Column('numero', sa.String(length=20), nullable=True),
    sa.Column('complemento', sa.String(length=50), nullable=True),
    sa.Column('bairro', sa.String(length=80), nullable=True),
    sa.Column('cidade', sa.String(length=80), nullable=True),
    sa.Column('estado', sa.String(length=2), nullable=True),
    sa.Column('ativo', sa.Boolean(), nullable=False),
    sa.Column('observacoes', sa.Text(), nullable=True),
    sa.Column('created_at', sa.DateTime(), nullable=False),
    sa.Column('updated_at', sa.DateTime(), nullable=False),
    sa.PrimaryKeyConstraint('id')
    )
    with op.batch_alter_table('clientes', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_clientes_documento'), ['documento'], unique=False)
        batch_op.create_index(batch_op.f('ix_clientes_email'), ['email'], unique=False)
        batch_op.create_index(batch_op.f('ix_clientes_nome'), ['nome'], unique=False)

    op.create_table('usuarios',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('nome', sa.String(length=100), nullable=False),
    sa.Column('username', sa.String(length=50), nullable=False),
    sa.Column('email', sa.String(length=120), nullable=False),
    sa.Column('password_hash', sa.String(length=255), nullable=False),
    sa.Column('ativo', sa.Boolean(), nullable=False),
    sa.Column('created_at', sa.DateTime(), nullable=False),
    sa.PrimaryKeyConstraint('id')
    )
    with op.batch_alter_table('usuarios', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_usuarios_email'), ['email'], unique=True)
        batch_op.create_index(batch_op.f('ix_usuarios_username'), ['username'], unique=True)

    op.create_table('pedidos',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('numero_pedido', sa.String(length=30), nullable=False),
    sa.Column('cliente_id', sa.Integer(), nullable=False),
    sa.Column('data_pedido', sa.DateTime(), nullable=False),
    sa.Column('status', sa.String(length=25), nullable=False),
    sa.Column('metodo_pagamento', sa.String(length=30), nullable=False),
    sa.Column('valor_total', sa.Float(), nullable=False),
    sa.Column('descricao', sa.Text(), nullable=False),
    sa.Column('observacoes', sa.Text(), nullable=True),
    sa.Column('created_at', sa.DateTime(), nullable=False),
    sa.Column('updated_at', sa.DateTime(), nullable=False),
    sa.ForeignKeyConstraint(['cliente_id'], ['clientes.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id')
    )
    with op.batch_alter_table('pedidos', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_pedidos_cliente_id'), ['cliente_id'], unique=False)
        batch_op.create_index(batch_op.f('ix_pedidos_data_pedido'), ['data_pedido'], unique=False)
        batch_op.create_index(batch_op.f('ix_pedidos_numero_pedido'), ['numero_pedido'], unique=True)
        batch_op.create_index(batch_op.f('ix_pedidos_status'), ['status'], unique=False)

    # ### end Alembic commands ###


def downgrade():
    # ### commands auto generated by Alembic - please adjust! ###
    with op.batch_alter_table('pedidos', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_pedidos_status'))
        batch_op.drop_index(batch_op.f('ix_pedidos_numero_pedido'))
        batch_op.drop_index(batch_op.f('ix_pedidos_data_pedido'))
        batch_op.drop_index(batch_op.f('ix_pedidos_cliente_id'))

    op.drop_table('pedidos')
    with op.batch_alter_table('usuarios', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_usuarios_username'))
        batch_op.drop_index(batch_op.f('ix_usuarios_email'))

    op.drop_table('usuarios')
    with op.batch_alter_table('clientes', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_clientes_nome'))
        batch_op.drop_index(batch_op.f('ix_clientes_email'))
        batch_op.drop_index(batch_op.f('ix_clientes_documento'))

    op.drop_table('clientes')
    # ### end Alembic commands ###
OMNI_EOF

# --- requirements.txt ---
cat > 'requirements.txt' <<'OMNI_EOF'
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
python-dotenv==1.2.4
SQLAlchemy==2.1.4
typing_extensions==4.16.0
Werkzeug==3.1.9
WTForms==3.2.2
OMNI_EOF

# --- tests/test_app.py ---
cat > 'tests/test_app.py' <<'OMNI_EOF'
import os
import unittest
from unittest import mock
from app import create_app
from app.config import Config, DEV_SECRET_KEY
from app.extensions import db
from app.models.user import User
from app.models.cliente import Cliente
from app.models.pedido import Pedido
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

        # Create a test user
        user = User(nome='Tester Admin', username='tester', email='tester@test.com')
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

    # --- CLIENTES CRUD TESTS ---
    def test_cliente_crud(self):
        self.login()

        # 1. Create client
        res = self.client.post('/clientes/novo', data={
            'nome': 'Empresa Alpha Tech Ltda',
            'email': 'alpha@tech.com',
            'telefone': '(11) 98888-7777',
            'documento': '11.222.333/0001-44',
            'cep': '01001-000',
            'logradouro': 'Praça da Sé',
            'numero': '10',
            'bairro': 'Sé',
            'cidade': 'São Paulo',
            'estado': 'SP',
            'ativo': 'y',
            'observacoes': 'Cliente prioritário'
        }, follow_redirects=True)
        self.assertEqual(res.status_code, 200)
        self.assertIn(b'Empresa Alpha Tech Ltda', res.data)

        cliente = Cliente.query.filter_by(email='alpha@tech.com').first()
        self.assertIsNotNone(cliente)
        self.assertEqual(cliente.cidade, 'São Paulo')

        # 2. View details
        res_detail = self.client.get(f'/clientes/{cliente.id}')
        self.assertEqual(res_detail.status_code, 200)
        self.assertIn(b'Empresa Alpha Tech Ltda', res_detail.data)

        # 3. Edit client
        res_edit = self.client.post(f'/clientes/{cliente.id}/editar', data={
            'nome': 'Empresa Alpha Tech Modificada',
            'email': 'alpha_editada@tech.com',
            'telefone': '(11) 99999-0000',
            'ativo': 'y'
        }, follow_redirects=True)
        self.assertEqual(res_edit.status_code, 200)
        self.assertIn(b'Empresa Alpha Tech Modificada', res_edit.data)

        # 4. Delete client
        res_del = self.client.post(f'/clientes/{cliente.id}/excluir', follow_redirects=True)
        self.assertEqual(res_del.status_code, 200)
        self.assertIsNone(db.session.get(Cliente, cliente.id))

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

    # --- CLI ---
    def test_seed_nao_usa_senha_fixa(self):
        runner = self.app.test_cli_runner()
        with mock.patch.dict(os.environ, {'SEED_ADMIN_PASSWORD': 'SenhaSeed#2026'}):
            result = runner.invoke(args=['seed'])
        self.assertEqual(result.exit_code, 0, result.output)
        self.assertNotIn('SenhaSeed#2026', result.output)
        admin = User.query.filter_by(username='admin').first()
        self.assertTrue(admin.check_password('SenhaSeed#2026'))
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
OMNI_EOF

# --- wsgi.py ---
cat > 'wsgi.py' <<'OMNI_EOF'
import os
from dotenv import load_dotenv

# Carrega o .env antes de criar o app: assim FLASK_DEBUG e SECRET_KEY valem
# também quando o servidor é iniciado com "python wsgi.py" (fora do "flask" CLI).
load_dotenv()

from app import create_app
from app.extensions import db
from app.models import User, Cliente, Pedido, ItemPedido

app = create_app()


@app.shell_context_processor
def make_shell_context():
    return {
        'db': db,
        'User': User,
        'Cliente': Cliente,
        'Pedido': Pedido,
        'ItemPedido': ItemPedido
    }



if __name__ == '__main__':
    # Running directly with python wsgi.py (servidor de desenvolvimento).
    # O modo debug segue a variável FLASK_DEBUG; em produção use gunicorn/waitress.
    port = int(os.environ.get('PORT', 5000))
    host = os.environ.get('HOST', '127.0.0.1')
    app.run(host=host, port=port, debug=app.debug)
OMNI_EOF

# --- .env (gerado com SECRET_KEY aleatória; preserva um .env existente) ---
if [ ! -f .env ]; then
    SECRET_KEY_GERADA="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
    cat > .env <<EOF_ENV
FLASK_APP=wsgi.py
FLASK_DEBUG=1
SECRET_KEY=${SECRET_KEY_GERADA}
DATABASE_URL=sqlite:///app_clientes.db
EOF_ENV
    echo -e "${GREEN}✓ Arquivo .env criado com SECRET_KEY aleatória.${NC}"
else
    echo -e "${YELLOW}• .env já existe — mantido sem alterações.${NC}"
fi

# --- Scripts utilitários (run.sh, test.sh, seed.sh) ---
cat > run.sh <<'OMNI_EOF'
#!/usr/bin/env bash
# Inicia a aplicação Flask em ambiente Linux (servidor de desenvolvimento)
set -e
source .venv/bin/activate
export FLASK_APP=wsgi.py
export HOST="${HOST:-127.0.0.1}"
export PORT="${PORT:-5000}"
echo "Iniciando servidor OmniGestão em http://${HOST}:${PORT} ..."
python3 wsgi.py
OMNI_EOF

cat > test.sh <<'OMNI_EOF'
#!/usr/bin/env bash
# Executa a suíte de testes automatizados no Linux
set -e
source .venv/bin/activate
echo "Executando suíte de testes automatizados..."
python3 -m unittest discover -s tests -v
OMNI_EOF

cat > seed.sh <<'OMNI_EOF'
#!/usr/bin/env bash
# Popula o banco de dados com usuário admin e dados de demonstração
set -e
source .venv/bin/activate
export FLASK_APP=wsgi.py
echo "Populando banco de dados com dados de teste..."
flask seed
OMNI_EOF

chmod +x run.sh test.sh seed.sh

echo -e "${GREEN}✓ Todos os arquivos fonte e utilitários foram criados.${NC}"

# 4. Criação do Ambiente Virtual (.venv)
echo -e "\n${YELLOW}[4/6] Criando o ambiente virtual Python (.venv)...${NC}"
python3 -m venv .venv
echo -e "${GREEN}✓ Ambiente virtual criado.${NC}"

# 5. Instalação das Dependências
echo -e "\n${YELLOW}[5/6] Instalando dependências (pip install)...${NC}"
.venv/bin/pip install --upgrade pip
.venv/bin/pip install -r requirements.txt
echo -e "${GREEN}✓ Todas as dependências foram instaladas com sucesso.${NC}"

# 6. Banco de dados (migrações versionadas), seed e testes
echo -e "\n${YELLOW}[6/6] Aplicando migrações e populando o banco de dados...${NC}"
export FLASK_APP=wsgi.py
.venv/bin/flask db upgrade
.venv/bin/flask seed

echo -e "\n${YELLOW}Executando testes automatizados para validação do sistema...${NC}"
.venv/bin/python3 -m unittest discover -s tests

echo -e "\n${BLUE}===================================================================${NC}"
echo -e "${GREEN}🎉 PROJETO CRIADO E CONFIGURADO COM SUCESSO!${NC}"
echo -e "${BLUE}===================================================================${NC}"
echo -e "Para iniciar o servidor agora mesmo, execute:"
echo -e "  ${YELLOW}./run.sh${NC}"
echo -e "\nOu manualmente:"
echo -e "  ${YELLOW}source .venv/bin/activate${NC}"
echo -e "  ${YELLOW}python3 wsgi.py${NC}"
echo -e "\nAcesse no navegador: ${BLUE}http://localhost:5000${NC}"
echo -e "Usuário: ${YELLOW}admin${NC} — senha exibida acima pelo seed (ou a definida em SEED_ADMIN_PASSWORD)."
echo -e "Para criar outro administrador: ${YELLOW}.venv/bin/flask create-admin${NC}"
echo -e "\n${RED}Produção:${NC} use FLASK_DEBUG=0 e um servidor WSGI (gunicorn/waitress)."
echo -e "${BLUE}===================================================================${NC}"
