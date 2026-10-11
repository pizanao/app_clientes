from flask import Blueprint, render_template, redirect, url_for, flash, request
from flask_login import login_required, current_user
from sqlalchemy import or_
from sqlalchemy.orm import selectinload
from app.extensions import db
from app.models.user import User, Grupo, PERFIL_ADMIN, PERFIL_LIDER, PERFIL_AGENTE, PERFIS
from app.models.plano import Plano, TIPO_PF, TIPO_PJ, TIPOS_PLANO
from app.forms.admin_forms import UsuarioCreateForm, UsuarioEditForm, GrupoForm, PlanoForm
from app.utils.auth_decorators import admin_required

admin_bp = Blueprint('admin', __name__, url_prefix='/admin')


# ==============================================================================
# GESTÃO DE USUÁRIOS
# ==============================================================================

@admin_bp.route('/usuarios')
@login_required
@admin_required
def usuarios():
    search = request.args.get('q', '').strip()
    perfil_filter = request.args.get('perfil', 'todos')
    status_filter = request.args.get('status', 'todos')
    grupo_filter = request.args.get('grupo_id', type=int)

    query = User.query.options(selectinload(User.grupos))

    if search:
        search_term = f"%{search}%"
        query = query.filter(
            or_(
                User.nome.ilike(search_term),
                User.username.ilike(search_term),
                User.email.ilike(search_term)
            )
        )

    if perfil_filter in PERFIS:
        query = query.filter(User.perfil == perfil_filter)

    if status_filter == 'ativo':
        query = query.filter(User.ativo == True)
    elif status_filter == 'inativo':
        query = query.filter(User.ativo == False)

    if grupo_filter:
        query = query.join(User.grupos).filter(Grupo.id == grupo_filter)

    usuarios_lista = query.order_by(User.nome.asc()).all()

    # Estatísticas rápidas
    total_usuarios = User.query.count()
    total_admins = User.query.filter_by(perfil=PERFIL_ADMIN).count()
    total_lideres = User.query.filter_by(perfil=PERFIL_LIDER).count()
    total_agentes = User.query.filter_by(perfil=PERFIL_AGENTE).count()
    grupos_disponiveis = Grupo.query.order_by(Grupo.nome.asc()).all()

    return render_template(
        'admin/usuarios/index.html',
        usuarios=usuarios_lista,
        search=search,
        perfil_filter=perfil_filter,
        status_filter=status_filter,
        grupo_filter=grupo_filter,
        total_encontrados=len(usuarios_lista),
        total_usuarios=total_usuarios,
        total_admins=total_admins,
        total_lideres=total_lideres,
        total_agentes=total_agentes,
        grupos=grupos_disponiveis,
        perfis=PERFIS
    )


@admin_bp.route('/usuarios/novo', methods=['GET', 'POST'])
@login_required
@admin_required
def usuario_novo():
    form = UsuarioCreateForm()
    grupos = Grupo.query.order_by(Grupo.nome.asc()).all()
    form.grupos.choices = [(g.id, f"{g.nome} ({g.papel_nome})") for g in grupos]

    if form.validate_on_submit():
        user = User(
            nome=form.nome.data.strip(),
            username=form.username.data.strip(),
            email=form.email.data.strip().lower(),
            perfil=form.perfil.data,
            ativo=form.ativo.data
        )
        user.set_password(form.password.data)

        if form.grupos.data:
            grupos_selecionados = Grupo.query.filter(Grupo.id.in_(form.grupos.data)).all()
            user.grupos = grupos_selecionados

        db.session.add(user)
        db.session.commit()

        flash(f'Usuário "{user.nome}" ({user.perfil_nome}) cadastrado com sucesso!', 'success')
        return redirect(url_for('admin.usuarios'))

    return render_template('admin/usuarios/form.html', form=form, titulo='Novo Usuário', acao='Cadastrar', grupos=grupos)


@admin_bp.route('/usuarios/<int:id>/editar', methods=['GET', 'POST'])
@login_required
@admin_required
def usuario_editar(id):
    user = db.session.get(User, id)
    if not user:
        flash('Usuário não encontrado.', 'danger')
        return redirect(url_for('admin.usuarios'))

    grupos = Grupo.query.order_by(Grupo.nome.asc()).all()
    form = UsuarioEditForm(original_user=user, obj=user)
    form.grupos.choices = [(g.id, f"{g.nome} ({g.papel_nome})") for g in grupos]

    if request.method == 'GET':
        form.grupos.data = [g.id for g in user.grupos]

    if form.validate_on_submit():
        # Trava: Administrador não pode desativar a própria conta
        if user.id == current_user.id and not form.ativo.data:
            flash('Você não pode desativar sua própria conta de usuário enquanto estiver conectado.', 'danger')
            return render_template('admin/usuarios/form.html', form=form, usuario=user, titulo='Editar Usuário', acao='Salvar Alterações', grupos=grupos)

        # Trava: Não remover perfil de admin do próprio usuário se for o único admin ativo
        if user.id == current_user.id and form.perfil.data != PERFIL_ADMIN:
            outros_admins = User.query.filter(User.perfil == PERFIL_ADMIN, User.ativo == True, User.id != user.id).count()
            if outros_admins == 0:
                flash('Você não pode revogar seu perfil de Administrador, pois é o único administrador ativo no sistema.', 'danger')
                return render_template('admin/usuarios/form.html', form=form, usuario=user, titulo='Editar Usuário', acao='Salvar Alterações', grupos=grupos)

        user.nome = form.nome.data.strip()
        user.username = form.username.data.strip()
        user.email = form.email.data.strip().lower()
        user.perfil = form.perfil.data
        user.ativo = form.ativo.data

        if form.password.data and form.password.data.strip():
            user.set_password(form.password.data.strip())

        if form.grupos.data is not None:
            grupos_selecionados = Grupo.query.filter(Grupo.id.in_(form.grupos.data)).all()
            user.grupos = grupos_selecionados

        db.session.commit()
        flash(f'Usuário "{user.nome}" atualizado com sucesso!', 'success')
        return redirect(url_for('admin.usuarios'))

    return render_template('admin/usuarios/form.html', form=form, usuario=user, titulo='Editar Usuário', acao='Salvar Alterações', grupos=grupos)


@admin_bp.route('/usuarios/<int:id>/toggle-status', methods=['POST'])
@login_required
@admin_required
def usuario_toggle_status(id):
    user = db.session.get(User, id)
    if not user:
        flash('Usuário não encontrado.', 'danger')
        return redirect(url_for('admin.usuarios'))

    if user.id == current_user.id:
        flash('Você não pode alterar o status da sua própria conta de usuário.', 'danger')
        return redirect(url_for('admin.usuarios'))

    # Se for admin e estiver ativo, verifica se não é o único
    if user.is_admin and user.ativo:
        outros_admins = User.query.filter(User.perfil == PERFIL_ADMIN, User.ativo == True, User.id != user.id).count()
        if outros_admins == 0:
            flash('Não é possível desativar o único Administrador ativo no sistema.', 'danger')
            return redirect(url_for('admin.usuarios'))

    user.ativo = not user.ativo
    db.session.commit()

    novo_status = 'ativado' if user.ativo else 'desativado'
    flash(f'Usuário "{user.nome}" {novo_status} com sucesso.', 'info')
    return redirect(url_for('admin.usuarios'))


@admin_bp.route('/usuarios/<int:id>/excluir', methods=['POST'])
@login_required
@admin_required
def usuario_excluir(id):
    user = db.session.get(User, id)
    if not user:
        flash('Usuário não encontrado.', 'danger')
        return redirect(url_for('admin.usuarios'))

    if user.id == current_user.id:
        flash('Você não pode excluir sua própria conta de usuário.', 'danger')
        return redirect(url_for('admin.usuarios'))

    if user.is_admin:
        outros_admins = User.query.filter(User.perfil == PERFIL_ADMIN, User.ativo == True, User.id != user.id).count()
        if outros_admins == 0:
            flash('Não é possível excluir o único Administrador ativo do sistema.', 'danger')
            return redirect(url_for('admin.usuarios'))

    nome = user.nome
    db.session.delete(user)
    db.session.commit()

    flash(f'Usuário "{nome}" excluído com sucesso.', 'info')
    return redirect(url_for('admin.usuarios'))


# ==============================================================================
# GESTÃO DE GRUPOS DE ACESSO E ATRIBUIÇÃO DE PAPÉIS
# ==============================================================================

@admin_bp.route('/grupos')
@login_required
@admin_required
def grupos():
    grupos_lista = Grupo.query.options(selectinload(Grupo.usuarios)).order_by(Grupo.nome.asc()).all()
    total_grupos = len(grupos_lista)
    return render_template(
        'admin/grupos/index.html',
        grupos=grupos_lista,
        total_grupos=total_grupos,
        perfis=PERFIS
    )


@admin_bp.route('/grupos/novo', methods=['GET', 'POST'])
@login_required
@admin_required
def grupo_novo():
    form = GrupoForm()
    usuarios_todos = User.query.filter_by(ativo=True).order_by(User.nome.asc()).all()
    form.membros.choices = [(u.id, f"{u.nome} (@{u.username})") for u in usuarios_todos]

    if form.validate_on_submit():
        grupo = Grupo(
            nome=form.nome.data.strip(),
            papel=form.papel.data,
            descricao=form.descricao.data.strip() if form.descricao.data else None
        )

        if form.membros.data:
            membros_selecionados = User.query.filter(User.id.in_(form.membros.data)).all()
            grupo.usuarios = membros_selecionados

        db.session.add(grupo)
        db.session.commit()

        flash(f'Grupo de acesso "{grupo.nome}" criado com sucesso com papel de {grupo.papel_nome}!', 'success')
        return redirect(url_for('admin.grupos'))

    return render_template('admin/grupos/form.html', form=form, titulo='Novo Grupo de Acesso', acao='Cadastrar', usuarios=usuarios_todos)


@admin_bp.route('/grupos/<int:id>/editar', methods=['GET', 'POST'])
@login_required
@admin_required
def grupo_editar(id):
    grupo = db.session.get(Grupo, id)
    if not grupo:
        flash('Grupo de acesso não encontrado.', 'danger')
        return redirect(url_for('admin.grupos'))

    usuarios_todos = User.query.filter_by(ativo=True).order_by(User.nome.asc()).all()
    form = GrupoForm(original_grupo=grupo, obj=grupo)
    form.membros.choices = [(u.id, f"{u.nome} (@{u.username})") for u in usuarios_todos]

    if request.method == 'GET':
        form.membros.data = [u.id for u in grupo.usuarios]

    if form.validate_on_submit():
        grupo.nome = form.nome.data.strip()
        grupo.papel = form.papel.data
        grupo.descricao = form.descricao.data.strip() if form.descricao.data else None

        if form.membros.data is not None:
            membros_selecionados = User.query.filter(User.id.in_(form.membros.data)).all()
            grupo.usuarios = membros_selecionados

        db.session.commit()
        flash(f'Grupo "{grupo.nome}" atualizado com sucesso!', 'success')
        return redirect(url_for('admin.grupos'))

    return render_template('admin/grupos/form.html', form=form, grupo=grupo, titulo='Editar Grupo de Acesso', acao='Salvar Alterações', usuarios=usuarios_todos)


@admin_bp.route('/grupos/<int:id>/excluir', methods=['POST'])
@login_required
@admin_required
def grupo_excluir(id):
    grupo = db.session.get(Grupo, id)
    if not grupo:
        flash('Grupo de acesso não encontrado.', 'danger')
        return redirect(url_for('admin.grupos'))

    nome = grupo.nome
    membros_qtd = len(grupo.usuarios)
    db.session.delete(grupo)
    db.session.commit()

    flash(f'Grupo "{nome}" excluído com sucesso ({membros_qtd} usuário(s) desvinculados).', 'info')
    return redirect(url_for('admin.grupos'))


# ==============================================================================
# GESTÃO DE PLANOS DE BANDA LARGA (PF & PJ - DIGITALNET)
# ==============================================================================

@admin_bp.route('/planos')
@login_required
@admin_required
def planos():
    search = request.args.get('q', '').strip()
    tipo_filter = request.args.get('tipo', 'todos')
    status_filter = request.args.get('status', 'todos')

    query = Plano.query

    if search:
        search_term = f"%{search}%"
        query = query.filter(
            or_(
                Plano.nome.ilike(search_term),
                Plano.descricao.ilike(search_term),
                Plano.beneficios.ilike(search_term),
                Plano.aplicativos_inclusos.ilike(search_term)
            )
        )

    if tipo_filter in [TIPO_PF, TIPO_PJ]:
        query = query.filter(Plano.tipo == tipo_filter)

    if status_filter == 'ativo':
        query = query.filter(Plano.ativo == True)
    elif status_filter == 'inativo':
        query = query.filter(Plano.ativo == False)

    planos_lista = query.order_by(Plano.tipo.asc(), Plano.velocidade_download.asc(), Plano.valor_mensal.asc()).all()

    # Estatísticas
    total_planos = Plano.query.count()
    total_pf = Plano.query.filter_by(tipo=TIPO_PF).count()
    total_pj = Plano.query.filter_by(tipo=TIPO_PJ).count()
    total_ativos = Plano.query.filter_by(ativo=True).count()

    return render_template(
        'admin/planos/index.html',
        planos=planos_lista,
        search=search,
        tipo_filter=tipo_filter,
        status_filter=status_filter,
        total_encontrados=len(planos_lista),
        total_planos=total_planos,
        total_pf=total_pf,
        total_pj=total_pj,
        total_ativos=total_ativos,
        tipos_plano=TIPOS_PLANO,
        tipo_pf=TIPO_PF,
        tipo_pj=TIPO_PJ
    )


@admin_bp.route('/planos/novo', methods=['GET', 'POST'])
@login_required
@admin_required
def plano_novo():
    form = PlanoForm()
    if form.validate_on_submit():
        plano = Plano(
            nome=form.nome.data.strip(),
            tipo=form.tipo.data,
            velocidade_download=form.velocidade_download.data,
            velocidade_upload=form.velocidade_upload.data,
            valor_mensal=float(form.valor_mensal.data),
            valor_cheio=float(form.valor_cheio.data) if form.valor_cheio.data else None,
            fidelidade_meses=form.fidelidade_meses.data,
            roteador_wifi=form.roteador_wifi.data.strip() if form.roteador_wifi.data else None,
            aplicativos_inclusos=form.aplicativos_inclusos.data.strip() if form.aplicativos_inclusos.data else None,
            beneficios=form.beneficios.data.strip() if form.beneficios.data else None,
            descricao=form.descricao.data.strip() if form.descricao.data else None,
            sla_horas=form.sla_horas.data,
            linhas_simultaneas=form.linhas_simultaneas.data,
            pabx_virtual=form.pabx_virtual.data,
            ip_fixo=form.ip_fixo.data,
            ativo=form.ativo.data,
            destaque=form.destaque.data,
            observacoes=form.observacoes.data.strip() if form.observacoes.data else None
        )
        db.session.add(plano)
        db.session.commit()

        flash(f'Plano "{plano.nome}" ({plano.tipo_nome}) cadastrado com sucesso!', 'success')
        return redirect(url_for('admin.planos'))

    return render_template(
        'admin/planos/form.html',
        form=form,
        titulo='Novo Plano de Banda Larga',
        acao='Cadastrar Plano'
    )


@admin_bp.route('/planos/<int:id>/editar', methods=['GET', 'POST'])
@login_required
@admin_required
def plano_editar(id):
    plano = db.session.get(Plano, id)
    if not plano:
        flash('Plano não encontrado.', 'danger')
        return redirect(url_for('admin.planos'))

    form = PlanoForm(original_plano=plano, obj=plano)

    if form.validate_on_submit():
        plano.nome = form.nome.data.strip()
        plano.tipo = form.tipo.data
        plano.velocidade_download = form.velocidade_download.data
        plano.velocidade_upload = form.velocidade_upload.data
        plano.valor_mensal = float(form.valor_mensal.data)
        plano.valor_cheio = float(form.valor_cheio.data) if form.valor_cheio.data else None
        plano.fidelidade_meses = form.fidelidade_meses.data
        plano.roteador_wifi = form.roteador_wifi.data.strip() if form.roteador_wifi.data else None
        plano.aplicativos_inclusos = form.aplicativos_inclusos.data.strip() if form.aplicativos_inclusos.data else None
        plano.beneficios = form.beneficios.data.strip() if form.beneficios.data else None
        plano.descricao = form.descricao.data.strip() if form.descricao.data else None
        plano.sla_horas = form.sla_horas.data
        plano.linhas_simultaneas = form.linhas_simultaneas.data
        plano.pabx_virtual = form.pabx_virtual.data
        plano.ip_fixo = form.ip_fixo.data
        plano.ativo = form.ativo.data
        plano.destaque = form.destaque.data
        plano.observacoes = form.observacoes.data.strip() if form.observacoes.data else None

        db.session.commit()
        flash(f'Plano "{plano.nome}" atualizado com sucesso!', 'success')
        return redirect(url_for('admin.planos'))

    return render_template(
        'admin/planos/form.html',
        form=form,
        plano=plano,
        titulo='Editar Plano de Banda Larga',
        acao='Salvar Alterações'
    )


@admin_bp.route('/planos/<int:id>/toggle-status', methods=['POST'])
@login_required
@admin_required
def plano_toggle_status(id):
    plano = db.session.get(Plano, id)
    if not plano:
        flash('Plano não encontrado.', 'danger')
        return redirect(url_for('admin.planos'))

    plano.ativo = not plano.ativo
    db.session.commit()

    status_str = 'ativado' if plano.ativo else 'desativado'
    flash(f'Plano "{plano.nome}" {status_str} com sucesso.', 'info')
    return redirect(url_for('admin.planos'))


@admin_bp.route('/planos/<int:id>/excluir', methods=['POST'])
@login_required
@admin_required
def plano_excluir(id):
    plano = db.session.get(Plano, id)
    if not plano:
        flash('Plano não encontrado.', 'danger')
        return redirect(url_for('admin.planos'))

    nome = plano.nome
    db.session.delete(plano)
    db.session.commit()

    flash(f'Plano "{nome}" excluído com sucesso.', 'info')
    return redirect(url_for('admin.planos'))


@admin_bp.route('/planos/sincronizar-padrao', methods=['POST'])
@login_required
@admin_required
def planos_sincronizar_padrao():
    total = Plano.seed_planos_iniciais()
    flash(f'{total} planos padrão oficiais da DigitalNet MS (PF e PJ) foram sincronizados com sucesso!', 'success')
    return redirect(url_for('admin.planos'))
