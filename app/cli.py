import os
import secrets
import click
from datetime import datetime, timedelta
from flask.cli import with_appcontext
from app.extensions import db
from app.models.user import User, Grupo, PERFIL_ADMIN, PERFIL_LIDER, PERFIL_AGENTE
from app.models.cliente import Cliente
from app.models.pedido import Pedido, ItemPedido
from app.models.lead import Lead
from app.models.plano import Plano
from app.data.perfis_sisgran import normalizar_bairro
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

        grupo_admin = Grupo.query.filter_by(nome='Administração').first()
        if not grupo_admin:
            grupo_admin = Grupo(
                nome='Administração',
                papel=PERFIL_ADMIN,
                descricao='Grupo master de administradores do sistema.'
            )
            db.session.add(grupo_admin)

        admin = User(
            nome='Administrador do Sistema',
            username=username,
            email=email,
            perfil=PERFIL_ADMIN,
            ativo=True
        )
        admin.set_password(password)
        admin.grupos.append(grupo_admin)
        db.session.add(admin)
        db.session.commit()
        click.echo(f'Administrador "{username}" criado com sucesso!')

    @app.cli.command('set-admin-password')
    @click.argument('password')
    @with_appcontext
    def set_admin_password_command(password):
        """Redefine a senha do usuário admin e sincroniza instance/.admin_password."""
        admin = User.query.filter_by(username='admin').first()
        if not admin:
            click.echo('Usuário admin não encontrado.')
            return
        admin.set_password(password)
        db.session.commit()
        try:
            os.makedirs('instance', exist_ok=True)
            with open(os.path.join('instance', '.admin_password'), 'w', encoding='utf-8') as f:
                f.write(password)
        except Exception:
            pass
        click.echo('Senha do usuário "admin" atualizada com sucesso no banco de dados e em instance/.admin_password!')

    @app.cli.command('seed-planos')
    @with_appcontext
    def seed_planos_command():
        """Popula ou sincroniza os planos oficiais da DigitalNet (PF e PJ)."""
        db.create_all()
        total = Plano.seed_planos_iniciais()
        click.echo(f'{total} planos padrão oficiais da DigitalNet MS (PF e PJ) carregados com sucesso!')

    @app.cli.command('seed')
    @with_appcontext
    def seed_command():
        """Popula o banco com usuário admin, grupos de acesso, planos e dados fictícios de exemplo."""
        db.create_all()

        # 1. Grupos de Acesso Padrão
        grupo_admin = Grupo.query.filter_by(nome='Administração').first()
        if not grupo_admin:
            grupo_admin = Grupo(
                nome='Administração',
                papel=PERFIL_ADMIN,
                descricao='Controle total do sistema, auditoria, configurações e gestão de usuários.'
            )
            db.session.add(grupo_admin)

        grupo_lider = Grupo.query.filter_by(nome='Liderança Técnica').first()
        if not grupo_lider:
            grupo_lider = Grupo(
                nome='Liderança Técnica',
                papel=PERFIL_LIDER,
                descricao='Supervisão técnica, gestão de clientes, pedidos e expansão óptica.'
            )
            db.session.add(grupo_lider)

        grupo_comercial = Grupo.query.filter_by(nome='Equipe Comercial').first()
        if not grupo_comercial:
            grupo_comercial = Grupo(
                nome='Equipe Comercial',
                papel=PERFIL_AGENTE,
                descricao='Agentes de prospecção geo-localizada, abordagem WhatsApp e novos pedidos.'
            )
            db.session.add(grupo_comercial)

        db.session.flush()

        # 2. Usuário Admin Principal
        admin = User.query.filter_by(username='admin').first()
        if not admin:
            senha_admin = os.environ.get('SEED_ADMIN_PASSWORD') or secrets.token_urlsafe(9)
            admin = User(
                nome='Administrador Master',
                username='admin',
                email='admin@exemplo.com',
                perfil=PERFIL_ADMIN,
                ativo=True
            )
            admin.set_password(senha_admin)
            admin.grupos.append(grupo_admin)
            db.session.add(admin)

            # Persiste a senha do admin gerada em instance/.admin_password para exibição no resumo final
            try:
                os.makedirs('instance', exist_ok=True)
                with open(os.path.join('instance', '.admin_password'), 'w', encoding='utf-8') as f:
                    f.write(senha_admin)
            except Exception:
                pass

            if os.environ.get('SEED_ADMIN_PASSWORD'):
                click.echo('Criado usuário "admin" com a senha definida em SEED_ADMIN_PASSWORD.')
            else:
                click.echo('Criado usuário "admin" com a seguinte senha gerada:')
                click.echo(f'  {senha_admin}')
                click.echo('Recomenda-se alterar esta senha após o primeiro acesso.')
        else:
            if not admin.grupos:
                admin.grupos.append(grupo_admin)
            if os.environ.get('SEED_ADMIN_PASSWORD'):
                senha_env = os.environ.get('SEED_ADMIN_PASSWORD')
                admin.set_password(senha_env)
                try:
                    os.makedirs('instance', exist_ok=True)
                    with open(os.path.join('instance', '.admin_password'), 'w', encoding='utf-8') as f:
                        f.write(senha_env)
                except Exception:
                    pass
                click.echo('Senha do usuário "admin" sincronizada conforme SEED_ADMIN_PASSWORD.')
            else:
                click.echo('Usuário "admin" já existe.')

        # 3. Usuários Operacionais Exemplares (Líder Técnico e Agente)
        lider = User.query.filter_by(username='lider.tecnico').first()
        if not lider:
            lider = User(
                nome='Carlos Eduardo Mendes',
                username='lider.tecnico',
                email='carlos.mendes@digitalnetms.com.br',
                perfil=PERFIL_LIDER,
                ativo=True
            )
            lider.set_password('Lider#2026')
            lider.grupos.append(grupo_lider)
            db.session.add(lider)
            click.echo('Criado usuário líder técnico: "lider.tecnico" (Senha: Lider#2026)')

        agente = User.query.filter_by(username='agente.comercial').first()
        if not agente:
            agente = User(
                nome='Mariana Souza',
                username='agente.comercial',
                email='mariana.souza@digitalnetms.com.br',
                perfil=PERFIL_AGENTE,
                ativo=True
            )
            agente.set_password('Agente#2026')
            agente.grupos.append(grupo_comercial)
            db.session.add(agente)
            click.echo('Criado usuário agente comercial: "agente.comercial" (Senha: Agente#2026)')

        # 4. Planos de Banda Larga Oficiais DigitalNet (PF e PJ)
        if Plano.query.count() == 0:
            total_planos = Plano.seed_planos_iniciais()
            click.echo(f'{total_planos} Planos oficiais de banda larga (PF e PJ) cadastrados com sucesso!')

        # Sample clients (100% Campo Grande - MS com bairros canônicos)
        if Cliente.query.count() == 0:
            clientes_exemplo = [
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
                    nome='Auto Posto Afonso Pena & Conveniência',
                    email='gerencia@postoafonsopena.com.br',
                    telefone='(67) 3383-1122',
                    documento='25.654.321/0001-89',
                    cep='79002-071',
                    logradouro='Avenida Afonso Pena',
                    numero='2450',
                    complemento=None,
                    bairro='Centro',
                    cidade='Campo Grande',
                    estado='MS',
                    ativo=True,
                    observacoes='Cliente corporativo DigiCorp com Wi-Fi 6 e redundância para maquininhas de cartão.'
                ),
                Cliente(
                    nome='Hospital Santa Marina Especialidades',
                    email='diretoria@santamarina.med.br',
                    telefone='(67) 3316-2000',
                    documento='33.456.789/0001-01',
                    cep='79040-020',
                    logradouro='Rua Dr. Paulo Machado',
                    numero='500',
                    complemento='Bloco A',
                    bairro='Chácara Cachoeira',
                    cidade='Campo Grande',
                    estado='MS',
                    ativo=True,
                    observacoes='Link Dedicado Corporativo de alta disponibilidade com SLA de 4 horas.'
                ),
                Cliente(
                    nome='Mendes Advogados & Consultoria Jurídica',
                    email='contato@mendesadv.com.br',
                    telefone='(67) 3384-9000',
                    documento='44.567.890/0001-12',
                    cep='79020-000',
                    logradouro='Rua Euclides da Cunha',
                    numero='1120',
                    complemento='Andar 3',
                    bairro='Jardim dos Estados',
                    cidade='Campo Grande',
                    estado='MS',
                    ativo=True,
                    observacoes='Fibra óptica empresarial com upload simétrico para reuniões e audiências online.'
                ),
                Cliente(
                    nome='Supermercado Pantanal & Distribuidora',
                    email='compras@superpantanal.com.br',
                    telefone='(67) 3341-8080',
                    documento='55.678.901/0001-23',
                    cep='79051-000',
                    logradouro='Avenida Bom Pastor',
                    numero='780',
                    complemento=None,
                    bairro='Vilas Boas',
                    cidade='Campo Grande',
                    estado='MS',
                    ativo=True,
                    observacoes='Conexão de fibra DigiCorp PME para os caixas e sistema de estoque em nuvem.'
                )
            ]
            db.session.add_all(clientes_exemplo)
            db.session.flush()

            # Planos oficiais para associação nos pedidos
            plano_fibra700 = Plano.query.filter(Plano.nome.ilike('%700%')).first()
            plano_digicorp = Plano.query.filter(Plano.nome.ilike('%DigiCorp%')).first()
            plano_fibra900 = Plano.query.filter(Plano.nome.ilike('%900%')).first()

            # Pedidos de exemplo vinculados a planos e clientes de Campo Grande
            pedidos_exemplo = [
                Pedido(
                    numero_pedido='PED-2026-0001',
                    cliente_id=clientes_exemplo[0].id,
                    plano_id=plano_fibra700.id if plano_fibra700 else None,
                    data_pedido=datetime.utcnow() - timedelta(days=5),
                    status='concluido',
                    metodo_pagamento='pix',
                    valor_total=139.90,
                    descricao='Plano Oficial: Fibra 700 + DigiMesh (Wi-Fi 6) - Mensalidade Recorrente',
                    observacoes='Instalação de fibra concluída com 1 ponto de acesso Wi-Fi 6.'
                ),
                Pedido(
                    numero_pedido='PED-2026-0002',
                    cliente_id=clientes_exemplo[1].id,
                    plano_id=plano_digicorp.id if plano_digicorp else None,
                    data_pedido=datetime.utcnow() - timedelta(days=3),
                    status='concluido',
                    metodo_pagamento='boleto',
                    valor_total=399.90,
                    descricao='Plano Oficial: DigiCorp Link Dedicado PME (500 Mbps) - Mensalidade Recorrente',
                    observacoes='Contrato corporativo anual com SLA de 8h e IP fixo configurado.'
                ),
                Pedido(
                    numero_pedido='PED-2026-0003',
                    cliente_id=clientes_exemplo[2].id,
                    plano_id=plano_digicorp.id if plano_digicorp else None,
                    data_pedido=datetime.utcnow() - timedelta(days=2),
                    status='processando',
                    metodo_pagamento='cartao_credito',
                    valor_total=399.90,
                    descricao='Plano Oficial: DigiCorp Link Dedicado PME (500 Mbps) - Ordem de Instalação',
                    observacoes='Equipe técnica em campo para passagem de fibra óptica até o rack principal.'
                ),
                Pedido(
                    numero_pedido='PED-2026-0004',
                    cliente_id=clientes_exemplo[3].id,
                    plano_id=plano_fibra900.id if plano_fibra900 else None,
                    data_pedido=datetime.utcnow() - timedelta(days=1),
                    status='pendente',
                    metodo_pagamento='pix',
                    valor_total=149.90,
                    descricao='Plano Oficial: Fibra 900 Advanced (Wi-Fi 6) - Nova Ativação',
                    observacoes='Aguardando aprovação de viabilidade e agendamento da visita técnica.'
                ),
                Pedido(
                    numero_pedido='PED-2026-0005',
                    cliente_id=clientes_exemplo[4].id,
                    plano_id=plano_fibra700.id if plano_fibra700 else None,
                    data_pedido=datetime.utcnow(),
                    status='pendente',
                    metodo_pagamento='boleto',
                    valor_total=139.90,
                    descricao='Plano Oficial: Fibra 700 + DigiMesh (Wi-Fi 6) - Assinatura Mensal',
                    observacoes='Pedido gerado via radar de prospecção geo-localizada.'
                ),
            ]
            db.session.add_all(pedidos_exemplo)
            db.session.flush()

            # Itens de pedido correspondentes
            itens_exemplo = [
                # Pedido 1
                ItemPedido(pedido_id=pedidos_exemplo[0].id, descricao='Mensalidade Fibra 700 + DigiMesh (Wi-Fi 6)', quantidade=1.0, valor_unitario=139.90, valor_total=139.90),
                # Pedido 2
                ItemPedido(pedido_id=pedidos_exemplo[1].id, descricao='Mensalidade DigiCorp Link Dedicado PME (500 Mbps)', quantidade=1.0, valor_unitario=399.90, valor_total=399.90),
                # Pedido 3
                ItemPedido(pedido_id=pedidos_exemplo[2].id, descricao='Ativação e Mensalidade DigiCorp Link Dedicado PME', quantidade=1.0, valor_unitario=399.90, valor_total=399.90),
                # Pedido 4
                ItemPedido(pedido_id=pedidos_exemplo[3].id, descricao='Mensalidade Fibra 900 Advanced (Wi-Fi 6)', quantidade=1.0, valor_unitario=149.90, valor_total=149.90),
                # Pedido 5
                ItemPedido(pedido_id=pedidos_exemplo[4].id, descricao='Mensalidade Fibra 700 + DigiMesh (Wi-Fi 6)', quantidade=1.0, valor_unitario=139.90, valor_total=139.90),
            ]
            db.session.add_all(itens_exemplo)
            click.echo('Clientes e Pedidos de exemplo em Campo Grande - MS cadastrados com sucesso!')

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

    @app.cli.command('limpar-e-normalizar-bairros')
    @with_appcontext
    def limpar_e_normalizar_bairros_command():
        """Remove cadastros fora de MS e unifica nomes de bairros de Campo Grande para formato canônico."""
        db.create_all()

        # 1. Remover cadastros fora de MS
        clientes_fora = Cliente.query.filter((Cliente.estado != 'MS') | (Cliente.estado.is_(None))).all()
        removidos_clientes = len(clientes_fora)
        for c in clientes_fora:
            for p in c.pedidos:
                ItemPedido.query.filter_by(pedido_id=p.id).delete()
            Pedido.query.filter_by(cliente_id=c.id).delete()
            db.session.delete(c)

        leads_fora = Lead.query.filter((Lead.estado != 'MS') | (Lead.estado.is_(None))).all()
        removidos_leads = len(leads_fora)
        for l in leads_fora:
            db.session.delete(l)

        # 2. Normalizar bairros de todos os clientes
        clientes = Cliente.query.all()
        atualizados_clientes = 0
        for c in clientes:
            if c.bairro:
                b_norm = normalizar_bairro(c.bairro)
                if b_norm and b_norm != c.bairro:
                    c.bairro = b_norm
                    atualizados_clientes += 1

        # 3. Normalizar bairros de todos os leads
        leads = Lead.query.all()
        atualizados_leads = 0
        for l in leads:
            if l.bairro:
                b_norm = normalizar_bairro(l.bairro)
                if b_norm and b_norm != l.bairro:
                    l.bairro = b_norm
                    atualizados_leads += 1

        db.session.commit()
        click.echo("Processo de limpeza e normalização concluído com sucesso:")
        click.echo(f"  - Clientes de fora de MS removidos: {removidos_clientes}")
        click.echo(f"  - Leads de fora de MS removidos: {removidos_leads}")
        click.echo(f"  - Bairros de clientes normalizados: {atualizados_clientes}")
        click.echo(f"  - Bairros de leads normalizados: {atualizados_leads}")
