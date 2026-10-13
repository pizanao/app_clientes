#!/usr/bin/env python3
"""
Script Automatizado de Demonstração e Gravação em Vídeo com Playwright.

Executa o fluxo completo do sistema DigitalNet-Prospector com gravação de vídeo em alta definição:
1. Autenticação e Login como Administrador (admin).
2. Acesso ao Radar de Leads & Expansão de Fibra Óptica (/leads/).
3. Demonstração do Mapa de Cobertura de Campo Grande com nós ópticos (CTO) e oportunidades.
4. Prospecção Geo-Localizada: clique no nó/cliente de fibra, acionando 'Carregar Empresas do Nó' e exibindo a gaveta lateral (Offcanvas).
5. Apresentação da Lista de Leads com DataTables Responsive e expansão de Linhas Aninhadas (Child Rows).
6. Acesso ao Dossiê 360° do Lead (/leads/<id>), exibindo decisor, dados de viabilidade e scripts anti-ban.
7. Interação com o Tutor de Quebra de Objeções (SDR Telecom) e opt-in via WhatsApp.
8. Simulação de conversão comercial do lead em Cliente com ativação imediata do Pedido de Banda Larga.
9. Apresentação do Cliente cadastrado e do Pedido gerado (/pedidos/<id>).
10. Demonstração do Controle de Acesso por Perfis (RBAC) e Painel Administrativo (/admin/usuarios e /admin/grupos).
11. Finalização e exportação do vídeo em formatos WebM e MP4 (via FFmpeg).

Uso:
    python scripts/gravar_demonstracao.py
    python scripts/gravar_demonstracao.py --headed     # Exibe a janela do navegador em tempo real
    python scripts/gravar_demonstracao.py --port 5055
"""

import argparse
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VIDEOS_DIR = ROOT / 'videos'


def obter_senha_admin() -> str:
    """Recupera a senha do usuário admin ou define a padrão."""
    senha_file = ROOT / 'instance' / '.admin_password'
    if senha_file.exists():
        senha = senha_file.read_text(encoding='utf-8').strip()
        if senha:
            return senha
    return 'SenhaSeed*2026'


def sincronizar_credenciais_admin(senha: str):
    """Garante que a senha do usuário admin no banco de dados SQLite esteja sincronizada com a senha esperada."""
    try:
        if str(ROOT) not in sys.path:
            sys.path.insert(0, str(ROOT))
        from wsgi import app
        from app.models.user import User
        from app.extensions import db
        with app.app_context():
            admin = User.query.filter_by(username='admin').first()
            if admin and not admin.check_password(senha):
                print(f"[*] Sincronizando senha do admin no banco para a gravação...")
                admin.set_password(senha)
                db.session.commit()
    except Exception as e:
        print(f"[!] Aviso ao verificar credenciais: {e}")


def verificar_ou_iniciar_servidor(base_url: str, port: int):
    """Verifica se o servidor Flask está respondendo na porta desejada ou inicia um."""
    import urllib.request
    try:
        with urllib.request.urlopen(f"{base_url}/auth/login", timeout=2) as resp:
            if resp.status == 200:
                print(f"[OK] Servidor detectado ativo em {base_url}")
                return None
    except Exception:
        pass

    print(f"[*] Iniciando servidor local Flask na porta {port}...")
    env = os.environ.copy()
    env['PORT'] = str(port)
    env['FLASK_APP'] = 'wsgi.py'
    env['FLASK_DEBUG'] = '1'
    env['SECRET_KEY'] = 'dev-secret-key-super-secure-change-in-prod-12345'
    
    python_bin = sys.executable
    processo = subprocess.Popen(
        [python_bin, 'wsgi.py'],
        cwd=str(ROOT),
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )

    for i in range(25):
        time.sleep(0.5)
        try:
            with urllib.request.urlopen(f"{base_url}/auth/login", timeout=1) as resp:
                if resp.status == 200:
                    print(f"[OK] Servidor inicializado com sucesso em {base_url}!")
                    return processo
        except Exception:
            continue

    print("[AVISO] Servidor iniciado, continuando com os testes...")
    return processo


def localizar_ffmpeg() -> str | None:
    """Localiza o binário do FFmpeg no sistema."""
    ffmpeg_cmd = shutil.which('ffmpeg')
    if ffmpeg_cmd:
        return ffmpeg_cmd

    winget_path = Path.home() / 'AppData' / 'Local' / 'Microsoft' / 'WinGet' / 'Links' / 'ffmpeg.exe'
    if winget_path.exists():
        return str(winget_path)

    local_app = os.environ.get('LOCALAPPDATA', '')
    if local_app:
        candidatos = list(Path(local_app).glob('**/ffmpeg.exe'))
        if candidatos:
            return str(candidatos[0])

    return None


def obter_duracao_audio(caminho: Path) -> float:
    """Retorna a duração em segundos de um arquivo de áudio via ffprobe."""
    try:
        res = subprocess.run(
            [
                'ffprobe', '-v', 'error',
                '-show_entries', 'format=duration',
                '-of', 'default=noprint_wrappers=1:nokey=1',
                str(caminho)
            ],
            capture_output=True,
            text=True,
            check=True
        )
        return float(res.stdout.strip())
    except Exception:
        return 0.0


def converter_para_mp4(webm_path: Path, audio_path: Path | None = None) -> Path:
    """Converte o arquivo WebM para MP4 usando FFmpeg e embute a trilha de áudio se disponível."""
    ffmpeg_cmd = localizar_ffmpeg()
    if not ffmpeg_cmd:
        print("[!] FFmpeg não encontrado no PATH. O vídeo em formato WebM foi preservado.")
        return webm_path

    mp4_path = webm_path.with_suffix('.mp4')

    if audio_path is None:
        audio_padrao = VIDEOS_DIR / 'naracao_demonstracao.wav'
        if audio_padrao.exists():
            audio_path = audio_padrao

    print(f"[*] Convertendo {webm_path.name} para MP4 usando FFmpeg ({ffmpeg_cmd})...")
    cmd = [ffmpeg_cmd, '-y', '-i', str(webm_path)]
    if audio_path and audio_path.exists():
        print(f"[*] Embutindo trilha de áudio narrada: {audio_path.name}...")
        cmd.extend([
            '-i', str(audio_path),
            '-c:v', 'libx264',
            '-pix_fmt', 'yuv420p',
            '-crf', '22',
            '-c:a', 'aac',
            '-b:a', '192k',
            '-shortest'
        ])
    else:
        cmd.extend(['-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '22'])

    cmd.append(str(mp4_path))
    try:
        subprocess.run(
            cmd,
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        print(f"[OK] Vídeo convertido com sucesso: {mp4_path}")
        return mp4_path
    except Exception as e:
        print(f"[!] Falha na conversão para MP4: {e}")
        return webm_path


def converter_para_whatsapp(mp4_origem: Path) -> Path | None:
    """Gera uma versão compactada do MP4 otimizada para envio e reprodução direta no WhatsApp."""
    ffmpeg_cmd = localizar_ffmpeg()
    if not ffmpeg_cmd or not mp4_origem.exists() or mp4_origem.suffix != '.mp4':
        return None

    saida_whatsapp = mp4_origem.parent / f"{mp4_origem.stem}_whatsapp.mp4"
    saida_recente_whatsapp = mp4_origem.parent / "demonstracao_digitalnet_whatsapp.mp4"

    print(f"[*] Gerando versão otimizada para WhatsApp (<16MB, 720p, +faststart)...")
    cmd = [
        ffmpeg_cmd, '-y', '-i', str(mp4_origem),
        '-vf', 'scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2',
        '-c:v', 'libx264', '-profile:v', 'high', '-level', '4.0', '-pix_fmt', 'yuv420p', '-crf', '24', '-preset', 'slow',
        '-c:a', 'aac', '-b:a', '96k', '-ar', '44100', '-ac', '1',
        '-movflags', '+faststart',
        str(saida_whatsapp)
    ]
    try:
        subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        shutil.copy(str(saida_whatsapp), str(saida_recente_whatsapp))
        tamanho_mb = saida_whatsapp.stat().st_size / (1024 * 1024)
        print(f"[OK] Versão para WhatsApp criada com sucesso: {saida_whatsapp.name} ({tamanho_mb:.2f} MB)")
        return saida_whatsapp
    except Exception as e:
        print(f"[!] Falha ao gerar versão para WhatsApp: {e}")
        return None




def gravar_fluxo(
    base_url: str,
    headed: bool = False,
    slow_mo: int = 500,
    audio_path: Path | None = None,
    sync_audio: bool = True,
    gerar_whatsapp: bool = True
):
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        print("\n" + "=" * 75)
        print("[ERRO] A biblioteca Playwright não está instalada no ambiente virtual.")
        print("Para utilizar o gravador automatizado de demonstração, instale com:")
        print("    pip install playwright")
        print("    playwright install chromium")
        print("=" * 75 + "\n")
        sys.exit(1)

    VIDEOS_DIR.mkdir(parents=True, exist_ok=True)
    temp_video_dir = VIDEOS_DIR / 'raw'
    temp_video_dir.mkdir(parents=True, exist_ok=True)

    senha_admin = obter_senha_admin()
    sincronizar_credenciais_admin(senha_admin)

    # Verifica áudio padrão se não foi informado
    if audio_path is None:
        audio_padrao = VIDEOS_DIR / 'naracao_demonstracao.wav'
        if audio_padrao.exists():
            audio_path = audio_padrao

    duracao_audio = obter_duracao_audio(audio_path) if audio_path and audio_path.exists() else 0.0

    print("=" * 75)
    print("=== GRAVADOR AUTOMATIZADO DE VÍDEO - DIGITALNET PROSPECTOR")
    print(f"=== URL Alvo: {base_url}")
    print(f"=== Credenciais Admin: admin / {senha_admin}")
    print(f"=== Modo Visual: {'Headed (Navegador Visível)' if headed else 'Headless (Segundo Plano)'}")
    print(f"=== Trilha de Áudio: {audio_path.name if audio_path and audio_path.exists() else 'Nenhuma'}")
    print(f"=== Sincronização com Áudio: {'Ativa (' + str(round(duracao_audio, 1)) + 's)' if (sync_audio and duracao_audio > 0) else 'Desativada'}")
    print("=" * 75)

    with sync_playwright() as p:
        browser = p.chromium.launch(
            headless=not headed,
            slow_mo=slow_mo,
            args=[
                '--window-size=1920,1080',
                '--start-maximized',
                '--disable-blink-features=AutomationControlled'
            ]
        )

        context = browser.new_context(
            record_video_dir=str(temp_video_dir),
            color_scheme="dark",
            record_video_size={"width": 1920, "height": 1080},
            viewport={"width": 1920, "height": 1080},
            locale="pt-BR",
            timezone_id="America/Campo_Grande",
        )

        page = context.new_page()

        # Aceita caixas de diálogo / confirmação automaticamente (ex: confirmação de conversão)
        page.on("dialog", lambda dialog: dialog.accept())

        tempo_inicio_gravacao = time.time()

        def aguardar_passo(inicio_passo: float, duracao_alvo: float):
            if sync_audio and duracao_audio > 0:
                restante = duracao_alvo - (time.time() - inicio_passo)
                if restante > 0:
                    page.wait_for_timeout(int(restante * 1000))

        # ----------------------------------------------------------------------
        # PASSO 1: LOGIN NO SISTEMA (Alinhado com Bloco 1 da Narração)
        # ----------------------------------------------------------------------
        t_passo1 = time.time()
        print("\n[1/8] Executando Login como Administrador...")
        page.goto(f"{base_url}/auth/login", wait_until="networkidle")
        page.wait_for_timeout(1000)

        page.fill('input[name="login"]', 'admin')
        page.wait_for_timeout(400)
        page.fill('input[name="password"]', senha_admin)
        page.wait_for_timeout(500)
        page.click('button[type="submit"]')
        page.wait_for_load_state("networkidle")
        page.wait_for_timeout(1500)
        print(f"    -> Autenticado com sucesso! Página atual: {page.url}")
        aguardar_passo(t_passo1, 22.0)

        # ----------------------------------------------------------------------
        # PASSO 2: DASHBOARD EXECUTIVO (Alinhado com Bloco 2 da Narração)
        # ----------------------------------------------------------------------
        t_passo2 = time.time()
        print("[2/8] Apresentando Dashboard Executivo e Indicadores...")
        page.mouse.wheel(0, 450)
        page.wait_for_timeout(2500)
        page.mouse.wheel(0, 300)
        page.wait_for_timeout(2500)
        page.mouse.wheel(0, -750)
        page.wait_for_timeout(2000)
        aguardar_passo(t_passo2, 27.0)

        # ----------------------------------------------------------------------
        # PASSO 3: RADAR DE LEADS & MAPA DE EXPANSÃO ÓPTICA (Alinhado com Bloco 3)
        # ----------------------------------------------------------------------
        t_passo3 = time.time()
        print("[3/8] Acessando Radar de Leads & Mapa de Campo Grande...")
        page.click('a.sidebar-link[href*="/leads"]')
        page.wait_for_load_state("networkidle")
        page.wait_for_timeout(3000)

        # Destaca o mapa e as camadas de calor
        print("    -> Interagindo com o Mapa de Cobertura e Clusters de Fibra...")
        page.mouse.wheel(0, 250)
        page.wait_for_timeout(2500)
        aguardar_passo(t_passo3, 23.5)

        # ----------------------------------------------------------------------
        # PASSO 4: PROSPECÇÃO GEO-LOCALIZADA (Alinhado com Bloco 4: Radar & Fibra)
        # ----------------------------------------------------------------------
        t_passo4 = time.time()
        print("[4/8] Prospecção Geo-Localizada: Selecionando Nó / Cliente de Fibra no Mapa...")
        mapa_loc = page.locator('#mapaCalor')
        if mapa_loc.is_visible():
            mapa_loc.scroll_into_view_if_needed()
            page.wait_for_timeout(1000)

        # Localiza o nó / cliente de fibra no mapa e clica nele com force=True
        print("    -> Clicando no Nó / Cliente óptico no mapa de Campo Grande...")
        pin_fibra = page.locator('.custom-pin-fibra').first
        try:
            pin_fibra.wait_for(state="visible", timeout=4000)
            pin_fibra.click(force=True, timeout=2500)
            page.wait_for_timeout(1500)
        except Exception as e:
            print(f"    [!] Ativando nó óptico via Leaflet: {e}")
            page.evaluate("""() => {
                if (typeof layerGroupFibra !== 'undefined') {
                    const layers = layerGroupFibra.getLayers();
                    if (layers.length > 0) {
                        layers[0].openPopup();
                    }
                }
            }""")
            page.wait_for_timeout(1500)

        # Clica em 'Carregar Empresas do Nó' no popup do marcador
        print("    -> Clicando no botão 'Carregar Empresas do Nó'...")
        btn_nodo = page.locator('button:has-text("Carregar Empresas do Nó")').first
        try:
            btn_nodo.wait_for(state="visible", timeout=4000)
            btn_nodo.click(force=True, timeout=2500)
        except Exception as e:
            print(f"    [!] Popup click fallback: {e}")
            page.evaluate("""() => {
                const p = (typeof rawMapPoints !== 'undefined') ? (rawMapPoints.find(x => x.tipo === 'cluster_fibra') || rawMapPoints[0]) : null;
                if (p && typeof carregarEmpresasDoNodo === 'function') {
                    carregarEmpresasDoNodo(escape(p.bairro), p.lat, p.lng);
                }
            }""")

        # Aguarda a gaveta lateral (Offcanvas) abrir e carregar as empresas da RFB
        print("    -> Aguardando abertura da gaveta lateral (Offcanvas) com empresas no nó...")
        page.wait_for_selector('#offcanvasNodoEmpresas.show', timeout=8000)
        card_empresa = page.locator('#offcanvasListaEmpresas .card').first
        try:
            card_empresa.wait_for(state="visible", timeout=12000)
            print("    -> Empresas no raio do nó carregadas com sucesso na gaveta!")
        except Exception as e:
            print(f"    [!] Aguardando cards da gaveta: {e}")

        page.wait_for_timeout(1500)

        # Demonstra as empresas na gaveta lateral
        print("    -> Apresentando empresas, scores e planos na gaveta lateral...")
        drawer_body = page.locator('#offcanvasNodoEmpresas .offcanvas-body')
        if drawer_body.is_visible():
            drawer_body.hover()
            page.mouse.wheel(0, 350)
            page.wait_for_timeout(2000)
            page.mouse.wheel(0, 350)
            page.wait_for_timeout(2000)
            page.mouse.wheel(0, -700)
            page.wait_for_timeout(1500)

        # Fecha a gaveta para continuar o fluxo na tabela e funil
        print("    -> Fechando a gaveta lateral para prosseguir pelo funil...")
        btn_close_drawer = page.locator('#offcanvasNodoEmpresas button[data-bs-dismiss="offcanvas"]').first
        if btn_close_drawer.is_visible():
            btn_close_drawer.click()
        else:
            page.evaluate("""() => {
                const el = document.getElementById('offcanvasNodoEmpresas');
                if (el) {
                    const inst = bootstrap.Offcanvas.getInstance(el);
                    if (inst) inst.hide();
                }
            }""")
        page.wait_for_selector('#offcanvasNodoEmpresas', state="hidden", timeout=5000)
        page.wait_for_timeout(1000)
        aguardar_passo(t_passo4, 25.0)

        # ----------------------------------------------------------------------
        # PASSO 5 & 6: TABELA, DOSSIÊ 360° & TUTOR DE OBJEÇÕES (Alinhado com Bloco 5)
        # ----------------------------------------------------------------------
        t_passo5 = time.time()
        print("[5/8] Demonstrando Tabela de Leads com Linhas Aninhadas...")
        tabela_loc = page.locator('#tabelaLeads')
        if tabela_loc.is_visible():
            tabela_loc.scroll_into_view_if_needed()
            page.wait_for_timeout(1200)

        btn_detalhes = page.locator('button.btn-details').first
        if btn_detalhes.is_visible():
            print("    -> Expandindo Dossiê Rápido e Script Anti-Ban na Linha Aninhada...")
            btn_detalhes.click()
            page.wait_for_timeout(2500)
            page.mouse.wheel(0, 300)
            page.wait_for_timeout(1800)

        print("[6/8] Acessando Dossiê Comercial 360° e Tutor de Objeções...")
        btn_dossie = page.locator('a[href*="/leads/"][title*="Dossiê"]').first
        if not btn_dossie.is_visible():
            btn_dossie = page.locator('a.btn-dn-blue:has-text("Dossiê")').first

        btn_dossie.click()
        page.wait_for_load_state("networkidle")
        page.wait_for_timeout(2500)

        print("    -> Simulando abordagem WhatsApp e Tutor de Objeções...")
        page.mouse.wheel(0, 350)
        page.wait_for_timeout(1500)

        btn_obj_preco = page.locator('a:has-text("Preço / Custo")')
        if btn_obj_preco.is_visible():
            btn_obj_preco.click()
            page.wait_for_timeout(1500)

        btn_obj_fid = page.locator('a:has-text("Fidelidade Concorrente")')
        if btn_obj_fid.is_visible():
            btn_obj_fid.click()
            page.wait_for_timeout(1500)

        aguardar_passo(t_passo5, 23.0)

        # ----------------------------------------------------------------------
        # PASSO 7: CONVERSÃO DO LEAD EM CLIENTE & GERAÇÃO DO PEDIDO (Alinhado com Bloco 6)
        # ----------------------------------------------------------------------
        t_passo7 = time.time()
        print("[7/8] Demonstrando WhatsApp, Conversão em Cliente e Pedido de Banda Larga...")
        btn_optin_aceito = page.locator('button:has-text("Opt-in Aceito!")')
        if btn_optin_aceito.is_visible():
            btn_optin_aceito.click()
            page.wait_for_load_state("networkidle")
            page.wait_for_timeout(1500)

        page.mouse.wheel(0, 450)
        page.wait_for_timeout(1500)

        btn_converter = page.locator('button[type="submit"]:has-text("Converter em Cliente")')
        if btn_converter.is_visible():
            btn_converter.click()
            page.wait_for_load_state("networkidle")
            page.wait_for_timeout(2500)

            print("    -> Cliente ativado com sucesso! Exibindo detalhes e histórico de pedidos...")
            page.mouse.wheel(0, 350)
            page.wait_for_timeout(1800)

            # Acessa o pedido de instalação gerado
            link_pedido = page.locator('a[href*="/pedidos/"]').first
            if link_pedido.is_visible():
                link_pedido.click()
                page.wait_for_load_state("networkidle")
                page.wait_for_timeout(2000)
                print("    -> Comprovante do Pedido de Instalação de Banda Larga apresentado.")
                page.mouse.wheel(0, 250)
                page.wait_for_timeout(1800)

        aguardar_passo(t_passo7, 22.0)

        # ----------------------------------------------------------------------
        # PASSO 8: CONTROLE DE ACESSO POR PERFIS (RBAC) & ADMINISTRAÇÃO (Alinhado com Bloco 7)
        # ----------------------------------------------------------------------
        t_passo8 = time.time()
        print("[8/9] Demonstrando Controle de Acesso por Perfis (RBAC), Grupos e Planos...")
        page.click('a.sidebar-link[href*="/admin/usuarios"]')
        page.wait_for_load_state("networkidle")
        page.wait_for_timeout(2000)

        print("    -> Painel de Usuários com perfis Administrador, Líder Técnico e Agente...")
        page.mouse.wheel(0, 300)
        page.wait_for_timeout(1800)

        # Acessa Grupos de Acesso
        print("    -> Acessando Gestão de Grupos de Acesso...")
        page.click('a.sidebar-link[href*="/admin/grupos"]')
        page.wait_for_load_state("networkidle")
        page.wait_for_timeout(2000)
        page.mouse.wheel(0, 250)
        page.wait_for_timeout(1800)
        aguardar_passo(t_passo8, 20.5)

        # ----------------------------------------------------------------------
        # PASSO 9: CONCLUSÃO, EVOLUÇÃO COM PROVA 02 E AGRADECIMENTO (Alinhado com Bloco 8)
        # ----------------------------------------------------------------------
        t_passo9 = time.time()
        print("[9/9] Retornando ao Dashboard: Apresentando Proposta de Evolução (Prova 02) e Agradecimento...")
        page.click('a.sidebar-link[href*="/dashboard"]')
        page.wait_for_load_state("networkidle")
        page.wait_for_timeout(3000)

        # Rola suavemente pelo dashboard executivo durante a explanação da Prova 02
        page.mouse.wheel(0, 350)
        page.wait_for_timeout(4000)
        page.mouse.wheel(0, 350)
        page.wait_for_timeout(4000)
        page.mouse.wheel(0, -700)
        page.wait_for_timeout(3000)
        aguardar_passo(t_passo9, 44.0)

        # Garante que toda a duração da narração seja coberta antes de finalizar o vídeo
        if sync_audio and duracao_audio > 0:
            total_decorrido = time.time() - tempo_inicio_gravacao
            if total_decorrido < duracao_audio:
                sobra = duracao_audio - total_decorrido + 1.0
                print(f"    -> Aguardando fechamento da narração ({sobra:.1f}s restantes)...")
                page.wait_for_timeout(int(sobra * 1000))

        # Finaliza e salva o vídeo
        context.close()
        video_raw_path = page.video.path()
        browser.close()

    # Move e renomeia o vídeo para nome amigável
    data_hora = time.strftime("%Y%m%d_%H%M%S")
    video_final_webm = VIDEOS_DIR / f"demonstracao_digitalnet_{data_hora}.webm"
    video_recente_webm = VIDEOS_DIR / "demonstracao_digitalnet_recente.webm"

    if os.path.exists(video_raw_path):
        shutil.move(video_raw_path, str(video_final_webm))
        shutil.copy(str(video_final_webm), str(video_recente_webm))
        shutil.rmtree(temp_video_dir, ignore_errors=True)

        print("\n" + "=" * 75)
        print(f"[OK] VÍDEO GRAVADO COM SUCESSO!")
        print(f"  • Arquivo WebM: {video_final_webm}")
        print(f"  • Atalho Fixo:  {video_recente_webm}")
        print(f"  • Tamanho:      {video_final_webm.stat().st_size / (1024 * 1024):.2f} MB")

        # Conversão opcional para MP4 embutindo a trilha de áudio
        video_mp4 = converter_para_mp4(video_final_webm, audio_path)
        if video_mp4 != video_final_webm:
            shutil.copy(str(video_mp4), str(VIDEOS_DIR / "demonstracao_digitalnet_recente.mp4"))
            if gerar_whatsapp:
                converter_para_whatsapp(video_mp4)
        print("=" * 75)
        return video_final_webm

    return None


def main():
    parser = argparse.ArgumentParser(
        description="Grava um vídeo automatizado com Playwright do ecossistema DigitalNet.",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument('--port', type=int, default=5055, help='Porta HTTP da aplicação (default: 5055)')
    parser.add_argument('--headed', action='store_true', help='Executa com o navegador visível')
    parser.add_argument('--slow-mo', type=int, default=600, help='Delay em ms entre ações (default: 600)')
    parser.add_argument('--audio', type=str, default=None, help='Caminho para arquivo de áudio de narração a embutir (default: videos/naracao_demonstracao.wav)')
    parser.add_argument('--no-audio', action='store_true', help='Não embute trilha de áudio no vídeo')
    parser.add_argument('--no-sync', action='store_true', help='Não sincroniza o tempo dos passos com a duração do áudio')
    parser.add_argument('--no-whatsapp', action='store_true', help='Não gera a versão compactada para WhatsApp')
    args = parser.parse_args()

    audio_path = None
    if not args.no_audio:
        if args.audio:
            audio_path = Path(args.audio)
        else:
            default_audio = VIDEOS_DIR / 'naracao_demonstracao.wav'
            if default_audio.exists():
                audio_path = default_audio

    base_url = f"http://127.0.0.1:{args.port}"
    processo_servidor = verificar_ou_iniciar_servidor(base_url, args.port)
    try:
        gravar_fluxo(
            base_url=base_url,
            headed=args.headed,
            slow_mo=args.slow_mo,
            audio_path=audio_path,
            sync_audio=not args.no_sync,
            gerar_whatsapp=not args.no_whatsapp
        )
    finally:
        if processo_servidor:
            print("[*] Encerrando servidor temporário...")
            processo_servidor.terminate()


if __name__ == '__main__':
    main()
