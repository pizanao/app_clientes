import os
from datetime import timedelta
from dotenv import load_dotenv

BASE_DIR = os.path.abspath(os.path.dirname(os.path.dirname(__file__)))
load_dotenv(os.path.join(BASE_DIR, '.env'))
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

    # AIsa API (Provedor de Leads e Inteligência Comercial)
    AISA_API_KEY = os.environ.get('AISA_API_KEY')
    AISA_MODEL = os.environ.get('AISA_MODEL') or 'asi1-mini'

    # Mapbox API (Telecom Geo-visualização)
    MAPBOX_API_KEY = os.environ.get('MAPBOX_API_KEY') or os.environ.get('MAPBOX_ACCESS_TOKEN')
