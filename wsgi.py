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
