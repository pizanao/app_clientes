#!/usr/bin/env python3
"""
Script de Análise Estrutural de Arquivos GeoJSON e Criação de Tabelas PostGIS.

Lê e analisa os arquivos .geojson do diretório geojson/, infere os tipos
corretos de cada coluna (INTEGER, BIGINT, NUMERIC, VARCHAR, TIMESTAMPTZ, DATE,
BOOLEAN, TEXT e GEOMETRY PostGIS), gera DDL com índices espaciais (GIST) e
permite criar as tabelas e importar os dados diretamente no PostgreSQL + PostGIS.

Uso:
    # Apenas analisar e exibir o relatório de tipos no terminal:
    python scripts/analisar_geojson_postgis.py

    # Gerar arquivo SQL DDL:
    python scripts/analisar_geojson_postgis.py --output-sql schema_geo.sql

    # Executar DDL e criar as tabelas no PostgreSQL (localhost / db_geo):
    python scripts/analisar_geojson_postgis.py --execute

    # Criar tabelas E importar todos os dados dos arquivos GeoJSON:
    python scripts/analisar_geojson_postgis.py --execute --import-data

Parâmetros adicionais:
    --dbname db_geo       (padrão: db_geo ou $PGDATABASE)
    --host localhost      (padrão: localhost ou $PGHOST)
    --port 5432           (padrão: 5432 ou $PGPORT)
    --user postgres       (padrão: postgres ou $PGUSER)
    --schema public       (padrão: public)
    --table-prefix geo_   (padrão: geo_)
    --srid 4326           (padrão: 4326 - WGS84)
"""

import argparse
import glob
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple


# ==============================================================================
# 1. INFERÊNCIA DE TIPOS E ANÁLISE ESTRUTURAL
# ==============================================================================

ISO_DATE_REGEX = re.compile(r'^\d{4}-\d{2}-\d{2}(?:Z|[+-]\d{2}:?\d{2})?$')
ISO_DATETIME_REGEX = re.compile(r'^\d{4}-\d{2}-\d{2}[T\s]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?$')


class FieldStats:
    """Acumula estatísticas e tipos observados em uma propriedade GeoJSON."""

    def __init__(self, name: str):
        self.name = name
        self.observed_types: Set[str] = set()
        self.total_count = 0
        self.null_count = 0
        self.min_val: Any = None
        self.max_val: Any = None
        self.max_str_len = 0
        self.distinct_samples: Set[Any] = set()

    def record_value(self, val: Any) -> None:
        self.total_count += 1
        if val is None:
            self.null_count += 1
            return

        if len(self.distinct_samples) < 5:
            self.distinct_samples.add(str(val)[:40])

        if isinstance(val, bool):
            self.observed_types.add('bool')
        elif isinstance(val, int):
            self.observed_types.add('int')
            self._update_min_max(val)
        elif isinstance(val, float):
            self.observed_types.add('float')
            self._update_min_max(val)
        elif isinstance(val, str):
            clean = val.strip()
            self.max_str_len = max(self.max_str_len, len(clean))
            if ISO_DATETIME_REGEX.match(clean):
                self.observed_types.add('timestamptz')
            elif ISO_DATE_REGEX.match(clean):
                self.observed_types.add('date')
            else:
                self.observed_types.add('str')
        elif isinstance(val, (dict, list)):
            self.observed_types.add('json')
        else:
            self.observed_types.add('str')
            self.max_str_len = max(self.max_str_len, len(str(val)))

    def _update_min_max(self, val: Any) -> None:
        if self.min_val is None or val < self.min_val:
            self.min_val = val
        if self.max_val is None or val > self.max_val:
            self.max_val = val

    def infer_postgres_type(self) -> str:
        """Determina o tipo ideal de dado do PostgreSQL baseado nos valores reais."""
        types = self.observed_types - {'null'}
        if not types:
            # Coluna 100% nula na amostra (ex: codigo_ibge)
            if any(term in self.name.lower() for term in ('id', 'cod', 'codigo', 'cod_')):
                return 'VARCHAR(50)'
            return 'TEXT'

        # Se houver bool e nada mais
        if types == {'bool'}:
            return 'BOOLEAN'

        # Numéricos
        if types == {'int'}:
            if self.min_val is not None and self.max_val is not None:
                if -2147483648 <= self.min_val and self.max_val <= 2147483647:
                    return 'INTEGER'
                return 'BIGINT'
            return 'INTEGER'

        if types in ({'float'}, {'int', 'float'}):
            # Se parecer área ou valor monetário, usa NUMERIC(14, 2)
            if any(term in self.name.lower() for term in ('area', 'valor', 'preco', 'taxa')):
                return 'NUMERIC(14, 2)'
            return 'DOUBLE PRECISION'

        # Datas
        if types == {'date'}:
            return 'DATE'
        if types == {'timestamptz'}:
            return 'TIMESTAMPTZ'
        if types == {'date', 'timestamptz'}:
            return 'TIMESTAMPTZ'

        # JSONB
        if 'json' in types:
            return 'JSONB'

        # Strings / Textos
        mlen = self.max_str_len
        if mlen == 0:
            return 'VARCHAR(50)'
        elif mlen <= 5:
            return 'VARCHAR(10)'
        elif mlen <= 15:
            return 'VARCHAR(25)'
        elif mlen <= 35:
            return 'VARCHAR(50)'
        elif mlen <= 80:
            return 'VARCHAR(120)'
        elif mlen <= 160:
            return 'VARCHAR(255)'
        else:
            return 'TEXT'


class TableSchema:
    """Metadados de uma tabela gerada a partir de um GeoJSON."""

    def __init__(self, filepath: str, table_name: str, srid: int = 4326):
        self.filepath = filepath
        self.filename = os.path.basename(filepath)
        self.table_name = table_name
        self.srid = srid
        self.feature_count = 0
        self.geometry_type = 'MultiPolygon'
        self.fields: Dict[str, FieldStats] = {}
        self.pk_field: Optional[str] = None
        self.has_geom = False
        self.bbox: Optional[Tuple[float, float, float, float]] = None

    def analyze(self) -> None:
        """Lê o GeoJSON e compila todas as propriedades e geometrias."""
        with open(self.filepath, 'r', encoding='utf-8') as fp:
            data = json.load(fp)

        features = data.get('features', [])
        self.feature_count = len(features)
        geom_types: Set[str] = set()

        min_x = min_y = float('inf')
        max_x = max_y = float('-inf')

        for feat in features:
            geom = feat.get('geometry')
            if geom:
                self.has_geom = True
                g_type = geom.get('type')
                if g_type:
                    geom_types.add(g_type)

            props = feat.get('properties') or {}
            for k, v in props.items():
                sanitized_name = re.sub(r'[^a-zA-Z0-9_]', '_', k.strip().lower())
                if sanitized_name not in self.fields:
                    self.fields[sanitized_name] = FieldStats(sanitized_name)
                self.fields[sanitized_name].record_value(v)

        # Determina tipo geométrico padrão
        if 'MultiPolygon' in geom_types or 'Polygon' in geom_types:
            self.geometry_type = 'MultiPolygon'
        elif 'Point' in geom_types or 'MultiPoint' in geom_types:
            self.geometry_type = 'Point' if geom_types == {'Point'} else 'MultiPoint'
        elif 'LineString' in geom_types or 'MultiLineString' in geom_types:
            self.geometry_type = 'MultiLineString'
        elif geom_types:
            self.geometry_type = list(geom_types)[0]
        else:
            self.geometry_type = 'Geometry'

        # Identifica candidato a chave primária
        for candidate in ('gid', 'id', 'codigo', 'codimo'):
            if candidate in self.fields:
                st = self.fields[candidate]
                if st.null_count == 0 and 'int' in st.observed_types:
                    self.pk_field = candidate
                    break

    def generate_ddl(self, schema: str = 'public', drop_existing: bool = False) -> str:
        """Gera o comando DDL SQL para criação da tabela e índices."""
        full_table = f'"{schema}"."{self.table_name}"'
        lines: List[str] = []

        if drop_existing:
            lines.append(f"DROP TABLE IF EXISTS {full_table} CASCADE;\n")

        lines.append(f"-- ============================================================================")
        lines.append(f"-- Tabela: {self.table_name}")
        lines.append(f"-- Origem: {self.filename} ({self.feature_count} features)")
        lines.append(f"-- Geometria: {self.geometry_type} (SRID {self.srid})")
        lines.append(f"-- ============================================================================")
        lines.append(f"CREATE TABLE IF NOT EXISTS {full_table} (")

        col_defs: List[str] = []

        # Se não houver campo PK inteiro, cria id_seq autoincremental
        if not self.pk_field:
            col_defs.append('    "id" SERIAL PRIMARY KEY')

        for col_name, st in self.fields.items():
            pg_type = st.infer_postgres_type()
            pk_clause = ' PRIMARY KEY' if col_name == self.pk_field else ''
            null_clause = '' if col_name == self.pk_field or st.null_count > 0 else ''
            col_defs.append(f'    "{col_name}" {pg_type}{pk_clause}{null_clause}')

        if self.has_geom:
            col_defs.append(f'    "geom" geometry({self.geometry_type}, {self.srid})')

        lines.append(',\n'.join(col_defs))
        lines.append(");")
        lines.append("")

        # Comentário na tabela
        lines.append(f"COMMENT ON TABLE {full_table} IS 'Importado do arquivo {self.filename} ({self.feature_count} feições geográficas).';")

        # Índices espaciais e B-Tree
        if self.has_geom:
            idx_name = f"idx_{self.table_name}_geom"
            lines.append(f"CREATE INDEX IF NOT EXISTS \"{idx_name}\" ON {full_table} USING GIST (\"geom\");")

        # Índices nas colunas de busca frequente
        common_search_cols = (
            'bairro', 'nomebairro', 'nome', 'nome_parcelamento', 'regiao_urb',
            'nomeregiao', 'codlote', 'inscant', 'codimo', 'ruaimo', 'cidade'
        )
        for c in common_search_cols:
            if c in self.fields and c != self.pk_field:
                idx_name = f"idx_{self.table_name}_{c}"
                lines.append(f"CREATE INDEX IF NOT EXISTS \"{idx_name}\" ON {full_table} (\"{c}\");")

        lines.append("")
        return '\n'.join(lines)


# ==============================================================================
# 2. INGESTÃO DE DADOS (IMPORTAÇÃO SQL NATIVA PARA POSTGIS)
# ==============================================================================

def escape_sql_val(val: Any, target_type: str) -> str:
    """Escapa e formata o valor para a instrução SQL INSERT."""
    if val is None:
        return 'NULL'
    if isinstance(val, bool):
        return 'TRUE' if val else 'FALSE'
    if isinstance(val, (int, float)):
        return str(val)
    if isinstance(val, (dict, list)):
        dumped = json.dumps(val, ensure_ascii=False).replace("'", "''")
        return f"'{dumped}'::jsonb"

    str_val = str(val).strip()
    if not str_val:
        return 'NULL' if target_type in ('INTEGER', 'BIGINT', 'DOUBLE PRECISION', 'DATE', 'TIMESTAMPTZ') else "''"

    # Conversão de datas com sufixo Z ou ISO
    if target_type == 'DATE':
        # Se for 2025-01-27Z, limpa o Z para formato puro date
        clean_date = str_val.replace('Z', '').split('T')[0]
        return f"'{clean_date}'::date"
    if target_type == 'TIMESTAMPTZ':
        return f"'{str_val}'::timestamptz"

    escaped = str_val.replace("'", "''")
    return f"'{escaped}'"


def generate_table_inserts(schema_obj: TableSchema, schema: str = 'public', batch_size: int = 500) -> List[str]:
    """Gera blocos de comandos INSERT com ST_Multi(ST_SetSRID(ST_GeomFromGeoJSON(...), SRID))."""
    with open(schema_obj.filepath, 'r', encoding='utf-8') as fp:
        data = json.load(fp)

    features = data.get('features', [])
    if not features:
        return []

    field_names = list(schema_obj.fields.keys())
    full_table = f'"{schema}"."{schema_obj.table_name}"'

    columns_sql = [f'"{f}"' for f in field_names]
    if schema_obj.has_geom:
        columns_sql.append('"geom"')
    cols_header = ', '.join(columns_sql)

    statements: List[str] = []
    current_values_batch: List[str] = []

    for feat in features:
        props = feat.get('properties') or {}
        row_vals: List[str] = []

        for field_name in field_names:
            val = props.get(field_name)
            target_type = schema_obj.fields[field_name].infer_postgres_type()
            row_vals.append(escape_sql_val(val, target_type))

        if schema_obj.has_geom:
            geom = feat.get('geometry')
            if geom:
                geom_json = json.dumps(geom, ensure_ascii=False).replace("'", "''")
                # ST_Multi garante conversão transparente para MultiPolygon
                row_vals.append(f"ST_Multi(ST_SetSRID(ST_GeomFromGeoJSON('{geom_json}'), {schema_obj.srid}))")
            else:
                row_vals.append('NULL')

        current_values_batch.append(f"({', '.join(row_vals)})")

        if len(current_values_batch) >= batch_size:
            sql = f"INSERT INTO {full_table} ({cols_header}) VALUES\n" + ',\n'.join(current_values_batch) + ';'
            statements.append(sql)
            current_values_batch = []

    if current_values_batch:
        sql = f"INSERT INTO {full_table} ({cols_header}) VALUES\n" + ',\n'.join(current_values_batch) + ';'
        statements.append(sql)

    return statements


# ==============================================================================
# 3. EXECUTOR POSTGRESQL / POSTGIS
# ==============================================================================

def execute_sql_in_postgres(sql_content: str, host: str, port: int, user: str, dbname: str, password: Optional[str] = None) -> None:
    """Executa o script SQL diretamente via psql no PostgreSQL."""
    env = os.environ.copy()
    if password:
        env['PGPASSWORD'] = password

    with tempfile.NamedTemporaryFile('w', suffix='.sql', encoding='utf-8', delete=False) as tf:
        tf.write(sql_content)
        temp_path = tf.name

    try:
        cmd = [
            'psql',
            '-h', host,
            '-p', str(port),
            '-U', user,
            '-d', dbname,
            '-v', 'ON_ERROR_STOP=1',
            '-f', temp_path,
        ]
        result = subprocess.run(cmd, env=env, capture_output=True, text=True, encoding='utf-8')
        if result.returncode != 0:
            sys.stderr.write(f"\n[ERRO AO EXECUTAR SQL VIA PSQL]\n{result.stderr}\n")
            raise RuntimeError(f"psql falhou com código {result.returncode}")
    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)


# ==============================================================================
# 4. FORMATAÇÃO E INTERFACE CLI
# ==============================================================================

def sanitize_table_name(filename: str, prefix: str = 'geo_') -> str:
    """Converte o nome do arquivo geojson para um nome de tabela SQL válido."""
    base = os.path.splitext(os.path.basename(filename))[0].lower()
    clean = re.sub(r'[^a-z0-9_]', '_', base)
    clean = re.sub(r'_+', '_', clean).strip('_')
    if prefix and not clean.startswith(prefix):
        clean = f"{prefix}{clean}"
    return clean


def print_table_report(schema_obj: TableSchema) -> None:
    """Exibe um relatório tabular elegante no terminal."""
    print("=" * 80)
    print(f"📁 ARQUIVO: {schema_obj.filename}")
    print(f"📊 TABELA:  {schema_obj.table_name}")
    print(f"📍 FEIÇÕES: {schema_obj.feature_count:,} | GEOMETRIA: {schema_obj.geometry_type} (SRID {schema_obj.srid})")
    if schema_obj.pk_field:
        print(f"🔑 CHAVE PRIMÁRIA: {schema_obj.pk_field} (automática)")
    print("-" * 80)
    print(f"{'COLUNA':<22} | {'TIPO POSTGRES':<18} | {'NULOS':<10} | {'AMOSTRA'}")
    print("-" * 80)

    for col_name, st in sorted(schema_obj.fields.items()):
        pg_type = st.infer_postgres_type()
        null_info = f"{st.null_count}/{st.total_count}"
        sample = list(st.distinct_samples)[0] if st.distinct_samples else '-'
        print(f"{col_name:<22} | {pg_type:<18} | {null_info:<10} | {sample}")

    if schema_obj.has_geom:
        print(f"{'geom':<22} | {f'geometry({schema_obj.geometry_type}, {schema_obj.srid})':<18} | {'0/total':<10} | PostGIS Geometry")
    print("=" * 80 + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Analisa GeoJSONs e cria tabelas correspondentes no PostgreSQL + PostGIS.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        'files',
        nargs='*',
        default=['geojson/*.geojson'],
        help="Caminhos ou globs para arquivos .geojson (padrão: geojson/*.geojson)",
    )
    parser.add_argument('--host', default=os.environ.get('PGHOST', 'localhost'), help="Host do PostgreSQL (padrão: localhost)")
    parser.add_argument('--port', type=int, default=int(os.environ.get('PGPORT', 5432)), help="Porta do PostgreSQL (padrão: 5432)")
    parser.add_argument('--user', default=os.environ.get('PGUSER', 'postgres'), help="Usuário do PostgreSQL (padrão: postgres)")
    parser.add_argument('--password', default=os.environ.get('PGPASSWORD'), help="Senha do PostgreSQL (opcional)")
    parser.add_argument('--dbname', default=os.environ.get('PGDATABASE', 'db_geo'), help="Nome do Banco de Dados (padrão: db_geo)")
    parser.add_argument('--schema', default='public', help="Schema do banco de dados (padrão: public)")
    parser.add_argument('--table-prefix', default='geo_', help="Prefixo para as tabelas criadas (padrão: geo_)")
    parser.add_argument('--srid', type=int, default=4326, help="SRID para geometrias (padrão: 4326 - WGS84)")
    parser.add_argument('--output-sql', help="Salva todo o DDL gerado em um arquivo .sql")
    parser.add_argument('--execute', action='store_true', help="Executa o DDL no PostgreSQL + PostGIS criando as tabelas")
    parser.add_argument('--import-data', action='store_true', help="Importa todos os dados das feições para as tabelas criadas")
    parser.add_argument('--drop-existing', action='store_true', help="Derruba tabelas existentes antes de recriar (DROP CASCADE)")
    parser.add_argument('--batch-size', type=int, default=500, help="Tamanho do lote para inserção de dados (padrão: 500)")

    args = parser.parse_args()

    # Expande padrões de arquivo
    target_files: List[str] = []
    for pattern in args.files:
        matches = glob.glob(pattern)
        if matches:
            target_files.extend(matches)
        elif os.path.isfile(pattern):
            target_files.append(pattern)

    target_files = sorted(list(set(target_files)))

    if not target_files:
        print(f"❌ Nenhum arquivo GeoJSON encontrado para o padrão: {args.files}")
        return 1

    print(f"\n🚀 Iniciando análise estrutural de {len(target_files)} arquivo(s) GeoJSON...\n")

    schemas: List[TableSchema] = []
    total_features = 0

    for fpath in target_files:
        tbl_name = sanitize_table_name(fpath, prefix=args.table_prefix)
        schema_obj = TableSchema(filepath=fpath, table_name=tbl_name, srid=args.srid)
        schema_obj.analyze()
        schemas.append(schema_obj)
        total_features += schema_obj.feature_count
        print_table_report(schema_obj)

    # 1. Monta o script DDL completo
    ddl_parts: List[str] = [
        "-- ============================================================================",
        f"-- DDL AUTOMÁTICO POSTGIS GERADO EM {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        "-- ============================================================================",
        "CREATE EXTENSION IF NOT EXISTS postgis;",
        f"CREATE SCHEMA IF NOT EXISTS \"{args.schema}\";",
        "",
    ]

    for s in schemas:
        ddl_parts.append(s.generate_ddl(schema=args.schema, drop_existing=args.drop_existing))

    full_ddl = '\n'.join(ddl_parts)

    # 2. Salva arquivo SQL se solicitado
    if args.output_sql:
        with open(args.output_sql, 'w', encoding='utf-8') as f:
            f.write(full_ddl)
        print(f"💾 Script DDL gerado com sucesso em: {args.output_sql}")

    # 3. Executa no PostgreSQL se solicitado
    if args.execute:
        print(f"🔌 Conectando ao PostgreSQL ({args.host}:{args.port} / {args.dbname} - usuário: {args.user})...")
        start_t = time.time()
        try:
            execute_sql_in_postgres(
                full_ddl,
                host=args.host,
                port=args.port,
                user=args.user,
                dbname=args.dbname,
                password=args.password,
            )
            print(f"✅ Tabelas e índices espaciais criados com sucesso em {time.time() - start_t:.2f}s!")
        except Exception as e:
            print(f"❌ Falha ao criar tabelas no PostgreSQL: {e}")
            return 1

        # 4. Importa dados se solicitado
        if args.import_data:
            print(f"\n📦 Iniciando importação de dados ({total_features:,} feições no total)...")
            import_start = time.time()
            for s in schemas:
                print(f"   ⏳ Inserindo dados em '{s.table_name}' ({s.feature_count:,} registros)...", end='', flush=True)
                t0 = time.time()
                inserts = generate_table_inserts(s, schema=args.schema, batch_size=args.batch_size)
                if inserts:
                    full_inserts_sql = "BEGIN;\n" + '\n'.join(inserts) + "\nCOMMIT;"
                    execute_sql_in_postgres(
                        full_inserts_sql,
                        host=args.host,
                        port=args.port,
                        user=args.user,
                        dbname=args.dbname,
                        password=args.password,
                    )
                print(f" Concluído em {time.time() - t0:.2f}s.")
            print(f"🎉 Importação completa concluída com sucesso em {time.time() - import_start:.2f}s!\n")
    else:
        print("💡 DICA: Para criar as tabelas no banco de dados local, execute:")
        print(f"    python scripts/analisar_geojson_postgis.py --execute")
        print("💡 Para criar as tabelas E já importar todas as feições:")
        print(f"    python scripts/analisar_geojson_postgis.py --execute --import-data\n")

    return 0


if __name__ == '__main__':
    sys.exit(main())
