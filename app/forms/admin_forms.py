from flask_wtf import FlaskForm
from wtforms import (
    StringField, PasswordField, BooleanField, SelectField, SelectMultipleField,
    TextAreaField, SubmitField, IntegerField, DecimalField
)
from wtforms.validators import (
    DataRequired, Email, Length, EqualTo, Optional, ValidationError, NumberRange
)
from app.models.user import User, Grupo, PERFIL_ADMIN, PERFIL_LIDER, PERFIL_AGENTE, PERFIS
from app.models.plano import Plano, TIPO_PF, TIPO_PJ, TIPOS_PLANO


class UsuarioCreateForm(FlaskForm):
    nome = StringField('Nome Completo', validators=[
        DataRequired(message='O nome é obrigatório.'),
        Length(min=3, max=100, message='O nome deve ter entre 3 e 100 caracteres.')
    ])
    username = StringField('Nome de Usuário (login)', validators=[
        DataRequired(message='O nome de usuário é obrigatório.'),
        Length(min=3, max=50, message='O usuário deve ter entre 3 e 50 caracteres.')
    ])
    email = StringField('E-mail Corporativo', validators=[
        DataRequired(message='O e-mail é obrigatório.'),
        Email(message='Informe um e-mail válido.')
    ])
    perfil = SelectField('Perfil de Acesso', choices=[
        (PERFIL_AGENTE, 'Agente (Operador de Prospecção/Vendas)'),
        (PERFIL_LIDER, 'Líder Técnico (Coordenação Operacional)'),
        (PERFIL_ADMIN, 'Administrador (Acesso Irrestrito)')
    ], default=PERFIL_AGENTE, validators=[DataRequired()])
    grupos = SelectMultipleField('Grupos de Acesso', coerce=int)
    password = PasswordField('Senha Inicial', validators=[
        DataRequired(message='A senha é obrigatória.'),
        Length(min=6, message='A senha deve ter pelo menos 6 caracteres.')
    ])
    confirm_password = PasswordField('Confirmar Senha', validators=[
        DataRequired(message='Confirme a senha.'),
        EqualTo('password', message='As senhas não coincidem.')
    ])
    ativo = BooleanField('Usuário Ativo', default=True)
    submit = SubmitField('Criar Usuário')

    def validate_username(self, field):
        if User.query.filter_by(username=field.data.strip()).first():
            raise ValidationError('Este nome de usuário já está em uso.')

    def validate_email(self, field):
        if User.query.filter_by(email=field.data.strip().lower()).first():
            raise ValidationError('Este e-mail já está cadastrado.')


class UsuarioEditForm(FlaskForm):
    nome = StringField('Nome Completo', validators=[
        DataRequired(message='O nome é obrigatório.'),
        Length(min=3, max=100, message='O nome deve ter entre 3 e 100 caracteres.')
    ])
    username = StringField('Nome de Usuário (login)', validators=[
        DataRequired(message='O nome de usuário é obrigatório.'),
        Length(min=3, max=50, message='O usuário deve ter entre 3 e 50 caracteres.')
    ])
    email = StringField('E-mail Corporativo', validators=[
        DataRequired(message='O e-mail é obrigatório.'),
        Email(message='Informe um e-mail válido.')
    ])
    perfil = SelectField('Perfil de Acesso', choices=[
        (PERFIL_AGENTE, 'Agente (Operador de Prospecção/Vendas)'),
        (PERFIL_LIDER, 'Líder Técnico (Coordenação Operacional)'),
        (PERFIL_ADMIN, 'Administrador (Acesso Irrestrito)')
    ], validators=[DataRequired()])
    grupos = SelectMultipleField('Grupos de Acesso', coerce=int)
    password = PasswordField('Nova Senha (deixe em branco para manter a atual)', validators=[
        Optional(),
        Length(min=6, message='A nova senha deve ter pelo menos 6 caracteres.')
    ])
    confirm_password = PasswordField('Confirmar Nova Senha', validators=[
        EqualTo('password', message='As senhas não coincidem.')
    ])
    ativo = BooleanField('Usuário Ativo')
    submit = SubmitField('Salvar Alterações')

    def __init__(self, original_user=None, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.original_user = original_user

    def validate_username(self, field):
        user = User.query.filter_by(username=field.data.strip()).first()
        if user and (self.original_user is None or user.id != self.original_user.id):
            raise ValidationError('Este nome de usuário já está em uso.')

    def validate_email(self, field):
        user = User.query.filter_by(email=field.data.strip().lower()).first()
        if user and (self.original_user is None or user.id != self.original_user.id):
            raise ValidationError('Este e-mail já está cadastrado.')


class GrupoForm(FlaskForm):
    nome = StringField('Nome do Grupo de Acesso', validators=[
        DataRequired(message='O nome do grupo é obrigatório.'),
        Length(min=2, max=80, message='O nome deve ter entre 2 e 80 caracteres.')
    ])
    papel = SelectField('Papel / Perfil Atribuído', choices=[
        (PERFIL_AGENTE, 'Agente'),
        (PERFIL_LIDER, 'Líder Técnico'),
        (PERFIL_ADMIN, 'Administrador')
    ], default=PERFIL_AGENTE, validators=[DataRequired()])
    descricao = TextAreaField('Descrição / Finalidade do Grupo', validators=[
        Optional(),
        Length(max=255, message='A descrição pode ter no máximo 255 caracteres.')
    ])
    membros = SelectMultipleField('Membros do Grupo', coerce=int)
    submit = SubmitField('Salvar Grupo')

    def __init__(self, original_grupo=None, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.original_grupo = original_grupo

    def validate_nome(self, field):
        grupo = Grupo.query.filter_by(nome=field.data.strip()).first()
        if grupo and (self.original_grupo is None or grupo.id != self.original_grupo.id):
            raise ValidationError('Já existe um grupo com este nome.')


class PlanoForm(FlaskForm):
    nome = StringField('Nome do Plano *', validators=[
        DataRequired(message='O nome do plano é obrigatório.'),
        Length(min=3, max=100, message='O nome deve ter entre 3 e 100 caracteres.')
    ])
    tipo = SelectField('Tipo de Público *', choices=[
        (TIPO_PF, 'Pessoa Física (Residencial)'),
        (TIPO_PJ, 'Pessoa Jurídica (Corporativo)')
    ], default=TIPO_PF, validators=[DataRequired(message='Selecione o tipo de público.')])

    velocidade_download = IntegerField('Velocidade de Download (Mbps) *', validators=[
        DataRequired(message='Informe a velocidade de download em Mbps.'),
        NumberRange(min=1, max=10000, message='A velocidade de download deve estar entre 1 e 10.000 Mbps.')
    ])
    velocidade_upload = IntegerField('Velocidade de Upload (Mbps) *', validators=[
        DataRequired(message='Informe a velocidade de upload em Mbps.'),
        NumberRange(min=1, max=10000, message='A velocidade de upload deve estar entre 1 e 10.000 Mbps.')
    ])

    valor_mensal = DecimalField('Valor Promocional / Pontualidade (R$) *', places=2, validators=[
        DataRequired(message='Informe o valor mensal de pontualidade.'),
        NumberRange(min=0.01, message='O valor mensal deve ser maior que zero.')
    ])
    valor_cheio = DecimalField('Valor Cheio de Tabela (R$)', places=2, validators=[
        Optional(),
        NumberRange(min=0.01, message='O valor cheio deve ser maior que zero.')
    ])
    fidelidade_meses = IntegerField('Fidelidade Contratual (Meses) *', default=12, validators=[
        DataRequired(message='Informe o prazo de fidelidade em meses (ex: 12 ou 24).'),
        NumberRange(min=0, max=60, message='A fidelidade deve ser entre 0 e 60 meses.')
    ])

    roteador_wifi = StringField('Equipamentos / Roteador Wi-Fi', validators=[
        Optional(),
        Length(max=150, message='O texto de equipamentos pode ter no máximo 150 caracteres.')
    ])
    aplicativos_inclusos = StringField('Aplicativos / Streaming Inclusos', validators=[
        Optional(),
        Length(max=255, message='Os aplicativos podem ter no máximo 255 caracteres.')
    ])
    beneficios = TextAreaField('Benefícios e Diferenciais', validators=[
        Optional()
    ])
    descricao = TextAreaField('Público-Alvo / Perfil Ideal', validators=[
        Optional()
    ])

    # Recursos Corporativos (PJ)
    sla_horas = IntegerField('SLA de Resposta (Horas)', validators=[
        Optional(),
        NumberRange(min=1, max=168, message='O SLA deve estar entre 1 e 168 horas.')
    ])
    linhas_simultaneas = IntegerField('Linhas / Ligações Simultâneas', validators=[
        Optional(),
        NumberRange(min=1, max=100, message='O número de linhas deve estar entre 1 e 100.')
    ])
    pabx_virtual = BooleanField('PABX Virtual em Nuvem Incluso (até 5 ramais + URA)', default=False)
    ip_fixo = BooleanField('IP Fixo Válido Incluso', default=False)

    # Status e Destaque
    ativo = BooleanField('Plano Ativo no Catálogo', default=True)
    destaque = BooleanField('Destacar no Catálogo (Selo Mais Popular)', default=False)
    observacoes = TextAreaField('Observações Internas', validators=[Optional()])

    submit = SubmitField('Salvar Plano')

    def __init__(self, original_plano=None, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.original_plano = original_plano

    def validate_nome(self, field):
        plano = Plano.query.filter_by(nome=field.data.strip()).first()
        if plano and (self.original_plano is None or plano.id != self.original_plano.id):
            raise ValidationError('Já existe um plano cadastrado com este nome.')
