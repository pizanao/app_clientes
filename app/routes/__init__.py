from app.routes.auth import auth_bp
from app.routes.main import main_bp
from app.routes.clientes import clientes_bp
from app.routes.pedidos import pedidos_bp

__all__ = ['auth_bp', 'main_bp', 'clientes_bp', 'pedidos_bp']
