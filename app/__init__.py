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
