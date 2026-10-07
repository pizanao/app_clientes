import os
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
    # Running directly with python wsgi.py
    port = int(os.environ.get('PORT', 5000))
    app.run(host='127.0.0.1', port=port, debug=True)
