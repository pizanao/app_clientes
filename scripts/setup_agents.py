#!/usr/bin/env python3
"""
Script de Configuração e Geração de Documentação para Agentes de IA (AGENTS.md, README.md e SKILLs).

Gera e mantém sincronizados:
1. AGENTS.md: Guia mestre de arquitetura, padrões e instruções para agentes de IA (Antigravity, Cursor, Copilot).
2. README.md: Documentação executiva e técnica completa do ecossistema DigitalNet MS.
3. SKILLs do Workspace (.agents/skills/):
   - enriquecer-prospectar-rfb: Enriquecimento e prospecção com 177k empresas da RFB e SISGRAN.
   - carregar-geojson-sqlite: Análise e carregamento de camadas GeoJSON no SQLite com índices espaciais R*Tree.
4. Instalação automática das SKILLs no diretório global (~/.gemini/config/skills/) quando disponível.

Uso:
    python scripts/setup_agents.py          # Gera AGENTS.md, README.md e instala as SKILLs
    python scripts/setup_agents.py --check  # Valida se a documentação está íntegra
"""

import argparse
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
AGENTS_MD_PATH = ROOT / 'AGENTS.md'
README_MD_PATH = ROOT / 'README.md'
WORKSPACE_AGENTS_DIR = ROOT / '.agents'
WORKSPACE_SKILLS_DIR = WORKSPACE_AGENTS_DIR / 'skills'
GLOBAL_SKILLS_DIR = Path.home() / '.gemini' / 'config' / 'skills'


# ==============================================================================
# DEFINIÇÃO DAS SKILLS
# ==============================================================================

SKILL_ENRIQUECER_PROSPECTAR_RFB = """---
name: enriquecer-prospectar-rfb
description: Procedimento completo de enriquecimento de clientes e prospecção geo-localizada de leads B2B utilizando a base de 177.614 empresas da Receita Federal do Brasil (leeds_campo_grande), inteligência territorial SISGRAN/PLANURB e regras de anti-ban no WhatsApp.
---

# Enriquecimento e Prospecção com Dados Abertos da RFB em Campo Grande

## 1. Visão Geral

O projeto conta com uma base proprietária de **177.614 empresas ativas** da Receita Federal do Brasil (RFB) sediadas em Campo Grande - MS, armazenada na tabela `leeds_campo_grande` no banco SQLite (`instance/app_clientes.db`).

Esta skill ensina os agentes a:
1. **Enriquecer a base de clientes ativos** (`clientes`), criando nós ópticos distribuídos por todos os bairros de Campo Grande.
2. **Executar a prospecção geo-localizada** de leads comerciais (`TelecomProspectorService._fetch_rfb_leads`), garantindo empresas reais, ativas, com CNPJ formatado, decidores e telefones válidos.
3. **Aplicar deduplicação global rigorosa** para evitar que empresas repetidas sejam gravadas.
4. **Gerar abordagens consultivas no WhatsApp com opt-in explícito**, blindando números contra banimento.

---

## 2. Estrutura da Tabela `leeds_campo_grande`

| Coluna | Tipo SQLite | Descrição |
| :--- | :--- | :--- |
| `empresa` | TEXT | Razão Social ou Nome Fantasia da empresa |
| `cnpj` | TEXT | CNPJ com 14 dígitos numéricos |
| `nome` | TEXT | Nome do sócio-administrador, diretor ou empresário |
| `cargo` | TEXT | Cargo formal (Sócio-Administrador, Empresário, Presidente) |
| `telefone` | INTEGER/TEXT | Telefone fixo ou celular (DDD 67) |
| `email` | TEXT | E-mail corporativo de contato |
| `logradouro` | TEXT | Logradouro cadastral da RFB |
| `numero` | TEXT | Número do imóvel |
| `cep` | TEXT | CEP de 8 dígitos (ex: 79040010) |
| `cnae_fiscal` | TEXT | Descrição da atividade econômica principal |
| `lead_score` | INTEGER | Pontuação de prioridade (80 a 95) |
| `situacao_cadastral` | TEXT | Situação na RFB (ex: 'ATIVA') |

---

## 3. Enriquecendo Clientes com `scripts/enriquecer_clientes_rfb.py`

Para transformar registros da RFB em clientes ativos (estabelecendo clusters de fibra óptica nos bairros):

```bash
# Importar 150 clientes distribuídos equilibradamente por todos os bairros:
python scripts/enriquecer_clientes_rfb.py

# Importar quantidade customizada (ex: 300 clientes):
python scripts/enriquecer_clientes_rfb.py --limit 300

# Simulação sem alterar o banco (dry-run):
python scripts/enriquecer_clientes_rfb.py --dry-run
```

### Regras do Script:
- Cruza o prefixo de CEP de cada empresa com o mapeamento territorial de `app.data.perfis_sisgran`.
- Associa ruas e números reais das camadas do SISGRAN/PostGIS daquele bairro.
- Garante unicidade por CNPJ e e-mail.
- Gera automaticamente endereços, coordenadas de centróide e marcação de viabilidade técnica.

---

## 4. Prospecção Dinâmica no Motor de Telecom (`TelecomProspectorService`)

Ao solicitar prospecção na aplicação (`POST /leads/prospectar` ou via Python):

```python
from app.services.prospector import TelecomProspectorService

prospects = TelecomProspectorService.prospect_neighborhood(
    bairro='Chácara Cachoeira',
    cidade='Campo Grande',
    estado='MS',
    niche='Clínicas e Escritórios',
    count=5
)
salvos = TelecomProspectorService.save_prospects(prospects)
```

### Cascata de Execução:
1. **AIsa API:** Se `AISA_API_KEY` estiver configurada, consulta o provedor AIsa (`asi1-mini`).
2. **Google Gemini:** Se `GEMINI_API_KEY` estiver configurada, consulta o modelo Gemini.
3. **Motor RFB Local (`_fetch_rfb_leads`):**
   - Executa `SELECT ... FROM leeds_campo_grande WHERE situacao_cadastral = 'ATIVA' AND cep LIKE :prefix AND empresa NOT IN (SELECT empresa FROM leads) ORDER BY lead_score DESC, RANDOM() LIMIT :count`.
   - Formata a razão social em Title Case preservando siglas (LTDA, ME, S/A).
   - Formata o CNPJ no padrão `XX.XXX.XXX/XXXX-XX`.
   - Formata telefones com DDD `(67) 9XXXX-XXXX`.
   - Adiciona rua real de imóveis mapeados no PostGIS/SISGRAN.
4. **Gerador Sintético Dinâmico (`_generate_synthetic_prospects`):**
   - Se o banco não possuir a tabela da RFB (como em testes unitários ou instalações limpas), combina 15 segmentos comerciais com 40 sobrenomes sul-mato-grossenses (600 combinações possíveis), excluindo qualquer nome já existente no banco.

---

## 5. Deduplicação Estrita em `save_prospects`

O método `TelecomProspectorService.save_prospects()` aplica 4 travas simultâneas:
1. **Por Documento (CNPJ):** `Lead.documento` não pode colidir com nenhum lead já gravado.
2. **Por Razão Social:** `func.lower(Lead.empresa) == empresa_nome.lower()`.
3. **Por Telefone no Bairro:** Dígitos normalizados com checagem de concorrência.
4. **Prevenção contra Clientes Ativos:** Empresas já cadastradas na tabela `Cliente` são descartadas para evitar prospectar a própria base.

---

## 6. Scripts WhatsApp Anti-Ban & Conversão

Para cada lead qualificado, o sistema gera o roteiro anti-ban em 3 blocos:
1. **Gancho hiperlocal:** Menciona a presença da empresa no bairro específico de Campo Grande.
2. **Comparativo contra concorrente:** Oferece Wi-Fi 6, pontos DigiMesh e suporte presencial 24h em Campo Grande.
3. **Pedido de Opt-in explícito:** *"Posso te enviar esse comparativo de 1 minuto aqui pelo WhatsApp sem compromisso?"*.

Ao clicar em **Converter em Cliente** na tela do lead (`/leads/<id>`):
- O lead passa para o status `convertido`.
- O cliente é cadastrado na tabela `clientes`.
- Um pedido de assinatura DigitalNet é criado na tabela `pedidos` com item e valor totalizados automaticamente.
"""

SKILL_CARREGAR_GEOJSON_SQLITE = """---
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

| Arquivo / Dump | Tabela SQLite | Features | Tipo Geométrico | Descrição |
| :--- | :--- | :--- | :--- | :--- |
| `bairros.geojson` | `geo_bairros` | 74 | MultiPolygon | 74 Bairros Oficiais de Campo Grande (PLANURB/SISGRAN) |
| `data/geo_imoveis.sql.gz` (`imoveis.geojson`) | `geo_imoveis` | 462.744 | MultiPolygon | Base completa de lotes, quadras e cadastros de imóveis municipais |
| `parcelamentos.geojson` | `geo_parcelamentos` | 894 | MultiPolygon | Parcelamentos urbanos e loteamentos aprovados |
| `pd-macrozonas-urbanas.geojson` | `geo_pd_macrozonas_urbanas` | 74 | MultiPolygon | Macrozonas do Plano Diretor de Campo Grande |

---

## 3. Execução dos Scripts de Carga e Restauração (`scripts/carregar_geojson_sqlite.py` e `scripts/restaurar_imoveis.py`)

```bash
# 1. Analisar os arquivos e exibir o relatório de colunas e limites geográficos (dry-run):
python scripts/carregar_geojson_sqlite.py

# 2. Executar a criação das tabelas e carregar/restaurar todas as 463.786 features no SQLite:
python scripts/carregar_geojson_sqlite.py --execute

# 3. Restaurar diretamente a camada completa de 462.744 imóveis a partir do dump comprimido (32,4 MB):
python scripts/restaurar_imoveis.py

# 4. Regenerar o dump comprimido data/geo_imoveis.sql.gz a partir de geojson/imoveis.geojson:
python scripts/restaurar_imoveis.py --gerar-dump
```

---

## 4. Estrutura das Tabelas Espaciais Criadas

Cada tabela recebe as propriedades inferidas do GeoJSON mais colunas espaciais padronizadas:

```sql
CREATE TABLE IF NOT EXISTS "geo_imoveis" (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    gid INTEGER,
    codlote TEXT,
    codimo INTEGER,
    ruaimo TEXT,
    nrporta INTEGER,
    nomebairro TEXT,
    nomeregiao TEXT,
    areaterren REAL,
    geometry_geojson TEXT,      -- Geometria GeoJSON completa (WGS84 EPSG:4326)
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
"""


# ==============================================================================
# GERAÇÃO DO AGENTS.MD
# ==============================================================================

def build_agents_md() -> str:
    return """# AGENTS.md - Diretrizes de Desenvolvimento e Arquitetura do Workspace

Bem-vindo ao workspace do **DigitalNet MS - Radar de Leads & Sistema de Gestão**.
Este documento define as regras de desenvolvimento, catálogo de modelos de dados, motores de inteligência artificial, controle de acesso e regras espaciais obrigatórias para todos os agentes de IA atuando neste repositório.

---

## 1. Visão Geral do Sistema

A aplicação é uma plataforma completa de **Gestão Comercial, Controle de Acesso (RBAC) e Radar de Expansão de Telecomunicações** (ISP B2B) para a **DigitalNet MS** em Campo Grande - MS.
- **Stack:** Python 3.11+, Flask 3, Flask-SQLAlchemy, Flask-Migrate (Alembic), Flask-Login, Flask-WTF, Bootstrap 5.3, Mapbox GL JS / Leaflet.
- **Bancos de Dados:**
  - **SQLite Primário:** `instance/app_clientes.db` (armazenamento de Usuários, Grupos de Acesso, Clientes, Pedidos, Leads, Tabelas Espaciais e Base RFB).
  - **PostgreSQL + PostGIS (Opcional/Espacial):** `localhost:5432/db_geo` para análises espaciais avançadas (`ST_Intersects`).
- **Deploy Autônomo:** `setup.sh` (script bash auto-contido gerado via `scripts/gerar_setup.py`).

---

## 2. Catálogo de Modelos de Dados e Tabelas

### 2.1 Tabelas Transacionais da Aplicação
- **`usuarios` (`app/models/user.py`):** Usuários do sistema, perfil de acesso (`administrador`, `lider_tecnico`, `agente`), status de ativação, hash seguro com `werkzeug.security`.
- **`grupos` e `usuario_grupos` (`app/models/user.py`):** Grupos de acesso configuráveis com atribuição de papel (`papel`), descrição e relacionamento many-to-many com usuários para herança coletiva de permissões.
- **`clientes` (`app/models/cliente.py`):** Clientes corporativos e residenciais ativos com endereço, CEP e coordenadas.
- **`pedidos` e `itens_pedido` (`app/models/pedido.py`):** Pedidos comerciais vinculados a clientes, de 1 a 10 itens com totalização automática em centavos (`REAL`).
- **`leads` (`app/models/lead.py`):** Oportunidades comerciais de prospecção geo-localizada, com pontuação (`lead_score`), operadora atual (Vivo Fibra / Claro), dor operacional mapeada, roteiro WhatsApp anti-ban, dossiê comercial e vínculo de conversão (`cliente_convertido_id`).

### 2.2 Base de Inteligência da Receita Federal (RFB)
- **`leeds_campo_grande`:** Base de 158.558 empresas comerciais e prestadores de serviço ativos em Campo Grande - MS com CNPJ, CNAE, razão social, logradouro, número, bairro, complemento, telefone, decisor e CEP (`data/leeds_campo_grande.sql.gz`). Utilizada prioritariamente pelo motor de prospecção.

### 2.3 Camadas Geoespaciais Urbanas (SISGRAN / PLANURB)
Carregadas no SQLite via `scripts/carregar_geojson_sqlite.py` e `scripts/restaurar_imoveis.py` (ou PostGIS via `scripts/analisar_geojson_postgis.py`):
- **`geo_bairros`:** 74 bairros oficiais com geometria, macrozona e dados legais.
- **`geo_imoveis`:** 462.744 cadastros imobiliários urbanos completos de Campo Grande - MS com logradouro, número de porta, uso do imóvel, área de lote/edificada, geometria WGS84 e índice espacial R*Tree (`data/geo_imoveis.sql.gz`).
- **`geo_parcelamentos`:** 894 parcelamentos e loteamentos urbanos aprovados.
- **`geo_pd_macrozonas_urbanas`:** Macrozonas do Plano Diretor Municipal.

---

## 3. Controle de Acesso por Perfis (RBAC) e Painel Administrativo

O sistema implementa três perfis de acesso hierárquicos:
1. **Administrador (`administrador`):** Acesso irrestrito a todas as funcionalidades, incluindo o Painel de Administração de Usuários (`/admin/usuarios`), Grupos de Acesso (`/admin/grupos`), configurações gerais e exclusões.
2. **Líder Técnico (`lider_tecnico`):** Coordenação operacional e técnica com permissão para gerenciar clientes, pedidos, radar de leads e executar exclusões de clientes e pedidos.
3. **Agente (`agente`):** Operação comercial diária (prospecção de leads, abordagem WhatsApp, cadastro e edição de pedidos/clientes). Não possui acesso ao painel admin nem permissão para excluir registros críticos.

Decorators de autorização em `app/utils/auth_decorators.py`:
- `@admin_required`: Restringe o endpoint exclusivamente a Administradores.
- `@lider_required`: Restringe o endpoint a Líderes Técnicos e Administradores.
- `@perfil_required(*perfis)`: Permite múltiplos perfis autorizados.

---

## 4. Motores de Prospecção e Cascata de IA (`TelecomProspectorService`)

O serviço [`TelecomProspectorService`](file:///home/pizani/Projects/app_clientes/app/services/prospector.py) implementa uma cascata com failover automático:

```mermaid
flowchart TD
    Req["Nova Prospecção (Bairro, Quantidade)"] --> AIsa{"AIsa API Configurada?"}
    AIsa -- "Sim (HTTP 200)" --> RespAIsa["Retorna Leads AIsa"]
    AIsa -- "Não / Falha" --> Gemini{"Gemini API Configurada?"}
    Gemini -- "Sim (HTTP 200)" --> RespGemini["Retorna Leads Gemini"]
    Gemini -- "Não / Falha (403/429)" --> RFB{"Tabela leeds_campo_grande Existe?"}
    RFB -- "Sim" --> RespRFB["Busca Empresas Reais da RFB (Random + Score)"]
    RFB -- "Não / Faltam Leads" --> Sintetico["Gerador Sintético Dinâmico (600 combinações)"]
    RespRFB --> Deduplicacao["save_prospects (Deduplicação Global)"]
    RespGemini --> Deduplicacao
    RespAIsa --> Deduplicacao
    Sintetico --> Deduplicacao
    Deduplicacao --> Banco[("Salva na Tabela leads")]
```

---

## 5. SKILLs Disponíveis no Workspace

As skills do projeto residem em `.agents/skills/` e ensinam os procedimentos comprovados do repositório:
- **`enriquecer-prospectar-rfb` (`.agents/skills/enriquecer-prospectar-rfb/SKILL.md`):** Procedimento de enriquecimento e prospecção com a base de empresas da RFB, scripts anti-ban no WhatsApp e conversão em 1-clique.
- **`carregar-geojson-sqlite` (`.agents/skills/carregar-geojson-sqlite/SKILL.md`):** Carregamento de camadas GeoJSON e dump comprimido de 462k imóveis no SQLite com inferência de tipos, bounding boxes e indexação espacial R*Tree.

---

## 6. Comandos e Ferramentas Essenciais do Repositório

| Comando | Descrição |
| :--- | :--- |
| `.venv/bin/python -m unittest discover -s tests -v` | Executa a suíte de testes unitários automatizados. |
| `python scripts/carregar_geojson_sqlite.py --execute` | Carrega as camadas GeoJSON no SQLite com índices espaciais R*Tree. |
| `python scripts/restaurar_imoveis.py` | Restaura os 462.744 imóveis urbanos (`geo_imoveis`) a partir de `data/geo_imoveis.sql.gz`. |
| `python scripts/restaurar_rfb.py` | Restaura a base de empresas da RFB a partir de `data/leeds_campo_grande.sql.gz`. |
| `python scripts/enriquecer_clientes_rfb.py --limit 150` | Enriquece a tabela `clientes` com empresas reais da RFB. |
| `python scripts/gerar_perfis_sisgran.py` | Atualiza o dicionário de bairros em `app/data/perfis_sisgran.py`. |
| `python scripts/gerar_setup.py && python scripts/gerar_setup.py --check` | Regenera o instalador autônomo `setup.sh` e verifica integridade. |
| `python scripts/setup_agents.py` | Regenera este `AGENTS.md`, `README.md` e sincroniza as SKILLs. |

---

## 7. Regras de Conduta para Agentes de IA

1. **Evidência Antes de Afirmações:** Nunca declare uma alteração concluída sem rodar a suíte de testes (`unittest`) e confirmar código de saída 0.
2. **Integridade de Documentação:** Mantenha docstrings e comentários existentes.
3. **Não poluir setup.sh com dumps temporários:** O `setup.sh` deve incluir apenas arquivos essenciais versionados; dumps brutos de curl `.json` e arquivos gigantes (`geojson/imoveis.geojson`) devem ser ignorados no `.gitignore`.
4. **Isolamento de Conexão no SQLite :memory::** Em testes unitários com SQLite `:memory:`, NUNCA chame `inspect(db.engine)` diretamente, pois isso causa alocação de conexões separadas no pool e isola a sessão de teste. Utilize consultas diretas via `db.session`.
5. **Estratégia Blindada para POC:** O `setup.sh` foi projetado para recriar 100% do sistema em ambientes Ubuntu limpos em menos de 30 segundos, suportando execução offline (com `data/leeds_campo_grande.sql.gz` e `data/geo_imoveis.sql.gz` locais) ou online (via GitHub público sem autenticação).
"""


# ==============================================================================
# GERAÇÃO DO README.MD
# ==============================================================================

def build_readme_md() -> str:
    return """# DigitalNet MS - Radar de Leads, Gestão Comercial & Controle de Acesso (RBAC)

Sistema integrado de **Gestão Comercial, Controle de Acesso por Perfis & Grupos, Prospecção Geo-Localizada e Expansão de Infraestrutura Óptica B2B** para a operadora **DigitalNet MS** em Campo Grande - MS.

Desenvolvido em **Python 3.11+ e Flask 3**, o sistema integra **Controle de Acesso RBAC**, **Inteligência Artificial (AIsa e Gemini)**, dados geográficos oficiais do **SISGRAN / PLANURB**, mais de **21.000 feições urbanas** (bairros, imóveis e loteamentos) com indexação espacial **R*Tree** no SQLite e uma base de **177.614 empresas da Receita Federal do Brasil**.

---

## Sumário

- [Visão Geral e Diferenciais](#visao-geral-e-diferenciais)
- [Arquitetura do Sistema](#arquitetura-do-sistema)
- [Controle de Acesso e Perfis (RBAC)](#controle-de-acesso-e-perfis-rbac)
- [Funcionalidades Principais](#funcionalidades-principais)
- [Instalação Rápida com setup.sh](#instalacao-rapida-com-setupsh)
- [Motores de Prospecção e Inteligência Artificial](#motores-de-prospeccao-e-inteligencia-artificial)
- [Dados Geoespaciais e SISGRAN](#dados-geoespaciais-e-sisgran)
- [Base de 177k Empresas da Receita Federal](#base-de-177k-empresas-da-receita-federal)
- [Scripts e Ferramentas CLI](#scripts-e-ferramentas-cli)
- [Suíte de Testes](#suite-de-testes)
- [Agentes de IA e SKILLs](#agentes-de-ia-e-skills)

---

## Visão Geral e Diferenciais

- **Controle de Acesso por Perfis (RBAC):** Hierarquia de permissões estruturada para **Administrador**, **Líder Técnico** e **Agente**, além de grupos de trabalho customizáveis.
- **Painel Administrativo Completo:** Gestão centralizada de usuários (`/admin/usuarios`) com criação, edição de perfis, ativação/desativação e grupos de acesso (`/admin/grupos`).
- **Viabilidade Óptica Hiperlocal:** O sistema calcula clusters de clientes conectados por bairro de Campo Grande, permitindo prospectar empresas exatamente onde a fibra óptica da DigitalNet já está nos postes (AS61588).
- **Interatividade nos Nós Ópticos (Offcanvas):** Ao clicar em um nó de fibra no mapa, abre uma gaveta lateral listando as empresas reais daquele raio, com scores, WhatsApp anti-ban em 1-clique e navegação focada no mapa.
- **Interface Imersiva (Menu Recolhível & Mapa Fullscreen):** Barra lateral retrátil com persistência em `localStorage` e badges identificadores do perfil do operador.
- **Roteiro WhatsApp Anti-Ban com Opt-in:** Reduz o risco de bloqueio de número para quase zero com um método consultivo em 3 passos, oferecendo Wi-Fi 6 em comodato e pontos DigiMesh sem custos de aluguel.
- **Cascata Multi-Provedor de Prospecção:** Integração com a API AIsa (`asi1-mini`), Google Gemini AI, banco de dados abertos da RFB e gerador sintético de alta diversidade.
- **Banco Espacial Dual (SQLite R*Tree & PostGIS):** Análise e ingestão automática de 21.042 feições urbanas com bounding boxes e centróides tanto em SQLite puro quanto em PostgreSQL + PostGIS.
- **Conversão em 1-Clique:** Transforma um lead prospectado em Cliente e gera automaticamente o Pedido com planos reais da operadora.
- **Deploy Autônomo Blindado (POC em 30s):** `setup.sh` auto-contido para demonstrações de POC, configurando todo o ambiente em menos de 30 segundos.

---

## Arquitetura do Sistema

```mermaid
flowchart TD
    subgraph Frontend["Interface Web (Bootstrap 5.3 + Mapbox GL JS)"]
        Dash["Dashboard Executivo"]
        Radar["Radar de Leads & Mapa"]
        Clientes["Gestão de Clientes"]
        Pedidos["Gestão de Pedidos (1-10 itens)"]
        AdminPanel["Painel Admin: Usuários & Grupos"]
    end

    subgraph Backend["Backend Flask 3"]
        Routes["Rotas & Blueprints (Admin, Auth, Leads, Clientes, Pedidos)"]
        RBAC["Camada RBAC & Auth Decorators"]
        Prospector["TelecomProspectorService"]
        AI_Gate["Gateway de Prospecção Multi-Provider"]
    end

    subgraph Data["Camada de Dados (SQLite & Geo)"]
        MainDB[("SQLite: instance/app_clientes.db")]
        UsersDB[("Tabelas: usuarios, grupos, usuario_grupos")]
        RFB[("Tabela leeds_campo_grande (177k RFB)")]
        GeoSQLite[("Tabelas Espaciais R*Tree (geo_*)")]
        GeoFiles["GeoJSON (bairros, imoveis, parcelamentos)"]
    end

    Frontend <--> Routes
    Routes --> RBAC
    Routes --> Prospector
    Prospector --> AI_Gate
    Prospector <--> MainDB
    MainDB --- UsersDB
    MainDB --- GeoSQLite
    GeoFiles --> GeoSQLite
```

---

## Controle de Acesso e Perfis (RBAC)

| Perfil | Escopo e Responsabilidades | Acesso ao Painel Admin | Exclusão de Registros |
| :--- | :--- | :---: | :---: |
| **Administrador** | Gestão irrestrita do sistema, criação de usuários, auditoria, configurações e criação de grupos de acesso. | Sim (`/admin/`) | Sim |
| **Líder Técnico** | Supervisão técnica e comercial, gestão de clientes, pedidos, conversão e exclusão autorizada de cadastros. | Não | Sim |
| **Agente** | Operação comercial, prospecção geo-localizada, disparo consultivo WhatsApp, cadastro de clientes e pedidos. | Não | Não |

---

## Funcionalidades Principais

### 1. Painel de Administração de Usuários & Grupos (`/admin/`)
- Listagem completa com filtros por perfil, status ativo/inativo e grupo de trabalho.
- Cadastro de novos operadores com atribuição imediata de perfil e grupos associados.
- Edição cadastral, redefinição segura de senha e proteção estrita contra auto-exclusão ou exclusão do último administrador ativo.
- Criação e gerenciamento de grupos de acesso com papel herdado.

### 2. Radar de Prospecção Geo-Localizada (`/leads/`)
- Mapa interativo com nós ópticos (clientes ativos) e oportunidades de leads com scores de conversão.
- Filtros por bairro oficial do SISGRAN (*Chácara Cachoeira, Centro, Santa Fé, Jardim dos Estados, etc.*).
- Dossiê comercial completo com perfil do decisor, dores de rede da concorrência e argumento de vendas.

### 3. Central WhatsApp & Abordagem Consultiva
- Script personalizado gerado sob demanda contendo gancho territorial, comparativo de plano e pedido explícito de opt-in.
- Botão de disparo direto via WhatsApp Web (`https://wa.me/...`).

### 4. Gestão Completa de Clientes e Pedidos
- CRUD de Clientes com preenchimento automático de CEP via ViaCEP e máscaras de CNPJ/Telefone.
- CRUD de Pedidos de 1 a 10 itens com totalização automática em tempo real e comprovante de impressão comercial.
- Dashboard executivo com métricas de faturamento, ticket médio e clientes ativos.

### 5. Tabelas Interativas com DataTables Responsive e Linhas Aninhadas
- **DataTables 2 & Extensão Responsive:** As tabelas de Clientes (/clientes/) e Leads (/leads/) adaptam-se com fluidez a qualquer resolução de tela (desktop, tablet e mobile).
- **Linhas Aninhadas (Child Rows com Subtabelas):** O botão interativo Detalhes expande painéis avançados sob demanda:
  - *Tabela de Clientes:* Dossiê cadastral, endereço completo, total gasto acumulado e subtabela aninhada com o histórico de pedidos conectados e atalhos rápidos de WhatsApp.
  - *Tabela de Leads:* Acordeão técnico com inteligência territorial de Campo Grande (CTO no quarteirão), script anti-ban para WhatsApp com botão de cópia de 1 clique, e pacote recomendado DigitalNet com botão de conversão imediata em cliente.

---

## Instalação Rápida com `setup.sh`

```bash
# 1. Dar permissão de execução:
chmod +x setup.sh

# 2. Executar a instalação automática (cria venv, dependências, banco e seed):
./setup.sh

# 3. Ativar o ambiente e iniciar a aplicação:
source .venv/bin/activate
flask run --host=0.0.0.0 --port=5000
```

### Credenciais de Acesso Exibidas ao Final do Setup

Ao concluir a instalação, o `setup.sh` exibe um resumo final destacado com os usuários e senhas prontos para uso (a senha gerada para o admin é preservada em `instance/.admin_password` e não se perde no log):

| Perfil | Usuário | Senha Padrão | Observações |
| :--- | :--- | :--- | :--- |
| **Administrador** | `admin` | *Exibida no resumo final* | Gerada dinamicamente ou definida via `SEED_ADMIN_PASSWORD=... ./setup.sh` |
| **Líder Técnico** | `lider.tecnico` | `Lider#2026` | Supervisão técnica e aprovação operacional |
| **Agente Comercial** | `agente.comercial` | `Agente#2026` | Operação de prospecção e abordagem WhatsApp |

---

## Scripts e Ferramentas CLI

| Script | Finalidade |
| :--- | :--- |
| `python scripts/carregar_geojson_sqlite.py --execute` | Carrega camadas GeoJSON no SQLite com índices espaciais R*Tree. |
| `python scripts/enriquecer_clientes_rfb.py` | Enriquece clientes com dados da Receita Federal e SISGRAN. |
| `python scripts/gerar_perfis_sisgran.py` | Atualiza o catálogo territorial em `app/data/perfis_sisgran.py`. |
| `python scripts/analisar_geojson_postgis.py --execute` | Importa os GeoJSONs para PostgreSQL + PostGIS (opcional). |
| `python scripts/gerar_setup.py` | Regenera o instalador autônomo `setup.sh`. |
| `python scripts/setup_agents.py` | Regenera `AGENTS.md`, `README.md` e instala as SKILLs. |
| `python scripts/gravar_demonstracao.py` | Grava vídeo automatizado de demonstração completa com Playwright. |

---

## Suíte de Testes

O projeto possui **53 testes unitários** cobrindo autenticação, controle de acesso RBAC, administração de usuários e grupos, catálogo e CRUD de planos de banda larga (PF/PJ), CRUDs de clientes e pedidos, totalização automática de itens, integridade de senhas do seed, rotas do radar de leads, geojson layers e prevenção de leads duplicados:

```bash
.venv/bin/python -m unittest discover -s tests -v
```

---

## Agentes de IA e SKILLs

As diretrizes detalhadas para LLMs e agentes de codificação estão estruturadas em:
- **`AGENTS.md`**: Regras de arquitetura, convenções e catalogo de tabelas.
- **`.agents/skills/enriquecer-prospectar-rfb/SKILL.md`**: Runbook completo para uso da base RFB e prospecção de ISP.
- **`.agents/skills/carregar-geojson-sqlite/SKILL.md`**: Guia para análise e consultas geoespaciais em SQLite com R*Tree.
"""


def main():
    parser = argparse.ArgumentParser(
        description="Gera AGENTS.md, README.md e instala as SKILLs do projeto."
    )
    parser.add_argument('--check', action='store_true', help="Verifica se os arquivos estão atualizados sem sobrescrever")
    args = parser.parse_args()

    print("=" * 75)
    print("=== SETUP AGENTS - GERADOR DE AGENTS.MD, README.MD E SKILLS")
    print("=" * 75)

    # 1. Cria diretórios de SKILLs no workspace
    WORKSPACE_SKILLS_DIR.mkdir(parents=True, exist_ok=True)
    skill_rfb_dir = WORKSPACE_SKILLS_DIR / 'enriquecer-prospectar-rfb'
    skill_geo_dir = WORKSPACE_SKILLS_DIR / 'carregar-geojson-sqlite'
    skill_rfb_dir.mkdir(parents=True, exist_ok=True)
    skill_geo_dir.mkdir(parents=True, exist_ok=True)

    rfb_file = skill_rfb_dir / 'SKILL.md'
    geo_file = skill_geo_dir / 'SKILL.md'

    # 2. Grava SKILLs no Workspace
    rfb_file.write_text(SKILL_ENRIQUECER_PROSPECTAR_RFB.strip() + "\n", encoding='utf-8')
    geo_file.write_text(SKILL_CARREGAR_GEOJSON_SQLITE.strip() + "\n", encoding='utf-8')
    print("[OK] SKILLs gravadas no workspace:")
    print(f"   - {rfb_file.relative_to(ROOT)}")
    print(f"   - {geo_file.relative_to(ROOT)}")

    # 3. Grava manifesto skills.json no workspace
    manifest = {
        "skills": [
            {
                "name": "enriquecer-prospectar-rfb",
                "path": "skills/enriquecer-prospectar-rfb/SKILL.md",
                "description": "Enriquecimento e prospecção com dados da RFB e inteligência territorial SISGRAN."
            },
            {
                "name": "carregar-geojson-sqlite",
                "path": "skills/carregar-geojson-sqlite/SKILL.md",
                "description": "Carregamento e indexação espacial de GeoJSON no SQLite com R*Tree."
            }
        ]
    }
    manifest_file = WORKSPACE_AGENTS_DIR / 'skills.json'
    manifest_file.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding='utf-8')
    print(f"[OK] Manifesto registrado em: {manifest_file.relative_to(ROOT)}")

    # 4. Instala nas SKILLs globais do usuário se diretório existir (~/.gemini/config/skills)
    if GLOBAL_SKILLS_DIR.exists():
        global_rfb = GLOBAL_SKILLS_DIR / 'enriquecer-prospectar-rfb'
        global_geo = GLOBAL_SKILLS_DIR / 'carregar-geojson-sqlite'
        global_rfb.mkdir(parents=True, exist_ok=True)
        global_geo.mkdir(parents=True, exist_ok=True)
        (global_rfb / 'SKILL.md').write_text(SKILL_ENRIQUECER_PROSPECTAR_RFB.strip() + "\n", encoding='utf-8')
        (global_geo / 'SKILL.md').write_text(SKILL_CARREGAR_GEOJSON_SQLITE.strip() + "\n", encoding='utf-8')
        print(f"[OK] SKILLs espelhadas no catálogo global do usuário: {GLOBAL_SKILLS_DIR}")

    # 5. Gera AGENTS.md
    agents_content = build_agents_md().strip() + "\n"
    if args.check and AGENTS_MD_PATH.exists():
        if AGENTS_MD_PATH.read_text(encoding='utf-8') != agents_content:
            print("[ERRO] AGENTS.md está desatualizado!")
            sys.exit(1)
    else:
        AGENTS_MD_PATH.write_text(agents_content, encoding='utf-8')
        print(f"[OK] AGENTS.md gerado com sucesso: {AGENTS_MD_PATH.name}")

    # 6. Gera README.md
    readme_content = build_readme_md().strip() + "\n"
    if args.check and README_MD_PATH.exists():
        if README_MD_PATH.read_text(encoding='utf-8') != readme_content:
            print("[ERRO] README.md está desatualizado!")
            sys.exit(1)
    else:
        README_MD_PATH.write_text(readme_content, encoding='utf-8')
        print(f"[OK] README.md gerado com sucesso: {README_MD_PATH.name}")

    print("=" * 75)
    print("=== SETUP DE AGENTES, DOCUMENTAÇÃO E SKILLS CONCLUÍDO COM SUCESSO!")
    print("=" * 75)


if __name__ == '__main__':
    main()
