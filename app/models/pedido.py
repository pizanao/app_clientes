from datetime import datetime
from app.extensions import db


class Pedido(db.Model):
    __tablename__ = 'pedidos'

    id = db.Column(db.Integer, primary_key=True)
    numero_pedido = db.Column(db.String(30), unique=True, nullable=False, index=True)
    cliente_id = db.Column(db.Integer, db.ForeignKey('clientes.id', ondelete='CASCADE'), nullable=False, index=True)
    data_pedido = db.Column(db.DateTime, default=datetime.utcnow, nullable=False, index=True)
    status = db.Column(db.String(25), default='pendente', nullable=False, index=True)
    metodo_pagamento = db.Column(db.String(30), default='pix', nullable=False)
    valor_total = db.Column(db.Float, default=0.0, nullable=False)
    descricao = db.Column(db.Text, nullable=False)
    observacoes = db.Column(db.Text, nullable=True)

    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    STATUS_CHOICES = {
        'pendente': ('Pendente', 'bg-warning text-dark'),
        'processando': ('Em Processamento', 'bg-info text-white'),
        'concluido': ('Concluído', 'bg-success text-white'),
        'cancelado': ('Cancelado', 'bg-danger text-white'),
    }

    METODOS_PAGAMENTO = {
        'pix': 'PIX',
        'cartao_credito': 'Cartão de Crédito',
        'cartao_debito': 'Cartão de Débito',
        'boleto': 'Boleto Bancário',
        'transferencia': 'Transferência / TED',
        'dinheiro': 'Dinheiro em Espécie',
    }

    @property
    def status_label(self) -> str:
        return self.STATUS_CHOICES.get(self.status, (self.status, 'bg-secondary'))[0]

    @property
    def status_badge_class(self) -> str:
        return self.STATUS_CHOICES.get(self.status, (self.status, 'bg-secondary'))[1]

    @property
    def metodo_pagamento_label(self) -> str:
        return self.METODOS_PAGAMENTO.get(self.metodo_pagamento, self.metodo_pagamento)

    def __repr__(self):
        return f'<Pedido {self.numero_pedido} - Cliente {self.cliente_id}>'
