from datetime import datetime
import urllib.parse
from app.extensions import db


class Lead(db.Model):
    __tablename__ = 'leads'

    id = db.Column(db.Integer, primary_key=True)
    nome = db.Column(db.String(120), nullable=False, index=True)
    empresa = db.Column(db.String(150), nullable=False, index=True)
    cargo = db.Column(db.String(100), nullable=True)
    telefone = db.Column(db.String(30), nullable=True)
    email = db.Column(db.String(120), nullable=True)
    documento = db.Column(db.String(30), nullable=True)
    niche = db.Column(db.String(100), nullable=True, default='Geral')

    # Geo-localização do Lead
    cep = db.Column(db.String(15), nullable=True)
    logradouro = db.Column(db.String(150), nullable=True)
    numero = db.Column(db.String(20), nullable=True)
    complemento = db.Column(db.String(50), nullable=True)
    bairro = db.Column(db.String(80), nullable=False, index=True)
    cidade = db.Column(db.String(80), nullable=False, default='Campo Grande', index=True)
    estado = db.Column(db.String(2), nullable=False, default='MS')

    # Vinculo com o cliente ativo que viabilizou a rede na região
    cliente_referencia_id = db.Column(
        db.Integer,
        db.ForeignKey('clientes.id', ondelete='SET NULL'),
        nullable=True,
        index=True
    )

    # Status de Funil e Opt-in
    status = db.Column(db.String(30), default='novo', nullable=False, index=True)
    optin_status = db.Column(db.String(20), default='pendente', nullable=False, index=True)

    # Dados Comerciais e Concorrência
    operadora_atual = db.Column(db.String(80), default='Vivo Fibra / Claro', nullable=True)
    plano_sugerido = db.Column(db.String(120), default='Fibra 700 + DigiMesh', nullable=True)
    valor_mensal_sugerido = db.Column(db.Float, default=139.90, nullable=False)
    lead_score = db.Column(db.Integer, default=85, nullable=False)
    dor_principal = db.Column(db.Text, nullable=True)
    icebreaker_optin = db.Column(db.Text, nullable=True)
    dossie_comercial = db.Column(db.Text, nullable=True)
    observacoes = db.Column(db.Text, nullable=True)

    # Vinculo com o cliente criado apos a conversão
    cliente_convertido_id = db.Column(
        db.Integer,
        db.ForeignKey('clientes.id', ondelete='SET NULL'),
        nullable=True,
        index=True
    )

    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    # Relacionamentos
    cliente_referencia = db.relationship('Cliente', foreign_keys=[cliente_referencia_id], backref='leads_vizinhos_gerados')
    cliente_convertido = db.relationship('Cliente', foreign_keys=[cliente_convertido_id], backref='lead_origem')

    STATUS_CONFIG = {
        'novo': ('Novo Lead', 'bg-secondary text-white'),
        'optin_solicitado': ('Opt-in Solicitado', 'bg-warning text-dark'),
        'optin_aceito': ('Opt-in Aceito', 'bg-info text-white'),
        'proposta_enviada': ('Proposta Enviada', 'bg-primary text-white'),
        'convertido': ('Convertido / Fechado', 'bg-success text-white'),
        'perdido': ('Perdido', 'bg-danger text-white'),
    }

    OPTIN_CONFIG = {
        'pendente': ('Pendente', 'badge bg-secondary'),
        'aceito': ('Aceito (Anti-Ban Ativo)', 'badge bg-success'),
        'recusado': ('Recusado', 'badge bg-danger'),
    }

    @property
    def status_label(self) -> str:
        return self.STATUS_CONFIG.get(self.status, (self.status.capitalize(), 'bg-secondary text-white'))[0]

    @property
    def status_badge_class(self) -> str:
        return self.STATUS_CONFIG.get(self.status, ('', 'bg-secondary text-white'))[1]

    @property
    def optin_label(self) -> str:
        return self.OPTIN_CONFIG.get(self.optin_status, (self.optin_status.capitalize(), 'badge bg-secondary'))[0]

    @property
    def optin_badge_class(self) -> str:
        return self.OPTIN_CONFIG.get(self.optin_status, ('', 'badge bg-secondary'))[1]

    @property
    def telefone_numeros(self) -> str:
        """Retorna apenas dígitos do telefone para montagem do link wa.me."""
        if not self.telefone:
            return ''
        digits = ''.join(c for c in self.telefone if c.isdigit())
        if len(digits) in (10, 11) and not digits.startswith('55'):
            digits = '55' + digits
        return digits

    @property
    def whatsapp_url(self) -> str:
        """Gera URL com a mensagem de opt-in pronta para o WhatsApp Web."""
        phone = self.telefone_numeros
        msg = self.icebreaker_optin or ''
        if not phone or not msg:
            return '#'
        encoded = urllib.parse.quote(msg)
        return f"https://wa.me/{phone}?text={encoded}"

    @property
    def endereco_resumido(self) -> str:
        partes = []
        if self.logradouro:
            partes.append(f"{self.logradouro}, {self.numero or 'S/N'}")
        if self.bairro:
            partes.append(self.bairro)
        if self.cidade and self.estado:
            partes.append(f"{self.cidade}/{self.estado}")
        return ' - '.join(partes) if partes else f"{self.bairro}, {self.cidade}/{self.estado}"

    def __repr__(self):
        return f'<Lead #{self.id}: {self.empresa} ({self.bairro})>'
