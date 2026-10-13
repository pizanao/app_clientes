"""add_plano_id_to_pedidos

Revision ID: d4e5f6a7b8c9
Revises: c3d4e5f6a7b8
Create Date: 2026-10-11 17:30:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'd4e5f6a7b8c9'
down_revision = 'c3d4e5f6a7b8'
branch_labels = None
depends_on = None


def upgrade():
    with op.batch_alter_table('pedidos', schema=None) as batch_op:
        batch_op.add_column(sa.Column('plano_id', sa.Integer(), nullable=True))
        batch_op.create_index(batch_op.f('ix_pedidos_plano_id'), ['plano_id'], unique=False)
        batch_op.create_foreign_key(
            'fk_pedidos_plano_id_planos',
            'planos',
            ['plano_id'],
            ['id'],
            ondelete='SET NULL'
        )


def downgrade():
    with op.batch_alter_table('pedidos', schema=None) as batch_op:
        batch_op.drop_constraint('fk_pedidos_plano_id_planos', type_='foreignkey')
        batch_op.drop_index(batch_op.f('ix_pedidos_plano_id'))
        batch_op.drop_column('plano_id')
