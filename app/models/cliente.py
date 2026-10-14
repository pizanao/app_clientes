from datetime import datetime
from app.extensions import db


class Cliente(db.Model):
    __tablename__ = 'clientes'

    id = db.Column(db.Integer, primary_key=True)
    nome = db.Column(db.String(120), nullable=False, index=True)
    email = db.Column(db.String(120), nullable=False, index=True)
    telefone = db.Column(db.String(30), nullable=True)
    documento = db.Column(db.String(30), nullable=True, index=True)  # CPF or CNPJ
    cep = db.Column(db.String(15), nullable=True)
    logradouro = db.Column(db.String(150), nullable=True)
    numero = db.Column(db.String(20), nullable=True)
    complemento = db.Column(db.String(50), nullable=True)
    bairro = db.Column(db.String(80), nullable=True)
    cidade = db.Column(db.String(80), nullable=True)
    estado = db.Column(db.String(2), nullable=True)  # UF
    ativo = db.Column(db.Boolean, default=True, nullable=False)
    observacoes = db.Column(db.Text, nullable=True)
    
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    # Relationship to Pedidos
    pedidos = db.relationship(
        'Pedido',
        backref='cliente',
        lazy=True,
        cascade='all, delete-orphan',
        order_by='desc(Pedido.data_pedido)'
    )

    @property
    def total_pedidos(self) -> int:
        return len(self.pedidos)

    @property
    def valor_total_gasto(self) -> float:
        return sum(p.valor_total for p in self.pedidos if p.status != 'cancelado')

    @property
    def endereco_completo(self) -> str:
        partes = []
        if self.logradouro:
            partes.append(f"{self.logradouro}, {self.numero or 'S/N'}")
        if self.bairro:
            partes.append(self.bairro)
        if self.cidade and self.estado:
            partes.append(f"{self.cidade}/{self.estado}")
        elif self.cidade:
            partes.append(self.cidade)
        if self.cep:
            partes.append(f"CEP: {self.cep}")
        return " - ".join(partes) if partes else "Endereço não informado"

    @property
    def telefone_numeros(self) -> str:
        """Retorna apenas dígitos do telefone no formato internacional E.164 (sem '+') para o wa.me."""
        if not self.telefone:
            return ''
        primeiro = self.telefone.split('|')[0].strip()
        digits = ''.join(c for c in primeiro if c.isdigit())
        if len(digits) in (10, 11) and not digits.startswith('55'):
            digits = '55' + digits
        return digits

    @property
    def telefone_e164(self) -> str:
        """Retorna no padrão E.164 canônico com sinal de '+' (ex: +5567991453123)."""
        num = self.telefone_numeros
        return f"+{num}" if num else ''

    @property
    def whatsapp_url(self) -> str:
        """Gera URL direta para iniciar conversa com o cliente no WhatsApp."""
        phone = self.telefone_numeros
        return f"https://wa.me/{phone}" if phone else '#'

    def __repr__(self):
        return f'<Cliente {self.nome}>'
