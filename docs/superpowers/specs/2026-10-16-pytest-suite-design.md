# Especificação de Design: Suíte de Testes Modulares com Pytest para Subagent-Driven Development

- **Data:** 2026-10-16
- **Projeto:** Leads Prospector — Radar de Leads & Sistema de Gestão (`app_clientes`)
- **Status:** Aprovado em Brainstorming — Pronto para Planejamento (`writing-plans`)

---

## 1. Objetivo e Contexto

Expandir a cobertura de testes automatizados da plataforma **Leads Prospector** introduzindo o framework **pytest** com arquitetura modular de *fixtures* compartilhadas (`tests/conftest.py`) e **3 novas suítes especializadas**, projetadas com fronteiras de arquivos estritamente isoladas para execução paralela e independente via **Subagent-Driven Development**.

### 1.1 Restrições e Regras Arquiteturais Obrigatórias
1. **Preservação Integral do Legado (`unittest`):** Os 4 arquivos existentes (`tests/test_app.py`, `tests/test_leads.py`, `tests/test_planos_admin.py` e `tests/test_rbac_admin.py`, totalizando 60 testes) devem permanecer intactos e funcionando tanto via `pytest` quanto via `python -m unittest discover -s tests -v`.
2. **Isolamento de Conexão SQLite `:memory:` (Regra 4 do `AGENTS.md`):** Nenhuma fixture ou teste com SQLite `:memory:` deve invocar `inspect(db.engine)` diretamente, pois isso aloca conexões separadas no pool e isola a transação em memória. Todas as criações e consultas de tabelas dinâmicas (como `leeds_campo_grande`) devem usar `db.session.execute(text(...))`.
3. **Zero Conflito entre Subagentes:** Após a etapa base de infraestrutura (`requirements.txt`, `pytest.ini` e `tests/conftest.py`), cada subagente trabalhará exclusivamente em seu próprio arquivo de teste (`test_pytest_*.py`), sem editar arquivos de outros subagentes.
4. **Atualização do `setup.sh`:** Ao final da implementação, `scripts/gerar_setup.py` deve ser atualizado e verificado com `--check` para garantir que o instalador autônomo inclua a nova suíte.

---

## 2. Arquitetura de Arquivos

```text
requirements.txt                      # Adição de pytest==8.3.5
pytest.ini                            # Configuração do runner pytest e filtros de warnings
tests/
├── conftest.py                       # [Camada Base] Fixtures compartilhadas (Flask, DB :memory:, RBAC, RFB)
├── test_pytest_prospector.py         # [Subagente 1] Cascata IA/RFB/Sintético, Score, Objeções e Conversão
├── test_pytest_geo_rfb.py            # [Subagente 2] Pipelines Geoespaciais (WGS84, R*Tree) e Dumps RFB/Imóveis
├── test_pytest_cli_security.py       # [Subagente 3] Comandos Flask CLI, Filtros Jinja, Segurança e Pedidos
├── test_app.py                       # (Legado preservado - 60 testes nos 4 arquivos)
├── test_leads.py                     # (Legado preservado)
├── test_planos_admin.py              # (Legado preservado)
└── test_rbac_admin.py                # (Legado preservado)
```

---

## 3. Especificação da Camada Base (`tests/conftest.py` e `pytest.ini`)

### 3.1 Configuração `pytest.ini`
- `testpaths = tests`
- `python_files = test_*.py`
- `python_classes = Test* *TestCase`
- `python_functions = test_*`
- Supressão de `ResourceWarning` e `DeprecationWarning` irrelevantes de terceiros para saída limpa.

### 3.2 Catálogo de Fixtures em `tests/conftest.py`
| Fixture | Escopo | Descrição e Contrato |
| :--- | :--- | :--- |
| `app` | `function` | Instancia `create_app(PytestConfig)` com `TESTING = True`, `SQLALCHEMY_DATABASE_URI = 'sqlite:///:memory:'`, `WTF_CSRF_ENABLED = False`, `AISA_API_KEY = ''`, `GEMINI_API_KEY = ''`. Empurra `app_context()`, executa `db.create_all()` e limpa no teardown (`db.session.remove()`, `db.drop_all()`). |
| `db_session(app)` | `function` | Retorna `db.session` ativa vinculada ao banco `:memory:` do teste. |
| `client(app)` | `function` | Retorna `app.test_client()`. |
| `cli_runner(app)` | `function` | Retorna `app.test_cli_runner()`. |
| `rbac_users(db_session)` | `function` | Cria e persiste 3 usuários ativos (`admin_user` com `administrador`, `lider_user` com `lider_tecnico`, `agente_user` com `agente`) e 2 grupos (`Grupo Lideranca`, `Grupo Comercial`), retornando dicionário com as instâncias. |
| `admin_client(client, rbac_users)` | `function` | Retorna `client` autenticado como `admin_user`. |
| `lider_client(client, rbac_users)` | `function` | Retorna `client` autenticado como `lider_user`. |
| `agente_client(client, rbac_users)` | `function` | Retorna `client` autenticado como `agente_user`. |
| `sample_planos(db_session)` | `function` | Cria planos PF e PJ de referência (`Fibra 700`, `Link Dedicado Pro`) no banco em memória. |
| `rfb_memory_seeded(db_session)` | `function` | Cria a tabela `leeds_campo_grande` e a view `leads_campo_grande` na mesma sessão `db.session` com 5 empresas reais de Campo Grande (incluindo telefones concatenados por `\|` e prefixo `+55`, logradouro, número, bairro e complemento). |

---

## 4. Especificação das 3 Suítes Modulares (Subagentes)

### 4.1 Suíte 1: Motor de Prospecção e Cascata IA (`tests/test_pytest_prospector.py`)
Responsável por testar a fundo `app/services/prospector.py` (`TelecomProspectorService`) e o modelo `app/models/lead.py`:
1. **Cascata de Failover (`prospect_neighborhood`):**
   - **Cenário 1 (AIsa Primário):** `AISA_API_KEY` configurada e mock HTTP 200 retornando JSON válido $\rightarrow$ retorna leads da AIsa sem acionar Gemini nem RFB.
   - **Cenário 2 (Failover AIsa $\rightarrow$ Gemini):** `AISA_API_KEY` lança `URLError`/`HTTPError(500)` e `GEMINI_API_KEY` retorna HTTP 200 $\rightarrow$ retorna leads do Gemini.
   - **Cenário 3 (Failover IA $\rightarrow$ Base RFB `leeds_campo_grande`):** AIsa e Gemini desabilitados ou com falha HTTP 429, e fixture `rfb_memory_seeded` ativa $\rightarrow$ retorna leads reais da RFB filtrados por bairro, formatando endereço com `logradouro`, `numero`, `complemento` e telefone E.164 (primeiro número antes de `|`).
   - **Cenário 4 (Complementação Sintética):** Quando `count=5` e a base RFB possui apenas 2 empresas no bairro solicitado $\rightarrow$ retorna as 2 empresas da RFB mais 3 geradas pelo motor sintético heurístico sem duplicatas.
2. **Deduplicação Global (`save_prospects`):**
   - Impede inserção de leads com mesmo nome de empresa (case-insensitive) já existentes na tabela `leads` ou já cadastrados na tabela `clientes`.
3. **Tutores de Objeção e Scripts Anti-Ban (`@pytest.mark.parametrize`):**
   - Valida `get_objection_tutor` para as chaves `'fidelidade'`, `'preco'`, `'ti_interna'` e fallback para chave desconhecida.
   - Valida `generate_anti_ban_whatsapp_script` e `generate_pitch` (canais `whatsapp` e `email`, tons `consultative`, `direct`, `urgent`).
4. **Conversão 1-Clique (`convert_lead_to_client`):**
   - Cria `Cliente` ativo + `Pedido` com `ItemPedido` vinculado ao `Plano` sugerido, atualiza `lead.status = 'convertido'` e `lead.cliente_convertido_id`.
   - Reutiliza `Cliente` existente caso o documento/CNPJ ou nome já esteja cadastrado, criando apenas o novo `Pedido`.

---

### 4.2 Suíte 2: Pipelines Geoespaciais e Base RFB (`tests/test_pytest_geo_rfb.py`)
Responsável por testar `scripts/restaurar_imoveis.py`, `scripts/restaurar_rfb.py`, `scripts/carregar_geojson_sqlite.py` e `scripts/enriquecer_clientes_rfb.py` utilizando `tmp_path` e `monkeypatch`:
1. **Reprojeção Geodésica e Inferência (`scripts/carregar_geojson_sqlite.py`):**
   - Testes parametrizados de `utm21s_to_wgs84` e `extract_coordinates_and_bounds` garantindo conversão exata de `EPSG:31981` (SIRGAS 2000 / UTM 21S) para `EPSG:4326` (WGS84) e preservação de coordenadas já em WGS84.
   - Testes parametrizados de `FieldStats` (`INTEGER`, `REAL`, `TEXT` com zero à esquerda como `'04160902071'`, booleanos, listas/dicts e valores nulos).
   - Teste de `GeoJsonTable.analyze()` e `generate_ddl()` com arquivo `.geojson` temporário em `tmp_path`, validando criação de índices B-Tree e tabela virtual R*Tree.
2. **Compressão e Restauração de Imóveis (`scripts/restaurar_imoveis.py`):**
   - Restauração via `.sql.gz` (`_restaurar_sql`) e via `.csv.gz` (`_restaurar_csv`) em banco SQLite temporário (`tmp_path`).
   - Idempotência de `restaurar_dump`: quando `geo_imoveis` já possui `> 20.000` registros (simulado via monkeypatch de `verificar_tabela_existente`) e `force=False`, não sobrescreve a tabela; com `force=True`, recria integralmente.
   - Teste de `baixar_dump` com `urllib.request.urlopen` mockado (sucesso e limpeza de arquivo `.tmp` em caso de falha de rede).
   - Consulta espacial real no índice `geo_imoveis_rtree` após restauração.
3. **Restauração e Enriquecimento RFB (`scripts/restaurar_rfb.py` e `scripts/enriquecer_clientes_rfb.py`):**
   - Restauração de `leeds_campo_grande` a partir de `.sql.gz` e `.csv.gz` temporários em `tmp_path`, verificando criação automática da `VIEW leads_campo_grande`.
   - Testes parametrizados de `format_telefone`, `format_cep` e `normalizar_bairro` em `enriquecer_clientes_rfb.py`.

---

### 4.3 Suíte 3: CLI Flask, Filtros Jinja, Segurança e Casos de Borda (`tests/test_pytest_cli_security.py`)
Responsável por testar `app/cli.py`, `app/utils/filters.py`, `app/routes/auth.py`, `app/utils/auth_decorators.py` e regras de negócio de `clientes`/`pedidos`:
1. **Comandos Flask CLI (`app/cli.py` via `cli_runner`):**
   - `flask seed`: valida criação de usuários padrão (`admin`, `lider.tecnico`, `agente.comercial`), grupos de acesso, planos PF/PJ, clientes e pedidos, além de idempotência ao rodar `flask seed` duas vezes seguidas.
   - `flask create-admin`: criação de novo administrador via argumentos/prompts e rejeição quando username/email já existem.
2. **Filtros de Template Jinja2 (`app/utils/filters.py`):**
   - Testes parametrizados de formatação de moeda (`format_currency` / filtro `currency` ou `brl`), datas e tratamento seguro de `None` ou strings inválidas.
3. **Segurança e Controle de Acesso (`app/routes/auth.py` e `app/utils/auth_decorators.py`):**
   - Testes parametrizados de `is_safe_redirect_url` bloqueando URLs externas (`https://malicious.com`, `//evil.com`, `javascript:alert(1)`) e permitindo caminhos relativos internos (`/clientes`, `/pedidos?page=2`).
   - Bloqueio de login para usuário com `ativo=False`.
   - Verificação de herança de permissões via grupo (`usuario_grupos`) para `@lider_required` e `@admin_required`.
4. **Casos de Borda de Pedidos e Clientes (`app/routes/pedidos.py` e `app/routes/clientes.py`):**
   - Criação de pedido no limite mínimo (1 item) e limite máximo (10 itens), verificando totalização exata em centavos.
   - Rejeição de pedido sem itens válidos ou com quantidade/preço inválidos.
   - Normalização automática do nome do bairro (ex.: `'CHÁCARA CACHOEIRA'` $\rightarrow$ `'Chácara Cachoeira'`) ao criar e editar clientes.

---

## 5. Orquestração para Subagent-Driven Development

O plano de implementação será dividido em **5 tarefas sequenciais/paralelas**:
1. **Tarefa 1 (Infraestrutura Base):** Atualizar `requirements.txt`, criar `pytest.ini` e implementar `tests/conftest.py`.
2. **Tarefa 2 (Subagente A — Isolado):** Implementar e validar `tests/test_pytest_prospector.py`.
3. **Tarefa 3 (Subagente B — Isolado):** Implementar e validar `tests/test_pytest_geo_rfb.py`.
4. **Tarefa 4 (Subagente C — Isolado):** Implementar e validar `tests/test_pytest_cli_security.py`.
5. **Tarefa 5 (Integração Final):** Executar a suíte completa via `pytest` e `unittest`, atualizar `scripts/gerar_setup.py` / `setup.sh` e validar `python scripts/gerar_setup.py --check`.
