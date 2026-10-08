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
