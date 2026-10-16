#!/usr/bin/env python3
"""
Gera a trilha de áudio narrada para o vídeo de demonstração do Leads Prospector.
Utiliza a voz clonada 'Considera' (id: bf91cd6a) via VoiceStudio local.
"""

import io
import json
import os
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VIDEOS_DIR = ROOT / 'videos'
OUTPUT_WAV = VIDEOS_DIR / 'naracao_demonstracao.wav'
OUTPUT_MP3 = VIDEOS_DIR / 'naracao_demonstracao.mp3'

VOICE_STUDIO_URL = os.environ.get('VOICESTUDIO_URL', 'http://localhost:3900/v1/audio/speech')
VOICE_PROFILE_ID = os.environ.get('VOICESTUDIO_VOICE', 'bf91cd6a')

# Roteiro adaptado em blocos narrativos alinhados aos passos visuais do vídeo
SCRIPT_SEGMENTS = [
    {
        "id": "intro",
        "pause_after": 0.6,
        "text": (
            "Olá! Esse é o vídeo de demonstração da aplicação da Prova 01. "
            "O projeto nasceu do que conversamos durante a entrevista presencial, "
            "quando pude entender o modelo de negócio da empresa e as necessidades do time de desenvolvimento de soluções."
        )
    },
    {
        "id": "contexto_shell",
        "pause_after": 0.6,
        "text": (
            "Depois da conversa, pesquisei as informações públicas da empresa e testei o chatbot de atendimento. "
            "Pensando em automação prática e captação de clientes, montei uma rotina em shell script capaz de subir todo o ambiente do zero, "
            "partindo apenas do instalador e do dump de empresas da Receita Federal."
        )
    },
    {
        "id": "leads_prospector_apresentacao",
        "pause_after": 0.7,
        "text": (
            "O resultado é o Leads Prospector: um CRM com foco em prospecção B2B geolocalizada para operadoras de telecomunicações. "
            "A ferramenta cruza a base oficial de 177 mil empresas ativas da Receita Federal com as camadas geográficas em GeoJSON de Campo Grande."
        )
    },
    {
        "id": "func1_radar",
        "pause_after": 0.7,
        "text": (
            "Na primeira funcionalidade, temos o Radar de Leads e expansão da rede óptica. "
            "O mapa mostra manchas térmicas de oportunidades e os pontos de fibra óptica ativa. "
            "Clicando em um nó, o sistema abre uma gaveta lateral e lista todas as empresas vizinhas com viabilidade imediata de atendimento."
        )
    },
    {
        "id": "func2_dossie",
        "pause_after": 0.7,
        "text": (
            "A segunda funcionalidade é o Dossiê Comercial do lead. "
            "O sistema calcula automaticamente a viabilidade e uma pontuação de zero a cem, identifica os sócios decisores "
            "e disponibiliza um tutor de quebra de objeções para apoiar o pré-vendedor em argumentos de preço ou concorrência."
        )
    },
    {
        "id": "func3_whatsapp_pedidos",
        "pause_after": 0.7,
        "text": (
            "Com a abordagem definida, o contato pode ser feito direto pelo WhatsApp Web com mensagem personalizada. "
            "Quando a negociação avança, o lead é convertido em cliente com um clique, "
            "gerando o pedido de banda larga com preenchimento automático pelo CEP."
        )
    },
    {
        "id": "func5_planos_rbac",
        "pause_after": 0.6,
        "text": (
            "A plataforma também conta com gerenciamento de planos residenciais e corporativos, com restauração rápida da tabela oficial, "
            "além de controle de acesso por perfis para separar as permissões de administradores, líderes e agentes."
        )
    },
    {
        "id": "evolucao_prova02_agradecimento",
        "pause_after": 0.5,
        "text": (
            "Como evolução natural, o próximo passo é conectar esses dados com o histórico tratado na Prova 02. "
            "Cruzar as instalações ativas e os chamados técnicos vai permitir calibrar a prospecção apenas onde a rede tem boa estabilidade. "
            "Além disso, o agente de inteligência artificial poderá atuar diretamente no suporte, identificando falhas recorrentes "
            "e recomendando soluções técnicas antes que o cliente sinta o impacto. "
            "Muito obrigado pela atenção e pela oportunidade durante todo o processo seletivo."
        )
    }
]


def testar_conexao_voicestudio() -> bool:
    """Verifica se o VoiceStudio está respondendo."""
    try:
        health_url = VOICE_STUDIO_URL.replace('/v1/audio/speech', '/health')
        req = urllib.request.Request(health_url, headers={'User-Agent': 'VoiceStudioClient/1.0'})
        with urllib.request.urlopen(req, timeout=3) as resp:
            data = json.loads(resp.read().decode('utf-8'))
            print(f"[OK] VoiceStudio conectado: status={data.get('status')} | device={data.get('device')}")
            return True
    except Exception as e:
        print(f"[ERRO] Não foi possível conectar ao VoiceStudio em {VOICE_STUDIO_URL}: {e}")
        return False


def sintetizar_segmento(texto: str, voice_id: str) -> bytes:
    """Envia requisição para a API de síntese do VoiceStudio e retorna os bytes do WAV."""
    payload = {
        "model": "tts-1",
        "voice": voice_id,
        "input": texto,
        "response_format": "wav"
    }
    data = json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(
        VOICE_STUDIO_URL,
        data=data,
        headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        return resp.read()


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


def gerar_trilha_completa():
    VIDEOS_DIR.mkdir(parents=True, exist_ok=True)
    temp_dir = VIDEOS_DIR / 'temp_audio'
    temp_dir.mkdir(parents=True, exist_ok=True)

    if not testar_conexao_voicestudio():
        sys.exit(1)

    print("=" * 70)
    print("=== GERANDO TRILHA DE ÁUDIO COM A VOZ 'CONSIDERA' (bf91cd6a) ===")
    print(f"=== Total de segmentos: {len(SCRIPT_SEGMENTS)}")
    print("=" * 70)

    segment_wavs = []
    concat_list_path = temp_dir / 'concat_list.txt'

    with open(concat_list_path, 'w', encoding='utf-8') as f_list:
        for i, seg in enumerate(SCRIPT_SEGMENTS, start=1):
            seg_id = seg["id"]
            texto = seg["text"]
            pause_sec = seg.get("pause_after", 0.5)

            seg_path = temp_dir / f"seg_{i:02d}_{seg_id}.wav"
            print(f"\n[{i}/{len(SCRIPT_SEGMENTS)}] Sintetizando bloco '{seg_id}'...")
            print(f"    Texto: \"{texto[:80]}...\"")

            t0 = time.time()
            audio_bytes = sintetizar_segmento(texto, VOICE_PROFILE_ID)
            seg_path.write_bytes(audio_bytes)
            elapsed = time.time() - t0
            dur = obter_duracao_audio(seg_path)
            print(f"    -> Gerado em {elapsed:.1f}s | Duração do áudio: {dur:.2f}s")

            # Se houver pausa, adiciona com lavfi anullsrc
            if pause_sec > 0:
                pause_wav = temp_dir / f"pause_{i:02d}.wav"
                subprocess.run(
                    [
                        'ffmpeg', '-y', '-f', 'lavfi',
                        '-i', f'anullsrc=r=24000:cl=mono',
                        '-t', str(pause_sec),
                        str(pause_wav)
                    ],
                    check=True,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL
                )
                f_list.write(f"file '{seg_path.name}'\n")
                f_list.write(f"file '{pause_wav.name}'\n")
            else:
                f_list.write(f"file '{seg_path.name}'\n")

    print("\n[*] Concatenando segmentos de áudio...")
    subprocess.run(
        [
            'ffmpeg', '-y', '-f', 'concat', '-safe', '0',
            '-i', str(concat_list_path),
            '-c:a', 'pcm_s16le',
            str(OUTPUT_WAV)
        ],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )

    # Gera também versão MP3 (192kbps)
    subprocess.run(
        [
            'ffmpeg', '-y', '-i', str(OUTPUT_WAV),
            '-c:a', 'libmp3lame', '-b:a', '192k',
            str(OUTPUT_MP3)
        ],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )

    dur_final = obter_duracao_audio(OUTPUT_WAV)
    print("=" * 70)
    print("[OK] TRILHA DE ÁUDIO GERADA COM SUCESSO!")
    print(f"  • WAV Final:    {OUTPUT_WAV}")
    print(f"  • MP3 Final:    {OUTPUT_MP3}")
    print(f"  • Duração Total: {dur_final:.2f} segundos ({dur_final/60:.2f} min)")
    print(f"  • Tamanho WAV:  {OUTPUT_WAV.stat().st_size / (1024 * 1024):.2f} MB")
    print("=" * 70)


if __name__ == '__main__':
    gerar_trilha_completa()
