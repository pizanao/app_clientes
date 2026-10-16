from datetime import datetime
from app.extensions import db


class ItemPedido(db.Model):
    __tablename__ = 'itens_pedido'

    id = db.Column(db.Integer, primary_key=True)
    pedido_id = db.Column(db.Integer, db.ForeignKey('pedidos.id', ondelete='CASCADE'), nullable=False, index=True)
    descricao = db.Column(db.String(255), nullable=False)
    quantidade = db.Column(db.Float, nullable=False, default=1.0)
    valor_unitario = db.Column(db.Float, nullable=False, default=0.0)
    valor_total = db.Column(db.Float, nullable=False, default=0.0)
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)

    def calcular_total(self) -> float:
        """Calcula e atualiza o valor total do item (Qtd * Vlr Unitario)."""
        qtd = float(self.quantidade or 0.0)
        unit = float(self.valor_unitario or 0.0)
        self.valor_total = round(qtd * unit, 2)
        return self.valor_total

    def __repr__(self):
        return f'<ItemPedido #{self.id}: {self.descricao} ({self.quantidade} x R$ {self.valor_unitario:.2f})>'


class Pedido(db.Model):
    __tablename__ = 'pedidos'

    id = db.Column(db.Integer, primary_key=True)
    numero_pedido = db.Column(db.String(30), unique=True, nullable=False, index=True)
    cliente_id = db.Column(db.Integer, db.ForeignKey('clientes.id', ondelete='CASCADE'), nullable=False, index=True)
    data_pedido = db.Column(db.DateTime, default=datetime.utcnow, nullable=False, index=True)
    status = db.Column(db.String(25), default='pendente', nullable=False, index=True)
    metodo_pagamento = db.Column(db.String(30), default='pix', nullable=False)
    valor_total = db.Column(db.Float, default=0.0, nullable=False)
    descricao = db.Column(db.Text, nullable=True)
    observacoes = db.Column(db.Text, nullable=True)

    # Relacionamento N:1 com Plano Oficial da DigitalNet MS
    plano_id = db.Column(db.Integer, db.ForeignKey('planos.id', ondelete='SET NULL'), nullable=True, index=True)
    plano = db.relationship('Plano', backref=db.backref('pedidos', lazy='select'))

    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    # Relacionamento 1:N com Itens do Pedido (1 a 10 itens por pedido)
    itens = db.relationship(
        'ItemPedido',
        backref='pedido',
        lazy='joined',
        cascade='all, delete-orphan',
        order_by='ItemPedido.id.asc()'
    )

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

    @property
    def total_itens(self) -> int:
        return len(self.itens)

    @property
    def total(self) -> float:
        return float(self.valor_total or 0.0)

    @property
    def plano_nome(self) -> str:
        if self.plano:
            return self.plano.nome
        return ""

    @property
    def resumo_itens(self) -> str:
        if self.itens:
            return ", ".join(item.descricao for item in self.itens)
        return self.descricao or "Sem itens cadastrados"

    def recalcular_total(self) -> float:
        """Totaliza o valor do pedido com base nos itens cadastrados."""
        total = sum(item.calcular_total() for item in self.itens)
        self.valor_total = round(total, 2)
        return self.valor_total

    def __repr__(self):
        return f'<Pedido {self.numero_pedido} - Cliente {self.cliente_id}>'

