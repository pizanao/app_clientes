#!/usr/bin/env bash
# ==============================================================================
# Script de Criação e Configuração Automatizada - OmniGestão (Linux)
# ==============================================================================
# Este script cria toda a estrutura de diretórios, todos os arquivos fonte,
# instala as dependências Python em ambiente virtual (.venv), executa as
# migrações do banco de dados e popula com dados de teste (seed).
#
# Uso em uma pasta vazia:
#   chmod +x setup.sh
#   ./setup.sh
# ==============================================================================

set -e

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

echo -e "${GREEN}✓ Python 3 encontrado: $(python3 --version)${NC}"

# 2. Criação da estrutura de pastas
echo -e "\n${YELLOW}[2/6] Criando a estrutura de diretórios...${NC}"
mkdir -p app/models \
         app/forms \
         app/routes \
         app/utils \
         app/static/css \
         app/static/js \
         app/templates/auth \
         app/templates/dashboard \
         app/templates/clientes \
         app/templates/pedidos \
         app/templates/errors \
         instance \
         tests

echo -e "${GREEN}✓ Estrutura de pastas criada com sucesso.${NC}"

# 3. Criação dos arquivos do projeto
echo -e "\n${YELLOW}[3/6] Criando arquivos de código-fonte...${NC}"

# --- requirements.txt ---
cat <<'EOF' > requirements.txt
alembic>=1.13.0
blinker>=1.8.0
cachelib>=0.13.0
click>=8.1.0
dnspython>=2.6.0
email-validator>=2.1.0
flask>=3.0.0
flask-login>=0.6.3
flask-migrate>=4.0.7
flask-session>=0.8.0
flask-sqlalchemy>=3.1.1
flask-wtf>=1.2.1
idna>=3.7
itsdangerous>=2.2.0
jinja2>=3.1.4
markupsafe>=2.1.5
msgspec>=0.18.6
python-dotenv>=1.0.1
sqlalchemy>=2.0.30
typing-extensions>=4.12.0
werkzeug>=3.0.3
wtforms>=3.1.2
EOF

# --- .env ---
cat <<'EOF' > .env
FLASK_APP=wsgi.py
FLASK_DEBUG=1
SECRET_KEY=dev-secret-key-super-secure-change-in-prod-12345
DATABASE_URL=sqlite:///app_clientes.db
EOF

# --- .env.example ---
cat <<'EOF' > .env.example
FLASK_APP=wsgi.py
FLASK_DEBUG=1
SECRET_KEY=sua-chave-secreta-muito-segura-aqui
DATABASE_URL=sqlite:///app_clientes.db
EOF

# --- .gitignore ---
cat <<'EOF' > .gitignore
__pycache__/
*.py[cod]
*$py.class
*.so
.venv/
instance/
*.db
*.sqlite3
.env
.vscode/
.idea/
EOF

# --- wsgi.py ---
cat <<'EOF' > wsgi.py
import os
from app import create_app
from app.extensions import db
from app.models import User, Cliente, Pedido

app = create_app()

@app.shell_context_processor
def make_shell_context():
    return {
        'db': db,
        'User': User,
        'Cliente': Cliente,
        'Pedido': Pedido
    }

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    app.run(host='0.0.0.0', port=port, debug=True)
EOF

# --- app/__init__.py ---
cat <<'EOF' > app/__init__.py
import os
from flask import Flask, render_template
from app.config import Config
from app.extensions import db, migrate, login_manager, sess
from app.utils.filters import init_filters

def create_app(config_class=Config):
    app = Flask(__name__)
    app.config.from_object(config_class)

    # Initialize extensions
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
EOF

# --- app/config.py ---
cat <<'EOF' > app/config.py
import os
from datetime import timedelta
from cachelib.file import FileSystemCache

BASE_DIR = os.path.abspath(os.path.dirname(os.path.dirname(__file__)))
INSTANCE_DIR = os.path.join(BASE_DIR, 'instance')
os.makedirs(INSTANCE_DIR, exist_ok=True)

class Config:
    SECRET_KEY = os.environ.get('SECRET_KEY', 'dev-secret-key-super-secure-change-in-prod-12345')
    _raw_db_url = os.environ.get('DATABASE_URL')
    if not _raw_db_url:
        SQLALCHEMY_DATABASE_URI = f"sqlite:///{os.path.join(INSTANCE_DIR, 'app_clientes.db')}"
    elif _raw_db_url.startswith('sqlite:///instance/'):
        SQLALCHEMY_DATABASE_URI = _raw_db_url.replace('sqlite:///instance/', 'sqlite:///', 1)
    else:
        SQLALCHEMY_DATABASE_URI = _raw_db_url
    SQLALCHEMY_TRACK_MODIFICATIONS = False

    # Flask-Session using CacheLib FileSystemCache
    SESSION_TYPE = 'cachelib'
    SESSION_CACHELIB = FileSystemCache(cache_dir=os.path.join(INSTANCE_DIR, 'flask_sessions'), threshold=1000)
    SESSION_PERMANENT = True
    PERMANENT_SESSION_LIFETIME = timedelta(days=7)
    WTF_CSRF_ENABLED = True
EOF

# --- app/extensions.py ---
cat <<'EOF' > app/extensions.py
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
EOF

# --- app/cli.py ---
cat <<'EOF' > app/cli.py
import click
from datetime import datetime, timedelta
from flask.cli import with_appcontext
from app.extensions import db
from app.models.user import User
from app.models.cliente import Cliente
from app.models.pedido import Pedido

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
    @click.option('--password', default='admin123', help='Senha do admin.')
    @with_appcontext
    def create_admin_command(username, email, password):
        """Cria um usuário administrador inicial."""
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
        click.echo(f'Administrador "{username}" criado com sucesso! Senha: {password}')

    @app.cli.command('seed')
    @with_appcontext
    def seed_command():
        """Popula o banco com usuário admin e dados fictícios de exemplo."""
        db.create_all()

        admin = User.query.filter_by(username='admin').first()
        if not admin:
            admin = User(
                nome='Administrador Master',
                username='admin',
                email='admin@exemplo.com',
                ativo=True
            )
            admin.set_password('admin123')
            db.session.add(admin)
            click.echo('Criado usuário admin padrão (admin / admin123).')

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
                    descricao='Lote de suprimentos de informática (50 unidades cabo de rede Cat6, 10 switches 8 portas gigabit).',
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
            click.echo('Clientes e Pedidos de exemplo cadastrados com sucesso!')

        db.session.commit()
        click.echo('Processo de Seed finalizado!')
EOF

# --- app/models/__init__.py ---
cat <<'EOF' > app/models/__init__.py
from app.models.user import User
from app.models.cliente import Cliente
from app.models.pedido import Pedido

__all__ = ['User', 'Cliente', 'Pedido']
EOF

# --- app/models/user.py ---
cat <<'EOF' > app/models/user.py
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
EOF

# --- app/models/cliente.py ---
cat <<'EOF' > app/models/cliente.py
from datetime import datetime
from app.extensions import db

class Cliente(db.Model):
    __tablename__ = 'clientes'

    id = db.Column(db.Integer, primary_key=True)
    nome = db.Column(db.String(120), nullable=False, index=True)
    email = db.Column(db.String(120), nullable=False, index=True)
    telefone = db.Column(db.String(30), nullable=True)
    documento = db.Column(db.String(30), nullable=True, index=True)
    cep = db.Column(db.String(15), nullable=True)
    logradouro = db.Column(db.String(150), nullable=True)
    numero = db.Column(db.String(20), nullable=True)
    complemento = db.Column(db.String(50), nullable=True)
    bairro = db.Column(db.String(80), nullable=True)
    cidade = db.Column(db.String(80), nullable=True)
    estado = db.Column(db.String(2), nullable=True)
    ativo = db.Column(db.Boolean, default=True, nullable=False)
    observacoes = db.Column(db.Text, nullable=True)
    
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

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
EOF

# --- app/models/pedido.py ---
cat <<'EOF' > app/models/pedido.py
from datetime import datetime
from app.extensions import db

class Pedido(db.Model):
    __tablename__ = 'pedidos'

    id = db.Column(db.Integer, primary_key=True)
    numero_pedido = db.Column(db.String(30), unique=True, nullable=False, index=True)
    cliente_id = db.Column(db.Integer, db.ForeignKey('clientes.id', ondelete='CASCADE'), nullable=False, index=True)
    data_pedido = db.Column(db.DateTime, default=datetime.utcnow, nullable=False, index=True)
    status = db.Column(db.String(25), default='pendente', nullable=False, index=True)
    metodo_pagamento = db.Column(db.String(30), default='pix', nullable=False)
    valor_total = db.Column(db.Float, default=0.0, nullable=False)
    descricao = db.Column(db.Text, nullable=False)
    observacoes = db.Column(db.Text, nullable=True)

    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

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

    def __repr__(self):
        return f'<Pedido {self.numero_pedido} - Cliente {self.cliente_id}>'
EOF

# --- app/forms/__init__.py ---
cat <<'EOF' > app/forms/__init__.py
from app.forms.auth_forms import LoginForm, RegisterForm
from app.forms.cliente_forms import ClienteForm
from app.forms.pedido_forms import PedidoForm

__all__ = ['LoginForm', 'RegisterForm', 'ClienteForm', 'PedidoForm']
EOF

# --- app/forms/auth_forms.py ---
cat <<'EOF' > app/forms/auth_forms.py
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
EOF

# --- app/forms/cliente_forms.py ---
cat <<'EOF' > app/forms/cliente_forms.py
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
EOF

# --- app/forms/pedido_forms.py ---
cat <<'EOF' > app/forms/pedido_forms.py
from datetime import datetime
from flask_wtf import FlaskForm
from wtforms import StringField, SelectField, TextAreaField, DecimalField, DateTimeLocalField, SubmitField
from wtforms.validators import DataRequired, NumberRange, Optional, Length

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
    valor_total = DecimalField('Valor Total (R$) *', places=2, validators=[
        DataRequired(message='Informe o valor total.'),
        NumberRange(min=0.01, message='O valor deve ser maior que zero.')
    ])
    descricao = TextAreaField('Descrição / Itens do Pedido *', validators=[
        DataRequired(message='Descreva os produtos ou serviços inclusos.'),
        Length(min=5, message='A descrição deve ter pelo menos 5 caracteres.')
    ])
    observacoes = TextAreaField('Observações Adicionais', validators=[
        Optional()
    ])
    submit = SubmitField('Salvar Pedido')
EOF

# --- app/utils/filters.py ---
cat <<'EOF' > app/utils/filters.py
def format_currency(value):
    if value is None:
        return "R$ 0,00"
    try:
        val = float(value)
        return f"R$ {val:,.2f}".replace(',', 'X').replace('.', ',').replace('X', '.')
    except (ValueError, TypeError):
        return str(value)

def format_date(value, fmt='%d/%m/%Y %H:%M'):
    if not value:
        return "-"
    try:
        return value.strftime(fmt)
    except Exception:
        return str(value)

def format_date_short(value):
    return format_date(value, fmt='%d/%m/%Y')

def format_document(doc):
    if not doc:
        return "-"
    digits = ''.join(filter(str.isdigit, str(doc)))
    if len(digits) == 11:
        return f"{digits[:3]}.{digits[3:6]}.{digits[6:9]}-{digits[9:]}"
    elif len(digits) == 14:
        return f"{digits[:2]}.{digits[2:5]}.{digits[5:8]}/{digits[8:12]}-{digits[12:]}"
    return doc

def format_phone(phone):
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
EOF

# --- app/utils/__init__.py ---
cat <<'EOF' > app/utils/__init__.py
from app.utils.filters import init_filters

__all__ = ['init_filters']
EOF

# --- app/routes/__init__.py ---
cat <<'EOF' > app/routes/__init__.py
from app.routes.auth import auth_bp
from app.routes.main import main_bp
from app.routes.clientes import clientes_bp
from app.routes.pedidos import pedidos_bp

__all__ = ['auth_bp', 'main_bp', 'clientes_bp', 'pedidos_bp']
EOF

# --- app/routes/auth.py ---
cat <<'EOF' > app/routes/auth.py
from flask import Blueprint, render_template, redirect, url_for, flash, request
from flask_login import login_user, logout_user, login_required, current_user
from app.extensions import db
from app.models.user import User
from app.forms.auth_forms import LoginForm, RegisterForm

auth_bp = Blueprint('auth', __name__, url_prefix='/auth')

@auth_bp.route('/login', methods=['GET', 'POST'])
def login():
    if current_user.is_authenticated:
        return redirect(url_for('main.dashboard'))

    form = LoginForm()
    if form.validate_on_submit():
        login_input = form.login.data.strip()
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
            if not next_page or not next_page.startswith('/'):
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
EOF

# --- app/routes/main.py ---
cat <<'EOF' > app/routes/main.py
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
    total_clientes = Cliente.query.count()
    clientes_ativos = Cliente.query.filter_by(ativo=True).count()
    total_pedidos = Pedido.query.count()

    pedidos_pendentes = Pedido.query.filter_by(status='pendente').count()
    pedidos_processando = Pedido.query.filter_by(status='processando').count()
    pedidos_concluidos = Pedido.query.filter_by(status='concluido').count()
    pedidos_cancelados = Pedido.query.filter_by(status='cancelado').count()

    faturamento_total = db.session.query(
        func.coalesce(func.sum(Pedido.valor_total), 0.0)
    ).filter(Pedido.status != 'cancelado').scalar() or 0.0

    faturamento_concluido = db.session.query(
        func.coalesce(func.sum(Pedido.valor_total), 0.0)
    ).filter(Pedido.status == 'concluido').scalar() or 0.0

    ticket_medio = (faturamento_total / total_pedidos) if total_pedidos > 0 else 0.0

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
EOF

# --- app/routes/clientes.py ---
cat <<'EOF' > app/routes/clientes.py
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
EOF

# --- app/routes/pedidos.py ---
cat <<'EOF' > app/routes/pedidos.py
from datetime import datetime
from flask import Blueprint, render_template, redirect, url_for, flash, request
from flask_login import login_required
from sqlalchemy import or_
from app.extensions import db
from app.models.cliente import Cliente
from app.models.pedido import Pedido
from app.forms.pedido_forms import PedidoForm

pedidos_bp = Blueprint('pedidos', __name__, url_prefix='/pedidos')

def gerar_numero_pedido():
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

@pedidos_bp.route('/')
@login_required
def index():
    search = request.args.get('q', '').strip()
    status_filter = request.args.get('status', 'todos')
    cliente_filter = request.args.get('cliente_id', type=int)

    query = Pedido.query.join(Cliente)

    if search:
        search_term = f"%{search}%"
        query = query.filter(
            or_(
                Pedido.numero_pedido.ilike(search_term),
                Pedido.descricao.ilike(search_term),
                Cliente.nome.ilike(search_term)
            )
        )

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

    preselected_cliente_id = request.args.get('cliente_id', type=int)
    if request.method == 'GET':
        if preselected_cliente_id and any(c.id == preselected_cliente_id for c in clientes):
            form.cliente_id.data = preselected_cliente_id
        form.numero_pedido.data = gerar_numero_pedido()
        form.data_pedido.data = datetime.now()

    if form.validate_on_submit():
        existente = Pedido.query.filter_by(numero_pedido=form.numero_pedido.data.strip()).first()
        if existente:
            flash(f'O número de pedido "{form.numero_pedido.data}" já existe. Geramos outro para você.', 'warning')
            form.numero_pedido.data = gerar_numero_pedido()
            return render_template('pedidos/form.html', form=form, titulo='Novo Pedido', acao='Cadastrar')

        pedido = Pedido(
            cliente_id=form.cliente_id.data,
            numero_pedido=form.numero_pedido.data.strip().upper(),
            data_pedido=form.data_pedido.data,
            status=form.status.data,
            metodo_pagamento=form.metodo_pagamento.data,
            valor_total=float(form.valor_total.data),
            descricao=form.descricao.data.strip(),
            observacoes=form.observacoes.data.strip() if form.observacoes.data else None
        )
        db.session.add(pedido)
        db.session.commit()

        flash(f'Pedido #{pedido.numero_pedido} criado com sucesso!', 'success')
        return redirect(url_for('pedidos.detalhe', id=pedido.id))

    return render_template('pedidos/form.html', form=form, titulo='Novo Pedido', acao='Cadastrar')

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

    if form.validate_on_submit():
        num_novo = form.numero_pedido.data.strip().upper()
        if num_novo != pedido.numero_pedido:
            existente = Pedido.query.filter_by(numero_pedido=num_novo).first()
            if existente:
                flash(f'Já existe outro pedido com o número {num_novo}.', 'danger')
                return render_template('pedidos/form.html', form=form, pedido=pedido, titulo='Editar Pedido', acao='Salvar Alterações')

        pedido.cliente_id = form.cliente_id.data
        pedido.numero_pedido = num_novo
        pedido.data_pedido = form.data_pedido.data
        pedido.status = form.status.data
        pedido.metodo_pagamento = form.metodo_pagamento.data
        pedido.valor_total = float(form.valor_total.data)
        pedido.descricao = form.descricao.data.strip()
        pedido.observacoes = form.observacoes.data.strip() if form.observacoes.data else None

        db.session.commit()
        flash(f'Pedido #{pedido.numero_pedido} atualizado com sucesso!', 'success')
        return redirect(url_for('pedidos.detalhe', id=pedido.id))

    return render_template('pedidos/form.html', form=form, pedido=pedido, titulo='Editar Pedido', acao='Salvar Alterações')

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
EOF

# --- app/static/css/style.css ---
cat <<'EOF' > app/static/css/style.css
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
EOF

# --- app/static/js/main.js ---
cat <<'EOF' > app/static/js/main.js
document.addEventListener('DOMContentLoaded', function () {
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

  const alerts = document.querySelectorAll('.alert-dismissible');
  alerts.forEach(function (alert) {
    setTimeout(function () {
      const bsAlert = bootstrap.Alert.getOrCreateInstance(alert);
      if (bsAlert) {
        bsAlert.close();
      }
    }, 6000);
  });

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

  const docInput = document.getElementById('documento');
  if (docInput) {
    docInput.addEventListener('input', function (e) {
      let v = e.target.value.replace(/\D/g, '');
      if (v.length <= 11) {
        v = v.replace(/(\d{3})(\d)/, '$1.$2');
        v = v.replace(/(\d{3})(\d)/, '$1.$2');
        v = v.replace(/(\d{3})(\d{1,2})$/, '$1-$2');
      } else {
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
        v = v.replace(/^(\d{2})(\d{5})(\d{4})$/, '($1) $2-$3');
      } else if (v.length > 5) {
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

  const tooltipTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="tooltip"]'));
  tooltipTriggerList.map(function (tooltipTriggerEl) {
    return new bootstrap.Tooltip(tooltipTriggerEl);
  });
});
EOF

# --- app/templates/base.html ---
cat <<'EOF' > app/templates/base.html
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{% block title %}Gestão de Clientes e Pedidos{% endblock %}</title>

  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&display=swap" rel="stylesheet">

  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css">
  <link rel="stylesheet" href="{{ url_for('static', filename='css/style.css') }}">
  {% block extra_css %}{% endblock %}
</head>
<body>

  <div class="sidebar-backdrop" id="sidebarBackdrop"></div>

  <div class="app-wrapper">
    <aside class="sidebar" id="sidebar">
      <div class="sidebar-header">
        <a href="{{ url_for('main.dashboard') }}" class="brand-logo">
          <div class="brand-icon">
            <i class="bi bi-layers-fill"></i>
          </div>
          <div>
            <div style="line-height: 1.1;">GestãoNET</div>
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

    <div class="main-content">
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

  <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"></script>
  <script src="{{ url_for('static', filename='js/main.js') }}"></script>
  {% block extra_js %}{% endblock %}
</body>
</html>
EOF

# --- app/templates/auth/login.html ---
cat <<'EOF' > app/templates/auth/login.html
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Login - GestãoNET</title>
  
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
EOF

# --- app/templates/auth/register.html ---
cat <<'EOF' > app/templates/auth/register.html
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Cadastrar Usuário - GestãoNET</title>
  
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
EOF

# --- app/templates/dashboard/index.html ---
cat <<'EOF' > app/templates/dashboard/index.html
{% extends "base.html" %}

{% block title %}Dashboard - GestãoNET{% endblock %}

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

<div class="row g-4">
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
EOF

# --- app/templates/clientes/index.html ---
cat <<'EOF' > app/templates/clientes/index.html
{% extends "base.html" %}

{% block title %}Clientes - GestãoNET{% endblock %}

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
EOF

# --- app/templates/clientes/form.html ---
cat <<'EOF' > app/templates/clientes/form.html
{% extends "base.html" %}

{% block title %}{{ titulo }} - GestãoNET{% endblock %}

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
EOF

# --- app/templates/clientes/detail.html ---
cat <<'EOF' > app/templates/clientes/detail.html
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

<div class="row g-4 mb-4">
  <div class="col-lg-4">
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
EOF

# --- app/templates/pedidos/index.html ---
cat <<'EOF' > app/templates/pedidos/index.html
{% extends "base.html" %}

{% block title %}Pedidos - GestãoNET{% endblock %}

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
            </td>
            <td>
              <div class="d-flex align-items-center gap-2">
                <a href="{{ url_for('clientes.detalhe', id=pedido.cliente.id) }}" class="text-dark fw-semibold text-decoration-none text-truncate" style="max-width: 220px;">
                  {{ pedido.cliente.nome }}
                </a>
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
EOF

# --- app/templates/pedidos/form.html ---
cat <<'EOF' > app/templates/pedidos/form.html
{% extends "base.html" %}

{% block title %}{{ titulo }} - GestãoNET{% endblock %}

{% block content %}
<div class="mb-4">
  <nav aria-label="breadcrumb">
    <ol class="breadcrumb small mb-1">
      <li class="breadcrumb-item"><a href="{{ url_for('pedidos.index') }}" class="text-decoration-none">Pedidos</a></li>
      <li class="breadcrumb-item active" aria-current="page">{{ titulo }}</li>
    </ol>
  </nav>
  <div class="d-flex align-items-center justify-content-between">
    <h2 class="fw-bold mb-0 text-dark">{{ titulo }}</h2>
    <a href="{{ url_for('pedidos.index') }}" class="btn btn-outline-secondary btn-sm">
      <i class="bi bi-arrow-left"></i> Voltar à Lista
    </a>
  </div>
</div>

<div class="row justify-content-center">
  <div class="col-lg-9">
    <form method="POST" novalidate>
      {{ form.hidden_tag() }}

      <div class="card-custom p-4 mb-4 bg-white">
        <h5 class="fw-bold text-dark mb-3 pb-2 border-bottom d-flex align-items-center gap-2">
          <i class="bi bi-receipt text-primary"></i> Dados Principais do Pedido
        </h5>

        <div class="row g-3">
          <div class="col-md-8">
            <label for="cliente_id" class="form-label">{{ form.cliente_id.label.text }}</label>
            {{ form.cliente_id(class="form-select" + (" is-invalid" if form.cliente_id.errors else "")) }}
            {% for error in form.cliente_id.errors %}
              <div class="invalid-feedback">{{ error }}</div>
            {% endfor %}
            <small class="text-muted" style="font-size: 0.75rem;">
              Não encontrou o cliente? <a href="{{ url_for('clientes.novo') }}" target="_blank">Cadastre um novo aqui</a>
            </small>
          </div>

          <div class="col-md-4">
            <label for="numero_pedido" class="form-label">{{ form.numero_pedido.label.text }}</label>
            {{ form.numero_pedido(class="form-control" + (" is-invalid" if form.numero_pedido.errors else ""), placeholder="PED-2026-0001") }}
            {% for error in form.numero_pedido.errors %}
              <div class="invalid-feedback">{{ error }}</div>
            {% endfor %}
          </div>

          <div class="col-md-4">
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

          <div class="col-md-12">
            <label for="valor_total" class="form-label">{{ form.valor_total.label.text }}</label>
            <div class="input-group">
              <span class="input-group-text bg-light fw-bold">R$</span>
              {{ form.valor_total(class="form-control" + (" is-invalid" if form.valor_total.errors else ""), placeholder="0.00", step="0.01") }}
              {% for error in form.valor_total.errors %}
                <div class="invalid-feedback">{{ error }}</div>
              {% endfor %}
            </div>
          </div>
        </div>
      </div>

      <div class="card-custom p-4 mb-4 bg-white">
        <h5 class="fw-bold text-dark mb-3 pb-2 border-bottom d-flex align-items-center gap-2">
          <i class="bi bi-box-seam text-info"></i> Detalhes dos Itens & Descrição
        </h5>

        <div class="mb-3">
          <label for="descricao" class="form-label">{{ form.descricao.label.text }}</label>
          {{ form.descricao(class="form-control" + (" is-invalid" if form.descricao.errors else ""), rows=4, placeholder="Descreva os produtos vendidos, serviços prestados, quantidades, especificações...") }}
          {% for error in form.descricao.errors %}
            <div class="invalid-feedback">{{ error }}</div>
          {% endfor %}
        </div>

        <div class="mb-0">
          <label for="observacoes" class="form-label">{{ form.observacoes.label.text }}</label>
          {{ form.observacoes(class="form-control" + (" is-invalid" if form.observacoes.errors else ""), rows=3, placeholder="Observações de entrega, termos de pagamento, notas de garantia...") }}
          {% for error in form.observacoes.errors %}
            <div class="invalid-feedback">{{ error }}</div>
          {% endfor %}
        </div>
      </div>

      <div class="d-flex align-items-center justify-content-end gap-2 mb-5">
        <a href="{{ url_for('pedidos.index') }}" class="btn btn-light-custom px-4">Cancelar</a>
        <button type="submit" class="btn btn-primary-custom px-4">
          <i class="bi bi-check-lg"></i> {{ acao }}
        </button>
      </div>
    </form>
  </div>
</div>
{% endblock %}
EOF

# --- app/templates/pedidos/detail.html ---
cat <<'EOF' > app/templates/pedidos/detail.html
{% extends "base.html" %}

{% block title %}Pedido #{{ pedido.numero_pedido }} - GestãoNET{% endblock %}

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
      <div class="d-flex flex-column flex-md-row justify-content-between align-items-start pb-4 border-bottom mb-4 gap-3">
        <div>
          <div class="d-flex align-items-center gap-2 mb-2">
            <div class="brand-icon" style="width: 36px; height: 36px; font-size: 1.1rem;">
              <i class="bi bi-layers-fill"></i>
            </div>
            <h4 class="fw-bold mb-0 text-dark">GestãoNET</h4>
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

      <div class="mb-4">
        <h6 class="text-uppercase text-muted fw-bold small mb-2">Itens / Descrição dos Serviços e Produtos</h6>
        <div class="p-3 bg-light rounded-3 border">
          <p class="mb-0 text-dark" style="white-space: pre-line;">{{ pedido.descricao }}</p>
        </div>
      </div>

      {% if pedido.observacoes %}
        <div class="mb-4">
          <h6 class="text-uppercase text-muted fw-bold small mb-2">Observações Adicionais</h6>
          <div class="p-3 bg-white border rounded-3 text-secondary small">
            <p class="mb-0" style="white-space: pre-line;">{{ pedido.observacoes }}</p>
          </div>
        </div>
      {% endif %}

      <div class="pt-4 border-top text-center text-muted small">
        <p class="mb-0">Documento gerado automaticamente pelo sistema GestãoNET.</p>
      </div>
    </div>
  </div>
</div>
{% endblock %}
EOF

# --- app/templates/errors/404.html ---
cat <<'EOF' > app/templates/errors/404.html
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
EOF

# --- app/templates/errors/500.html ---
cat <<'EOF' > app/templates/errors/500.html
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
EOF

# --- tests/test_app.py ---
cat <<'EOF' > tests/test_app.py
import unittest
from app import create_app
from app.config import Config
from app.extensions import db
from app.models.user import User
from app.models.cliente import Cliente
from app.models.pedido import Pedido

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

        res_login = self.login(username='novousuario', password='secretpassword')
        self.assertEqual(res_login.status_code, 200)
        self.assertIn(b'Painel de Controle', res_login.data)

    def test_cliente_crud(self):
        self.login()

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

        res_detail = self.client.get(f'/clientes/{cliente.id}')
        self.assertEqual(res_detail.status_code, 200)
        self.assertIn(b'Empresa Alpha Tech Ltda', res_detail.data)

        res_edit = self.client.post(f'/clientes/{cliente.id}/editar', data={
            'nome': 'Empresa Alpha Tech Modificada',
            'email': 'alpha_editada@tech.com',
            'telefone': '(11) 99999-0000',
            'ativo': 'y'
        }, follow_redirects=True)
        self.assertEqual(res_edit.status_code, 200)
        self.assertIn(b'Empresa Alpha Tech Modificada', res_edit.data)

        res_del = self.client.post(f'/clientes/{cliente.id}/excluir', follow_redirects=True)
        self.assertEqual(res_del.status_code, 200)
        self.assertIsNone(db.session.get(Cliente, cliente.id))

    def test_pedido_crud(self):
        self.login()

        c = Cliente(nome='Cliente Para Pedidos', email='pedido@cliente.com')
        db.session.add(c)
        db.session.commit()

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

        res_detail = self.client.get(f'/pedidos/{pedido.id}')
        self.assertEqual(res_detail.status_code, 200)
        self.assertIn(b'PED-2026-9999', res_detail.data)

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

        res_del = self.client.post(f'/pedidos/{pedido.id}/excluir', follow_redirects=True)
        self.assertEqual(res_del.status_code, 200)
        self.assertIsNone(db.session.get(Pedido, pedido.id))

if __name__ == '__main__':
    unittest.main()
EOF

# --- Helper scripts (run.sh, test.sh, seed.sh) ---
cat <<'EOF' > run.sh
#!/usr/bin/env bash
source .venv/bin/activate
export FLASK_APP=wsgi.py
export FLASK_DEBUG=1
echo "Iniciando servidor GestãoNET em http://0.0.0.0:5000 ..."
python3 wsgi.py
EOF
chmod +x run.sh

cat <<'EOF' > test.sh
#!/usr/bin/env bash
source .venv/bin/activate
echo "Executando suíte de testes automatizados..."
python3 -m unittest tests/test_app.py
EOF
chmod +x test.sh

cat <<'EOF' > seed.sh
#!/usr/bin/env bash
source .venv/bin/activate
export FLASK_APP=wsgi.py
echo "Executando seed de dados..."
flask seed
EOF
chmod +x seed.sh

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

# 6. Inicialização do Banco de Dados e Seed
echo -e "\n${YELLOW}[6/6] Inicializando o banco de dados e migrações...${NC}"
export FLASK_APP=wsgi.py
export FLASK_DEBUG=1

# Inicializa migrações e banco de dados
.venv/bin/flask db init || true
.venv/bin/flask db migrate -m "Initial migration" || true
.venv/bin/flask db upgrade

# Popula o banco com usuário admin e dados de demonstração
.venv/bin/flask seed

# Executa os testes automatizados para validar
echo -e "\n${YELLOW}Executando testes automatizados para validação do sistema...${NC}"
.venv/bin/python3 -m unittest tests/test_app.py

echo -e "\n${BLUE}===================================================================${NC}"
echo -e "${GREEN}🎉 PROJETO CRIADO E CONFIGURADO COM SUCESSO!${NC}"
echo -e "${BLUE}===================================================================${NC}"
echo -e "Para iniciar o servidor agora mesmo, execute:"
echo -e "  ${YELLOW}./run.sh${NC}"
echo -e "\nOu manualmente:"
echo -e "  ${YELLOW}source .venv/bin/activate${NC}"
echo -e "  ${YELLOW}python3 wsgi.py${NC}"
echo -e "\nAcesse no navegador: ${BLUE}http://localhost:5000${NC}"
echo -e "Credenciais Padrão: ${YELLOW}admin${NC} / ${YELLOW}admin123${NC}"
echo -e "${BLUE}===================================================================${NC}"
