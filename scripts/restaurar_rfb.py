#!/usr/bin/env python3
"""
Restaura a base de inteligência RFB (177.614 empresas comerciais de Campo Grande - MS)
a partir do dump comprimido data/leeds_campo_grande.sql.gz no banco SQLite instance/app_clientes.db.

Suporta:
1. Arquivo local: data/leeds_campo_grande.sql.gz ou caminho informado.
2. Download automático via URL pública (GitHub Raw / Releases) sem necessidade de login.
"""
import argparse
import gzip
import os
import sqlite3
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB_PATH = ROOT / 'instance' / 'app_clientes.db'
LOCAL_DUMP = ROOT / 'data' / 'leeds_campo_grande.sql.gz'

# URL pública padrão (pode ser sobrescrita via variável de ambiente RFB_DUMP_URL ou argumento --url)
DEFAULT_URL = os.environ.get(
    'RFB_DUMP_URL',
    'https://raw.githubusercontent.com/pizanao/leads-prospector/main/data/leeds_campo_grande.sql.gz'
)


def verificar_tabela_existente(conn) -> int:
    try:
        cur = conn.cursor()
        for tbl in ('leeds_campo_grande', 'leads_campo_grande'):
            try:
                cur.execute(f"SELECT COUNT(*) FROM {tbl}")
                res = cur.fetchone()
                if res and res[0] > 0:
                    return res[0]
            except (sqlite3.OperationalError, sqlite3.DatabaseError):
                continue
        return 0
    except (sqlite3.OperationalError, sqlite3.DatabaseError):
        return 0


def baixar_dump(url: str, destino: Path):
    print(f"📥 Baixando base RFB de repositório público:\n   {url}")
    destino.parent.mkdir(parents=True, exist_ok=True)
    temp_dest = destino.with_suffix('.tmp')

    req = urllib.request.Request(
        url,
        headers={'User-Agent': 'LeadsProspector-Setup/1.0'}
    )
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=60) as resp, open(temp_dest, 'wb') as out_f:
            tamanho_total = int(resp.headers.get('content-length', 0))
            baixado = 0
            bloco = 1024 * 64

            while True:
                chunk = resp.read(bloco)
                if not chunk:
                    break
                baixado += len(chunk)
                out_f.write(chunk)
                if tamanho_total > 0:
                    pct = (baixado / tamanho_total) * 100
                    print(f"\r   Progresso: {pct:.1f}% ({baixado / (1024*1024):.1f} MB)", end='', flush=True)

            print()

        temp_dest.rename(destino)
        print(f"✓ Download concluído em {time.time() - t0:.2f}s ({destino.stat().st_size / (1024*1024):.1f} MB)")
    except Exception as e:
        if temp_dest.exists():
            temp_dest.unlink()
        raise RuntimeError(f"Falha ao baixar dump RFB de {url}: {e}")


import csv


def _restaurar_sql(conn, caminho_gz: Path):
    open_fn = gzip.open if str(caminho_gz).endswith('.gz') else open
    with open_fn(caminho_gz, 'rt', encoding='utf-8') as f:
        sql_content = f.read()

    cur = conn.cursor()
    cur.execute("DROP VIEW IF EXISTS leads_campo_grande;")
    cur.execute("DROP TABLE IF EXISTS leeds_campo_grande;")

    # Envolve em transação explícita se ainda não possuir
    if 'BEGIN TRANSACTION' not in sql_content.upper():
        sql_content = f"BEGIN TRANSACTION;\n{sql_content}\nCOMMIT;"

    cur.executescript(sql_content)
    cur.execute("CREATE VIEW IF NOT EXISTS leads_campo_grande AS SELECT * FROM leeds_campo_grande;")


def _restaurar_csv(conn, caminho_gz: Path):
    open_fn = gzip.open if str(caminho_gz).endswith('.gz') else open
    with open_fn(caminho_gz, 'rt', encoding='utf-8', newline='') as f:
        reader = csv.reader(f)
        header = next(reader)
        cur = conn.cursor()
        cur.execute("DROP VIEW IF EXISTS leads_campo_grande;")
        cur.execute("DROP TABLE IF EXISTS leeds_campo_grande;")
        cols_def = ", ".join([f'"{c}" TEXT' for c in header])
        cur.execute(f"CREATE TABLE leeds_campo_grande ({cols_def});")
        placeholders = ",".join(["?"] * len(header))
        sql = f"INSERT INTO leeds_campo_grande VALUES ({placeholders})"
        conn.execute("BEGIN TRANSACTION;")
        cur.executemany(sql, reader)
        cur.execute("CREATE VIEW IF NOT EXISTS leads_campo_grande AS SELECT * FROM leeds_campo_grande;")


def restaurar_dump(caminho_gz: Path, db_path: Path, force: bool = False):
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(db_path))

    total_atual = verificar_tabela_existente(conn)
    if total_atual > 0 and not force:
        print(f"✓ Tabela 'leeds_campo_grande' já contém {total_atual:,} empresas. Use --force para recarregar.")
        conn.close()
        return

    print(f"📦 Restaurando leeds_campo_grande a partir de {caminho_gz.name} com PRAGMAs de alta velocidade...")
    t0 = time.time()

    # Otimizações críticas de escrita em lote para SQLite
    conn.execute("PRAGMA synchronous = OFF;")
    conn.execute("PRAGMA journal_mode = MEMORY;")
    conn.execute("PRAGMA cache_size = 100000;")
    conn.execute("PRAGMA temp_store = MEMORY;")

    ext = caminho_gz.name.lower()
    if ext.endswith('.csv.gz') or ext.endswith('.csv'):
        _restaurar_csv(conn, caminho_gz)
    else:
        _restaurar_sql(conn, caminho_gz)

    conn.commit()
    conn.execute("PRAGMA synchronous = NORMAL;")
    total_final = verificar_tabela_existente(conn)
    conn.close()

    print(f"✓ Sucesso! {total_final:,} empresas da RFB restauradas no SQLite em {time.time() - t0:.2f}s.")


def main():
    parser = argparse.ArgumentParser(description="Restaura a base de inteligência RFB no SQLite.")
    parser.add_argument('--arquivo', type=str, default=None, help="Caminho do arquivo .sql.gz ou .csv.gz local.")
    parser.add_argument('--url', type=str, default=DEFAULT_URL, help="URL pública para download caso arquivo não exista.")
    parser.add_argument('--force', action='store_true', help="Força a recriação mesmo se a tabela já existir.")
    args = parser.parse_args()

    caminho_gz = Path(args.arquivo) if args.arquivo else None

    # Se não foi especificado, procura arquivos locais existentes
    if not caminho_gz or not caminho_gz.exists():
        for candidato in [
            ROOT / 'data' / 'leeds_campo_grande.sql.gz',
            ROOT / 'data' / 'leeds_campo_grande.csv.gz',
            ROOT / 'leeds_campo_grande.sql.gz',
            ROOT / 'leeds_campo_grande.csv.gz',
        ]:
            if candidato.exists() and candidato.stat().st_size > 1000:
                caminho_gz = candidato
                break
        if not caminho_gz:
            caminho_gz = LOCAL_DUMP

    # 1. Se não existir localmente, tenta baixar
    if not caminho_gz.exists() or caminho_gz.stat().st_size < 1000:
        if args.url:
            try:
                baixar_dump(args.url, caminho_gz)
            except Exception as e:
                print(f"⚠️ {e}")
                print("Dica: coloque o arquivo data/leeds_campo_grande.sql.gz ou .csv.gz localmente ou forneça uma --url válida.")
                sys.exit(1)
        else:
            print(f"ERRO: Arquivo {caminho_gz} não encontrado e nenhuma URL fornecida.")
            sys.exit(1)

    # 2. Restaura no SQLite
    restaurar_dump(caminho_gz, DB_PATH, force=args.force)


if __name__ == '__main__':
    main()
