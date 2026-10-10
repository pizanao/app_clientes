#!/usr/bin/env python3
"""
Script de Análise Estrutural de Arquivos GeoJSON e Criação de Tabelas SQLite com Indexação Espacial.

Lê e analisa os arquivos .geojson do diretório geojson/, infere os tipos
corretos de cada coluna (INTEGER, REAL, TEXT), calcula bounding boxes (min/max lat e lng),
centróides geométricos, armazena a geometria GeoJSON completa e cria índices
B-Tree e R*Tree espaciais diretamente no SQLite (instance/app_clientes.db).

Uso:
    # Apenas analisar e exibir o relatório de tipos no terminal:
    python scripts/carregar_geojson_sqlite.py

    # Gerar arquivo SQL DDL:
    python scripts/carregar_geojson_sqlite.py --output-sql schema_geo_sqlite.sql

    # Executar DDL e importar todos os dados para o SQLite (instance/app_clientes.db):
    python scripts/carregar_geojson_sqlite.py --execute

    # Limpar tabelas anteriores e reimportar:
    python scripts/carregar_geojson_sqlite.py --execute --clean

Parâmetros adicionais:
    --db instance/app_clientes.db    (caminho para o banco SQLite)
    --geojson-dir geojson            (pasta contendo os arquivos .geojson)
    --table-prefix geo_              (prefixo das tabelas geradas)
    --batch-size 1000                (tamanho do lote para executemany)
"""

import argparse
import glob
import json
import math
import os
import re
import sqlite3
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DB = ROOT / 'instance' / 'app_clientes.db'
DEFAULT_GEOJSON_DIR = ROOT / 'geojson'

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
            self.observed_types.add('int')
        elif isinstance(val, int):
            self.observed_types.add('int')
            self._update_min_max(val)
        elif isinstance(val, float):
            self.observed_types.add('float')
            self._update_min_max(val)
        elif isinstance(val, str):
            clean = val.strip()
            self.max_str_len = max(self.max_str_len, len(clean))
            if clean.isdigit():
                self.observed_types.add('int')
            else:
                self.observed_types.add('str')
        elif isinstance(val, (dict, list)):
            self.observed_types.add('str')
        else:
            self.observed_types.add('str')

    def _update_min_max(self, val: Any) -> None:
        if self.min_val is None or val < self.min_val:
            self.min_val = val
        if self.max_val is None or val > self.max_val:
            self.max_val = val

    def infer_sqlite_type(self) -> str:
        """Determina o tipo ideal de dado do SQLite (INTEGER, REAL, TEXT)."""
        types = self.observed_types - {'null'}
        if not types:
            return 'TEXT'
        if types == {'int'}:
            return 'INTEGER'
        if types in ({'float'}, {'int', 'float'}):
            return 'REAL'
        return 'TEXT'


def extract_coordinates_and_bounds(geometry: Dict[str, Any]) -> Tuple[str, Tuple[float, float, float, float], Tuple[float, float]]:
    """
    Extrai tipo de geometria, bounding box (min_lng, min_lat, max_lng, max_lat)
    e centróide aproximado (centroid_lat, centroid_lng).
    """
    g_type = geometry.get('type', 'Geometry')
    coords = geometry.get('coordinates', [])

    all_points: List[Tuple[float, float]] = []

    def walk_coords(c: Any) -> None:
        if isinstance(c, (list, tuple)):
            if len(c) >= 2 and isinstance(c[0], (int, float)) and isinstance(c[1], (int, float)):
                all_points.append((float(c[0]), float(c[1])))
            else:
                for item in c:
                    walk_coords(item)

    walk_coords(coords)

    if not all_points:
        return g_type, (-54.62, -20.45, -54.62, -20.45), (-20.45, -54.62)

    min_lng = min(p[0] for p in all_points)
    max_lng = max(p[0] for p in all_points)
    min_lat = min(p[1] for p in all_points)
    max_lat = max(p[1] for p in all_points)

    centroid_lng = sum(p[0] for p in all_points) / len(all_points)
    centroid_lat = sum(p[1] for p in all_points) / len(all_points)

    return g_type, (min_lng, min_lat, max_lng, max_lat), (centroid_lat, centroid_lng)


class GeoJsonTable:
    """Representa uma camada GeoJSON a ser importada no SQLite."""

    def __init__(self, filepath: str, table_name: str):
        self.filepath = filepath
        self.filename = os.path.basename(filepath)
        self.table_name = table_name
        self.fields: Dict[str, FieldStats] = {}
        self.features: List[Dict[str, Any]] = []
        self.geometry_type = 'Geometry'
        self.bbox: Tuple[float, float, float, float] = (0, 0, 0, 0)

    def analyze(self) -> None:
        with open(self.filepath, 'r', encoding='utf-8') as f:
            data = json.load(f)

        self.features = data.get('features', [])
        all_lons: List[float] = []
        all_lats: List[float] = []

        for feat in self.features:
            geom = feat.get('geometry')
            if geom:
                g_type, (min_x, min_y, max_x, max_y), _ = extract_coordinates_and_bounds(geom)
                self.geometry_type = g_type
                all_lons.extend([min_x, max_x])
                all_lats.extend([min_y, max_y])

            props = feat.get('properties') or {}
            for k, v in props.items():
                col = re.sub(r'[^a-zA-Z0-9_]', '_', k.strip().lower())
                if not col:
                    col = 'col'
                if col not in self.fields:
                    self.fields[col] = FieldStats(col)
                self.fields[col].record_value(v)

        if all_lons and all_lats:
            self.bbox = (min(all_lons), min(all_lats), max(all_lons), max(all_lats))

    def generate_ddl(self) -> List[str]:
        """Gera comandos SQL DDL para a tabela principal e índices espaciais."""
        col_defs = ["id INTEGER PRIMARY KEY AUTOINCREMENT"]
        for col, stats in self.fields.items():
            if col == 'id':
                continue
            sqlite_type = stats.infer_sqlite_type()
            col_defs.append(f'"{col}" {sqlite_type}')

        # Colunas espaciais padronizadas
        col_defs.extend([
            "geometry_geojson TEXT",
            "geometry_type TEXT",
            "min_lng REAL",
            "min_lat REAL",
            "max_lng REAL",
            "max_lat REAL",
            "centroid_lat REAL",
            "centroid_lng REAL",
            "created_at TEXT DEFAULT (datetime('now'))"
        ])

        ddl = [
            f'CREATE TABLE IF NOT EXISTS "{self.table_name}" (\n    ' + ',\n    '.join(col_defs) + '\n);',
            f'CREATE INDEX IF NOT EXISTS "idx_{self.table_name}_bbox" ON "{self.table_name}" (min_lng, min_lat, max_lng, max_lat);',
            f'CREATE INDEX IF NOT EXISTS "idx_{self.table_name}_centroid" ON "{self.table_name}" (centroid_lat, centroid_lng);',
        ]

        # Índices úteis para atributos textuais frequentes
        for col in self.fields.keys():
            if col in ('nome', 'bairro', 'nm_bairro', 'regiao_urbana', 'logradouro', 'inscricao', 'cep'):
                ddl.append(f'CREATE INDEX IF NOT EXISTS "idx_{self.table_name}_{col}" ON "{self.table_name}" ("{col}");')

        # Virtual Table R*Tree para buscas geométricas ultra-rápidas (se suportado)
        rtree_name = f"{self.table_name}_rtree"
        ddl.append(f'CREATE VIRTUAL TABLE IF NOT EXISTS "{rtree_name}" USING rtree(id, min_lng, max_lng, min_lat, max_lat);')

        return ddl


def main():
    parser = argparse.ArgumentParser(
        description="Analisa arquivos GeoJSON e cria tabelas estruturadas no SQLite com índices espaciais."
    )
    parser.add_argument('--db', default=str(DEFAULT_DB), help="Caminho do banco SQLite (padrão: instance/app_clientes.db)")
    parser.add_argument('--geojson-dir', default=str(DEFAULT_GEOJSON_DIR), help="Diretório dos arquivos .geojson")
    parser.add_argument('--table-prefix', default='geo_', help="Prefixo para as tabelas criadas (padrão: geo_)")
    parser.add_argument('--execute', action='store_true', help="Executa a criação das tabelas e importação dos dados no SQLite")
    parser.add_argument('--clean', action='store_true', help="Remove tabelas existentes antes de recriar")
    parser.add_argument('--output-sql', help="Salva os comandos DDL gerados em um arquivo SQL")
    parser.add_argument('--batch-size', type=int, default=1000, help="Tamanho do lote para inserção (padrão: 1000)")
    parser.add_argument('--quiet', action='store_true', help="Suprime saída detalhada no terminal")

    args = parser.parse_args()

    geojson_dir = Path(args.geojson_dir)
    if not geojson_dir.exists():
        print(f"❌ Diretório não encontrado: {geojson_dir}")
        sys.exit(1)

    arquivos = sorted(glob.glob(str(geojson_dir / '*.geojson')))
    if not arquivos:
        print(f"❌ Nenhum arquivo .geojson encontrado em: {geojson_dir}")
        sys.exit(1)

    print("=" * 80)
    print("📍 ANÁLISE E CARREGAMENTO DE GEOJSON NO SQLITE COM SUPORTE ESPACIAL")
    print("=" * 80)
    print(f"Diretório GeoJSON: {geojson_dir}")
    print(f"Banco SQLite:      {args.db}")
    print(f"Arquivos achados:  {len(arquivos)}")
    print(f"Modo de execução:  {'EXECUTAR CRIAÇÃO E CARGA' if args.execute else 'APENAS ANÁLISE (DRY-RUN)'}")
    print("=" * 80)

    tables: List[GeoJsonTable] = []
    total_features = 0

    for arq in arquivos:
        base = Path(arq).stem
        sanitized = re.sub(r'[^a-zA-Z0-9_]', '_', base.lower())
        table_name = f"{args.table_prefix}{sanitized}"
        gt = GeoJsonTable(arq, table_name)
        gt.analyze()
        tables.append(gt)
        total_features += len(gt.features)

        if not args.quiet:
            print(f"\n📂 Arquivo: {gt.filename}")
            print(f"   Tabela:    {gt.table_name}")
            print(f"   Features:  {len(gt.features):,}")
            print(f"   Geometria: {gt.geometry_type}")
            print(f"   Bounds:    LNG [{gt.bbox[0]:.4f}, {gt.bbox[2]:.4f}] | LAT [{gt.bbox[1]:.4f}, {gt.bbox[3]:.4f}]")
            print("   Colunas Inferidas:")
            for col, stats in gt.fields.items():
                print(f"     - {col:<24} {stats.infer_sqlite_type():<8} (não-nulos: {stats.total_count - stats.null_count}/{stats.total_count})")

    # Gera SQL DDL consolidado
    all_ddl: List[str] = []
    for gt in tables:
        all_ddl.extend(gt.generate_ddl())

    if args.output_sql:
        with open(args.output_sql, 'w', encoding='utf-8') as f:
            f.write("-- DDL gerado para camadas GeoJSON no SQLite\n\n")
            f.write("\n\n".join(all_ddl))
            f.write("\n")
        print(f"\n💾 DDL salvo com sucesso em: {args.output_sql}")

    if not args.execute:
        print("\n💡 Para criar as tabelas e carregar os dados no SQLite, rode:")
        print("   python scripts/carregar_geojson_sqlite.py --execute")
        return

    # Execução no SQLite
    db_path = Path(args.db)
    db_path.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(str(db_path))
    cur = con.cursor()

    # Otimizações pragmas de performance para inserção em lote
    cur.execute("PRAGMA synchronous = OFF;")
    cur.execute("PRAGMA journal_mode = MEMORY;")
    cur.execute("PRAGMA cache_size = -64000;")  # 64MB cache

    inicio_total = time.time()

    for gt in tables:
        t_inicio = time.time()
        print(f"\n🚀 Processando tabela {gt.table_name}...")

        if args.clean:
            cur.execute(f'DROP TABLE IF EXISTS "{gt.table_name}_rtree";')
            cur.execute(f'DROP TABLE IF EXISTS "{gt.table_name}";')

        # Executa DDL
        for cmd in gt.generate_ddl():
            try:
                cur.execute(cmd)
            except Exception as e:
                # Se falhar RTree (em versão antiga sem suporte), segue normalmente com índices b-tree
                if "rtree" in cmd.lower():
                    pass
                else:
                    raise e

        # Prepara inserção de dados
        field_names = [f for f in gt.fields.keys() if f != 'id']
        cols = ['"' + f + '"' for f in field_names] + [
            "geometry_geojson", "geometry_type", "min_lng", "min_lat", "max_lng", "max_lat", "centroid_lat", "centroid_lng"
        ]
        placeholders = ', '.join(['?'] * len(cols))
        insert_sql = f'INSERT INTO "{gt.table_name}" ({", ".join(cols)}) VALUES ({placeholders})'

        batch_rows: List[List[Any]] = []
        rtree_rows: List[Tuple[int, float, float, float, float]] = []
        inserted = 0

        for feat in gt.features:
            props = feat.get('properties') or {}
            geom = feat.get('geometry') or {}

            g_type, (min_lng, min_lat, max_lng, max_lat), (cent_lat, cent_lng) = extract_coordinates_and_bounds(geom)

            row: List[Any] = []
            for f_name in field_names:
                # Procura correspondência insensitive nos properties originais
                val = None
                for k, v in props.items():
                    if re.sub(r'[^a-zA-Z0-9_]', '_', k.strip().lower()) == f_name:
                        val = v
                        break
                if isinstance(val, (dict, list)):
                    val = json.dumps(val, ensure_ascii=False)
                row.append(val)

            geom_json_str = json.dumps(geom, ensure_ascii=False) if geom else None
            row.extend([
                geom_json_str,
                g_type,
                min_lng, min_lat, max_lng, max_lat,
                cent_lat, cent_lng
            ])
            batch_rows.append(row)

            if len(batch_rows) >= args.batch_size:
                cur.executemany(insert_sql, batch_rows)
                inserted += len(batch_rows)
                batch_rows = []

        if batch_rows:
            cur.executemany(insert_sql, batch_rows)
            inserted += len(batch_rows)

        # Popula o RTree
        try:
            cur.execute(f'SELECT id, min_lng, max_lng, min_lat, max_lat FROM "{gt.table_name}"')
            rtree_batch = cur.fetchall()
            cur.executemany(f'INSERT OR REPLACE INTO "{gt.table_name}_rtree" VALUES (?, ?, ?, ?, ?)', rtree_batch)
        except Exception:
            pass

        t_fim = time.time()
        print(f"   ✅ {inserted:,} registros inseridos com sucesso ({t_fim - t_inicio:.2f}s).")

    con.commit()
    con.close()

    tempo_total = time.time() - inicio_total
    print("\n" + "=" * 80)
    print(f"🎉 SUCESSO! {total_features:,} features carregadas nas tabelas espaciais do SQLite em {tempo_total:.2f}s.")
    print("=" * 80)


if __name__ == '__main__':
    main()
