"""add_perfis_e_grupos

Revision ID: b2c3d4e5f6a7
Revises: a1b2c3d4e5f6
Create Date: 2026-10-11 12:00:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'b2c3d4e5f6a7'
down_revision = 'a1b2c3d4e5f6'
branch_labels = None
depends_on = None


def upgrade():
    # Cria a tabela 'grupos'
    op.create_table('grupos',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('nome', sa.String(length=80), nullable=False),
        sa.Column('descricao', sa.String(length=255), nullable=True),
        sa.Column('papel', sa.String(length=50), server_default='agente', nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.PrimaryKeyConstraint('id')
    )
    with op.batch_alter_table('grupos', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_grupos_nome'), ['nome'], unique=True)

    # Cria a tabela associativa 'usuario_grupos'
    op.create_table('usuario_grupos',
        sa.Column('usuario_id', sa.Integer(), nullable=False),
        sa.Column('grupo_id', sa.Integer(), nullable=False),
        sa.ForeignKeyConstraint(['grupo_id'], ['grupos.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['usuario_id'], ['usuarios.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('usuario_id', 'grupo_id')
    )

    # Adiciona a coluna 'perfil' na tabela 'usuarios'
    with op.batch_alter_table('usuarios', schema=None) as batch_op:
        batch_op.add_column(sa.Column('perfil', sa.String(length=50), server_default='administrador', nullable=False))


def downgrade():
    with op.batch_alter_table('usuarios', schema=None) as batch_op:
        batch_op.drop_column('perfil')

    op.drop_table('usuario_grupos')

    with op.batch_alter_table('grupos', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_grupos_nome'))

    op.drop_table('grupos')
