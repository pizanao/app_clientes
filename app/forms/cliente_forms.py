from flask_wtf import FlaskForm
from wtforms import StringField, BooleanField, TextAreaField, SelectField, SubmitField
from wtforms.validators import DataRequired, Email, Length, Optional, ValidationError

ESTADOS_BRASIL = [
    ('', 'Selecione o Estado'),
    ('MS', 'Mato Grosso do Sul (MS)'),
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
    cidade = StringField('Cidade *', default='Campo Grande', validators=[
        DataRequired(message='A cidade é obrigatória.'),
        Length(max=80)
    ])
    estado = SelectField('Estado (UF) *', choices=ESTADOS_BRASIL, default='MS', validators=[
        DataRequired(message='O estado é obrigatório.')
    ])
    ativo = BooleanField('Cliente Ativo', default=True)
    observacoes = TextAreaField('Observações Internas', validators=[
        Optional()
    ])
    submit = SubmitField('Salvar Cliente')

    def validate_estado(self, field):
        if field.data and field.data.strip().upper() != 'MS':
            raise ValidationError('A DigitalNet MS atende exclusivamente no estado de Mato Grosso do Sul (MS).')
