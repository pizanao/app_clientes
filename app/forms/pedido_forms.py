from datetime import datetime
from flask_wtf import FlaskForm
from wtforms import StringField, SelectField, TextAreaField, DecimalField, DateTimeLocalField, SubmitField
from wtforms.validators import DataRequired, NumberRange, Optional, Length


class PedidoForm(FlaskForm):
    cliente_id = SelectField('Cliente *', coerce=int, validators=[
        DataRequired(message='Selecione um cliente.')
    ])
    numero_pedido = StringField('Número do Pedido *', validators=[
        DataRequired(message='O número do pedido é obrigatório.'),
        Length(max=30)
    ])
    data_pedido = DateTimeLocalField('Data e Hora do Pedido *', format='%Y-%m-%dT%H:%M', default=datetime.utcnow, validators=[
        DataRequired(message='Informe a data do pedido.')
    ])
    status = SelectField('Status do Pedido *', choices=[
        ('pendente', 'Pendente'),
        ('processando', 'Em Processamento'),
        ('concluido', 'Concluído'),
        ('cancelado', 'Cancelado')
    ], default='pendente', validators=[
        DataRequired(message='Selecione o status do pedido.')
    ])
    metodo_pagamento = SelectField('Método de Pagamento *', choices=[
        ('pix', 'PIX'),
        ('cartao_credito', 'Cartão de Crédito'),
        ('cartao_debito', 'Cartão de Débito'),
        ('boleto', 'Boleto Bancário'),
        ('transferencia', 'Transferência / TED'),
        ('dinheiro', 'Dinheiro em Espécie')
    ], default='pix', validators=[
        DataRequired(message='Selecione o método de pagamento.')
    ])
    valor_total = DecimalField('Valor Total (R$) *', places=2, validators=[
        DataRequired(message='Informe o valor total.'),
        NumberRange(min=0.01, message='O valor deve ser maior que zero.')
    ])
    descricao = TextAreaField('Descrição / Itens do Pedido *', validators=[
        DataRequired(message='Descreva os produtos ou serviços inclusos.'),
        Length(min=5, message='A descrição deve ter pelo menos 5 caracteres.')
    ])
    observacoes = TextAreaField('Observações Adicionais', validators=[
        Optional()
    ])
    submit = SubmitField('Salvar Pedido')
