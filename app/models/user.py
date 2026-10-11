from datetime import datetime
from flask_login import UserMixin
from werkzeug.security import generate_password_hash, check_password_hash
from app.extensions import db, login_manager

# Constantes dos Perfis de Acesso
PERFIL_ADMIN = 'administrador'
PERFIL_LIDER = 'lider_tecnico'
PERFIL_AGENTE = 'agente'

PERFIS = {
    PERFIL_ADMIN: 'Administrador',
    PERFIL_LIDER: 'Líder Técnico',
    PERFIL_AGENTE: 'Agente',
}

# Tabela Associativa Many-to-Many entre Usuários e Grupos de Acesso
usuario_grupos = db.Table(
    'usuario_grupos',
    db.Column('usuario_id', db.Integer, db.ForeignKey('usuarios.id', ondelete='CASCADE'), primary_key=True),
    db.Column('grupo_id', db.Integer, db.ForeignKey('grupos.id', ondelete='CASCADE'), primary_key=True)
)


class Grupo(db.Model):
    __tablename__ = 'grupos'

    id = db.Column(db.Integer, primary_key=True)
    nome = db.Column(db.String(80), unique=True, nullable=False, index=True)
    descricao = db.Column(db.String(255), nullable=True)
    papel = db.Column(db.String(50), default=PERFIL_AGENTE, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)

    usuarios = db.relationship('User', secondary=usuario_grupos, back_populates='grupos', lazy='select')

    @property
    def papel_nome(self) -> str:
        return PERFIS.get(self.papel, self.papel.capitalize())

    def __repr__(self):
        return f'<Grupo {self.nome} ({self.papel})>'


class User(UserMixin, db.Model):
    __tablename__ = 'usuarios'

    id = db.Column(db.Integer, primary_key=True)
    nome = db.Column(db.String(100), nullable=False)
    username = db.Column(db.String(50), unique=True, nullable=False, index=True)
    email = db.Column(db.String(120), unique=True, nullable=False, index=True)
    password_hash = db.Column(db.String(255), nullable=False)
    perfil = db.Column(db.String(50), default=PERFIL_AGENTE, nullable=False)
    ativo = db.Column(db.Boolean, default=True, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)

    grupos = db.relationship('Grupo', secondary=usuario_grupos, back_populates='usuarios', lazy='select')

    def set_password(self, password: str):
        self.password_hash = generate_password_hash(password)

    def check_password(self, password: str) -> bool:
        return check_password_hash(self.password_hash, password)

    @property
    def perfil_nome(self) -> str:
        return PERFIS.get(self.perfil, self.perfil.capitalize())

    @property
    def papel_efetivo(self) -> str:
        if self.is_admin:
            return PERFIL_ADMIN
        if self.is_lider_tecnico:
            return PERFIL_LIDER
        return PERFIL_AGENTE

    @property
    def papel_efetivo_nome(self) -> str:
        return PERFIS.get(self.papel_efetivo, self.papel_efetivo.capitalize())

    @property
    def is_admin(self) -> bool:
        if self.perfil == PERFIL_ADMIN:
            return True
        return any(g.papel == PERFIL_ADMIN for g in self.grupos)

    @property
    def is_lider_tecnico(self) -> bool:
        if self.is_admin:
            return True
        if self.perfil == PERFIL_LIDER:
            return True
        return any(g.papel == PERFIL_LIDER for g in self.grupos)

    @property
    def is_agente(self) -> bool:
        return True

    def has_perfil(self, *perfis) -> bool:
        perfis_set = set(perfis)
        if PERFIL_ADMIN in perfis_set and self.is_admin:
            return True
        if PERFIL_LIDER in perfis_set and self.is_lider_tecnico:
            return True
        if self.perfil in perfis_set:
            return True
        return any(g.papel in perfis_set for g in self.grupos)

    def has_role(self, *roles) -> bool:
        return self.has_perfil(*roles)

    @property
    def grupos_nomes(self) -> list:
        return [g.nome for g in self.grupos]

    def __repr__(self):
        return f'<User {self.username} ({self.perfil})>'


@login_manager.user_loader
def load_user(user_id):
    return db.session.get(User, int(user_id))
