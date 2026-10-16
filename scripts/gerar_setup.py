#!/usr/bin/env python3
"""
Gera o setup.sh a partir dos arquivos atuais do repositório.

O setup.sh recria o projeto inteiro em uma pasta vazia (Linux). Para que ele
nunca fique defasado em relação ao código, rode este script sempre que alterar
a aplicação:

    python scripts/gerar_setup.py            # escreve ./setup.sh
    python scripts/gerar_setup.py --check    # falha se o setup.sh estiver desatualizado

Quais arquivos entram: tudo o que o git versiona ou que é novo e não está no
.gitignore (git ls-files --cached --others --exclude-standard), exceto os itens
de EXCLUIR abaixo. Arquivos de texto são embutidos via heredoc; binários em base64.
"""
import argparse
import base64
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SAIDA = ROOT / 'setup.sh'
DELIM = 'OMNI_EOF'

# Arquivos que não fazem sentido dentro do setup.sh
EXCLUIR = {
    'setup.sh',                 # o próprio script gerado
    'README.md',                # documentação do repositório
    'scripts/gerar_setup.py',   # ferramenta de manutenção
    'geojson/imoveis.geojson',  # base bruta de 469MB (restaurada via data/geo_imoveis.sql.gz)
}
EXCLUIR_PREFIXOS = ('.idea/', '.vscode/', 'instance/', '.venv/', 'data/', 'docs/superpowers/')


def listar_arquivos():
    saida = subprocess.run(
        ['git', 'ls-files', '--cached', '--others', '--exclude-standard'],
        cwd=ROOT, check=True, capture_output=True, text=True, encoding='utf-8',
    ).stdout
    arquivos = []
    for linha in saida.splitlines():
        caminho = linha.strip().replace('\\', '/')
        if not caminho or caminho in EXCLUIR or caminho.startswith(EXCLUIR_PREFIXOS):
            continue
        if '__pycache__/' in caminho or caminho.endswith(('.pyc', '.pyo')):
            continue
        if not (ROOT / caminho).is_file():  # removido do disco, mas ainda no índice
            continue
        arquivos.append(caminho)
    return sorted(arquivos)


def bloco_arquivo(caminho):
    dados = (ROOT / caminho).read_bytes()
    try:
        texto = dados.decode('utf-8').replace('\r\n', '\n')
    except UnicodeDecodeError:
        b64 = base64.encodebytes(dados).decode('ascii')
        return (f"# --- {caminho} (binário) ---\n"
                f"base64 -d > '{caminho}' <<'{DELIM}'\n{b64}{DELIM}\n")

    if any(l == DELIM for l in texto.split('\n')):
        raise SystemExit(f'ERRO: {caminho} contém uma linha igual ao delimitador {DELIM!r}.')
    if not texto.endswith('\n'):
        texto += '\n'
    return f"# --- {caminho} ---\ncat > '{caminho}' <<'{DELIM}'\n{texto}{DELIM}\n"


CABECALHO = r'''#!/usr/bin/env bash
# ==============================================================================
# Script de Criação e Configuração Automatizada - DigitalNet-Prospector (Linux)
# ==============================================================================
# ARQUIVO GERADO AUTOMATICAMENTE por scripts/gerar_setup.py — não edite à mão.
# Para atualizar após mudanças no código: python scripts/gerar_setup.py
#
# Este script cria toda a estrutura de diretórios e todos os arquivos fonte,
# gera um .env com SECRET_KEY aleatória, instala as dependências Python em
# ambiente virtual (.venv), aplica as migrações do banco de dados, popula com
# dados de teste (seed) e executa os testes automatizados.
#
# Uso em uma pasta vazia:
#   chmod +x setup.sh
#   ./setup.sh
#
# Variáveis opcionais:
#   SEED_ADMIN_PASSWORD=MinhaSenha ./setup.sh   # senha do usuário "admin"
#   (se omitida, uma senha aleatória é gerada e exibida ao final do seed)
#   AISA_API_KEY=xxx ./setup.sh                 # chave de API da AIsa (api.aisa.one)
#   AISA_MODEL=asi1-mini ./setup.sh             # modelo da AIsa (default: asi1-mini)
#   MAPBOX_API_KEY=pk.xxx ./setup.sh            # chave/token de API do Mapbox
# ==============================================================================

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}===================================================================${NC}"
echo -e "${BLUE}    Iniciando a instalação e recriação do projeto DigitalNet-Prospector       ${NC}"
echo -e "${BLUE}===================================================================${NC}"

# 1. Verificação de pré-requisitos no Linux
echo -e "\n${YELLOW}[1/6] Verificando pré-requisitos do sistema...${NC}"

if ! command -v python3 &> /dev/null; then
    echo -e "${RED}ERRO: python3 não foi encontrado. Instale com:${NC}"
    echo "  sudo apt update && sudo apt install -y python3 python3-venv python3-pip"
    exit 1
fi

if ! python3 -c "import venv" &> /dev/null; then
    echo -e "${RED}ERRO: o módulo venv não está disponível. Instale com:${NC}"
    echo "  sudo apt install -y python3-venv"
    exit 1
fi

echo -e "${GREEN}✓ Python 3 encontrado: $(python3 --version)${NC}"
'''


def gerar():
    arquivos = listar_arquivos()
    diretorios = sorted({str(Path(a).parent).replace('\\', '/') for a in arquivos} - {'.'} | {'instance'})

    partes = [CABECALHO]

    partes.append(
        '\n# 2. Criação da estrutura de pastas\n'
        'echo -e "\\n${YELLOW}[2/6] Criando a estrutura de diretórios...${NC}"\n'
        'mkdir -p \\\n' + ' \\\n'.join(f"    '{d}'" for d in diretorios) + '\n'
        'echo -e "${GREEN}✓ Estrutura de pastas criada com sucesso.${NC}"\n'
    )

    partes.append(
        '\n# 3. Criação dos arquivos do projeto\n'
        f'echo -e "\\n${{YELLOW}}[3/6] Criando {len(arquivos)} arquivos de código-fonte...${{NC}}"\n\n'
    )
    for caminho in arquivos:
        partes.append(bloco_arquivo(caminho) + '\n')

    partes.append(RODAPE)
    return ''.join(partes), arquivos


RODAPE = r'''# --- .env (gerado com SECRET_KEY aleatória; preserva um .env existente) ---
if [ ! -f .env ]; then
    SECRET_KEY_GERADA="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
    MAPBOX_KEY_CONFIG="${MAPBOX_API_KEY:-${MAPBOX_ACCESS_TOKEN:-}}"
    AISA_KEY_CONFIG="${AISA_API_KEY:-}"
    AISA_MODEL_CONFIG="${AISA_MODEL:-asi1-mini}"
    SEED_ADMIN_PASSWORD="${SEED_ADMIN_PASSWORD:-SenhaSeed*2026}"
    cat > .env <<EOF_ENV
FLASK_APP=wsgi.py
FLASK_DEBUG=1
SECRET_KEY=${SECRET_KEY_GERADA}
DATABASE_URL=sqlite:///app_clientes.db

# Chave de API da AIsa (api.aisa.one)
AISA_API_KEY=${AISA_KEY_CONFIG}
AISA_MODEL=${AISA_MODEL_CONFIG}
SEED_ADMIN_PASSWORD="${SEED_ADMIN_PASSWORD}"

# Chave de API / Access Token do Mapbox
MAPBOX_API_KEY=${MAPBOX_KEY_CONFIG}
EOF_ENV
    echo -e "${GREEN}✓ Arquivo .env criado com SECRET_KEY aleatória.${NC}"
else
    echo -e "${YELLOW}• .env já existe — mantido sem alterações.${NC}"
fi

# --- Scripts utilitários (run.sh, test.sh, seed.sh) ---
cat > run.sh <<'OMNI_EOF'
#!/usr/bin/env bash
# Inicia a aplicação Flask em ambiente Linux (servidor de desenvolvimento)
set -e
source .venv/bin/activate
export FLASK_APP=wsgi.py
export HOST="${HOST:-127.0.0.1}"
export PORT="${PORT:-5000}"
echo "Iniciando servidor DigitalNet-Prospector em http://${HOST}:${PORT} ..."
python3 wsgi.py
OMNI_EOF

cat > test.sh <<'OMNI_EOF'
#!/usr/bin/env bash
# Executa a suíte de testes automatizados no Linux
set -e
source .venv/bin/activate
echo "Executando suíte de testes automatizados..."
python3 -m unittest discover -s tests -v
OMNI_EOF

cat > seed.sh <<'OMNI_EOF'
#!/usr/bin/env bash
# Popula o banco de dados com usuário admin e dados de demonstração
set -e
source .venv/bin/activate
export FLASK_APP=wsgi.py
echo "Populando banco de dados com dados de teste..."
flask seed
OMNI_EOF

chmod +x run.sh test.sh seed.sh

echo -e "${GREEN}✓ Todos os arquivos fonte e utilitários foram criados.${NC}"

# 4. Criação do Ambiente Virtual (.venv)
echo -e "\n${YELLOW}[4/6] Criando o ambiente virtual Python (.venv)...${NC}"
python3 -m venv .venv
echo -e "${GREEN}✓ Ambiente virtual criado.${NC}"

# 5. Instalação das Dependências
echo -e "\n${YELLOW}[5/6] Instalando dependências (pip install)...${NC}"
.venv/bin/pip install --upgrade pip
.venv/bin/pip install -r requirements.txt
echo -e "${GREEN}✓ Todas as dependências foram instaladas com sucesso.${NC}"

# 6. Banco de dados (migrações versionadas), seed e testes
echo -e "\n${YELLOW}[6/6] Aplicando migrações e populando o banco de dados...${NC}"
export FLASK_APP=wsgi.py
.venv/bin/flask db upgrade
if [ -z "${SEED_ADMIN_PASSWORD:-}" ] && [ ! -f instance/.admin_password ]; then
    export SEED_ADMIN_PASSWORD="$(.venv/bin/python -c 'import secrets; print(secrets.token_urlsafe(9))')"
fi
.venv/bin/flask seed

echo -e "\n${YELLOW}• Carregando camadas geoespaciais urbanas no SQLite...${NC}"
mkdir -p data
if [ ! -f data/geo_imoveis.sql.gz ]; then
    if [ -f geo_imoveis.sql.gz ]; then
        cp geo_imoveis.sql.gz data/
    elif [ -f ../geo_imoveis.sql.gz ]; then
        cp ../geo_imoveis.sql.gz data/
    fi
fi
.venv/bin/python scripts/carregar_geojson_sqlite.py --execute --skip-imoveis
.venv/bin/python scripts/restaurar_imoveis.py || true

echo -e "\n${YELLOW}• Configurando base de dados RFB (177.614 empresas de Campo Grande)...${NC}"
# Se o dump comprimido estiver junto no pendrive ou pasta atual, copia para data/
if [ ! -f data/leeds_campo_grande.sql.gz ]; then
    if [ -f leeds_campo_grande.sql.gz ]; then
        cp leeds_campo_grande.sql.gz data/
    elif [ -f ../leeds_campo_grande.sql.gz ]; then
        cp ../leeds_campo_grande.sql.gz data/
    fi
fi
.venv/bin/python scripts/restaurar_rfb.py || true

# Enriquece clientes com dados reais da RFB
echo -e "\n${YELLOW}• Enriquecendo clientes ativos com empresas reais da RFB...${NC}"
.venv/bin/python scripts/enriquecer_clientes_rfb.py --limit 150 || true

echo -e "\n${YELLOW}Executando testes automatizados para validação do sistema...${NC}"
.venv/bin/python3 -m unittest discover -s tests

ADMIN_PASS=""
if [ -f instance/.admin_password ]; then
    ADMIN_PASS="$(cat instance/.admin_password)"
elif [ -n "${SEED_ADMIN_PASSWORD:-}" ]; then
    ADMIN_PASS="${SEED_ADMIN_PASSWORD}"
fi

echo -e "\n${BLUE}===================================================================${NC}"
echo -e "${GREEN}PROJETO CRIADO E CONFIGURADO COM SUCESSO!${NC}"
echo -e "${BLUE}===================================================================${NC}"
echo -e "Para iniciar o servidor agora mesmo, execute:"
echo -e "  ${YELLOW}./run.sh${NC}"
echo -e "\nOu manualmente:"
echo -e "  ${YELLOW}source .venv/bin/activate${NC}"
echo -e "  ${YELLOW}python3 wsgi.py${NC}"
echo -e "\nAcesse no navegador: ${BLUE}http://localhost:5000${NC}"
echo -e "\n${GREEN}Credenciais de Acesso ao Sistema:${NC}"
if [ -n "$ADMIN_PASS" ]; then
    echo -e "  • ${YELLOW}Administrador:${NC}  ${BLUE}admin${NC}            — Senha: ${GREEN}${ADMIN_PASS}${NC}"
else
    echo -e "  • ${YELLOW}Administrador:${NC}  ${BLUE}admin${NC}            — Senha: ${GREEN}(mantida a senha anterior)${NC}"
fi
echo -e "  • ${YELLOW}Líder Técnico:${NC}  ${BLUE}lider.tecnico${NC}    — Senha: ${GREEN}Lider#2026${NC}"
echo -e "  • ${YELLOW}Agente Comercial:${NC} ${BLUE}agente.comercial${NC} — Senha: ${GREEN}Agente#2026${NC}"
echo -e "\nPara criar outro administrador: ${YELLOW}.venv/bin/flask create-admin${NC}"
echo -e "\n${RED}Produção:${NC} use FLASK_DEBUG=0 e um servidor WSGI (gunicorn/waitress)."
echo -e "${BLUE}===================================================================${NC}"
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--check', action='store_true', help='apenas verifica se o setup.sh está atualizado')
    args = parser.parse_args()

    conteudo, arquivos = gerar()

    if args.check:
        atual = SAIDA.read_text(encoding='utf-8') if SAIDA.exists() else ''
        if atual != conteudo:
            print('setup.sh está DESATUALIZADO. Rode: python scripts/gerar_setup.py')
            return 1
        print('setup.sh está atualizado.')
        return 0

    # newline='\n' garante finais de linha LF mesmo gerando no Windows (bash não aceita CRLF)
    with open(SAIDA, 'w', encoding='utf-8', newline='\n') as f:
        f.write(conteudo)
    print(f'setup.sh gerado com {len(arquivos)} arquivos embutidos ({SAIDA.stat().st_size:,} bytes).')
    for a in arquivos:
        print(f'  - {a}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
