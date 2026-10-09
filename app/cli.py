import os
import secrets
import click
from datetime import datetime, timedelta
from flask.cli import with_appcontext
from app.extensions import db
from app.models.user import User
from app.models.cliente import Cliente
from app.models.pedido import Pedido, ItemPedido
from app.models.lead import Lead
from app.services.prospector import TelecomProspectorService


def register_cli_commands(app):

    @app.cli.command('init-db')
    @with_appcontext
    def init_db_command():
        """Cria as tabelas do banco de dados diretamente."""
        db.create_all()
        click.echo('Banco de dados inicializado com sucesso!')

    @app.cli.command('create-admin')
    @click.option('--username', default='admin', help='Nome de usuário do admin.')
    @click.option('--email', default='admin@sistema.local', help='E-mail do admin.')
    @click.password_option('--password', help='Senha do admin (solicitada de forma oculta se omitida).')
    @with_appcontext
    def create_admin_command(username, email, password):
        """Cria um usuário administrador inicial."""
        if len(password) < 8:
            raise click.BadParameter('A senha deve ter pelo menos 8 caracteres.', param_hint='--password')

        user = User.query.filter((User.username == username) | (User.email == email)).first()
        if user:
            click.echo(f'Usuário {username} ou e-mail {email} já existe.')
            return

        admin = User(
            nome='Administrador do Sistema',
            username=username,
            email=email,
            ativo=True
        )
        admin.set_password(password)
        db.session.add(admin)
        db.session.commit()
        click.echo(f'Administrador "{username}" criado com sucesso!')

    @app.cli.command('seed')
    @with_appcontext
    def seed_command():
        """Popula o banco com usuário admin e dados fictícios de exemplo."""
        db.create_all()

        # Admin user
        admin = User.query.filter_by(username='admin').first()
        if not admin:
            # Sem senha fixa no código: usa SEED_ADMIN_PASSWORD ou gera uma aleatória
            senha_admin = os.environ.get('SEED_ADMIN_PASSWORD') or secrets.token_urlsafe(9)
            admin = User(
                nome='Administrador Master',
                username='admin',
                email='admin@exemplo.com',
                ativo=True
            )
            admin.set_password(senha_admin)
            db.session.add(admin)
            if os.environ.get('SEED_ADMIN_PASSWORD'):
                click.echo('Criado usuário "admin" com a senha definida em SEED_ADMIN_PASSWORD.')
            else:
                click.echo(f'Criado usuário "admin" com senha gerada: {senha_admin}')
                click.echo('Anote esta senha agora: ela não será exibida novamente.')

        # Sample clients
        if Cliente.query.count() == 0:
            clientes_exemplo = [
                Cliente(
                    nome='TechNova Soluções Digitais Ltda',
                    email='contato@technova.com.br',
                    telefone='(11) 98765-4321',
                    documento='12.345.678/0001-90',
                    cep='01310-100',
                    logradouro='Avenida Paulista',
                    numero='1000',
                    complemento='Conjunto 502',
                    bairro='Bela Vista',
                    cidade='São Paulo',
                    estado='SP',
                    ativo=True,
                    observacoes='Cliente corporativo, faturamento mensal.'
                ),
                Cliente(
                    nome='Mariana Albuquerque Silva',
                    email='mariana.albuquerque@gmail.com',
                    telefone='(21) 99876-5432',
                    documento='123.456.789-00',
                    cep='22041-001',
                    logradouro='Rua Barata Ribeiro',
                    numero='340',
                    complemento='Apto 402',
                    bairro='Copacabana',
                    cidade='Rio de Janeiro',
                    estado='RJ',
                    ativo=True,
                    observacoes='Cliente VIP desde 2024.'
                ),
                Cliente(
                    nome='Carlos Eduardo Mendes',
                    email='carlos.mendes@outlook.com',
                    telefone='(31) 98452-1122',
                    documento='987.654.321-99',
                    cep='30130-110',
                    logradouro='Avenida Afonso Pena',
                    numero='1500',
                    complemento='',
                    bairro='Centro',
                    cidade='Belo Horizonte',
                    estado='MG',
                    ativo=True,
                    observacoes='Prefere pagamentos via PIX.'
                ),
                Cliente(
                    nome='Distribuidora Sul Brasil',
                    email='compras@sulbrasil.com.br',
                    telefone='(41) 3222-8899',
                    documento='98.765.432/0001-11',
                    cep='80020-310',
                    logradouro='Rua XV de Novembro',
                    numero='780',
                    complemento='Loja 3',
                    bairro='Centro',
                    cidade='Curitiba',
                    estado='PR',
                    ativo=True,
                    observacoes='Pedido mínimo de 10 unidades.'
                ),
                Cliente(
                    nome='Juliana Prado Costa',
                    email='juliana.prado@yahoo.com.br',
                    telefone='(71) 99123-4567',
                    documento='333.444.555-66',
                    cep='40140-110',
                    logradouro='Avenida Oceânica',
                    numero='420',
                    complemento='Bloco B',
                    bairro='Barra',
                    cidade='Salvador',
                    estado='BA',
                    ativo=False,
                    observacoes='Cadastro temporariamente inativo a pedido do cliente.'
                ),
                # Clientes Estratégicos DigitalNet MS (Campo Grande)
                Cliente(
                    nome='Condomínio Residencial Parque das Nações',
                    email='sindico@parquedasnacoes.ms.gov.br',
                    telefone='(67) 3321-4455',
                    documento='04.123.456/0001-78',
                    cep='79040-010',
                    logradouro='Rua Raul Pires Barbosa',
                    numero='1250',
                    complemento='Administração',
                    bairro='Chácara Cachoeira',
                    cidade='Campo Grande',
                    estado='MS',
                    ativo=True,
                    observacoes='Condomínio atendido pela fibra DigitalNet com 60 apartamentos conectados.'
                ),
                Cliente(
                    nome='Clínica Médica Santa Fé Especializada',
                    email='contato@clinicasantafe.com.br',
                    telefone='(67) 3345-6789',
                    documento='18.987.654/0001-32',
                    cep='79021-120',
                    logradouro='Rua Ceará',
                    numero='840',
                    complemento='Sala 10',
                    bairro='Santa Fé',
                    cidade='Campo Grande',
                    estado='MS',
                    ativo=True,
                    observacoes='Link Fibra 700 + DigiMesh em comodato com suporte 24h.'
                ),
                Cliente(
                    nome='Escritório Silva & Associados Advocacia',
                    email='administrativo@silvaadvocacia.com.br',
                    telefone='(67) 3388-9900',
                    documento='22.333.444/0001-55',
                    cep='79002-001',
                    logradouro='Rua 14 de Julho',
                    numero='2100',
                    complemento='Andar 4',
                    bairro='Centro',
                    cidade='Campo Grande',
                    estado='MS',
                    ativo=True,
                    observacoes='Link Dedicado Pro com IP Fixo e redundância.'
                ),
                Cliente(
                    nome='Restaurante e Parrilla Pantaneira',
                    email='financeiro@parrillapantaneira.com.br',
                    telefone='(67) 3356-7890',
                    documento='33.444.555/0001-66',
                    cep='79020-000',
                    logradouro='Rua Euclides da Cunha',
                    numero='650',
                    complemento='',
                    bairro='Jardim dos Estados',
                    cidade='Campo Grande',
                    estado='MS',
                    ativo=True,
                    observacoes='Wi-Fi 6 de alta densidade para 80 clientes simultâneos.'
                ),
            ]
            db.session.add_all(clientes_exemplo)
            db.session.flush()

            # Sample orders with items
            pedidos_exemplo = [
                Pedido(
                    numero_pedido='PED-2026-0001',
                    cliente_id=clientes_exemplo[0].id,
                    data_pedido=datetime.utcnow() - timedelta(days=5),
                    status='concluido',
                    metodo_pagamento='pix',
                    valor_total=4850.00,
                    descricao='Desenvolvimento de módulo de relatórios e consultoria técnica especializada (40h).',
                    observacoes='Pago à vista via PIX com desconto de 5%.'
                ),
                Pedido(
                    numero_pedido='PED-2026-0002',
                    cliente_id=clientes_exemplo[1].id,
                    data_pedido=datetime.utcnow() - timedelta(days=3),
                    status='concluido',
                    metodo_pagamento='cartao_credito',
                    valor_total=1299.90,
                    descricao='Assinatura de plano anual Premium + Suporte prioritário 24/7.',
                    observacoes='Parcelado em 3x no cartão de crédito.'
                ),
                Pedido(
                    numero_pedido='PED-2026-0003',
                    cliente_id=clientes_exemplo[2].id,
                    data_pedido=datetime.utcnow() - timedelta(days=2),
                    status='processando',
                    metodo_pagamento='boleto',
                    valor_total=890.00,
                    descricao='Kit de equipamentos de automação e licença de software de gestão.',
                    observacoes='Aguardando compensação bancária do boleto emitido.'
                ),
                Pedido(
                    numero_pedido='PED-2026-0004',
                    cliente_id=clientes_exemplo[3].id,
                    data_pedido=datetime.utcnow() - timedelta(days=1),
                    status='pendente',
                    metodo_pagamento='pix',
                    valor_total=6420.50,
                    descricao='Lote de suprimentos de informática (cabos de rede Cat6, switches 8 portas gigabit).',
                    observacoes='Orçamento aprovado. Enviada chave PIX para faturamento.'
                ),
                Pedido(
                    numero_pedido='PED-2026-0005',
                    cliente_id=clientes_exemplo[0].id,
                    data_pedido=datetime.utcnow(),
                    status='pendente',
                    metodo_pagamento='transferencia',
                    valor_total=2500.00,
                    descricao='Renovação de hospedagem em nuvem e backup corporativo dedicado.',
                    observacoes='Fatura gerada com vencimento em 5 dias.'
                ),
            ]
            db.session.add_all(pedidos_exemplo)
            db.session.flush()

            # Add sample items for each order
            itens_exemplo = [
                # Pedido 1 (Total: 4850.00)
                ItemPedido(pedido_id=pedidos_exemplo[0].id, descricao='Desenvolvimento de módulo de relatórios personalizados', quantidade=1.0, valor_unitario=3500.00, valor_total=3500.00),
                ItemPedido(pedido_id=pedidos_exemplo[0].id, descricao='Consultoria técnica especializada (horas)', quantidade=10.0, valor_unitario=135.00, valor_total=1350.00),

                # Pedido 2 (Total: 1299.90)
                ItemPedido(pedido_id=pedidos_exemplo[1].id, descricao='Assinatura Anual Plano Premium Cloud', quantidade=1.0, valor_unitario=999.90, valor_total=999.90),
                ItemPedido(pedido_id=pedidos_exemplo[1].id, descricao='Pacote Suporte Prioritário 24/7 (trimestral)', quantidade=3.0, valor_unitario=100.00, valor_total=300.00),

                # Pedido 3 (Total: 890.00)
                ItemPedido(pedido_id=pedidos_exemplo[2].id, descricao='Kit de Equipamentos de Automação Comercial', quantidade=1.0, valor_unitario=590.00, valor_total=590.00),
                ItemPedido(pedido_id=pedidos_exemplo[2].id, descricao='Licença Adicional de Terminal OmniGestão', quantidade=1.0, valor_unitario=300.00, valor_total=300.00),

                # Pedido 4 (Total: 6420.50)
                ItemPedido(pedido_id=pedidos_exemplo[3].id, descricao='Cabo de Rede Furukawa Cat6 (Caixa 100m)', quantidade=2.0, valor_unitario=350.00, valor_total=700.00),
                ItemPedido(pedido_id=pedidos_exemplo[3].id, descricao='Switch Gigabit Ethernet 8 Portas TP-Link', quantidade=10.0, valor_unitario=180.00, valor_total=1800.00),
                ItemPedido(pedido_id=pedidos_exemplo[3].id, descricao='Roteador Corporativo Dual Band Wi-Fi 6', quantidade=3.0, valor_unitario=640.00, valor_total=1920.00),
                ItemPedido(pedido_id=pedidos_exemplo[3].id, descricao='Serviço de Conectorização e Certificação de Rede', quantidade=1.0, valor_unitario=2000.50, valor_total=2000.50),

                # Pedido 5 (Total: 2500.00)
                ItemPedido(pedido_id=pedidos_exemplo[4].id, descricao='Hospedagem Dedicada Cloud Server (Mensal)', quantidade=1.0, valor_unitario=1800.00, valor_total=1800.00),
                ItemPedido(pedido_id=pedidos_exemplo[4].id, descricao='Rotina de Backup Corporativo Offsite (500GB)', quantidade=1.0, valor_unitario=700.00, valor_total=700.00),
            ]
            db.session.add_all(itens_exemplo)
            click.echo('Clientes, Pedidos e Itens de exemplo cadastrados com sucesso!')

        # Sample leads for telecom prospecting in Campo Grande
        if Lead.query.count() == 0:
            leads_chacara = TelecomProspectorService.prospect_neighborhood(
                bairro='Chácara Cachoeira',
                cidade='Campo Grande',
                estado='MS',
                niche='Clínicas e Escritórios',
                count=4
            )
            leads_centro = TelecomProspectorService.prospect_neighborhood(
                bairro='Centro',
                cidade='Campo Grande',
                estado='MS',
                niche='Comércios e Contabilidade',
                count=3
            )
            TelecomProspectorService.save_prospects(leads_chacara + leads_centro)
            click.echo('Leads de prospecção geo-localizada em Campo Grande cadastrados com sucesso!')

        db.session.commit()
        click.echo('Processo de Seed finalizado!')
