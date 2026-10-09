"""add_leads_table

Revision ID: a1b2c3d4e5f6
Revises: 99d1cc5b3cb2
Create Date: 2026-10-08 15:35:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'a1b2c3d4e5f6'
down_revision = '99d1cc5b3cb2'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table('leads',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('nome', sa.String(length=120), nullable=False),
    sa.Column('empresa', sa.String(length=150), nullable=False),
    sa.Column('cargo', sa.String(length=100), nullable=True),
    sa.Column('telefone', sa.String(length=30), nullable=True),
    sa.Column('email', sa.String(length=120), nullable=True),
    sa.Column('documento', sa.String(length=30), nullable=True),
    sa.Column('niche', sa.String(length=100), nullable=True),
    sa.Column('cep', sa.String(length=15), nullable=True),
    sa.Column('logradouro', sa.String(length=150), nullable=True),
    sa.Column('numero', sa.String(length=20), nullable=True),
    sa.Column('complemento', sa.String(length=50), nullable=True),
    sa.Column('bairro', sa.String(length=80), nullable=False),
    sa.Column('cidade', sa.String(length=80), nullable=False),
    sa.Column('estado', sa.String(length=2), nullable=False),
    sa.Column('cliente_referencia_id', sa.Integer(), nullable=True),
    sa.Column('status', sa.String(length=30), nullable=False),
    sa.Column('optin_status', sa.String(length=20), nullable=False),
    sa.Column('operadora_atual', sa.String(length=80), nullable=True),
    sa.Column('plano_sugerido', sa.String(length=120), nullable=True),
    sa.Column('valor_mensal_sugerido', sa.Float(), nullable=False),
    sa.Column('lead_score', sa.Integer(), nullable=False),
    sa.Column('dor_principal', sa.Text(), nullable=True),
    sa.Column('icebreaker_optin', sa.Text(), nullable=True),
    sa.Column('dossie_comercial', sa.Text(), nullable=True),
    sa.Column('observacoes', sa.Text(), nullable=True),
    sa.Column('cliente_convertido_id', sa.Integer(), nullable=True),
    sa.Column('created_at', sa.DateTime(), nullable=False),
    sa.Column('updated_at', sa.DateTime(), nullable=False),
    sa.ForeignKeyConstraint(['cliente_referencia_id'], ['clientes.id'], ondelete='SET NULL'),
    sa.ForeignKeyConstraint(['cliente_convertido_id'], ['clientes.id'], ondelete='SET NULL'),
    sa.PrimaryKeyConstraint('id')
    )
    with op.batch_alter_table('leads', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_leads_nome'), ['nome'], unique=False)
        batch_op.create_index(batch_op.f('ix_leads_empresa'), ['empresa'], unique=False)
        batch_op.create_index(batch_op.f('ix_leads_bairro'), ['bairro'], unique=False)
        batch_op.create_index(batch_op.f('ix_leads_cidade'), ['cidade'], unique=False)
        batch_op.create_index(batch_op.f('ix_leads_status'), ['status'], unique=False)
        batch_op.create_index(batch_op.f('ix_leads_optin_status'), ['optin_status'], unique=False)
        batch_op.create_index(batch_op.f('ix_leads_cliente_referencia_id'), ['cliente_referencia_id'], unique=False)
        batch_op.create_index(batch_op.f('ix_leads_cliente_convertido_id'), ['cliente_convertido_id'], unique=False)


def downgrade():
    with op.batch_alter_table('leads', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_leads_cliente_convertido_id'))
        batch_op.drop_index(batch_op.f('ix_leads_cliente_referencia_id'))
        batch_op.drop_index(batch_op.f('ix_leads_optin_status'))
        batch_op.drop_index(batch_op.f('ix_leads_status'))
        batch_op.drop_index(batch_op.f('ix_leads_cidade'))
        batch_op.drop_index(batch_op.f('ix_leads_bairro'))
        batch_op.drop_index(batch_op.f('ix_leads_empresa'))
        batch_op.drop_index(batch_op.f('ix_leads_nome'))

    op.drop_table('leads')
