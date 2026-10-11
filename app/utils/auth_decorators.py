from functools import wraps
from flask import abort, flash, redirect, url_for, request
from flask_login import current_user
from app.models.user import PERFIL_ADMIN, PERFIL_LIDER, PERFIL_AGENTE


def admin_required(f):
    """
    Exige que o usuário esteja autenticado e tenha o perfil ou grupo de Administrador.
    """
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if not current_user.is_authenticated:
            flash('Por favor, faça login para acessar esta página.', 'warning')
            return redirect(url_for('auth.login', next=request.url))
        if not current_user.is_admin:
            flash('Acesso negado. Esta funcionalidade é restrita a Administradores.', 'danger')
            abort(403)
        return f(*args, **kwargs)
    return decorated_function


def lider_required(f):
    """
    Exige que o usuário seja Líder Técnico ou Administrador.
    """
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if not current_user.is_authenticated:
            flash('Por favor, faça login para acessar esta página.', 'warning')
            return redirect(url_for('auth.login', next=request.url))
        if not current_user.is_lider_tecnico:
            flash('Acesso negado. Apenas Líderes Técnicos e Administradores possuem esta permissão.', 'danger')
            abort(403)
        return f(*args, **kwargs)
    return decorated_function


def perfil_required(*perfis):
    """
    Exige que o usuário pertença a um dos perfis fornecidos.
    """
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            if not current_user.is_authenticated:
                flash('Por favor, faça login para acessar esta página.', 'warning')
                return redirect(url_for('auth.login', next=request.url))
            if not current_user.has_perfil(*perfis):
                flash('Acesso negado para o seu perfil de usuário.', 'danger')
                abort(403)
            return f(*args, **kwargs)
        return decorated_function
    return decorator
