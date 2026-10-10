---
name: carregar-geojson-sqlite
description: Guia e ferramenta para análise estrutural de arquivos GeoJSON, inferência dinâmica de tipos e carregamento em banco SQLite com bounding boxes, centróides e indexação espacial R*Tree (geo_bairros, geo_imoveis, geo_parcelamentos, geo_pd_macrozonas_urbanas).
---

# Carregamento e Indexação Espacial de GeoJSON no SQLite

## 1. Visão Geral

Esta skill orienta os agentes a processar e consultar arquivos GeoJSON urbanos de Campo Grande - MS diretamente no banco SQLite (`instance/app_clientes.db`), replicando as capacidades de um banco espacial PostGIS sem a necessidade de dependências C pesadas.

Utiliza a biblioteca padrão `sqlite3` do Python com suporte nativo a tabelas virtuais **R*Tree** para acelerar filtros de bounding box e proximidade geográfica.

---

## 2. Camadas GeoJSON Suportadas

Os arquivos estão localizados em `geojson/`:

| Arquivo GeoJSON | Tabela SQLite | Features | Tipo Geométrico | Descrição |
| :--- | :--- | :--- | :--- | :--- |
| `bairros.geojson` | `geo_bairros` | 74 | MultiPolygon | 74 Bairros Oficiais de Campo Grande (PLANURB/SISGRAN) |
| `imoveis.geojson` | `geo_imoveis` | 20.000 | MultiPolygon | Lotes, quadras e cadastros de imóveis municipais |
| `parcelamentos.geojson` | `geo_parcelamentos` | 894 | MultiPolygon | Parcelamentos urbanos e loteamentos aprovados |
| `pd-macrozonas-urbanas.geojson` | `geo_pd_macrozonas_urbanas` | 74 | MultiPolygon | Macrozonas do Plano Diretor de Campo Grande |

---

## 3. Execução do Script de Carga (`scripts/carregar_geojson_sqlite.py`)

```bash
# 1. Analisar os arquivos e exibir o relatório de colunas e limites geográficos (dry-run):
python scripts/carregar_geojson_sqlite.py

# 2. Executar a criação das tabelas e carregar todas as 21.042 features no SQLite:
python scripts/carregar_geojson_sqlite.py --execute

# 3. Limpar tabelas anteriores e reimportar do zero:
python scripts/carregar_geojson_sqlite.py --execute --clean

# 4. Exportar o schema SQL DDL gerado para arquivo:
python scripts/carregar_geojson_sqlite.py --output-sql schema_geo_sqlite.sql
```

---

## 4. Estrutura das Tabelas Espaciais Criadas

Cada tabela recebe as propriedades inferidas do GeoJSON mais colunas espaciais padronizadas:

```sql
CREATE TABLE IF NOT EXISTS "geo_imoveis" (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    gid INTEGER,
    codlote INTEGER,
    codimo INTEGER,
    ruaimo TEXT,
    nrporta INTEGER,
    nomebairro TEXT,
    nomeregiao TEXT,
    areaterren REAL,
    geometry_geojson TEXT,      -- Geometria GeoJSON completa
    geometry_type TEXT,         -- MultiPolygon / Polygon / Point
    min_lng REAL,               -- Limite Oeste
    min_lat REAL,               -- Limite Sul
    max_lng REAL,               -- Limite Leste
    max_lat REAL,               -- Limite Norte
    centroid_lat REAL,          -- Latitude do Centróide
    centroid_lng REAL,          -- Longitude do Centróide
    created_at TEXT DEFAULT (datetime('now'))
);

-- Índices B-Tree compostos
CREATE INDEX idx_geo_imoveis_bbox ON geo_imoveis (min_lng, min_lat, max_lng, max_lat);
CREATE INDEX idx_geo_imoveis_centroid ON geo_imoveis (centroid_lat, centroid_lng);

-- Tabela Virtual R*Tree (alta performance para buscas de área)
CREATE VIRTUAL TABLE geo_imoveis_rtree USING rtree(id, min_lng, max_lng, min_lat, max_lat);
```

---

## 5. Consultas Espaciais Rápidas em SQLite

### A. Busca por Bounding Box / Janela de Visualização do Mapa:
```sql
SELECT i.id, i.ruaimo, i.nrporta, i.nomebairro, i.centroid_lat, i.centroid_lng
FROM geo_imoveis i
JOIN geo_imoveis_rtree r ON i.id = r.id
WHERE r.min_lng >= -54.60 AND r.max_lng <= -54.55
  AND r.min_lat >= -20.48 AND r.max_lat <= -20.44
LIMIT 50;
```

### B. Busca de Imóveis Mais Próximos de um Ponto (Centróide do Bairro):
```sql
SELECT 
    ruaimo, nrporta, nomebairro, centroid_lat, centroid_lng,
    ((centroid_lat - (-20.45))*(centroid_lat - (-20.45)) + 
     (centroid_lng - (-54.60))*(centroid_lng - (-54.60))) AS dist_sq
FROM geo_imoveis
WHERE nomebairro = 'Chácara Cachoeira' AND ruaimo IS NOT NULL
ORDER BY dist_sq ASC
LIMIT 10;
```

### C. Contagem de Imóveis por Bairro no SQLite:
```sql
SELECT nomebairro, count(*) AS total_imoveis
FROM geo_imoveis
WHERE nomebairro IS NOT NULL
GROUP BY nomebairro
ORDER BY total_imoveis DESC;
```

---

## 6. Integração com o Módulo `perfis_sisgran.py`

Os dados carregados no SQLite servem de suporte para enriquecer os perfis territoriais de `app/data/perfis_sisgran.py`:
- `obter_perfil_bairro(bairro)`: Retorna centróide oficial, macrozona, regiao urbana e prefixo de CEP.
- `obter_ruas_bairro(bairro)`: Retorna os logradouros reais identificados nos imóveis do bairro.
- `obter_imoveis_amostra(bairro)`: Fornece amostras de logradouro e número para calibrar leads de telecomunicações.
