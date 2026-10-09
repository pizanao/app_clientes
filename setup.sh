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
    'app/services' \
    'app/static/css' \
    'app/static/js' \
    'app/templates' \
    'app/templates/auth' \
    'app/templates/clientes' \
    'app/templates/dashboard' \
    'app/templates/errors' \
    'app/templates/leads' \
    'app/templates/pedidos' \
    'app/utils' \
    'instance' \
    'migrations' \
    'migrations/versions' \
    'tests'
echo -e "${GREEN}✓ Estrutura de pastas criada com sucesso.${NC}"

# 3. Criação dos arquivos do projeto
echo -e "\n${YELLOW}[3/6] Criando 52 arquivos de código-fonte...${NC}"

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

# Chave de API do Google Gemini (opcional - ativa IA em tempo real para prospecção de telecom)
# GEMINI_API_KEY=
OMNI_EOF

# --- .gitattributes ---
cat > '.gitattributes' <<'OMNI_EOF'
# Scripts shell precisam de LF: com CRLF o bash falha ("$'\r': command not found"),
# o que acontece ao clonar no Windows com core.autocrlf=true e copiar para o Linux.
*.sh text eol=lf
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
    from app.routes.leads import leads_bp

    app.register_blueprint(auth_bp)
    app.register_blueprint(main_bp)
    app.register_blueprint(clientes_bp)
    app.register_blueprint(pedidos_bp)
    app.register_blueprint(leads_bp)

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
from app.models.lead import Lead
from app.services.prospector import TelecomProspectorService


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
                # Clientes Estratégicos DigitalNet MS (Campo Grande)
                Cliente(
                    nome='Condomínio Residencial Parque das Nações',
                    email='sindico@parquedasnacoes.ms.gov.br',
                    telefone='(67) 3321-4455',
                    documento='04.123.456/0001-78',
                    cep='79040-010',
                    logradouro='Rua Raul Pires Barbosa',
                    numero='1250',
                    complemento='Administração',
                    bairro='Chácara Cachoeira',
                    cidade='Campo Grande',
                    estado='MS',
                    ativo=True,
                    observacoes='Condomínio atendido pela fibra DigitalNet com 60 apartamentos conectados.'
                ),
                Cliente(
                    nome='Clínica Médica Santa Fé Especializada',
                    email='contato@clinicasantafe.com.br',
                    telefone='(67) 3345-6789',
                    documento='18.987.654/0001-32',
                    cep='79021-120',
                    logradouro='Rua Ceará',
                    numero='840',
                    complemento='Sala 10',
                    bairro='Santa Fé',
                    cidade='Campo Grande',
                    estado='MS',
                    ativo=True,
                    observacoes='Link Fibra 700 + DigiMesh em comodato com suporte 24h.'
                ),
                Cliente(
                    nome='Escritório Silva & Associados Advocacia',
                    email='administrativo@silvaadvocacia.com.br',
                    telefone='(67) 3388-9900',
                    documento='22.333.444/0001-55',
                    cep='79002-001',
                    logradouro='Rua 14 de Julho',
                    numero='2100',
                    complemento='Andar 4',
                    bairro='Centro',
                    cidade='Campo Grande',
                    estado='MS',
                    ativo=True,
                    observacoes='Link Dedicado Pro com IP Fixo e redundância.'
                ),
                Cliente(
                    nome='Restaurante e Parrilla Pantaneira',
                    email='financeiro@parrillapantaneira.com.br',
                    telefone='(67) 3356-7890',
                    documento='33.444.555/0001-66',
                    cep='79020-000',
                    logradouro='Rua Euclides da Cunha',
                    numero='650',
                    complemento='',
                    bairro='Jardim dos Estados',
                    cidade='Campo Grande',
                    estado='MS',
                    ativo=True,
                    observacoes='Wi-Fi 6 de alta densidade para 80 clientes simultâneos.'
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

        # Sample leads for telecom prospecting in Campo Grande
        if Lead.query.count() == 0:
            leads_chacara = TelecomProspectorService.prospect_neighborhood(
                bairro='Chácara Cachoeira',
                cidade='Campo Grande',
                estado='MS',
                niche='Clínicas e Escritórios',
                count=4
            )
            leads_centro = TelecomProspectorService.prospect_neighborhood(
                bairro='Centro',
                cidade='Campo Grande',
                estado='MS',
                niche='Comércios e Contabilidade',
                count=3
            )
            TelecomProspectorService.save_prospects(leads_chacara + leads_centro)
            click.echo('Leads de prospecção geo-localizada em Campo Grande cadastrados com sucesso!')

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

    # Google Gemini AI (Telecom Prospector)
    GEMINI_API_KEY = os.environ.get('GEMINI_API_KEY')
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

# --- app/models/lead.py ---
cat > 'app/models/lead.py' <<'OMNI_EOF'
from datetime import datetime
import urllib.parse
from app.extensions import db


class Lead(db.Model):
    __tablename__ = 'leads'

    id = db.Column(db.Integer, primary_key=True)
    nome = db.Column(db.String(120), nullable=False, index=True)
    empresa = db.Column(db.String(150), nullable=False, index=True)
    cargo = db.Column(db.String(100), nullable=True)
    telefone = db.Column(db.String(30), nullable=True)
    email = db.Column(db.String(120), nullable=True)
    documento = db.Column(db.String(30), nullable=True)
    niche = db.Column(db.String(100), nullable=True, default='Geral')

    # Geo-localização do Lead
    cep = db.Column(db.String(15), nullable=True)
    logradouro = db.Column(db.String(150), nullable=True)
    numero = db.Column(db.String(20), nullable=True)
    complemento = db.Column(db.String(50), nullable=True)
    bairro = db.Column(db.String(80), nullable=False, index=True)
    cidade = db.Column(db.String(80), nullable=False, default='Campo Grande', index=True)
    estado = db.Column(db.String(2), nullable=False, default='MS')

    # Vinculo com o cliente ativo que viabilizou a rede na região
    cliente_referencia_id = db.Column(
        db.Integer,
        db.ForeignKey('clientes.id', ondelete='SET NULL'),
        nullable=True,
        index=True
    )

    # Status de Funil e Opt-in
    status = db.Column(db.String(30), default='novo', nullable=False, index=True)
    optin_status = db.Column(db.String(20), default='pendente', nullable=False, index=True)

    # Dados Comerciais e Concorrência
    operadora_atual = db.Column(db.String(80), default='Vivo Fibra / Claro', nullable=True)
    plano_sugerido = db.Column(db.String(120), default='Fibra 700 + DigiMesh', nullable=True)
    valor_mensal_sugerido = db.Column(db.Float, default=139.90, nullable=False)
    lead_score = db.Column(db.Integer, default=85, nullable=False)
    dor_principal = db.Column(db.Text, nullable=True)
    icebreaker_optin = db.Column(db.Text, nullable=True)
    dossie_comercial = db.Column(db.Text, nullable=True)
    observacoes = db.Column(db.Text, nullable=True)

    # Vinculo com o cliente criado apos a conversão
    cliente_convertido_id = db.Column(
        db.Integer,
        db.ForeignKey('clientes.id', ondelete='SET NULL'),
        nullable=True,
        index=True
    )

    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    # Relacionamentos
    cliente_referencia = db.relationship('Cliente', foreign_keys=[cliente_referencia_id], backref='leads_vizinhos_gerados')
    cliente_convertido = db.relationship('Cliente', foreign_keys=[cliente_convertido_id], backref='lead_origem')

    STATUS_CONFIG = {
        'novo': ('Novo Lead', 'bg-secondary text-white'),
        'optin_solicitado': ('Opt-in Solicitado', 'bg-warning text-dark'),
        'optin_aceito': ('Opt-in Aceito', 'bg-info text-white'),
        'proposta_enviada': ('Proposta Enviada', 'bg-primary text-white'),
        'convertido': ('Convertido / Fechado', 'bg-success text-white'),
        'perdido': ('Perdido', 'bg-danger text-white'),
    }

    OPTIN_CONFIG = {
        'pendente': ('Pendente', 'badge bg-secondary'),
        'aceito': ('Aceito (Anti-Ban Ativo)', 'badge bg-success'),
        'recusado': ('Recusado', 'badge bg-danger'),
    }

    @property
    def status_label(self) -> str:
        return self.STATUS_CONFIG.get(self.status, (self.status.capitalize(), 'bg-secondary text-white'))[0]

    @property
    def status_badge_class(self) -> str:
        return self.STATUS_CONFIG.get(self.status, ('', 'bg-secondary text-white'))[1]

    @property
    def optin_label(self) -> str:
        return self.OPTIN_CONFIG.get(self.optin_status, (self.optin_status.capitalize(), 'badge bg-secondary'))[0]

    @property
    def optin_badge_class(self) -> str:
        return self.OPTIN_CONFIG.get(self.optin_status, ('', 'badge bg-secondary'))[1]

    @property
    def telefone_numeros(self) -> str:
        """Retorna apenas dígitos do telefone para montagem do link wa.me."""
        if not self.telefone:
            return ''
        digits = ''.join(c for c in self.telefone if c.isdigit())
        if len(digits) in (10, 11) and not digits.startswith('55'):
            digits = '55' + digits
        return digits

    @property
    def whatsapp_url(self) -> str:
        """Gera URL com a mensagem de opt-in pronta para o WhatsApp Web."""
        phone = self.telefone_numeros
        msg = self.icebreaker_optin or ''
        if not phone or not msg:
            return '#'
        encoded = urllib.parse.quote(msg)
        return f"https://wa.me/{phone}?text={encoded}"

    @property
    def endereco_resumido(self) -> str:
        partes = []
        if self.logradouro:
            partes.append(f"{self.logradouro}, {self.numero or 'S/N'}")
        if self.bairro:
            partes.append(self.bairro)
        if self.cidade and self.estado:
            partes.append(f"{self.cidade}/{self.estado}")
        return ' - '.join(partes) if partes else f"{self.bairro}, {self.cidade}/{self.estado}"

    def __repr__(self):
        return f'<Lead #{self.id}: {self.empresa} ({self.bairro})>'
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

# --- app/routes/leads.py ---
cat > 'app/routes/leads.py' <<'OMNI_EOF'
from flask import Blueprint, render_template, request, redirect, url_for, flash, jsonify
from flask_login import login_required, current_user
from app.extensions import db
from app.models.lead import Lead
from app.models.cliente import Cliente
from app.services.prospector import TelecomProspectorService, PLANOS_DIGITALNET

leads_bp = Blueprint('leads', __name__, url_prefix='/leads')


# -----------------------------------------------------------------------------
# ROTAS WEB (INTERFACE HTML/BOOTSTRAP)
# -----------------------------------------------------------------------------

@leads_bp.route('/')
@login_required
def index():
    """Painel de Prospecção Geo-Localizada & Funil de Leads."""
    bairro_filtro = request.args.get('bairro', '').strip()
    status_filtro = request.args.get('status', '').strip()
    busca = request.args.get('busca', '').strip()

    # Clusters de bairros com clientes ativos (densidade de rede)
    clusters = TelecomProspectorService.get_neighborhood_clusters()

    # Query de Leads
    query = Lead.query
    if bairro_filtro:
        query = query.filter(Lead.bairro.ilike(f"%{bairro_filtro}%"))
    if status_filtro:
        query = query.filter(Lead.status == status_filtro)
    if busca:
        termo = f"%{busca}%"
        query = query.filter(
            (Lead.empresa.ilike(termo)) |
            (Lead.nome.ilike(termo)) |
            (Lead.telefone.ilike(termo)) |
            (Lead.logradouro.ilike(termo))
        )

    leads = query.order_by(Lead.lead_score.desc(), Lead.created_at.desc()).all()

    # Métricas do Funil
    total_leads = Lead.query.count()
    total_novos = Lead.query.filter_by(status='novo').count()
    total_optin_solicitado = Lead.query.filter_by(status='optin_solicitado').count()
    total_optin_aceito = Lead.query.filter_by(optin_status='aceito').count()
    total_proposta = Lead.query.filter_by(status='proposta_enviada').count()
    total_convertidos = Lead.query.filter_by(status='convertido').count()

    # Pontos para o Mapa de Calor & Nós de Fibra
    map_points = []
    for c in clusters:
        map_points.append({
            'tipo': 'cluster_fibra',
            'titulo': f"Nó Óptico: {c['bairro']}",
            'bairro': c['bairro'],
            'lat': c.get('lat', -20.4697),
            'lng': c.get('lng', -54.6201),
            'clientes': c['total_clientes'],
            'leads': c['total_leads'],
            'viabilidade': c['viabilidade_estimada'],
            'cor': '#1b4f99',
            'intensidade': round(min(1.0, 0.4 + (c['total_clientes'] * 0.15)), 2),
        })

    for l in leads:
        base_coords = TelecomProspectorService.COORDENADAS_BAIRROS.get(l.bairro, (-20.4697, -54.6201))
        jitter_lat = ((l.id * 17) % 19 - 9) * 0.00075
        jitter_lng = ((l.id * 31) % 19 - 9) * 0.00075
        map_points.append({
            'tipo': 'lead_oportunidade',
            'id': l.id,
            'titulo': l.empresa,
            'contato': l.nome,
            'cargo': l.cargo or '',
            'bairro': l.bairro,
            'endereco': l.endereco_resumido,
            'lat': round(base_coords[0] + jitter_lat, 6),
            'lng': round(base_coords[1] + jitter_lng, 6),
            'score': l.lead_score,
            'plano': l.plano_sugerido,
            'valor': f"R$ {l.valor_mensal_sugerido:.2f}".replace('.', ','),
            'operadora': l.operadora_atual,
            'status': l.status_label,
            'optin': l.optin_label,
            'whatsapp_url': l.whatsapp_url,
            'detail_url': url_for('leads.detail', lead_id=l.id),
            'cor': '#f59e0b',
            'intensidade': round(l.lead_score / 100.0, 2),
        })

    return render_template(
        'leads/index.html',
        leads=leads,
        clusters=clusters,
        planos=PLANOS_DIGITALNET,
        total_leads=total_leads,
        total_novos=total_novos,
        total_optin_solicitado=total_optin_solicitado,
        total_optin_aceito=total_optin_aceito,
        total_proposta=total_proposta,
        total_convertidos=total_convertidos,
        bairro_selecionado=bairro_filtro,
        status_selecionado=status_filtro,
        busca=busca,
        map_points=map_points,
    )


@leads_bp.route('/prospectar', methods=['POST'])
@login_required
def prospectar_regiao():
    """Dispara a geração de leads vizinhos baseada na região selecionada."""
    bairro = request.form.get('bairro', '').strip() or 'Chácara Cachoeira'
    cidade = request.form.get('cidade', '').strip() or 'Campo Grande'
    niche = request.form.get('niche', '').strip() or 'Empresas e Clínicas'
    count = int(request.form.get('count', 5))
    cliente_ref_id = request.form.get('cliente_referencia_id')

    cliente_ref_id_int = int(cliente_ref_id) if cliente_ref_id and cliente_ref_id.isdigit() else None

    # Executa a prospecção com IA / Heurística de Campo Grande
    novos_dados = TelecomProspectorService.prospect_neighborhood(
        bairro=bairro,
        cidade=cidade,
        estado='MS',
        niche=niche,
        count=count,
        cliente_ref_id=cliente_ref_id_int
    )

    salvos = TelecomProspectorService.save_prospects(novos_dados, cliente_ref_id=cliente_ref_id_int)

    if salvos:
        flash(f"Sucesso! {len(salvos)} novos leads foram gerados no bairro {bairro} com viabilidade óptica mapeada.", 'success')
    else:
        flash(f"Nenhum novo lead precisou ser gerado (empresas da região já cadastradas no bairro {bairro}).", 'info')

    return redirect(url_for('leads.index', bairro=bairro))


@leads_bp.route('/<int:lead_id>')
@login_required
def detail(lead_id: int):
    """Exibe o dossiê comercial, central de WhatsApp e quebra de objeções."""
    lead = Lead.query.get_or_404(lead_id)

    # Garante script anti-ban atualizado
    if not lead.icebreaker_optin:
        lead.icebreaker_optin = TelecomProspectorService.generate_anti_ban_whatsapp_script(lead)
        db.session.commit()

    # Prepara tutores de objeção
    obj_key = request.args.get('obj', 'fidelidade')
    tutor_obj = TelecomProspectorService.get_objection_tutor(obj_key, lead)

    return render_template(
        'leads/detail.html',
        lead=lead,
        tutor_obj=tutor_obj,
        obj_key=obj_key,
        planos=PLANOS_DIGITALNET
    )


@leads_bp.route('/<int:lead_id>/status', methods=['POST'])
@login_required
def atualizar_status(lead_id: int):
    """Atualiza o status de funil e/ou opt-in do lead."""
    lead = Lead.query.get_or_404(lead_id)

    novo_status = request.form.get('status')
    novo_optin = request.form.get('optin_status')

    if novo_status and novo_status in Lead.STATUS_CONFIG:
        lead.status = novo_status
    if novo_optin and novo_optin in Lead.OPTIN_CONFIG:
        lead.optin_status = novo_optin
        if novo_optin == 'aceito' and lead.status in ('novo', 'optin_solicitado'):
            lead.status = 'optin_aceito'

    db.session.commit()
    flash(f"Status do lead #{lead.id} ({lead.empresa}) atualizado com sucesso!", 'success')
    return redirect(url_for('leads.detail', lead_id=lead.id))


@leads_bp.route('/<int:lead_id>/converter', methods=['POST'])
@login_required
def converter_cliente(lead_id: int):
    """Converte o lead em cliente e cria o pedido da assinatura DigitalNet."""
    lead = Lead.query.get_or_404(lead_id)

    plano_escolhido = request.form.get('plano_sugerido')
    valor_escolhido = request.form.get('valor_mensal_sugerido')

    if plano_escolhido:
        lead.plano_sugerido = plano_escolhido
    if valor_escolhido:
        try:
            lead.valor_mensal_sugerido = float(valor_escolhido)
        except ValueError:
            pass

    cliente = TelecomProspectorService.convert_lead_to_client(lead)
    flash(f"Parabéns! Lead convertido em Cliente '{cliente.nome}' com Pedido de Ativação gerado!", 'success')
    return redirect(url_for('clientes.detalhe', id=cliente.id))


@leads_bp.route('/<int:lead_id>/excluir', methods=['POST'])
@login_required
def excluir(lead_id: int):
    """Exclui um lead do sistema."""
    lead = Lead.query.get_or_404(lead_id)
    empresa = lead.empresa
    db.session.delete(lead)
    db.session.commit()
    flash(f"Lead '{empresa}' removido com sucesso.", 'warning')
    return redirect(url_for('leads.index'))


# -----------------------------------------------------------------------------
# REST API (JSON PARA REACT 19 / VITE / INTEGRACAO)
# -----------------------------------------------------------------------------

@leads_bp.route('/api/clusters', methods=['GET'])
@login_required
def api_clusters():
    """Retorna clusters de bairros de clientes em JSON."""
    clusters = TelecomProspectorService.get_neighborhood_clusters()
    return jsonify({'success': True, 'clusters': clusters})


@leads_bp.route('/api/prospectar', methods=['POST'])
@login_required
def api_prospectar():
    """Endpoint REST para acionar a prospecção via frontend moderno."""
    data = request.get_json() or {}
    bairro = data.get('bairro', 'Chácara Cachoeira')
    cidade = data.get('cidade', 'Campo Grande')
    niche = data.get('niche', 'Empresas e Clínicas')
    count = int(data.get('count', 5))

    novos_dados = TelecomProspectorService.prospect_neighborhood(
        bairro=bairro,
        cidade=cidade,
        estado='MS',
        niche=niche,
        count=count
    )
    salvos = TelecomProspectorService.save_prospects(novos_dados)

    return jsonify({
        'success': True,
        'count': len(salvos),
        'leads': [
            {
                'id': l.id,
                'empresa': l.empresa,
                'nome': l.nome,
                'telefone': l.telefone,
                'bairro': l.bairro,
                'plano_sugerido': l.plano_sugerido,
                'valor': l.valor_mensal_sugerido,
                'lead_score': l.lead_score,
                'whatsapp_url': l.whatsapp_url,
                'optin_status': l.optin_status
            }
            for l in salvos
        ]
    })
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

# --- app/services/prospector.py ---
cat > 'app/services/prospector.py' <<'OMNI_EOF'
from datetime import datetime
import json
import logging
import os
import random
import re
import urllib.parse
import urllib.request
from typing import Dict, List, Any, Optional
from flask import current_app
from app.extensions import db
from app.models.cliente import Cliente
from app.models.lead import Lead
from app.models.pedido import Pedido, ItemPedido

logger = logging.getLogger(__name__)

# Planos reais da DigitalNet MS
PLANOS_DIGITALNET = [
    {
        'nome': 'Fibra 600 Standard (Wi-Fi 6)',
        'download': '600 Mbps',
        'upload': '300 Mbps',
        'preco': 129.90,
        'diferencial': 'Wi-Fi 6 em comodato + Skeelo + Instalação inclusa',
    },
    {
        'nome': 'Fibra 700 + DigiMesh (Wi-Fi 6)',
        'download': '700 Mbps',
        'upload': '350 Mbps',
        'preco': 139.90,
        'diferencial': 'Ponto extra DigiMesh sem fios + Wi-Fi 6 + Instalação inclusa',
    },
    {
        'nome': 'Fibra 900 Advanced (Wi-Fi 6)',
        'download': '900 Mbps',
        'upload': '450 Mbps',
        'preco': 149.90,
        'promocao_entrada': 'R$ 99,90 nos primeiros 3 meses',
        'diferencial': 'Máxima velocidade residencial/comercial + Wi-Fi 6 + Skeelo',
    },
    {
        'nome': 'DigitalNet B2B Link Dedicado Pro',
        'download': '1000 Mbps',
        'upload': '1000 Mbps (100% Simétrico)',
        'preco': 399.90,
        'diferencial': 'IP Fixo + SLA de 4h + Wi-Fi 6 Alta Densidade + Suporte 24h Campo Grande',
    },
]

# Ruas e perfis de empresas em Campo Grande - MS para Fallback
PERFIS_CAMPO_GRANDE = {
    'Chácara Cachoeira': {
        'ruas': ['Rua Raul Pires Barbosa', 'Rua Afonso Pena', 'Rua Jeribá', 'Rua Dr. Paulo Machado'],
        'cep_prefix': '79040',
        'nichos': ['Clínicas Médicas & Odontológicas', 'Escritórios de Advocacia', 'Coworkings & Startups', 'Consultórios'],
    },
    'Centro': {
        'ruas': ['Rua 14 de Julho', 'Avenida Calógeras', 'Rua Dom Aquino', 'Rua Barão do Rio Branco'],
        'cep_prefix': '79002',
        'nichos': ['Comércio & Varejo', 'Escritórios de Contabilidade', 'Imobiliárias', 'Restaurantes & Lanchonetes'],
    },
    'Santa Fé': {
        'ruas': ['Rua Ceará', 'Rua Abrão Júlio Rahe', 'Rua Alagoas', 'Rua Goiás'],
        'cep_prefix': '79021',
        'nichos': ['Clínicas de Estética', 'Escritórios Corporativos', 'Agências de Marketing', 'Boutiques'],
    },
    'Jardim dos Estados': {
        'ruas': ['Rua Euclides da Cunha', 'Rua Rio Grande do Sul', 'Rua Bahia', 'Avenida Mato Grosso'],
        'cep_prefix': '79020',
        'nichos': ['Escritórios Executivos', 'Restaurantes Gastronômicos', 'Centros Médicos', 'Empresas de TI'],
    },
    'Tiradentes': {
        'ruas': ['Avenida Marquês de Pombal', 'Rua José Nogueira Vieira', 'Avenida Três Barras'],
        'cep_prefix': '79041',
        'nichos': ['Supermercados & Farmácias', 'Auto Centers', 'Academias', 'Escolas & Cursos'],
    },
    'Vilas Boas': {
        'ruas': ['Avenida Bom Pastor', 'Rua Domingos Jorge Velho', 'Rua Cel. Salustiano'],
        'cep_prefix': '79051',
        'nichos': ['Gastronomia & Restaurantes', 'Lojas de Conveniência', 'Pet Shops & Veterinárias'],
    },
}

# Coordenadas geográficas reais dos bairros de Campo Grande - MS para o Mapa de Calor
COORDENADAS_BAIRROS = {
    'Chácara Cachoeira': (-20.4578, -54.5824),
    'Centro': (-20.4628, -54.6156),
    'Santa Fé': (-20.4485, -54.5952),
    'Jardim dos Estados': (-20.4552, -54.6063),
    'Tiradentes': (-20.4682, -54.5615),
    'Vilas Boas': (-20.4851, -54.5889),
    'Bela Vista': (-20.4720, -54.5900),
    'Copacabana': (-20.4900, -54.6300),
}


class TelecomProspectorService:
    COORDENADAS_BAIRROS = COORDENADAS_BAIRROS

    @staticmethod
    def get_neighborhood_clusters() -> List[Dict[str, Any]]:
        """
        Agrupa clientes existentes por bairro e cidade para identificar
        onde a DigitalNet já possui infraestrutura óptica instalada (CTO/Cabos).
        """
        clientes = Cliente.query.filter_by(ativo=True).all()
        clusters_map: Dict[str, Dict[str, Any]] = {}

        for c in clientes:
            bairro = (c.bairro or 'Centro').strip()
            cidade = (c.cidade or 'Campo Grande').strip()
            estado = (c.estado or 'MS').strip()
            chave = f"{cidade}|{bairro}"

            if chave not in clusters_map:
                clusters_map[chave] = {
                    'cidade': cidade,
                    'bairro': bairro,
                    'estado': estado,
                    'total_clientes': 0,
                    'clientes_ids': [],
                    'exemplo_ruas': set(),
                }

            clusters_map[chave]['total_clientes'] += 1
            clusters_map[chave]['clientes_ids'].append(c.id)
            if c.logradouro:
                clusters_map[chave]['exemplo_ruas'].add(c.logradouro)

        # Se não houver clientes ou poucos, garante os principais bairros de Campo Grande
        if not clusters_map:
            for b in ['Chácara Cachoeira', 'Centro', 'Santa Fé', 'Jardim dos Estados']:
                clusters_map[f"Campo Grande|{b}"] = {
                    'cidade': 'Campo Grande',
                    'bairro': b,
                    'estado': 'MS',
                    'total_clientes': 0,
                    'clientes_ids': [],
                    'exemplo_ruas': set(PERFIS_CAMPO_GRANDE.get(b, {}).get('ruas', [])[:2]),
                }

        resultado = []
        for chave, dado in clusters_map.items():
            bairro = dado['bairro']
            # Conta leads já cadastrados nessa região
            total_leads = Lead.query.filter_by(bairro=bairro).count()
            leads_convertidos = Lead.query.filter_by(bairro=bairro, status='convertido').count()

            coords = COORDENADAS_BAIRROS.get(bairro, (-20.4697, -54.6201))
            resultado.append({
                'cidade': dado['cidade'],
                'bairro': bairro,
                'estado': dado['estado'],
                'lat': coords[0],
                'lng': coords[1],
                'total_clientes': dado['total_clientes'],
                'total_leads': total_leads,
                'leads_convertidos': leads_convertidos,
                'ruas': list(dado['exemplo_ruas'])[:3],
                'viabilidade_estimada': '99% (Fibra Ativa no Poste)' if dado['total_clientes'] > 0 else 'Alta (Área de Cobertura)',
                'badge_class': 'bg-success' if dado['total_clientes'] >= 2 else 'bg-primary',
            })

        # Ordena por bairros com mais clientes
        resultado.sort(key=lambda x: (x['total_clientes'], x['total_leads']), reverse=True)
        return resultado

    @classmethod
    def generate_anti_ban_whatsapp_script(cls, lead: Lead) -> str:
        """
        Cria o roteiro de abordagem consultiva com pedido explícito de opt-in
        para evitar banimento por spam no WhatsApp.
        """
        nome_curto = (lead.nome or 'Olá').split()[0]
        empresa = lead.empresa or 'sua empresa'
        bairro = lead.bairro or 'sua região'
        operadora = lead.operadora_atual or 'outras operadoras'
        plano = lead.plano_sugerido or 'Fibra 700 + DigiMesh com Wi-Fi 6'

        script = (
            f"Olá {nome_curto}, tudo bem? Notei a presença da {empresa} aqui no bairro {bairro}.\n\n"
            f"A DigitalNet acabou de concluir a modernização da rede de fibra óptica com roteadores Wi-Fi 6 "
            f"aqui na sua rua. Identificamos que muitos comércios e escritórios locais sofrem com lentidão e "
            f"suporte demorado de operadoras nacionais como {operadora}.\n\n"
            f"Estruturamos um comparativo rápido mostrando como ter mais velocidade e suporte local 24h em Campo Grande "
            f"com o nosso plano {plano}.\n\n"
            f"👉 *Posso te enviar esse comparativo de 1 minuto aqui pelo WhatsApp sem compromisso?*\n"
            f"_(Se não for o momento, fique à vontade para responder 'Não')_"
        )
        return script

    @classmethod
    def prospect_neighborhood(
        cls,
        bairro: str,
        cidade: str = 'Campo Grande',
        estado: str = 'MS',
        niche: str = 'Empresas e Comércios',
        count: int = 5,
        cliente_ref_id: Optional[int] = None
    ) -> List[Dict[str, Any]]:
        """
        Gera leads vizinhos qualificados na mesma região dos clientes.
        Tenta chamar o Google Gemini se GEMINI_API_KEY estiver configurado;
        caso contrário, usa o motor heurístico local hiper-realista.
        """
        api_key = current_app.config.get('GEMINI_API_KEY')
        if api_key:
            try:
                leads_ai = cls._call_gemini_prospector(bairro, cidade, estado, niche, count, api_key)
                if leads_ai:
                    return leads_ai
            except Exception as e:
                logger.warning(f"Falha na chamada ao Gemini API ({e}). Usando motor local de telecom.")

        return cls._generate_fallback_prospects(bairro, cidade, estado, niche, count)

    @classmethod
    def _call_gemini_prospector(
        cls,
        bairro: str,
        cidade: str,
        estado: str,
        niche: str,
        count: int,
        api_key: str
    ) -> List[Dict[str, Any]]:
        """Chama a API do Google Gemini via HTTP padrão (sem bibliotecas externas pesadas)."""
        prompt = f"""Você é o maior especialista em prospecção de vendas B2B e expansão de provedores de internet fibra óptica (ISP).
A empresa é a DigitalNet MS (provedor com rede própria AS61588, Wi-Fi 6 em comodato, suporte local 24h e planos de 600 a 900 Mega em Campo Grande - MS).

Gere uma lista de {count} leads B2B/comerciais realistas e altamente prováveis localizados EXATAMENTE no bairro "{bairro}" em "{cidade} - {estado}", nicho "{niche}".

Retorne EXCLUSIVAMENTE um JSON array (sem formatação markdown, sem ```json) com a seguinte estrutura para cada item:
[
  {{
    "empresa": "Nome da Empresa / Clínica / Comércio",
    "nome": "Nome do Decisor (Ex: Dra. Camila Rocha, Dr. Marcos Silva, Roberto Santos)",
    "cargo": "Cargo (Ex: Sócio-Diretor, Gerente Geral, Médico Responsável)",
    "telefone": "(67) 99876-1234",
    "email": "contato@empresa.com.br",
    "logradouro": "Rua ou Avenida real deste bairro em Campo Grande",
    "numero": "120",
    "cep": "79000-000",
    "operadora_atual": "Vivo Fibra ou Claro",
    "plano_sugerido": "Fibra 700 + DigiMesh (Wi-Fi 6) ou Fibra 900 Advanced",
    "valor_mensal_sugerido": 139.90,
    "lead_score": 88,
    "dor_principal": "Descrição da dor (ex: maquininha oscilando, sinal Wi-Fi fraco, suporte 0800 demorado)",
    "icebreaker_optin": "Texto persuasivo de 3 parágrafos pedindo opt-in para comparativo sem ban"
  }}
]"""

        url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key={api_key}"
        payload = json.dumps({
            "contents": [{"parts": [{"text": prompt}]}],
            "generationConfig": {"temperature": 0.4}
        }).encode('utf-8')

        req = urllib.request.Request(
            url,
            data=payload,
            headers={'Content-Type': 'application/json'},
            method='POST'
        )

        with urllib.request.urlopen(req, timeout=12) as response:
            res_data = json.loads(response.read().decode('utf-8'))
            text_resp = res_data['candidates'][0]['content']['parts'][0]['text']
            # Remove blocos ```json se houver
            text_clean = re.sub(r'^```json\s*', '', text_resp.strip(), flags=re.MULTILINE)
            text_clean = re.sub(r'```$', '', text_clean.strip(), flags=re.MULTILINE)
            dados = json.loads(text_clean)
            if isinstance(dados, list):
                return dados
        return []

    @classmethod
    def _generate_fallback_prospects(
        cls,
        bairro: str,
        cidade: str,
        estado: str,
        niche: str,
        count: int
    ) -> List[Dict[str, Any]]:
        """Motor heurístico de telecomunicações para Campo Grande."""
        info_bairro = PERFIS_CAMPO_GRANDE.get(bairro, {
            'ruas': ['Avenida Principal', 'Rua Central', 'Rua das Palmeiras'],
            'cep_prefix': '79000',
            'nichos': ['Comércio & Serviços', 'Consultórios', 'Escritórios'],
        })

        ruas = info_bairro['ruas']
        cep_prefix = info_bairro['cep_prefix']

        templates_empresas = [
            {
                'empresa_tpl': 'Clínica Integrada {sobrenome}',
                'contato': 'Dra. Patricia {sobrenome}',
                'cargo': 'Diretora Clínica',
                'dor': 'Lentidão no sistema de agendamento online e máquinas de cartão travando em horários de pico.',
                'operadora': 'Vivo Fibra',
                'plano': 'Fibra 700 + DigiMesh (Wi-Fi 6)',
                'valor': 139.90,
                'score': 92,
            },
            {
                'empresa_tpl': '{sobrenome} Advogados Associados',
                'contato': 'Dr. Marcos Eduardo {sobrenome}',
                'cargo': 'Sócio Coordenador',
                'dor': 'Queda de conexão durante audiências virtuais pelo Teams/Zoom e demora no upload de petições pesadas.',
                'operadora': 'Claro NET',
                'plano': 'DigitalNet B2B Link Dedicado Pro',
                'valor': 399.90,
                'score': 95,
            },
            {
                'empresa_tpl': 'Studio & Boutique {sobrenome}',
                'contato': 'Camila {sobrenome}',
                'cargo': 'Sócia Proprietária',
                'dor': 'Wi-Fi da operadora atual não cobre a recepção e o estoque; sinal fraco para clientes.',
                'operadora': 'Vivo Fibra',
                'plano': 'Fibra 700 + DigiMesh (Wi-Fi 6)',
                'valor': 139.90,
                'score': 88,
            },
            {
                'empresa_tpl': '{sobrenome} Contabilidade & Gestão',
                'contato': 'Carlos Roberto {sobrenome}',
                'cargo': 'Contador Responsável',
                'dor': 'Falta de suporte aos finais de semana e suporte telefônico via robô 0800 quando cai o sinal.',
                'operadora': 'Claro NET',
                'plano': 'Fibra 900 Advanced (Wi-Fi 6)',
                'valor': 149.90,
                'score': 90,
            },
            {
                'empresa_tpl': 'Espaço Saúde & Bem-Estar {sobrenome}',
                'contato': 'Juliana {sobrenome}',
                'cargo': 'Gerente Geral',
                'dor': 'Cobrança alta de fatura na fatura atual sem entrega da velocidade contratada.',
                'operadora': 'Vivo Fibra',
                'plano': 'Fibra 600 Standard (Wi-Fi 6)',
                'valor': 129.90,
                'score': 84,
            },
            {
                'empresa_tpl': 'Restaurante & Café {sobrenome}',
                'contato': 'Fernando {sobrenome}',
                'cargo': 'Proprietário',
                'dor': 'Queda no link de dados afeta o tablet de pedidos dos garçons e a emissão de cupons fiscais.',
                'operadora': 'Claro NET',
                'plano': 'Fibra 700 + DigiMesh (Wi-Fi 6)',
                'valor': 139.90,
                'score': 91,
            },
        ]

        sobrenomes = ['Albuquerque', 'Mendes', 'Fontana', 'Vasconcelos', 'Barreto', 'Nogueira', 'Pires', 'Ribeiro']
        resultado = []

        for i in range(min(count, len(templates_empresas))):
            t = templates_empresas[i]
            sobrenome = sobrenomes[i % len(sobrenomes)]
            empresa = t['empresa_tpl'].format(sobrenome=sobrenome)
            nome_contato = t['contato'].format(sobrenome=sobrenome)
            rua = ruas[i % len(ruas)]
            num = str(100 + i * 85)
            tel = f"(67) 9{random.randint(9100, 9999)}-{random.randint(1000, 9999)}"
            email_empresa = f"contato@{re.sub(r'[^a-z0-9]', '', empresa.lower())[:14]}.com.br"
            cep = f"{cep_prefix}-{random.randint(100, 999):03d}"

            # Cria lead estruturado
            lead_item = {
                'empresa': empresa,
                'nome': nome_contato,
                'cargo': t['cargo'],
                'telefone': tel,
                'email': email_empresa,
                'logradouro': rua,
                'numero': num,
                'bairro': bairro,
                'cidade': cidade,
                'estado': estado,
                'cep': cep,
                'niche': niche,
                'operadora_atual': t['operadora'],
                'plano_sugerido': t['plano'],
                'valor_mensal_sugerido': t['valor'],
                'lead_score': t['score'],
                'dor_principal': t['dor'],
            }

            # Monta script de opt-in
            temp_lead = Lead(**lead_item)
            lead_item['icebreaker_optin'] = cls.generate_anti_ban_whatsapp_script(temp_lead)
            lead_item['dossie_comercial'] = json.dumps({
                'perfil_decisor': f"{nome_contato} ({t['cargo']}) busca estabilidade de rede e atendimento direto sem burocracia.",
                'vantagem_digitalnet': 'Fibra óptica com Wi-Fi 6 de alta densidade + suporte presencial 24h com equipe em Campo Grande.',
                'angulo_venda': f"Focar na eliminação da dor de '{t['dor']}' demonstrando que a DigitalNet já atende vizinhos nesta mesma rua.",
            }, ensure_ascii=False)

            resultado.append(lead_item)

        return resultado

    @classmethod
    def save_prospects(cls, prospects_data: List[Dict[str, Any]], cliente_ref_id: Optional[int] = None) -> List[Lead]:
        """Salva a lista de leads prospectados no banco de dados."""
        salvos = []
        for d in prospects_data:
            # Evita duplicidade exata de empresa + bairro
            existente = Lead.query.filter_by(
                empresa=d['empresa'],
                bairro=d.get('bairro', 'Campo Grande')
            ).first()

            if existente:
                continue

            lead = Lead(
                empresa=d['empresa'],
                nome=d['nome'],
                cargo=d.get('cargo'),
                telefone=d.get('telefone'),
                email=d.get('email'),
                logradouro=d.get('logradouro'),
                numero=d.get('numero'),
                bairro=d.get('bairro', 'Centro'),
                cidade=d.get('cidade', 'Campo Grande'),
                estado=d.get('estado', 'MS'),
                cep=d.get('cep'),
                niche=d.get('niche', 'Geral'),
                cliente_referencia_id=cliente_ref_id,
                status='novo',
                optin_status='pendente',
                operadora_atual=d.get('operadora_atual', 'Vivo Fibra / Claro'),
                plano_sugerido=d.get('plano_sugerido', 'Fibra 700 + DigiMesh'),
                valor_mensal_sugerido=float(d.get('valor_mensal_sugerido', 139.90)),
                lead_score=int(d.get('lead_score', 85)),
                dor_principal=d.get('dor_principal'),
                icebreaker_optin=d.get('icebreaker_optin'),
                dossie_comercial=d.get('dossie_comercial') if isinstance(d.get('dossie_comercial'), str) else json.dumps(d.get('dossie_comercial') or {}, ensure_ascii=False),
            )

            # Se não veio o script de opt-in, gera automaticamente
            if not lead.icebreaker_optin:
                lead.icebreaker_optin = cls.generate_anti_ban_whatsapp_script(lead)

            db.session.add(lead)
            salvos.append(lead)

        db.session.commit()
        return salvos

    @classmethod
    def convert_lead_to_client(cls, lead: Lead) -> Cliente:
        """
        Converte o lead em Cliente efetivo e cria automaticamente o Pedido
        da assinatura da DigitalNet MS com itens totalizados.
        """
        if lead.cliente_convertido_id:
            cliente_existente = Cliente.query.get(lead.cliente_convertido_id)
            if cliente_existente:
                return cliente_existente

        # 1. Cria o Cliente
        novo_cliente = Cliente(
            nome=f"{lead.empresa} ({lead.nome})",
            email=lead.email or f"contato@{re.sub(r'[^a-z0-9]', '', lead.empresa.lower())[:10]}.com.br",
            telefone=lead.telefone or '(67) 99999-9999',
            documento=lead.documento or '00.000.000/0001-00',
            cep=lead.cep or '79000-000',
            logradouro=lead.logradouro or 'Rua de Acesso',
            numero=lead.numero or 'S/N',
            complemento=lead.complemento,
            bairro=lead.bairro,
            cidade=lead.cidade,
            estado=lead.estado,
            ativo=True,
            observacoes=f"Cliente convertido via Prospecção Geo-Localizada. Dor anterior: {lead.dor_principal or 'N/A'}"
        )
        db.session.add(novo_cliente)
        db.session.flush()

        # 2. Cria o Pedido da Assinatura
        prefixo = f"NET-{datetime.utcnow().year}"
        ultimo_pedido = Pedido.query.filter(Pedido.numero_pedido.like(f"{prefixo}-%")).order_by(Pedido.id.desc()).first()
        if ultimo_pedido:
            try:
                seq = int(ultimo_pedido.numero_pedido.split('-')[-1]) + 1
            except ValueError:
                seq = 1
        else:
            seq = 1
        num_pedido = f"{prefixo}-{seq:04d}"

        valor = float(lead.valor_mensal_sugerido or 139.90)
        pedido = Pedido(
            numero_pedido=num_pedido,
            cliente_id=novo_cliente.id,
            status='processando',
            metodo_pagamento='pix',
            valor_total=valor,
            descricao=f"Assinatura Mensal {lead.plano_sugerido} - Instalação Inclusa com Roteador Wi-Fi 6",
            observacoes="Ativação inicial de fibra óptica DigitalNet MS."
        )
        db.session.add(pedido)
        db.session.flush()

        # 3. Item do Pedido
        item = ItemPedido(
            pedido_id=pedido.id,
            descricao=f"Mensalidade {lead.plano_sugerido} (Instalação + Wi-Fi 6 em comodato)",
            quantidade=1.0,
            valor_unitario=valor,
            valor_total=valor
        )
        db.session.add(item)

        # 4. Atualiza o status do Lead
        lead.status = 'convertido'
        lead.optin_status = 'aceito'
        lead.cliente_convertido_id = novo_cliente.id
        db.session.commit()

        return novo_cliente

    @staticmethod
    def get_objection_tutor(objection_key: str, lead: Lead) -> Dict[str, Any]:
        """Tutor de contorno de objeções com técnicas psicológicas."""
        bairro = lead.bairro or 'seu bairro'
        operadora = lead.operadora_atual or 'concorrência'
        plano = lead.plano_sugerido or 'Fibra com Wi-Fi 6'

        tutores = {
            'fidelidade': {
                'titulo': 'Objeção: "Ainda tenho contrato de fidelidade com a Vivo/Claro"',
                'diagnostico': 'O cliente tem medo de pagar multa rescisória e ficar no prejuízo.',
                'tecnica': 'Ponte de Transição / Teste em Paralelo',
                'script_whatsapp': (
                    f"Entendo perfeitamente! Ninguém gosta de pagar multas desnecessárias.\n\n"
                    f"O que muitos clientes aqui do {bairro} fazem é instalar a DigitalNet nos últimos 60 dias da fidelidade como 'link de segurança', "
                    f"aproveitando a nossa condição de R$ 99,90 nos primeiros 3 meses. Assim você não fica sem internet se a {operadora} cair "
                    f"e faz a transição 100% suave sem pagar multa. Que tal agendarmos a viabilidade?"
                ),
            },
            'preco': {
                'titulo': 'Objeção: "Achei o valor um pouco acima do que pago hoje"',
                'diagnostico': 'O cliente está comparando preço nominal de plano antigo sem perceber que tem metade da velocidade e Wi-Fi obsoleto.',
                'tecnica': 'Custo por Mega & Custo de Queda',
                'script_whatsapp': (
                    f"Compreendo! Se olharmos só o valor final parece similar, mas na prática você está pagando mais caro por Mega.\n\n"
                    f"Na DigitalNet você recebe {plano} com dobro de upload e roteador Wi-Fi 6 de alta densidade incluso em comodato (que a concorrência cobra R$ 25/mês de aluguel). "
                    f"Além disso, uma única hora sem internet na sua operação custa muito mais que a diferença de mensalidade. Faz sentido dar uma olhada na comparação?"
                ),
            },
            'marca': {
                'titulo': 'Objeção: "Nunca ouvi falar da DigitalNet, prefiro as grandes teles"',
                'diagnostico': 'Insegurança em relação à estabilidade e suporte.',
                'tecnica': 'Autoridade Local + Atendimento Humanizado',
                'script_whatsapp': (
                    f"Ótimo ponto! A grande diferença é que a DigitalNet é uma operadora com rede própria autorizada pela Anatel (AS61588) e mais de 700 condomínios atendidos em Campo Grande.\n\n"
                    f"Enquanto nas teles nacionais você fala com robôs no 0800 e espera 3 dias por um técnico de fora, a nossa equipe de suporte é 100% própria, local e 24h aqui na cidade. "
                    f"Se precisar de suporte, o técnico chega no mesmo dia. Vale a pena testar a estabilidade local!"
                ),
            },
            'satisfeito': {
                'titulo': 'Objeção: "Minha internet atual já me atende, não quero mexer"',
                'diagnostico': 'Acomodação até que ocorra uma queda crítica.',
                'tecnica': 'Pergunta de Tensão Construtiva',
                'script_whatsapp': (
                    f"Excelente saber que está funcionando! Posso te fazer uma pergunta rápida de 30 segundos?\n\n"
                    f"Quando a sua internet atual oscila nos horários de pico, qual é o plano de contingência da {lead.empresa} para não parar os computadores e maquininhas? "
                    f"A DigitalNet pode ficar como sua rota principal com Wi-Fi 6 de alta velocidade para que sua equipe nunca mais sofra lentidão. Posso te passar um comparativo?"
                ),
            },
        }

        return tutores.get(objection_key, tutores['fidelidade'])
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

/* ==========================================================================
   DIGITALNET MS - TEMA AZUL TELECOM & AMARELO FIBRA
   ========================================================================== */

:root {
  --dn-blue: #1b4f99;
  --dn-blue-dark: #0f2d57;
  --dn-blue-deep: #091c36;
  --dn-blue-light: #eff6ff;
  --dn-blue-border: #bfdbfe;
  
  --dn-yellow: #f59e0b;
  --dn-yellow-gold: #ffbe18;
  --dn-yellow-light: #fefce8;
  --dn-yellow-dark: #92400e;
  --dn-yellow-border: #fde68a;
}

/* Header & Banner */
.dn-header-title {
  color: var(--dn-blue-deep);
  font-weight: 800;
  letter-spacing: -0.02em;
}

.dn-badge-corp {
  background: linear-gradient(135deg, var(--dn-blue), var(--dn-blue-dark));
  color: #ffffff;
  border: 1px solid rgba(255, 255, 255, 0.2);
  font-weight: 600;
}

.dn-badge-yellow {
  background: var(--dn-yellow-gold);
  color: #0f172a;
  font-weight: 700;
  border-radius: 9999px;
  box-shadow: 0 2px 4px rgba(245, 158, 11, 0.25);
}

/* Botões com Identidade DigitalNet */
.btn-dn-blue {
  background: linear-gradient(135deg, var(--dn-blue), #143e79);
  color: #ffffff !important;
  border: none;
  font-weight: 600;
  box-shadow: 0 3px 8px rgba(27, 79, 153, 0.25);
  transition: all 0.2s ease;
}
.btn-dn-blue:hover {
  background: linear-gradient(135deg, #143e79, var(--dn-blue-deep));
  transform: translateY(-1px);
  box-shadow: 0 6px 14px rgba(27, 79, 153, 0.35);
}

.btn-dn-yellow {
  background: linear-gradient(135deg, var(--dn-yellow-gold), var(--dn-yellow));
  color: #0f172a !important;
  border: none;
  font-weight: 700;
  box-shadow: 0 3px 8px rgba(245, 158, 11, 0.25);
  transition: all 0.2s ease;
}
.btn-dn-yellow:hover {
  background: linear-gradient(135deg, var(--dn-yellow), #d97706);
  transform: translateY(-1px);
  box-shadow: 0 6px 14px rgba(245, 158, 11, 0.35);
}

.btn-dn-outline {
  border: 1.5px solid var(--dn-blue);
  color: var(--dn-blue);
  background: #ffffff;
  font-weight: 600;
  transition: all 0.2s ease;
}
.btn-dn-outline:hover {
  background: var(--dn-blue);
  color: #ffffff;
}

/* Cards de Clusters de Bairros */
.dn-cluster-card {
  background: #ffffff;
  border: 1px solid #e2e8f0;
  border-radius: var(--radius-md);
  padding: 1.15rem;
  box-shadow: 0 2px 6px rgba(0, 0, 0, 0.04);
  transition: all 0.25s ease;
  position: relative;
  overflow: hidden;
}
.dn-cluster-card::before {
  content: '';
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  height: 4px;
  background: linear-gradient(90deg, var(--dn-blue), var(--dn-yellow-gold));
}
.dn-cluster-card:hover {
  transform: translateY(-3px);
  box-shadow: 0 10px 22px rgba(27, 79, 153, 0.12);
  border-color: var(--dn-blue-border);
}
.dn-cluster-card.active-cluster {
  border-color: var(--dn-blue);
  background-color: var(--dn-blue-light);
}

/* Indicadores de Funil (KPI Cards) */
.dn-kpi-card {
  background: #ffffff;
  border: 1px solid #e2e8f0;
  border-radius: var(--radius-md);
  padding: 1rem 1.15rem;
  box-shadow: 0 2px 5px rgba(0, 0, 0, 0.03);
  position: relative;
  transition: all 0.2s ease;
}
.dn-kpi-card:hover {
  transform: translateY(-2px);
  box-shadow: 0 6px 12px rgba(0, 0, 0, 0.06);
}
.dn-kpi-card .kpi-number {
  font-size: 1.85rem;
  font-weight: 800;
  line-height: 1.1;
  color: var(--dn-blue-deep);
}
.dn-kpi-card .kpi-label {
  font-size: 0.75rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: #64748b;
  margin-bottom: 0.25rem;
}

/* Tabela de Leads */
.dn-table-header {
  background: linear-gradient(135deg, var(--dn-blue-deep), var(--dn-blue));
  color: #ffffff;
}
.dn-table-header th {
  font-weight: 600;
  font-size: 0.8rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  padding: 0.85rem 1rem;
  border: none;
}

/* Hero Banner do Lead (detail.html) */
.dn-hero-banner {
  background: linear-gradient(135deg, var(--dn-blue-deep) 0%, var(--dn-blue) 100%);
  color: #ffffff;
  border-radius: var(--radius-lg);
  padding: 1.75rem 2rem;
  position: relative;
  overflow: hidden;
  box-shadow: 0 10px 25px rgba(15, 45, 87, 0.2);
}
.dn-hero-banner::after {
  content: '';
  position: absolute;
  top: -50px;
  right: -50px;
  width: 200px;
  height: 200px;
  background: radial-gradient(circle, rgba(255, 190, 24, 0.15) 0%, transparent 70%);
  border-radius: 50%;
  pointer-events: none;
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
          <div class="brand-icon" style="background: linear-gradient(135deg, #1b4f99, #0f2d57); box-shadow: 0 4px 12px rgba(27, 79, 153, 0.4);">
            <i class="bi bi-broadcast-pin" style="color: #fbbf24;"></i>
          </div>
          <div>
            <div style="line-height: 1.1; font-weight: 800; letter-spacing: -0.02em;">Digital<span style="color: #fbbf24;">Net</span></div>
            <small style="font-size: 0.7rem; color: #94a3b8; font-weight: 500;">Gestão & Expansão MS</small>
          </div>
        </a>
      </div>

      <nav class="sidebar-nav">
        <div class="nav-section-title">Principal</div>
        <a href="{{ url_for('main.dashboard') }}" class="sidebar-link {% if request.endpoint == 'main.dashboard' %}active{% endif %}">
          <i class="bi bi-speedometer2"></i>
          <span>Dashboard</span>
        </a>

        <div class="nav-section-title">Expansão Telecom</div>
        <a href="{{ url_for('leads.index') }}" class="sidebar-link {% if request.blueprint == 'leads' %}active{% endif %}">
          <i class="bi bi-radar text-warning"></i>
          <span>Radar de Leads</span>
          <span class="badge ms-auto" style="background: #fbbf24; color: #0f172a; font-weight: 700; font-size: 0.65rem;">Wi-Fi 6</span>
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
          <div class="d-none d-md-flex align-items-center gap-2">
            <span class="text-muted small">Portal de Gestão & Expansão</span>
            <span class="badge py-1 px-2 rounded-pill" style="background: #fef3c7; color: #92400e; border: 1px solid #fde68a; font-size: 0.7rem; font-weight: 700;">
              <i class="bi bi-geo-alt-fill text-danger me-1"></i>Campo Grande - MS
            </span>
          </div>
        </div>

        <div class="d-flex align-items-center gap-2">
          <a href="{{ url_for('clientes.novo') }}" class="btn btn-sm btn-dn-outline d-none d-sm-inline-flex align-items-center gap-1">
            <i class="bi bi-person-plus"></i> + Cliente
          </a>
          <a href="{{ url_for('pedidos.novo') }}" class="btn btn-sm btn-dn-blue d-none d-sm-inline-flex align-items-center gap-1">
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

# --- app/templates/leads/detail.html ---
cat > 'app/templates/leads/detail.html' <<'OMNI_EOF'
{% extends "base.html" %}

{% block title %}Dossiê Comercial & Central WhatsApp - {{ lead.empresa }} - DigitalNet MS{% endblock %}

{% block content %}
<div class="container-fluid px-0">

  <!-- BREADCRUMB & VOLTAR -->
  <div class="d-flex justify-content-between align-items-center mb-3">
    <a href="{{ url_for('leads.index', bairro=lead.bairro) }}" class="btn btn-dn-outline btn-sm shadow-sm">
      <i class="bi bi-arrow-left me-1"></i> Voltar ao Radar de Leads
    </a>

    <div class="d-flex gap-2">
      <span class="badge {{ lead.status_badge_class }} py-2 px-3 fs-6 shadow-sm">
        Status: {{ lead.status_label }}
      </span>
      {% if lead.optin_status == 'aceito' %}
      <span class="badge bg-success py-2 px-3 fs-6 shadow-sm">
        <i class="bi bi-shield-check me-1"></i> Opt-in Aceito
      </span>
      {% elif lead.optin_status == 'recusado' %}
      <span class="badge bg-danger py-2 px-3 fs-6 shadow-sm">
        Opt-in Recusado
      </span>
      {% else %}
      <span class="badge bg-warning text-dark py-2 px-3 fs-6 shadow-sm">
        <i class="bi bi-clock-history me-1"></i> Opt-in Pendente
      </span>
      {% endif %}
    </div>
  </div>

  <!-- HERO BANNER DO LEAD COM IDENTIDADE DIGITALNET -->
  <div class="dn-hero-banner mb-4">
    <div class="row align-items-center">
      <div class="col-lg-8">
        <div class="d-flex align-items-center gap-3 mb-2">
          <div class="rounded-circle p-3 d-flex align-items-center justify-content-center shadow" style="background: rgba(255, 190, 24, 0.2); color: var(--dn-yellow-gold); width: 64px; height: 64px;">
            <i class="bi bi-building fs-2"></i>
          </div>
          <div>
            <h2 class="h3 fw-bold mb-1 text-white">{{ lead.empresa }}</h2>
            <div class="text-white-50 small d-flex align-items-center gap-2 flex-wrap">
              <span><i class="bi bi-person-fill text-warning me-1"></i> Decisor: <strong class="text-white">{{ lead.nome }}</strong></span>
              {% if lead.cargo %}
              <span class="badge" style="background: rgba(255, 190, 24, 0.25); color: #fde047; font-weight: 600;">{{ lead.cargo }}</span>
              {% endif %}
              <span>&bull; <i class="bi bi-tag-fill text-warning me-1"></i> {{ lead.niche }}</span>
            </div>
          </div>
        </div>

        <div class="d-flex flex-wrap gap-4 text-white-50 small mt-3 pt-3 border-top" style="border-color: rgba(255, 255, 255, 0.15) !important;">
          <div><i class="bi bi-geo-alt-fill text-danger me-1"></i> <span class="text-white">{{ lead.endereco_resumido }}</span></div>
          {% if lead.telefone %}
          <div><i class="bi bi-telephone-fill text-success me-1"></i> <span class="text-white">{{ lead.telefone }}</span></div>
          {% endif %}
          {% if lead.email %}
          <div><i class="bi bi-envelope-fill text-info me-1"></i> <span class="text-white">{{ lead.email }}</span></div>
          {% endif %}
          <div><i class="bi bi-hdd-network text-warning me-1"></i> Operadora Atual: <strong class="text-white">{{ lead.operadora_atual }}</strong></div>
        </div>
      </div>

      <div class="col-lg-4 text-lg-end mt-3 mt-lg-0">
        <div class="d-inline-block text-center p-3 rounded-3 shadow" style="background: rgba(9, 28, 54, 0.6); border: 1px solid rgba(255, 190, 24, 0.3); min-width: 170px;">
          <small class="text-white-50 d-block text-uppercase fw-semibold" style="font-size: 0.7rem; letter-spacing: 0.05em;">Score de Conversão</small>
          <h2 class="fw-bold mb-0 text-warning" style="font-size: 2.5rem;">{{ lead.lead_score }}<small class="fs-6 text-white-50">/100</small></h2>
          <small class="text-success fw-semibold"><i class="bi bi-check2-circle me-1"></i>Alta Viabilidade Óptica</small>
        </div>
      </div>
    </div>
  </div>

  <div class="row g-4">

    <!-- COLUNA ESQUERDA: CENTRAL WHATSAPP & QUEBRA DE OBJEÇÕES -->
    <div class="col-lg-7">

      <!-- CARD WHATSAPP ANTI-BAN -->
      <div class="card border-0 shadow-sm mb-4">
        <div class="card-header bg-white py-3 border-bottom d-flex justify-content-between align-items-center">
          <div class="d-flex align-items-center gap-2">
            <div class="p-2 rounded-2 text-white" style="background: #25d366;">
              <i class="bi bi-whatsapp fs-5"></i>
            </div>
            <div>
              <h5 class="fw-bold mb-0" style="color: var(--dn-blue-deep);">Abordagem WhatsApp com Opt-in Anti-Ban</h5>
              <small class="text-muted">Mensagem consultiva sem links promocionais no primeiro contato</small>
            </div>
          </div>
          <span class="badge py-2 px-3 rounded-pill" style="background: #ecfdf5; color: #065f46; border: 1px solid #a7f3d0; font-weight: 700;">
            <i class="bi bi-shield-check me-1"></i> Blindado contra Ban
          </span>
        </div>
        
        <div class="card-body p-4">
          <div class="alert alert-light border py-2 px-3 small mb-3 text-secondary">
            <i class="bi bi-info-circle text-primary me-1"></i>
            Este roteiro segue o método de 3 passos: <strong>1)</strong> Gancho hiperlocal em Campo Grande, <strong>2)</strong> Comparativo contra a operadora atual e <strong>3)</strong> Pedido de consentimento explícito.
          </div>

          <div class="position-relative mb-3">
            <textarea id="scriptWhatsApp" class="form-control bg-light border text-dark font-monospace small p-3" rows="8" readonly style="line-height: 1.5; resize: none;">{{ lead.icebreaker_optin }}</textarea>
            <button class="btn btn-sm btn-outline-secondary position-absolute top-0 end-0 m-2 shadow-sm" onclick="copiarScript()" title="Copiar para área de transferência">
              <i class="bi bi-clipboard me-1"></i> Copiar
            </button>
          </div>

          <div class="d-flex flex-wrap gap-2 justify-content-between align-items-center pt-2">
            {% if lead.whatsapp_url != '#' %}
            <a href="{{ lead.whatsapp_url }}" target="_blank" class="btn btn-success px-4 shadow-sm" id="btnDispararWhatsApp">
              <i class="bi bi-whatsapp me-2"></i> Abrir WhatsApp Web
            </a>
            {% else %}
            <button class="btn btn-secondary" disabled>Sem telefone cadastrado</button>
            {% endif %}

            <div class="d-flex gap-2">
              <form action="{{ url_for('leads.atualizar_status', lead_id=lead.id) }}" method="POST" class="d-inline">
                <input type="hidden" name="status" value="optin_solicitado">
                <input type="hidden" name="optin_status" value="pendente">
                <button type="submit" class="btn btn-sm btn-outline-warning text-dark fw-semibold" title="Marcar que enviou mensagem">
                  <i class="bi bi-send me-1"></i> Marcar Enviado
                </button>
              </form>

              <form action="{{ url_for('leads.atualizar_status', lead_id=lead.id) }}" method="POST" class="d-inline">
                <input type="hidden" name="status" value="optin_aceito">
                <input type="hidden" name="optin_status" value="aceito">
                <button type="submit" class="btn btn-sm btn-dn-blue" title="Lead respondeu com interesse">
                  <i class="bi bi-check-circle-fill text-warning me-1"></i> Opt-in Aceito!
                </button>
              </form>
            </div>
          </div>
        </div>
      </div>

      <!-- TUTOR DE QUEBRA DE OBJEÇÕES -->
      <div class="card border-0 shadow-sm mb-4">
        <div class="card-header bg-white py-3 border-bottom">
          <div class="d-flex align-items-center gap-2">
            <div class="p-2 rounded-2 text-dark" style="background: var(--dn-yellow-gold);">
              <i class="bi bi-mortarboard-fill fs-5"></i>
            </div>
            <div>
              <h5 class="fw-bold mb-0" style="color: var(--dn-blue-deep);">Tutor de Quebra de Objeções (SDR Telecom)</h5>
              <small class="text-muted">Selecione a objeção do cliente para obter a técnica psicológica e o script imediato</small>
            </div>
          </div>
        </div>

        <div class="card-body p-4">
          <div class="btn-group btn-group-sm w-100 mb-3 shadow-sm" role="group">
            <a href="{{ url_for('leads.detail', lead_id=lead.id, obj='fidelidade') }}" class="btn {% if obj_key == 'fidelidade' %}btn-dn-yellow{% else %}btn-outline-secondary{% endif %}">
              Fidelidade Concorrente
            </a>
            <a href="{{ url_for('leads.detail', lead_id=lead.id, obj='preco') }}" class="btn {% if obj_key == 'preco' %}btn-dn-yellow{% else %}btn-outline-secondary{% endif %}">
              Preço / Custo
            </a>
            <a href="{{ url_for('leads.detail', lead_id=lead.id, obj='marca') }}" class="btn {% if obj_key == 'marca' %}btn-dn-yellow{% else %}btn-outline-secondary{% endif %}">
              Não Conheço a Marca
            </a>
            <a href="{{ url_for('leads.detail', lead_id=lead.id, obj='satisfeito') }}" class="btn {% if obj_key == 'satisfeito' %}btn-dn-yellow{% else %}btn-outline-secondary{% endif %}">
              Já Estou Satisfeito
            </a>
          </div>

          <div class="p-3 bg-light rounded-3 border mb-2">
            <div class="d-flex justify-content-between align-items-start mb-2 flex-wrap gap-1">
              <h6 class="fw-bold mb-0" style="color: var(--dn-blue);"><i class="bi bi-chat-quote-fill me-1 text-warning"></i>{{ tutor_obj.titulo }}</h6>
              <span class="badge py-1 px-2 rounded-pill bg-dark text-white">Técnica: {{ tutor_obj.tecnica }}</span>
            </div>
            
            <p class="small text-muted mb-2"><strong>Diagnóstico Psicológico:</strong> {{ tutor_obj.diagnostico }}</p>
            
            <div class="p-3 bg-white rounded border border-warning font-monospace small text-dark mt-2 shadow-sm" style="border-left: 4px solid var(--dn-yellow) !important;">
              {{ tutor_obj.script_whatsapp|replace('\n', '<br>')|safe }}
            </div>
          </div>
        </div>
      </div>

    </div>

    <!-- COLUNA DIREITA: VIABILIDADE & CONVERSÃO EM CLIENTE -->
    <div class="col-lg-5">

      <!-- DIAGNÓSTICO E DOR -->
      <div class="card border-0 shadow-sm mb-4">
        <div class="card-header bg-white py-3 border-bottom">
          <div class="d-flex align-items-center gap-2">
            <i class="bi bi-speedometer2 fs-5 text-primary"></i>
            <h5 class="fw-bold mb-0" style="color: var(--dn-blue-deep);">Diagnóstico da Conexão Atual</h5>
          </div>
        </div>
        
        <div class="card-body p-4">
          <div class="mb-3">
            <label class="small fw-bold text-muted text-uppercase d-block mb-1">Principal Gargalo / Dor Mapeada:</label>
            <div class="alert alert-warning border-warning bg-warning bg-opacity-10 small mb-0 py-2">
              <i class="bi bi-exclamation-triangle-fill text-warning-emphasis me-2"></i>
              <strong class="text-dark">{{ lead.dor_principal or "Lentidão nas maquininhas e lentidão no sinal Wi-Fi durante os horários de pico." }}</strong>
            </div>
          </div>

          <div class="mb-3">
            <label class="small fw-bold text-muted text-uppercase d-block mb-1">Viabilidade Óptica no Bairro (DigitalNet MS):</label>
            <div class="d-flex align-items-center gap-3 p-3 bg-light rounded-3 border">
              <div class="p-2 rounded-circle bg-success bg-opacity-10 text-success">
                <i class="bi bi-check-circle-fill fs-4"></i>
              </div>
              <div>
                <strong class="text-dark d-block">Porta Óptica Confirmada no Bairro {{ lead.bairro }}</strong>
                <div class="text-muted" style="font-size: 0.75rem;">Rede FTTH própria AS61588. Instalação rápida inclusa sem obras.</div>
              </div>
            </div>
          </div>

          <div class="border-top pt-3">
            <label class="small fw-bold text-muted text-uppercase d-block mb-1">Plano Recomendado DigitalNet:</label>
            <h5 class="fw-bold mb-1" style="color: var(--dn-blue);">{{ lead.plano_sugerido }}</h5>
            <div class="text-muted small">Valor mensal: <strong class="text-dark fs-6">R$ {{ "%.2f"|format(lead.valor_mensal_sugerido)|replace('.', ',') }}</strong> com roteador Wi-Fi 6 em comodato.</div>
          </div>
        </div>
      </div>

      <!-- FORMULÁRIO DE CONVERSÃO EM CLIENTE (DIGITALNET THEMED) -->
      <div class="card border-0 shadow-sm" style="border-top: 4px solid var(--dn-yellow) !important;">
        <div class="card-header bg-white py-3 border-bottom">
          <div class="d-flex align-items-center gap-2">
            <i class="bi bi-person-check-fill fs-5" style="color: var(--dn-blue);"></i>
            <div>
              <h5 class="fw-bold mb-0" style="color: var(--dn-blue-deep);">Fechar Venda & Ativar Assinatura</h5>
              <small class="text-muted">Cria o Cliente e gera o Pedido de instalação no banco de dados</small>
            </div>
          </div>
        </div>
        
        <div class="card-body p-4">
          <form action="{{ url_for('leads.converter_cliente', lead_id=lead.id) }}" method="POST">
            <div class="mb-3">
              <label class="form-label small fw-bold text-dark">Plano Contratado da DigitalNet</label>
              <select name="plano_sugerido" class="form-select bg-light" id="selectPlano">
                {% for p in planos %}
                <option value="{{ p.nome }}" data-preco="{{ p.preco }}" {% if p.nome == lead.plano_sugerido %}selected{% endif %}>
                  {{ p.nome }} ({{ p.download }}) - R$ {{ "%.2f"|format(p.preco)|replace('.', ',') }}/mês
                </option>
                {% endfor %}
              </select>
            </div>

            <div class="mb-3">
              <label class="form-label small fw-bold text-dark">Valor da Mensalidade (R$)</label>
              <input type="number" step="0.01" name="valor_mensal_sugerido" id="inputValor" class="form-control bg-light" value="{{ lead.valor_mensal_sugerido }}" required>
            </div>

            <div class="alert alert-info border-info bg-info bg-opacity-10 small mb-3 py-2">
              <i class="bi bi-info-circle-fill text-info me-1"></i>
              Ao clicar no botão abaixo, este lead será inserido na tabela <strong>clientes</strong> e um <strong>pedido de assinatura</strong> será gerado com totalização automática.
            </div>

            <button type="submit" class="btn btn-dn-yellow w-100 py-3 fw-bold shadow-sm" style="font-size: 1rem;">
              <i class="bi bi-check2-circle me-2"></i> Converter em Cliente & Gerar Pedido
            </button>
          </form>
        </div>
      </div>

    </div>

  </div>

</div>

<script>
function copiarScript() {
  const textarea = document.getElementById('scriptWhatsApp');
  textarea.select();
  textarea.setSelectionRange(0, 99999);
  navigator.clipboard.writeText(textarea.value).then(() => {
    alert('Script de WhatsApp copiado para a área de transferência!');
  });
}

document.getElementById('selectPlano').addEventListener('change', function() {
  const selectedOpt = this.options[this.selectedIndex];
  const preco = selectedOpt.getAttribute('data-preco');
  if (preco) {
    document.getElementById('inputValor').value = preco;
  }
});
</script>
{% endblock %}
OMNI_EOF

# --- app/templates/leads/index.html ---
cat > 'app/templates/leads/index.html' <<'OMNI_EOF'
{% extends "base.html" %}

{% block title %}Radar de Leads Telecom & Expansão de Fibra - DigitalNet MS{% endblock %}

{% block extra_css %}
<!-- Leaflet CSS para o Mapa de Calor -->
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" integrity="sha256-p4NxAoJBhIIN+hmNHrzRCf9tD/miZyoHS5obTRR9BMY=" crossorigin="" />
<style>
  .leaflet-popup-content-wrapper {
    border-radius: 12px;
    box-shadow: 0 12px 30px rgba(15, 45, 87, 0.22);
    padding: 0;
    overflow: hidden;
    border: 1px solid #e2e8f0;
  }
  .leaflet-popup-content {
    margin: 0 !important;
    line-height: 1.4;
  }
  .leaflet-container {
    font-family: 'Plus Jakarta Sans', sans-serif !important;
  }
  .heat-badge-chip {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-size: 0.75rem;
    font-weight: 600;
    padding: 4px 10px;
    border-radius: 20px;
  }
  .custom-pin-fibra {
    background: #1b4f99;
    color: #ffffff;
    border: 2px solid #ffffff;
    border-radius: 50%;
    width: 32px;
    height: 32px;
    display: flex;
    align-items: center;
    justify-content: center;
    box-shadow: 0 4px 12px rgba(27, 79, 153, 0.45);
    font-size: 0.85rem;
  }
  .custom-pin-lead {
    background: #f59e0b;
    color: #0f172a;
    border: 2px solid #ffffff;
    border-radius: 50%;
    width: 28px;
    height: 28px;
    display: flex;
    align-items: center;
    justify-content: center;
    box-shadow: 0 4px 10px rgba(245, 158, 11, 0.5);
    font-size: 0.75rem;
    font-weight: bold;
  }
  .custom-pin-lead.high-score {
    background: #ef4444;
    color: #ffffff;
    box-shadow: 0 4px 12px rgba(239, 68, 68, 0.55);
  }
</style>
{% endblock %}

{% block content %}
<div class="container-fluid px-0">

  <!-- CABEÇALHO COM IDENTIDADE DIGITALNET -->
  <div class="d-flex flex-column flex-md-row justify-content-between align-items-start align-items-md-center gap-3 mb-4">
    <div>
      <div class="d-flex align-items-center gap-2 flex-wrap">
        <h1 class="h3 mb-0 dn-header-title">Radar de Prospecção & Expansão de Fibra</h1>
        <span class="badge py-2 px-3 dn-badge-corp rounded-pill">
          <i class="bi bi-broadcast-pin text-warning me-1"></i> DigitalNet MS &bull; Campo Grande
        </span>
      </div>
      <p class="text-muted small mb-0 mt-1">
        Geo-prospecção inteligente na mesma região dos clientes ativos com abordagem anti-ban e opt-in via WhatsApp.
      </p>
    </div>

    <div class="d-flex align-items-center gap-2">
      <button class="btn btn-outline-primary btn-sm" type="button" data-bs-toggle="collapse" data-bs-target="#comoFunciona" aria-expanded="false">
        <i class="bi bi-shield-check text-warning me-1"></i> Blindagem Anti-Ban
      </button>
      <button class="btn btn-dn-yellow btn-sm px-3 shadow-sm" data-bs-toggle="modal" data-bs-target="#modalProspectar">
        <i class="bi bi-lightning-charge-fill me-1"></i> Nova Prospecção Geo
      </button>
    </div>
  </div>

  <!-- BOX EXPLICATIVO ANTI-BAN (COLLAPSIBLE) -->
  <div class="collapse mb-4" id="comoFunciona">
    <div class="card border-0 shadow-sm rounded-3" style="background: linear-gradient(135deg, #0f2d57, #1b4f99); color: #ffffff;">
      <div class="card-body p-4">
        <div class="d-flex align-items-center gap-2 mb-3">
          <i class="bi bi-shield-lock-fill fs-4 text-warning"></i>
          <h5 class="fw-bold mb-0 text-white">Estratégia Anti-Ban & Prospecção por Nós Ópticos</h5>
        </div>
        <div class="row g-3 small">
          <div class="col-md-4">
            <div class="p-3 rounded-3" style="background: rgba(255, 255, 255, 0.08);">
              <strong class="text-warning d-block mb-1"><i class="bi bi-geo-alt-fill me-1"></i>1. Viabilidade por Vizinhos:</strong>
              Prospecta apenas em quarteirões onde a DigitalNet já possui clientes ativos. Custo de instalação mínimo e viabilidade técnica garantida no poste.
            </div>
          </div>
          <div class="col-md-4">
            <div class="p-3 rounded-3" style="background: rgba(255, 255, 255, 0.08);">
              <strong class="text-warning d-block mb-1"><i class="bi bi-router-fill me-1"></i>2. Oferta Superior à Concorrência:</strong>
              Aborda com argumentos imbatíveis contra Vivo/Claro: roteador Wi-Fi 6 comodato, pontos extras DigiMesh, upload de 50% e suporte 24h presencial em Campo Grande.
            </div>
          </div>
          <div class="col-md-4">
            <div class="p-3 rounded-3" style="background: rgba(255, 255, 255, 0.08);">
              <strong class="text-warning d-block mb-1"><i class="bi bi-chat-check-fill me-1"></i>3. Opt-in Conversacional Obrigatório:</strong>
              O primeiro contato nunca envia links externos nem arquivos pesados. Pede permissão explícita para enviar o comparativo, blindando o WhatsApp contra bans.
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>

  <!-- MAPA DE CALOR: DENSIDADE ÓPTICA & OPORTUNIDADES EM CAMPO GRANDE -->
  <div class="card border-0 shadow-sm mb-4 overflow-hidden">
    <div class="card-header bg-white py-3 border-bottom d-flex flex-column flex-md-row justify-content-between align-items-start align-items-md-center gap-2">
      <div class="d-flex align-items-center gap-2">
        <div class="p-2 rounded-3" style="background: #fef3c7; color: #b45309;">
          <i class="bi bi-fire fs-5"></i>
        </div>
        <div>
          <h5 class="fw-bold mb-0" style="color: var(--dn-blue-deep);">
            Mapa de Calor: Cobertura Óptica & Densidade de Oportunidades
          </h5>
          <small class="text-muted">Concentração geo-espacial de clientes DigitalNet MS e leads potenciais em Campo Grande</small>
        </div>
      </div>

      <div class="d-flex align-items-center gap-2 flex-wrap">
        <div class="btn-group btn-group-sm shadow-sm" role="group">
          <button type="button" class="btn btn-outline-secondary active" id="btnFiltroTodos" onclick="filtrarMapa('todos')">
            <i class="bi bi-grid-fill me-1"></i> Todos
          </button>
          <button type="button" class="btn btn-outline-secondary" id="btnFiltroFibra" onclick="filtrarMapa('fibra')">
            <i class="bi bi-broadcast text-primary me-1"></i> Nós de Fibra
          </button>
          <button type="button" class="btn btn-outline-secondary" id="btnFiltroLeads" onclick="filtrarMapa('leads')">
            <i class="bi bi-fire text-warning me-1"></i> Oportunidades
          </button>
        </div>

        <button type="button" class="btn btn-sm btn-light border shadow-sm" onclick="centralizarCampoGrande()" title="Centralizar em Campo Grande">
          <i class="bi bi-crosshair me-1"></i> Recentralizar
        </button>
      </div>
    </div>

    <!-- LEGENDA DO MAPA DE CALOR -->
    <div class="px-3 py-2 bg-light border-bottom d-flex align-items-center justify-content-between flex-wrap gap-2 small">
      <div class="d-flex align-items-center gap-3 flex-wrap">
        <span class="text-muted fw-semibold">Gradiente Térmico:</span>
        <span class="heat-badge-chip bg-white border">
          <span style="width: 12px; height: 12px; border-radius: 50%; background: #1b4f99; display: inline-block;"></span>
          Rede DigitalNet Iluminada (CTO Ativa)
        </span>
        <span class="heat-badge-chip bg-white border">
          <span style="width: 12px; height: 12px; border-radius: 50%; background: #f59e0b; display: inline-block;"></span>
          Lead Quente (Score 80-89)
        </span>
        <span class="heat-badge-chip bg-white border">
          <span style="width: 12px; height: 12px; border-radius: 50%; background: #ef4444; display: inline-block;"></span>
          Alta Prioridade / Alto Ticket (Score 90+)
        </span>
      </div>
      <div class="text-muted small">
        <i class="bi bi-cursor me-1 text-primary"></i> Clique em qualquer ponto para ver detalhes ou iniciar o WhatsApp
      </div>
    </div>

    <!-- CONTAINER LEAFLET -->
    <div class="position-relative">
      <div id="mapaCalor" style="height: 440px; width: 100%; z-index: 1;"></div>
    </div>
  </div>

  <!-- RADAR DE BAIRROS (CLUSTERS DE REDE ÓPTICA) -->
  <div class="card border-0 shadow-sm mb-4">
    <div class="card-header bg-white py-3 border-bottom d-flex justify-content-between align-items-center">
      <div class="d-flex align-items-center gap-2">
        <div class="p-2 rounded-3" style="background: #e8f0fe; color: var(--dn-blue);">
          <i class="bi bi-geo-alt-fill fs-5"></i>
        </div>
        <div>
          <h5 class="fw-bold mb-0" style="color: var(--dn-blue-dark);">Clusters de Cobertura Óptica (Bairros com Clientes Ativos)</h5>
          <small class="text-muted">Selecione uma região para prospectar empresas e residências no mesmo nó de fibra da DigitalNet</small>
        </div>
      </div>
      <span class="badge py-2 px-3 rounded-pill bg-light text-dark border fw-semibold">
        <i class="bi bi-pin-map-fill text-primary me-1"></i> {{ clusters|length }} Regiões Mapeadas
      </span>
    </div>
    <div class="card-body p-3 bg-light bg-opacity-50">
      <div class="row g-3">
        {% for c in clusters %}
        <div class="col-xl-3 col-lg-4 col-md-6">
          <div class="dn-cluster-card {% if bairro_selecionado == c.bairro %}active-cluster{% endif %} h-100 d-flex flex-column">
            <div class="d-flex justify-content-between align-items-start mb-2">
              <h6 class="fw-bold mb-0" style="color: var(--dn-blue-deep);">{{ c.bairro }}</h6>
              <span class="badge py-1 px-2 rounded-pill" style="background: #e0f2fe; color: #0369a1; font-size: 0.7rem; font-weight: 700;">
                <i class="bi bi-check-circle-fill me-1 text-success"></i>{{ c.viabilidade_estimada }}
              </span>
            </div>
            
            <div class="small text-muted mb-2">
              <i class="bi bi-building text-secondary me-1"></i> {{ c.cidade }} &bull; {{ c.estado }}
            </div>

            <div class="d-flex justify-content-between text-muted small py-2 my-2 border-top border-bottom">
              <span><strong class="text-dark">{{ c.total_clientes }}</strong> clientes ativos</span>
              <span><strong class="text-primary">{{ c.total_leads }}</strong> leads na fila</span>
            </div>

            <div class="d-flex gap-2 mt-auto pt-2">
              <a href="{{ url_for('leads.index', bairro=c.bairro) }}" class="btn btn-sm btn-outline-secondary flex-fill" title="Ver leads deste bairro">
                <i class="bi bi-funnel me-1"></i> Filtrar
              </a>
              <form action="{{ url_for('leads.prospectar_regiao') }}" method="POST" class="d-inline flex-fill">
                <input type="hidden" name="bairro" value="{{ c.bairro }}">
                <input type="hidden" name="cidade" value="{{ c.cidade }}">
                <input type="hidden" name="count" value="4">
                <button type="submit" class="btn btn-sm btn-dn-blue w-100" title="Gerar mais leads vizinhos com IA">
                  <i class="bi bi-lightning-charge-fill text-warning me-1"></i> Prospectar
                </button>
              </form>
            </div>
          </div>
        </div>
        {% endfor %}
      </div>
    </div>
  </div>

  <!-- MÉTRICAS DO FUNIL DE LEADS (KPI CARDS DIGITALNET) -->
  <div class="row g-3 mb-4">
    <div class="col-xl-2 col-md-4 col-6">
      <div class="dn-kpi-card" style="border-top: 3px solid var(--dn-blue);">
        <span class="kpi-label">Total Leads</span>
        <div class="kpi-number" style="color: var(--dn-blue);">{{ total_leads }}</div>
      </div>
    </div>
    <div class="col-xl-2 col-md-4 col-6">
      <div class="dn-kpi-card" style="border-top: 3px solid #64748b;">
        <span class="kpi-label">Novos / Fila</span>
        <div class="kpi-number" style="color: #475569;">{{ total_novos }}</div>
      </div>
    </div>
    <div class="col-xl-2 col-md-4 col-6">
      <div class="dn-kpi-card" style="border-top: 3px solid var(--dn-yellow);">
        <span class="kpi-label">Opt-in Enviado</span>
        <div class="kpi-number" style="color: var(--dn-yellow-dark);">{{ total_optin_solicitado }}</div>
      </div>
    </div>
    <div class="col-xl-2 col-md-4 col-6">
      <div class="dn-kpi-card" style="border-top: 3px solid #0284c7;">
        <span class="kpi-label">Opt-in Aceito</span>
        <div class="kpi-number" style="color: #0284c7;">{{ total_optin_aceito }}</div>
      </div>
    </div>
    <div class="col-xl-2 col-md-4 col-6">
      <div class="dn-kpi-card" style="border-top: 3px solid #2563eb;">
        <span class="kpi-label">Proposta Enviada</span>
        <div class="kpi-number" style="color: #2563eb;">{{ total_proposta }}</div>
      </div>
    </div>
    <div class="col-xl-2 col-md-4 col-6">
      <div class="dn-kpi-card" style="border-top: 3px solid #10b981;">
        <span class="kpi-label">Convertidos</span>
        <div class="kpi-number" style="color: #059669;">{{ total_convertidos }}</div>
      </div>
    </div>
  </div>

  <!-- FILTROS E TABELA DE LEADS -->
  <div class="card border-0 shadow-sm mb-4">
    <div class="card-header bg-white py-3 border-bottom">
      <form method="GET" action="{{ url_for('leads.index') }}" class="row g-2 align-items-center">
        <div class="col-md-4">
          <div class="input-group input-group-sm">
            <span class="input-group-text bg-light text-muted border-end-0"><i class="bi bi-search"></i></span>
            <input type="text" name="busca" class="form-control border-start-0 bg-light" placeholder="Buscar por empresa, decisor, rua..." value="{{ busca }}">
          </div>
        </div>
        <div class="col-md-3">
          <select name="bairro" class="form-select form-select-sm bg-light">
            <option value="">Todos os Bairros</option>
            {% for c in clusters %}
            <option value="{{ c.bairro }}" {% if bairro_selecionado == c.bairro %}selected{% endif %}>{{ c.bairro }} ({{ c.total_clientes }} clientes)</option>
            {% endfor %}
          </select>
        </div>
        <div class="col-md-3">
          <select name="status" class="form-select form-select-sm bg-light">
            <option value="">Todos os Status</option>
            <option value="novo" {% if status_selecionado == 'novo' %}selected{% endif %}>Novo Lead</option>
            <option value="optin_solicitado" {% if status_selecionado == 'optin_solicitado' %}selected{% endif %}>Opt-in Solicitado</option>
            <option value="optin_aceito" {% if status_selecionado == 'optin_aceito' %}selected{% endif %}>Opt-in Aceito</option>
            <option value="proposta_enviada" {% if status_selecionado == 'proposta_enviada' %}selected{% endif %}>Proposta Enviada</option>
            <option value="convertido" {% if status_selecionado == 'convertido' %}selected{% endif %}>Convertido</option>
          </select>
        </div>
        <div class="col-md-2 d-flex gap-2">
          <button type="submit" class="btn btn-sm btn-dn-blue flex-fill">
            <i class="bi bi-funnel-fill me-1"></i> Filtrar
          </button>
          {% if busca or bairro_selecionado or status_selecionado %}
          <a href="{{ url_for('leads.index') }}" class="btn btn-sm btn-outline-secondary" title="Limpar filtros">
            <i class="bi bi-x-lg"></i>
          </a>
          {% endif %}
        </div>
      </form>
    </div>

    <div class="table-responsive">
      <table class="table table-hover align-middle mb-0">
        <thead class="dn-table-header">
          <tr>
            <th class="ps-3">Lead / Empresa</th>
            <th>Localização (MS)</th>
            <th>Plano Recomendado</th>
            <th>Operadora Atual</th>
            <th>Score</th>
            <th>Opt-in WhatsApp</th>
            <th>Status</th>
            <th class="text-end pe-3">Ações</th>
          </tr>
        </thead>
        <tbody>
          {% if leads %}
            {% for l in leads %}
            <tr>
              <td class="ps-3">
                <div class="fw-bold" style="color: var(--dn-blue-deep);">{{ l.empresa }}</div>
                <small class="text-muted">{{ l.nome }} {% if l.cargo %}&bull; <span class="text-secondary">{{ l.cargo }}</span>{% endif %}</small>
              </td>
              <td>
                <span class="badge bg-light text-dark border"><i class="bi bi-geo-alt-fill text-danger me-1"></i>{{ l.bairro }}</span>
                <div class="small text-muted mt-1">{{ l.logradouro or 'Área Central' }}, {{ l.numero or 'S/N' }}</div>
              </td>
              <td>
                <div class="small fw-bold" style="color: var(--dn-blue);">{{ l.plano_sugerido }}</div>
                <small class="text-muted">R$ {{ "%.2f"|format(l.valor_mensal_sugerido)|replace('.', ',') }}/mês</small>
              </td>
              <td>
                <span class="badge bg-secondary bg-opacity-10 text-dark border" style="font-size: 0.75rem;">{{ l.operadora_atual }}</span>
              </td>
              <td>
                <span class="badge {% if l.lead_score >= 90 %}bg-success{% elif l.lead_score >= 80 %}bg-primary{% else %}bg-warning text-dark{% endif %} px-2 py-1">
                  {{ l.lead_score }} pts
                </span>
              </td>
              <td>
                {% if l.optin_status == 'aceito' %}
                <span class="badge bg-success"><i class="bi bi-check-circle-fill me-1"></i>Opt-in Aceito</span>
                {% elif l.optin_status == 'recusado' %}
                <span class="badge bg-danger">Recusado</span>
                {% else %}
                <span class="badge bg-warning text-dark"><i class="bi bi-clock-history me-1"></i>Pendente</span>
                {% endif %}
              </td>
              <td>
                <span class="badge {{ l.status_badge_class }}">{{ l.status_label }}</span>
              </td>
              <td class="text-end pe-3">
                <div class="btn-group btn-group-sm">
                  {% if l.telefone and l.whatsapp_url != '#' %}
                  <a href="{{ l.whatsapp_url }}" target="_blank" class="btn btn-success" title="Iniciar Abordagem com Opt-in no WhatsApp Web">
                    <i class="bi bi-whatsapp"></i>
                  </a>
                  {% endif %}
                  <a href="{{ url_for('leads.detail', lead_id=l.id) }}" class="btn btn-dn-blue" title="Abrir Dossiê 360° e Quebra de Objeções">
                    <i class="bi bi-eye-fill me-1"></i> Dossiê
                  </a>
                </div>
              </td>
            </tr>
            {% endfor %}
          {% else %}
            <tr>
              <td colspan="8" class="text-center py-5 text-muted">
                <i class="bi bi-radar fs-1 d-block mb-3 text-secondary"></i>
                <p class="mb-2 fw-semibold text-dark">Nenhum lead encontrado para os filtros selecionados.</p>
                <small>Clique em <strong>"Nova Prospecção Geo"</strong> acima para mapear clientes em Campo Grande!</small>
              </td>
            </tr>
          {% endif %}
        </tbody>
      </table>
    </div>
  </div>

</div>

<!-- MODAL PROSPECTAR COM IA (TEMA DIGITALNET) -->
<div class="modal fade" id="modalProspectar" tabindex="-1" aria-labelledby="modalProspectarLabel" aria-hidden="true">
  <div class="modal-dialog">
    <div class="modal-content border-0 shadow-lg">
      <form action="{{ url_for('leads.prospectar_regiao') }}" method="POST">
        <div class="modal-header text-white" style="background: linear-gradient(135deg, var(--dn-blue-deep), var(--dn-blue));">
          <h5 class="modal-title" id="modalProspectarLabel">
            <i class="bi bi-radar me-2 text-warning"></i>Nova Prospecção Geo-Localizada
          </h5>
          <button type="button" class="btn-close btn-close-white" data-bs-dismiss="modal" aria-label="Fechar"></button>
        </div>
        <div class="modal-body p-4">
          <p class="small text-muted mb-3">
            O motor de IA identifica novos clientes potenciais no mesmo bairro onde a <strong>DigitalNet MS</strong> já possui rede óptica ativa, garantindo viabilidade e gerando o script anti-ban para WhatsApp.
          </p>

          <div class="mb-3">
            <label class="form-label small fw-bold text-dark">Bairro / Região em Campo Grande (MS)</label>
            <select name="bairro" class="form-select bg-light" required>
              <option value="Chácara Cachoeira">Chácara Cachoeira (Alta Densidade Empresarial / Clínicas)</option>
              <option value="Centro">Centro (Comércios, Escritórios e Contabilidades)</option>
              <option value="Santa Fé">Santa Fé (Boutiques, Estética e Consultórios)</option>
              <option value="Jardim dos Estados">Jardim dos Estados (Gastronomia e Escritórios)</option>
              <option value="Tiradentes">Tiradentes (Escolas, Academias e Varejo)</option>
              <option value="Vilas Boas">Vilas Boas (Comércio Local e Gastronomia)</option>
            </select>
          </div>

          <div class="mb-3">
            <label class="form-label small fw-bold text-dark">Nicho Comercial / Segmento</label>
            <input type="text" name="niche" class="form-control bg-light" value="Clínicas, Consultórios e Escritórios" required>
          </div>

          <div class="mb-3">
            <label class="form-label small fw-bold text-dark">Quantidade de Leads para Mapear</label>
            <select name="count" class="form-select bg-light">
              <option value="3">3 leads qualificados</option>
              <option value="5" selected>5 leads qualificados</option>
              <option value="8">8 leads qualificados</option>
            </select>
          </div>

          <div class="alert alert-warning border-warning bg-warning bg-opacity-10 py-2 small mb-0 d-flex align-items-center">
            <i class="bi bi-shield-check text-warning-emphasis fs-5 me-2"></i>
            <div>
              Cada lead virá com <strong>score de qualificação</strong>, <strong>dor mapeada</strong> e o <strong>script de opt-in de 1 clique</strong>.
            </div>
          </div>
        </div>
        <div class="modal-footer bg-light">
          <button type="button" class="btn btn-secondary btn-sm" data-bs-dismiss="modal">Cancelar</button>
          <button type="submit" class="btn btn-dn-blue btn-sm px-3 shadow-sm">
            <i class="bi bi-lightning-charge-fill text-warning me-1"></i> Iniciar Varredura de Leads
          </button>
        </div>
      </form>
    </div>
  </div>
</div>
{% endblock %}

{% block extra_js %}
<!-- Leaflet JS para Renderização do Mapa de Calor -->
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js" integrity="sha256-20nQCchB9co0qIjJZRGuk2/Z9VM+kNiyxNV1lvTlZBo=" crossorigin=""></script>
<script>
  // Dados passados pelo backend Flask
  const rawMapPoints = {{ map_points|tojson|safe }};
  const centroCG = [-20.4600, -54.5980];
  
  let mapInstance = null;
  let layerGroupFibra = null;
  let layerGroupLeads = null;
  let layerGroupHeat = null;

  function initMap() {
    const mapContainer = document.getElementById('mapaCalor');
    if (!mapContainer || typeof L === 'undefined') return;

    // Inicializa o mapa Leaflet
    mapInstance = L.map('mapaCalor', {
      center: centroCG,
      zoom: 13,
      zoomControl: true,
      scrollWheelZoom: false
    });

    // Camada de Azulejos (CartoDB Voyager - visual executivo e limpo)
    L.tileLayer('https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png', {
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> &copy; <a href="https://carto.com/attributions">CARTO</a>',
      subdomains: 'abcd',
      maxZoom: 19
    }).addTo(mapInstance);

    // Grupos de camadas
    layerGroupFibra = L.layerGroup().addTo(mapInstance);
    layerGroupLeads = L.layerGroup().addTo(mapInstance);
    layerGroupHeat = L.layerGroup().addTo(mapInstance);

    renderPoints();
  }

  function renderPoints() {
    if (!mapInstance) return;

    layerGroupFibra.clearLayers();
    layerGroupLeads.clearLayers();
    layerGroupHeat.clearLayers();

    rawMapPoints.forEach(pt => {
      if (pt.tipo === 'cluster_fibra') {
        // Círculo de calor térmico para rede ativa
        const raio = 380 + (pt.clientes * 100);
        const heatCircle = L.circle([pt.lat, pt.lng], {
          radius: raio,
          color: '#1b4f99',
          fillColor: '#1b4f99',
          fillOpacity: 0.18,
          weight: 1.5,
          dashArray: '4, 4'
        });
        layerGroupHeat.addLayer(heatCircle);

        // Marcador do Nó Óptico
        const iconFibra = L.divIcon({
          className: 'custom-pin-fibra-wrapper',
          html: `<div class="custom-pin-fibra" title="${pt.titulo}"><i class="bi bi-broadcast"></i></div>`,
          iconSize: [32, 32],
          iconAnchor: [16, 16]
        });

        const marker = L.marker([pt.lat, pt.lng], { icon: iconFibra });
        const popupContent = `
          <div style="width: 250px;">
            <div style="background: linear-gradient(135deg, #0f2d57, #1b4f99); color: white; padding: 12px 14px;">
              <small style="color: #fbbf24; text-transform: uppercase; font-weight: 700; font-size: 0.7rem;">Nó de Fibra DigitalNet</small>
              <h6 style="margin: 0; font-weight: 700; font-size: 1rem;">${pt.bairro}</h6>
            </div>
            <div style="padding: 12px 14px; background: white; font-size: 0.85rem;">
              <div style="display: flex; justify-content: space-between; margin-bottom: 6px;">
                <span style="color: #64748b;">Clientes Ativos:</span>
                <strong style="color: #0f172a;">${pt.clientes}</strong>
              </div>
              <div style="display: flex; justify-content: space-between; margin-bottom: 6px;">
                <span style="color: #64748b;">Leads Mapeados:</span>
                <strong style="color: #1b4f99;">${pt.leads}</strong>
              </div>
              <div style="display: flex; justify-content: space-between; margin-bottom: 10px;">
                <span style="color: #64748b;">Viabilidade:</span>
                <span style="color: #059669; font-weight: 700;">${pt.viabilidade}</span>
              </div>
              <a href="?bairro=${encodeURIComponent(pt.bairro)}" class="btn btn-sm btn-dn-blue w-100" style="padding: 4px 8px; font-size: 0.75rem;">
                <i class="bi bi-funnel me-1"></i> Filtrar este Bairro
              </a>
            </div>
          </div>
        `;
        marker.bindPopup(popupContent);
        layerGroupFibra.addLayer(marker);

      } else if (pt.tipo === 'lead_oportunidade') {
        // Círculo térmico (Amarelo ou Vermelho conforme score)
        const isHighScore = pt.score >= 90;
        const heatColor = isHighScore ? '#ef4444' : '#f59e0b';
        const heatRadius = 220 + (pt.score * 1.5);

        const leadHeat = L.circle([pt.lat, pt.lng], {
          radius: heatRadius,
          color: heatColor,
          fillColor: heatColor,
          fillOpacity: isHighScore ? 0.28 : 0.20,
          weight: 1
        });
        layerGroupHeat.addLayer(leadHeat);

        // Marcador do Lead
        const pinClass = isHighScore ? 'custom-pin-lead high-score' : 'custom-pin-lead';
        const iconLead = L.divIcon({
          className: 'custom-pin-lead-wrapper',
          html: `<div class="${pinClass}" title="${pt.titulo}"><i class="bi bi-building"></i></div>`,
          iconSize: [28, 28],
          iconAnchor: [14, 14]
        });

        const marker = L.marker([pt.lat, pt.lng], { icon: iconLead });
        const popupContent = `
          <div style="width: 270px;">
            <div style="background: ${isHighScore ? 'linear-gradient(135deg, #b91c1c, #ef4444)' : 'linear-gradient(135deg, #d97706, #f59e0b)'}; color: white; padding: 10px 14px;">
              <div style="display: flex; justify-content: space-between; align-items: center;">
                <small style="color: white; opacity: 0.85; font-size: 0.7rem; font-weight: 600;">Oportunidade</small>
                <span style="background: rgba(0,0,0,0.25); color: white; padding: 2px 8px; border-radius: 12px; font-size: 0.7rem; font-weight: 700;">Score: ${pt.score}</span>
              </div>
              <h6 style="margin: 2px 0 0 0; font-weight: 700; font-size: 0.95rem; color: white;">${pt.titulo}</h6>
            </div>
            <div style="padding: 12px 14px; background: white; font-size: 0.85rem;">
              <div style="color: #475569; margin-bottom: 6px; font-size: 0.8rem;">
                <i class="bi bi-person me-1"></i> ${pt.contato} ${pt.cargo ? '&bull; ' + pt.cargo : ''}
              </div>
              <div style="color: #64748b; margin-bottom: 8px; font-size: 0.75rem;">
                <i class="bi bi-geo-alt me-1 text-danger"></i> ${pt.endereco}
              </div>
              <div style="background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 6px; padding: 6px 10px; margin-bottom: 10px;">
                <div style="color: #1b4f99; font-weight: 700; font-size: 0.8rem;">${pt.plano}</div>
                <small style="color: #64748b;">${pt.valor} &bull; Operadora atual: <strong>${pt.operadora}</strong></small>
              </div>
              <div style="display: flex; gap: 6px;">
                ${pt.whatsapp_url !== '#' ? `
                  <a href="${pt.whatsapp_url}" target="_blank" class="btn btn-sm btn-success" style="flex: 1; font-size: 0.75rem; padding: 5px;">
                    <i class="bi bi-whatsapp me-1"></i> WhatsApp
                  </a>
                ` : ''}
                <a href="${pt.detail_url}" class="btn btn-sm btn-dn-blue" style="flex: 1; font-size: 0.75rem; padding: 5px;">
                  <i class="bi bi-eye me-1"></i> Dossiê
                </a>
              </div>
            </div>
          </div>
        `;
        marker.bindPopup(popupContent);
        layerGroupLeads.addLayer(marker);
      }
    });
  }

  function filtrarMapa(tipo) {
    document.querySelectorAll('.btn-group .btn').forEach(b => b.classList.remove('active'));
    
    if (tipo === 'todos') {
      document.getElementById('btnFiltroTodos').classList.add('active');
      if (!mapInstance.hasLayer(layerGroupFibra)) mapInstance.addLayer(layerGroupFibra);
      if (!mapInstance.hasLayer(layerGroupLeads)) mapInstance.addLayer(layerGroupLeads);
      if (!mapInstance.hasLayer(layerGroupHeat)) mapInstance.addLayer(layerGroupHeat);
    } else if (tipo === 'fibra') {
      document.getElementById('btnFiltroFibra').classList.add('active');
      if (!mapInstance.hasLayer(layerGroupFibra)) mapInstance.addLayer(layerGroupFibra);
      if (mapInstance.hasLayer(layerGroupLeads)) mapInstance.removeLayer(layerGroupLeads);
    } else if (tipo === 'leads') {
      document.getElementById('btnFiltroLeads').classList.add('active');
      if (mapInstance.hasLayer(layerGroupFibra)) mapInstance.removeLayer(layerGroupFibra);
      if (!mapInstance.hasLayer(layerGroupLeads)) mapInstance.addLayer(layerGroupLeads);
    }
  }

  function centralizarCampoGrande() {
    if (mapInstance) {
      mapInstance.setView(centroCG, 13);
    }
  }

  // Inicializa quando a página carregar
  document.addEventListener('DOMContentLoaded', function() {
    initMap();
  });
</script>
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

# --- migrations/versions/a1b2c3d4e5f6_add_leads_table.py ---
cat > 'migrations/versions/a1b2c3d4e5f6_add_leads_table.py' <<'OMNI_EOF'
"""add_leads_table

Revision ID: a1b2c3d4e5f6
Revises: 99d1cc5b3cb2
Create Date: 2026-10-08 15:35:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'a1b2c3d4e5f6'
down_revision = '99d1cc5b3cb2'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table('leads',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('nome', sa.String(length=120), nullable=False),
    sa.Column('empresa', sa.String(length=150), nullable=False),
    sa.Column('cargo', sa.String(length=100), nullable=True),
    sa.Column('telefone', sa.String(length=30), nullable=True),
    sa.Column('email', sa.String(length=120), nullable=True),
    sa.Column('documento', sa.String(length=30), nullable=True),
    sa.Column('niche', sa.String(length=100), nullable=True),
    sa.Column('cep', sa.String(length=15), nullable=True),
    sa.Column('logradouro', sa.String(length=150), nullable=True),
    sa.Column('numero', sa.String(length=20), nullable=True),
    sa.Column('complemento', sa.String(length=50), nullable=True),
    sa.Column('bairro', sa.String(length=80), nullable=False),
    sa.Column('cidade', sa.String(length=80), nullable=False),
    sa.Column('estado', sa.String(length=2), nullable=False),
    sa.Column('cliente_referencia_id', sa.Integer(), nullable=True),
    sa.Column('status', sa.String(length=30), nullable=False),
    sa.Column('optin_status', sa.String(length=20), nullable=False),
    sa.Column('operadora_atual', sa.String(length=80), nullable=True),
    sa.Column('plano_sugerido', sa.String(length=120), nullable=True),
    sa.Column('valor_mensal_sugerido', sa.Float(), nullable=False),
    sa.Column('lead_score', sa.Integer(), nullable=False),
    sa.Column('dor_principal', sa.Text(), nullable=True),
    sa.Column('icebreaker_optin', sa.Text(), nullable=True),
    sa.Column('dossie_comercial', sa.Text(), nullable=True),
    sa.Column('observacoes', sa.Text(), nullable=True),
    sa.Column('cliente_convertido_id', sa.Integer(), nullable=True),
    sa.Column('created_at', sa.DateTime(), nullable=False),
    sa.Column('updated_at', sa.DateTime(), nullable=False),
    sa.ForeignKeyConstraint(['cliente_referencia_id'], ['clientes.id'], ondelete='SET NULL'),
    sa.ForeignKeyConstraint(['cliente_convertido_id'], ['clientes.id'], ondelete='SET NULL'),
    sa.PrimaryKeyConstraint('id')
    )
    with op.batch_alter_table('leads', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_leads_nome'), ['nome'], unique=False)
        batch_op.create_index(batch_op.f('ix_leads_empresa'), ['empresa'], unique=False)
        batch_op.create_index(batch_op.f('ix_leads_bairro'), ['bairro'], unique=False)
        batch_op.create_index(batch_op.f('ix_leads_cidade'), ['cidade'], unique=False)
        batch_op.create_index(batch_op.f('ix_leads_status'), ['status'], unique=False)
        batch_op.create_index(batch_op.f('ix_leads_optin_status'), ['optin_status'], unique=False)
        batch_op.create_index(batch_op.f('ix_leads_cliente_referencia_id'), ['cliente_referencia_id'], unique=False)
        batch_op.create_index(batch_op.f('ix_leads_cliente_convertido_id'), ['cliente_convertido_id'], unique=False)


def downgrade():
    with op.batch_alter_table('leads', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_leads_cliente_convertido_id'))
        batch_op.drop_index(batch_op.f('ix_leads_cliente_referencia_id'))
        batch_op.drop_index(batch_op.f('ix_leads_optin_status'))
        batch_op.drop_index(batch_op.f('ix_leads_status'))
        batch_op.drop_index(batch_op.f('ix_leads_cidade'))
        batch_op.drop_index(batch_op.f('ix_leads_bairro'))
        batch_op.drop_index(batch_op.f('ix_leads_empresa'))
        batch_op.drop_index(batch_op.f('ix_leads_nome'))

    op.drop_table('leads')
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

# --- tests/test_leads.py ---
cat > 'tests/test_leads.py' <<'OMNI_EOF'
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
