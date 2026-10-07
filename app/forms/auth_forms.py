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
