#!/usr/bin/env python3
"""
Restaura e gerencia a camada geoespacial completa de imóveis urbanos de Campo Grande - MS
(462.744 lotes e edificações do cadastro municipal SISGRAN/PLANURB na tabela geo_imoveis
com índice espacial R*Tree geo_imoveis_rtree) a partir do dump comprimido
data/geo_imoveis.sql.gz no banco SQLite instance/app_clientes.db.

Segue o mesmo padrão arquitetural de scripts/restaurar_rfb.py (leeds_campo_grande):
1. Restaura a partir de arquivo local (data/geo_imoveis.sql.gz ou .csv.gz).
2. Faz download automático via URL pública caso o arquivo local não exista.
3. Permite gerar/atualizar o dump comprimido (--gerar-dump) a partir do banco SQLite
   ou do arquivo bruto geojson/imoveis.geojson.
"""
import argparse
import csv
import gzip
import os
import sqlite3
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
DB_PATH = ROOT / 'instance' / 'app_clientes.db'
LOCAL_DUMP = ROOT / 'data' / 'geo_imoveis.sql.gz'
GEOJSON_IMOVEIS = ROOT / 'geojson' / 'imoveis.geojson'

# URL pública padrão (pode ser sobrescrita via variável de ambiente IMOVEIS_DUMP_URL ou argumento --url)
DEFAULT_URL = os.environ.get(
    'IMOVEIS_DUMP_URL',
    'https://raw.githubusercontent.com/pizanao/leads-prospector/main/data/geo_imoveis.sql.gz'
)

CREATE_TABLE_GEO_IMOVEIS_SQL = """CREATE TABLE IF NOT EXISTS "geo_imoveis" (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    "gid" INTEGER,
    "codlote" TEXT,
    "codimo" INTEGER,
    "digito" INTEGER,
    "inscant" TEXT,
    "cidade" TEXT,
    "tipoloc" TEXT,
    "ruaimo" TEXT,
    "nrporta" INTEGER,
    "complement" TEXT,
    "parcelamen" TEXT,
    "quadra" TEXT,
    "lote" TEXT,
    "codbairro" INTEGER,
    "codregiao" INTEGER,
    "nomeregiao" TEXT,
    "nomebairro" TEXT,
    "areaterren" REAL,
    "arealote" REAL,
    "areaedific" REAL,
    "usoimovel" TEXT,
    "codlogrado" INTEGER,
    "codparcela" INTEGER,
    "inscant_busca" TEXT,
    "codlote_busca" TEXT,
    "logradouro_busca" TEXT,
    "data_referencia" TEXT,
    geometry_geojson TEXT,
    geometry_type TEXT,
    min_lng REAL,
    min_lat REAL,
    max_lng REAL,
    max_lat REAL,
    centroid_lat REAL,
    centroid_lng REAL,
    created_at TEXT DEFAULT (datetime('now'))
);"""

INDEXES_GEO_IMOVEIS_SQL = [
    'CREATE INDEX IF NOT EXISTS "idx_geo_imoveis_bbox" ON "geo_imoveis" (min_lng, min_lat, max_lng, max_lat);',
    'CREATE INDEX IF NOT EXISTS "idx_geo_imoveis_centroid" ON "geo_imoveis" (centroid_lat, centroid_lng);',
    'CREATE INDEX IF NOT EXISTS "idx_geo_imoveis_codlote" ON "geo_imoveis" ("codlote");',
    'CREATE INDEX IF NOT EXISTS "idx_geo_imoveis_ruaimo" ON "geo_imoveis" ("ruaimo");',
    'CREATE INDEX IF NOT EXISTS "idx_geo_imoveis_nomeregiao" ON "geo_imoveis" ("nomeregiao");',
    'CREATE INDEX IF NOT EXISTS "idx_geo_imoveis_nomebairro" ON "geo_imoveis" ("nomebairro");',
    'CREATE INDEX IF NOT EXISTS "idx_geo_imoveis_usoimovel" ON "geo_imoveis" ("usoimovel");',
    'CREATE VIRTUAL TABLE IF NOT EXISTS "geo_imoveis_rtree" USING rtree(id, min_lng, max_lng, min_lat, max_lat);',
    'INSERT OR REPLACE INTO "geo_imoveis_rtree" SELECT id, min_lng, max_lng, min_lat, max_lat FROM "geo_imoveis";',
]


def verificar_tabela_existente(conn) -> int:
    """Retorna a quantidade de registros atualmente na tabela geo_imoveis."""
    try:
        cur = conn.cursor()
        cur.execute("SELECT COUNT(*) FROM geo_imoveis")
        res = cur.fetchone()
        return res[0] if res and res[0] > 0 else 0
    except (sqlite3.OperationalError, sqlite3.DatabaseError):
        return 0


def baixar_dump(url: str, destino: Path):
    """Baixa o dump comprimido de geo_imoveis a partir de uma URL pública."""
    print(f"📥 Baixando base de imóveis urbanos (geo_imoveis) de repositório público:\n   {url}")
    destino.parent.mkdir(parents=True, exist_ok=True)
    temp_dest = destino.with_suffix('.tmp')

    req = urllib.request.Request(
        url,
        headers={'User-Agent': 'LeadsProspector-Setup/1.0'}
    )
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=120) as resp, open(temp_dest, 'wb') as out_f:
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
        raise RuntimeError(f"Falha ao baixar dump geo_imoveis de {url}: {e}")


def _sql_literal(val) -> str:
    """Formata um valor Python como literal SQL seguro e compacto."""
    if val is None:
        return 'NULL'
    if isinstance(val, bool):
        return '1' if val else '0'
    if isinstance(val, int):
        return str(val)
    if isinstance(val, float):
        return repr(round(val, 6))
    s = str(val).replace("'", "''")
    return f"'{s}'"


def gerar_dump(db_path: Path, destino_gz: Path, batch_size: int = 100):
    """
    Exporta a tabela geo_imoveis do SQLite para o arquivo comprimido data/geo_imoveis.sql.gz.
    Se a tabela ainda não estiver carregada com os dados completos e geojson/imoveis.geojson
    existir, executa a carga prévia automaticamente.
    """
    conn = sqlite3.connect(str(db_path))
    total = verificar_tabela_existente(conn)
    if total <= 20000 and GEOJSON_IMOVEIS.exists():
        conn.close()
        print("🔄 Carregando geojson/imoveis.geojson completo no SQLite antes de gerar o dump...")
        from scripts.carregar_geojson_sqlite import main as carregar_main
        old_argv = sys.argv
        try:
            sys.argv = [
                'carregar_geojson_sqlite.py',
                '--db', str(db_path),
                '--only', 'imoveis',
                '--execute',
                '--clean',
            ]
            carregar_main()
        finally:
            sys.argv = old_argv
        conn = sqlite3.connect(str(db_path))
        total = verificar_tabela_existente(conn)

    if total == 0:
        conn.close()
        raise RuntimeError("Tabela 'geo_imoveis' está vazia e geojson/imoveis.geojson não foi encontrado.")

    destino_gz.parent.mkdir(parents=True, exist_ok=True)
    temp_gz = destino_gz.with_suffix('.tmp.gz')

    print(f"🗜️  Gerando dump comprimido {destino_gz} para {total:,} imóveis...")
    t0 = time.time()

    cur = conn.cursor()
    cur.execute('PRAGMA table_info("geo_imoveis")')
    col_names = [r[1] for r in cur.fetchall()]
    cols_quoted = ', '.join(f'"{c}"' for c in col_names)

    cur.execute(f'SELECT {cols_quoted} FROM "geo_imoveis" ORDER BY id')

    with gzip.open(temp_gz, 'wt', encoding='utf-8', compresslevel=9) as gz:
        gz.write("BEGIN TRANSACTION;\n")
        gz.write('DROP TABLE IF EXISTS "geo_imoveis_rtree";\n')
        gz.write('DROP TABLE IF EXISTS "geo_imoveis";\n')
        gz.write(CREATE_TABLE_GEO_IMOVEIS_SQL + "\n")

        while True:
            rows = cur.fetchmany(batch_size)
            if not rows:
                break
            for row in rows:
                vals_sql = ','.join(_sql_literal(v) for v in row)
                gz.write(f'INSERT INTO "geo_imoveis" VALUES({vals_sql});\n')

        for idx_sql in INDEXES_GEO_IMOVEIS_SQL:
            gz.write(idx_sql + "\n")

        gz.write("COMMIT;\n")

    conn.close()
    temp_gz.replace(destino_gz)
    tamanho_mb = destino_gz.stat().st_size / (1024 * 1024)
    print(f"✓ Dump gerado com sucesso em {time.time() - t0:.2f}s: {destino_gz} ({tamanho_mb:.2f} MB)")


def _restaurar_sql(conn, caminho_gz: Path):
    """Restaura geo_imoveis a partir de arquivo .sql.gz ou .sql em streaming."""
    open_fn = gzip.open if str(caminho_gz).endswith('.gz') else open
    cur = conn.cursor()

    cur.execute("BEGIN TRANSACTION;")
    cur.execute('DROP TABLE IF EXISTS "geo_imoveis_rtree";')
    cur.execute('DROP TABLE IF EXISTS "geo_imoveis";')

    buffer = []
    with open_fn(caminho_gz, 'rt', encoding='utf-8') as f:
        for line in f:
            stripped = line.strip()
            if not stripped or stripped.startswith('--'):
                continue
            upper = stripped.upper()
            if upper in ('BEGIN TRANSACTION;', 'BEGIN;', 'COMMIT;'):
                continue
            buffer.append(line)
            if stripped.endswith(';'):
                stmt = ''.join(buffer).strip()
                buffer.clear()
                try:
                    cur.execute(stmt)
                except Exception as e:
                    if 'rtree' in stmt.lower():
                        pass
                    else:
                        raise e

    if buffer:
        stmt = ''.join(buffer).strip()
        if stmt:
            cur.execute(stmt)

    # Garante índices e R*Tree caso o dump contenha apenas a tabela e INSERTs
    for idx_sql in INDEXES_GEO_IMOVEIS_SQL:
        try:
            cur.execute(idx_sql)
        except Exception:
            pass


def _restaurar_csv(conn, caminho_gz: Path):
    """Restaura geo_imoveis a partir de arquivo .csv.gz ou .csv."""
    open_fn = gzip.open if str(caminho_gz).endswith('.gz') else open
    with open_fn(caminho_gz, 'rt', encoding='utf-8', newline='') as f:
        reader = csv.reader(f)
        header = next(reader)
        cur = conn.cursor()
        cur.execute("BEGIN TRANSACTION;")
        cur.execute('DROP TABLE IF EXISTS "geo_imoveis_rtree";')
        cur.execute('DROP TABLE IF EXISTS "geo_imoveis";')
        cur.execute(CREATE_TABLE_GEO_IMOVEIS_SQL)

        cols_quoted = ', '.join([f'"{c}"' for c in header])
        placeholders = ','.join(['?'] * len(header))
        sql = f'INSERT INTO "geo_imoveis" ({cols_quoted}) VALUES ({placeholders})'

        batch = []
        for row in reader:
            cleaned = [None if v == '' else v for v in row]
            batch.append(cleaned)
            if len(batch) >= 2000:
                cur.executemany(sql, batch)
                batch.clear()
        if batch:
            cur.executemany(sql, batch)

        for idx_sql in INDEXES_GEO_IMOVEIS_SQL:
            try:
                cur.execute(idx_sql)
            except Exception:
                pass


def restaurar_dump(caminho_gz: Path, db_path: Path, force: bool = False):
    """Restaura o dump comprimido de geo_imoveis no banco SQLite com PRAGMAs de alta velocidade."""
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(db_path))

    total_atual = verificar_tabela_existente(conn)
    # Se já possui a base completa (> 20.000 registros da amostra antiga) e não for --force, preserva
    if total_atual > 20000 and not force:
        print(f"✓ Tabela 'geo_imoveis' já contém {total_atual:,} imóveis. Use --force para recarregar.")
        conn.close()
        return

    print(f"📦 Restaurando geo_imoveis a partir de {caminho_gz.name} com PRAGMAs de alta velocidade...")
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

    print(f"✓ Sucesso! {total_final:,} imóveis urbanos restaurados em geo_imoveis no SQLite em {time.time() - t0:.2f}s.")


def main():
    parser = argparse.ArgumentParser(description="Restaura ou gera o dump comprimido da base geo_imoveis no SQLite.")
    parser.add_argument('--arquivo', type=str, default=None, help="Caminho do arquivo .sql.gz ou .csv.gz local.")
    parser.add_argument('--db', type=str, default=str(DB_PATH), help="Caminho do banco SQLite (padrão: instance/app_clientes.db).")
    parser.add_argument('--url', type=str, default=DEFAULT_URL, help="URL pública para download caso arquivo não exista.")
    parser.add_argument('--force', action='store_true', help="Força a recriação mesmo se a tabela já existir.")
    parser.add_argument('--gerar-dump', action='store_true', help="Gera o arquivo data/geo_imoveis.sql.gz a partir do banco/GeoJSON.")
    args = parser.parse_args()

    db_path = Path(args.db)
    caminho_gz = Path(args.arquivo) if args.arquivo else None

    if args.gerar_dump:
        destino = caminho_gz or LOCAL_DUMP
        gerar_dump(db_path, destino)
        return

    # Se não foi especificado, procura arquivos locais existentes
    if not caminho_gz or not caminho_gz.exists():
        for candidato in [
            ROOT / 'data' / 'geo_imoveis.sql.gz',
            ROOT / 'data' / 'geo_imoveis.csv.gz',
            ROOT / 'geo_imoveis.sql.gz',
            ROOT / 'geo_imoveis.csv.gz',
        ]:
            if candidato.exists() and candidato.stat().st_size > 1000:
                caminho_gz = candidato
                break
        if not caminho_gz:
            caminho_gz = LOCAL_DUMP

    # 1. Se não existir localmente, mas geojson/imoveis.geojson existir, gera o dump localmente
    if (not caminho_gz.exists() or caminho_gz.stat().st_size < 1000) and GEOJSON_IMOVEIS.exists():
        gerar_dump(db_path, caminho_gz)
        return

    # 2. Se não existir localmente, tenta baixar da URL pública
    if not caminho_gz.exists() or caminho_gz.stat().st_size < 1000:
        if args.url:
            try:
                baixar_dump(args.url, caminho_gz)
            except Exception as e:
                print(f"⚠️ {e}")
                print("Dica: coloque o arquivo data/geo_imoveis.sql.gz localmente ou forneça uma --url válida.")
                sys.exit(1)
        else:
            print(f"ERRO: Arquivo {caminho_gz} não encontrado e nenhuma URL fornecida.")
            sys.exit(1)

    # 3. Restaura no SQLite
    restaurar_dump(caminho_gz, db_path, force=args.force)


if __name__ == '__main__':
    main()
