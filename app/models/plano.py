from datetime import datetime
from app.extensions import db

TIPO_PF = 'PF'
TIPO_PJ = 'PJ'

TIPOS_PLANO = {
    TIPO_PF: 'Pessoa Física (Residencial)',
    TIPO_PJ: 'Pessoa Jurídica (Corporativo)',
}


class Plano(db.Model):
    __tablename__ = 'planos'

    id = db.Column(db.Integer, primary_key=True)
    nome = db.Column(db.String(100), unique=True, nullable=False, index=True)
    tipo = db.Column(db.String(10), default=TIPO_PF, nullable=False, index=True)  # 'PF' ou 'PJ'
    velocidade_download = db.Column(db.Integer, nullable=False)  # Mbps
    velocidade_upload = db.Column(db.Integer, nullable=False)  # Mbps
    valor_mensal = db.Column(db.Float, nullable=False)  # Preço pontualidade / promocional
    valor_cheio = db.Column(db.Float, nullable=True)  # Preço cheio de tabela
    fidelidade_meses = db.Column(db.Integer, default=12, nullable=False)  # 12 meses PF, 24 meses PJ
    roteador_wifi = db.Column(db.String(150), nullable=True)  # ex: "Roteador Wi-Fi 6 em comodato"
    beneficios = db.Column(db.Text, nullable=True)  # Benefícios gerais
    aplicativos_inclusos = db.Column(db.String(255), nullable=True)  # ex: "Skeelo + 1 app da Grade Standard"
    sla_horas = db.Column(db.Integer, nullable=True)  # SLA de resposta para PJ (ex: 12 ou 24)
    linhas_simultaneas = db.Column(db.Integer, nullable=True)  # Ligações simultâneas / Tronco SIP
    pabx_virtual = db.Column(db.Boolean, default=False, nullable=False)  # PABX Virtual em nuvem
    ip_fixo = db.Column(db.Boolean, default=False, nullable=False)  # IP Fixo válido incluso
    ativo = db.Column(db.Boolean, default=True, nullable=False, index=True)
    destaque = db.Column(db.Boolean, default=False, nullable=False)  # Selo Destaque / Recomendado
    descricao = db.Column(db.Text, nullable=True)  # Descrição / público-alvo ideal
    observacoes = db.Column(db.Text, nullable=True)

    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    @property
    def tipo_nome(self) -> str:
        return TIPOS_PLANO.get(self.tipo, self.tipo)

    @property
    def is_pf(self) -> bool:
        return self.tipo == TIPO_PF

    @property
    def is_pj(self) -> bool:
        return self.tipo == TIPO_PJ

    @property
    def valor_mensal_formatado(self) -> str:
        return f"R$ {self.valor_mensal:.2f}".replace('.', ',')

    @property
    def valor_cheio_formatado(self) -> str:
        if self.valor_cheio:
            return f"R$ {self.valor_cheio:.2f}".replace('.', ',')
        return "-"

    @property
    def velocidade_formatada(self) -> str:
        return f"{self.velocidade_download} Mega ({self.velocidade_upload} Mbps Upload)"

    def to_dict(self) -> dict:
        return {
            'id': self.id,
            'nome': self.nome,
            'tipo': self.tipo,
            'tipo_nome': self.tipo_nome,
            'velocidade_download': self.velocidade_download,
            'velocidade_upload': self.velocidade_upload,
            'velocidade_formatada': self.velocidade_formatada,
            'valor_mensal': self.valor_mensal,
            'valor_mensal_formatado': self.valor_mensal_formatado,
            'valor_cheio': self.valor_cheio,
            'valor_cheio_formatado': self.valor_cheio_formatado,
            'fidelidade_meses': self.fidelidade_meses,
            'roteador_wifi': self.roteador_wifi,
            'beneficios': self.beneficios,
            'aplicativos_inclusos': self.aplicativos_inclusos,
            'sla_horas': self.sla_horas,
            'linhas_simultaneas': self.linhas_simultaneas,
            'pabx_virtual': self.pabx_virtual,
            'ip_fixo': self.ip_fixo,
            'ativo': self.ativo,
            'destaque': self.destaque,
            'descricao': self.descricao,
        }

    @classmethod
    def seed_planos_iniciais(cls) -> int:
        """
        Cadastra ou atualiza os planos padrão oficiais de telecomunicações (PF e PJ).
        Retorna o total de planos criados ou atualizados.
        """
        planos_padrao = [
            # -----------------------------------------------------------------
            # PLANOS PESSOA FÍSICA (RESIDENCIAIS)
            # -----------------------------------------------------------------
            {
                'nome': 'Fibra 600 Standard',
                'tipo': TIPO_PF,
                'velocidade_download': 600,
                'velocidade_upload': 300,
                'valor_mensal': 119.90,
                'valor_cheio': 129.90,
                'fidelidade_meses': 12,
                'roteador_wifi': 'Roteador Wi-Fi 6 em comodato + instalação inclusa',
                'aplicativos_inclusos': '1 app da Grade Standard (troca mensal) + Skeelo',
                'beneficios': 'Skeelo livros e audiolivros inclusos; 1 app de streaming à escolha com troca 1 vez por mês; 100% fibra óptica com equipe em Campo Grande.',
                'sla_horas': None,
                'linhas_simultaneas': None,
                'pabx_virtual': False,
                'ip_fixo': False,
                'ativo': True,
                'destaque': False,
                'descricao': 'Casal ou home office, streaming em HD',
            },
            {
                'nome': 'Fibra 700 Standard',
                'tipo': TIPO_PF,
                'velocidade_download': 700,
                'velocidade_upload': 350,
                'valor_mensal': 129.90,
                'valor_cheio': 139.90,
                'fidelidade_meses': 12,
                'roteador_wifi': 'Roteador Wi-Fi 6 em comodato + instalação inclusa',
                'aplicativos_inclusos': '1 app da Grade Standard (troca mensal) + Skeelo',
                'beneficios': 'Skeelo livros e audiolivros inclusos; 1 app de streaming com troca mensal; alta estabilidade para múltiplos dispositivos conectados.',
                'sla_horas': None,
                'linhas_simultaneas': None,
                'pabx_virtual': False,
                'ip_fixo': False,
                'ativo': True,
                'destaque': True,
                'descricao': 'Quem quer mais velocidade e mantém o app de streaming',
            },
            {
                'nome': 'Fibra 700 + DigiMesh',
                'tipo': TIPO_PF,
                'velocidade_download': 700,
                'velocidade_upload': 350,
                'valor_mensal': 129.90,
                'valor_cheio': 139.90,
                'fidelidade_meses': 12,
                'roteador_wifi': 'Roteador Wi-Fi 6 + 1 ponto DigiMesh (roteador adicional)',
                'aplicativos_inclusos': 'Skeelo livros e audiolivros (sem app de streaming)',
                'beneficios': '1 ponto de Wi-Fi extra DigiMesh que leva sinal aos cantos da casa sem cabo e sem obra; Skeelo incluso; sem app de streaming.',
                'sla_horas': None,
                'linhas_simultaneas': None,
                'pabx_virtual': False,
                'ip_fixo': False,
                'ativo': True,
                'destaque': False,
                'descricao': 'Casa com sinal fraco nos fundos ou no andar de cima',
            },
            {
                'nome': 'Fibra 900 Advanced',
                'tipo': TIPO_PF,
                'velocidade_download': 900,
                'velocidade_upload': 450,
                'valor_mensal': 149.90,
                'valor_cheio': 159.90,
                'fidelidade_meses': 12,
                'roteador_wifi': 'Roteador Wi-Fi 6 em comodato + instalação inclusa',
                'aplicativos_inclusos': '1 app escolha livre (troca mensal) + SKY+ com Amazon Prime',
                'beneficios': 'Promocional R$ 99,90/mês nos primeiros 3 meses (R$ 149,90 pontualidade a partir do 4º mês); SKY+ com Amazon Prime incluso; Skeelo livros e audiolivros.',
                'sla_horas': None,
                'linhas_simultaneas': None,
                'pabx_virtual': False,
                'ip_fixo': False,
                'ativo': True,
                'destaque': False,
                'descricao': 'Quem quer 900 Mega pagando menos nos primeiros meses',
            },
            {
                'nome': 'Fibra 900 Top',
                'tipo': TIPO_PF,
                'velocidade_download': 900,
                'velocidade_upload': 450,
                'valor_mensal': 159.90,
                'valor_cheio': 169.90,
                'fidelidade_meses': 12,
                'roteador_wifi': 'Roteador Wi-Fi 6 em comodato + instalação inclusa',
                'aplicativos_inclusos': '1 app da Grade Top (HBO Max, Disney+, Apple TV+, Globoplay)',
                'beneficios': 'Streaming de alto padrão: escolha entre HBO Max, Disney+, Apple TV+ e Globoplay trocando 1 vez por mês; Skeelo incluso; ultra velocidade 900 Mega.',
                'sla_horas': None,
                'linhas_simultaneas': None,
                'pabx_virtual': False,
                'ip_fixo': False,
                'ativo': True,
                'destaque': True,
                'descricao': 'Família que assiste muito e quer um app premium',
            },
            {
                'nome': 'Fibra 900 Top + DigiMesh',
                'tipo': TIPO_PF,
                'velocidade_download': 900,
                'velocidade_upload': 450,
                'valor_mensal': 169.90,
                'valor_cheio': 179.90,
                'fidelidade_meses': 12,
                'roteador_wifi': 'Roteador Wi-Fi 6 + 1 ponto DigiMesh (roteador adicional)',
                'aplicativos_inclusos': '1 app da Grade Top (troca mensal) + Skeelo',
                'beneficios': 'Combinação máxima: 900 Mega, streaming Grade Top, ponto de Wi-Fi extra DigiMesh cobrindo toda a residência sem zonas de sombra, Skeelo.',
                'sla_horas': None,
                'linhas_simultaneas': None,
                'pabx_virtual': False,
                'ip_fixo': False,
                'ativo': True,
                'destaque': False,
                'descricao': 'Casa grande, muitos aparelhos, jogos online',
            },
            # -----------------------------------------------------------------
            # PLANOS PESSOA JURÍDICA (CORPORATIVOS - DIGICORP)
            # -----------------------------------------------------------------
            {
                'nome': 'DigiCorp Profissional',
                'tipo': TIPO_PJ,
                'velocidade_download': 500,
                'velocidade_upload': 250,
                'valor_mensal': 229.90,
                'valor_cheio': 259.90,
                'fidelidade_meses': 24,
                'roteador_wifi': '2 repetidores Wi-Fi 6 em comodato',
                'aplicativos_inclusos': '1 linha digital · 2 ligações simultâneas',
                'beneficios': 'Telefonia digital com minutos ilimitados (até 10.000 min fixo/móvel); 2 ligações simultâneas; 2 repetidores Wi-Fi 6; IP fixo válido; SLA de resposta de até 24h em contrato.',
                'sla_horas': 24,
                'linhas_simultaneas': 2,
                'pabx_virtual': False,
                'ip_fixo': True,
                'ativo': True,
                'destaque': False,
                'descricao': 'Escritório / Loja - Perfeito para pequenos comércios e clínicas',
            },
            {
                'nome': 'DigiCorp Elite',
                'tipo': TIPO_PJ,
                'velocidade_download': 900,
                'velocidade_upload': 450,
                'valor_mensal': 399.90,
                'valor_cheio': 489.70,
                'fidelidade_meses': 24,
                'roteador_wifi': '2 repetidores Wi-Fi 6 em comodato',
                'aplicativos_inclusos': 'PABX Virtual (até 5 ramais) + URA + Tronco SIP',
                'beneficios': 'Tronco SIP com 2 ligações simultâneas; minutos ilimitados; PABX Virtual em nuvem (até 5 ramais Wi-Fi/PC/celular); URA de atendimento personalizada; 2 repetidores Wi-Fi 6; IP fixo válido; SLA de até 12h.',
                'sla_horas': 12,
                'linhas_simultaneas': 2,
                'pabx_virtual': True,
                'ip_fixo': True,
                'ativo': True,
                'destaque': True,
                'descricao': 'PME com telefonia - Estrutura profissional com atendimento automatizado',
            },
            {
                'nome': 'DigiCorp Premium',
                'tipo': TIPO_PJ,
                'velocidade_download': 900,
                'velocidade_upload': 450,
                'valor_mensal': 519.90,
                'valor_cheio': 639.70,
                'fidelidade_meses': 24,
                'roteador_wifi': '3 repetidores Wi-Fi 6 em comodato',
                'aplicativos_inclusos': 'PABX Virtual (até 5 ramais) + URA + Tronco SIP (4 linhas)',
                'beneficios': 'Tronco SIP com 4 ligações simultâneas; minutos ilimitados; PABX Virtual em nuvem (até 5 ramais); URA personalizada; 3 repetidores Wi-Fi 6; IP fixo válido; SLA prioritário de até 12h em contrato.',
                'sla_horas': 12,
                'linhas_simultaneas': 4,
                'pabx_virtual': True,
                'ip_fixo': True,
                'ativo': True,
                'destaque': False,
                'descricao': 'Operação crítica - Alta densidade de chamadas e redundância total',
            },
        ]

        total = 0
        for dados in planos_padrao:
            plano = cls.query.filter_by(nome=dados['nome']).first()
            if not plano:
                plano = cls(**dados)
                db.session.add(plano)
                total += 1
            else:
                for k, v in dados.items():
                    setattr(plano, k, v)
                total += 1

        db.session.commit()
        return total

    def __repr__(self):
        return f'<Plano #{self.id}: {self.nome} ({self.tipo}) - R$ {self.valor_mensal:.2f}>'
