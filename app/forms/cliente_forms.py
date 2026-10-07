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
