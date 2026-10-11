"""add_planos_table

Revision ID: c3d4e5f6a7b8
Revises: b2c3d4e5f6a7
Create Date: 2026-10-11 15:00:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'c3d4e5f6a7b8'
down_revision = 'b2c3d4e5f6a7'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table('planos',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('nome', sa.String(length=100), nullable=False),
        sa.Column('tipo', sa.String(length=10), server_default='PF', nullable=False),
        sa.Column('velocidade_download', sa.Integer(), nullable=False),
        sa.Column('velocidade_upload', sa.Integer(), nullable=False),
        sa.Column('valor_mensal', sa.Float(), nullable=False),
        sa.Column('valor_cheio', sa.Float(), nullable=True),
        sa.Column('fidelidade_meses', sa.Integer(), server_default='12', nullable=False),
        sa.Column('roteador_wifi', sa.String(length=150), nullable=True),
        sa.Column('beneficios', sa.Text(), nullable=True),
        sa.Column('aplicativos_inclusos', sa.String(length=255), nullable=True),
        sa.Column('sla_horas', sa.Integer(), nullable=True),
        sa.Column('linhas_simultaneas', sa.Integer(), nullable=True),
        sa.Column('pabx_virtual', sa.Boolean(), server_default='0', nullable=False),
        sa.Column('ip_fixo', sa.Boolean(), server_default='0', nullable=False),
        sa.Column('ativo', sa.Boolean(), server_default='1', nullable=False),
        sa.Column('destaque', sa.Boolean(), server_default='0', nullable=False),
        sa.Column('descricao', sa.Text(), nullable=True),
        sa.Column('observacoes', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.PrimaryKeyConstraint('id')
    )
    with op.batch_alter_table('planos', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_planos_nome'), ['nome'], unique=True)
        batch_op.create_index(batch_op.f('ix_planos_tipo'), ['tipo'], unique=False)
        batch_op.create_index(batch_op.f('ix_planos_ativo'), ['ativo'], unique=False)


def downgrade():
    with op.batch_alter_table('planos', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_planos_ativo'))
        batch_op.drop_index(batch_op.f('ix_planos_tipo'))
        batch_op.drop_index(batch_op.f('ix_planos_nome'))
    op.drop_table('planos')
