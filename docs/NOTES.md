# Notas de Desenvolvimento e Arquitetura - DigitalNet MS Prospector

**Data de Consolidação:** 11 de Outubro de 2026  
**Sistema:** DigitalNet MS - Radar de Leads Telecom, Gestão Comercial & Controle de Acesso (RBAC)  
**Ambiente:** Linux (Ubuntu 22.04+) / Python 3.11+ / Flask 3.1 / SQLite 3 (com suporte a R*Tree) / PostgreSQL 16 + PostGIS  

---

## 1. Visão Geral e Propósito do Sistema

A aplicação foi projetada como uma plataforma integrada para a operadora **DigitalNet MS** em Campo Grande - MS, combinando três pilares essenciais:

1. **Gestão Operacional de Telecom:** Cadastro de clientes corporativos e residenciais, histórico de conexões, emissão de pedidos com totalização automática e controle de status de instalação.
2. **Controle de Acesso Baseado em Papéis (RBAC):** Estrutura hierárquica dividida em Administrador Master, Líder Técnico e Agente Comercial, com suporte a herança dinâmica de papéis via grupos de acesso configuráveis.
3. **Radar de Expansão & Geo-Prospecção:** Mapeamento geoespacial dos clientes ativos e caixas de emenda/terminação óptica (CTO), permitindo prospecção territorial na vizinhança imediata dos nós de rede, apoiada por failover de IA (AIsa, Gemini e RFB) e scripts conversacionais blindados contra banimento no WhatsApp.

---

## 2. Linha do Tempo e Evolução do Desenvolvimento

### Fase 1: Fundação do Sistema Comercial (CRUDs e Totalização)
- Estruturação do padrão Application Factory (`app/__init__.py`), extensões SQLAlchemy, Flask-Login, Flask-Migrate e Flask-WTF.
- Implementação dos modelos [`Cliente`](app/models/cliente.py), [`Pedido`](app/models/pedido.py) e [`ItemPedido`](app/models/pedido.py).
- Regra de negócio obrigatória: pedidos comerciais contêm de 1 a 10 itens com totalização automática e cálculos monetários em centavos.
- Proteção estrita contra *Open Redirect* no fluxo de autenticação via `is_safe_redirect_url`.

### Fase 2: Radar de Prospecção Geo-Localizada & Cascata de IA
- Criação do modelo [`Lead`](app/models/lead.py) com score comercial, operadora concorrente mapeada e roteiro de abordagem.
- Implementação do [`TelecomProspectorService`](app/services/prospector.py) com cascata de 4 camadas:
  1. **AIsa API:** Endpoint `/v1/chat/completions` com modelo `asi1-mini`.
  2. **Google Gemini:** Prospecção com modelos generativos Gemini.
  3. **Base Local da RFB (`leeds_campo_grande`):** 177.614 empresas ativas de Campo Grande.
  4. **Gerador Sintético Dinâmico:** Combinação combinatória de nichos e sobrenomes locais para evitar falha total de geração.
- Implementação de algoritmo global de deduplicação evitando duplicatas de leads por bairro em prospecções consecutivas.
- Mapeamento de objeções comerciais (*Tutor de Quebra de Objeções*) e conversão em 1-clique de Lead para Cliente + Pedido.

### Fase 3: Inteligência Geoespacial Urbana (SISGRAN / PLANURB)
- Integração de 4 camadas GeoJSON oficiais do município de Campo Grande:
  - `geojson/bairros.geojson` (74 bairros oficiais).
  - `geojson/imoveis.geojson` (20.000 cadastros imobiliários urbanos).
  - `geojson/parcelamentos.geojson` (894 loteamentos aprovados).
  - `geojson/pd-macrozonas-urbanas.geojson` (Macrozonas do Plano Diretor).
- Criação de scripts para carregamento com indexação espacial virtual R*Tree (`scripts/carregar_geojson_sqlite.py`) e PostGIS (`scripts/analisar_geojson_postgis.py`).

### Fase 4: Otimização Crítica de Performance da Base RFB (177k registros)
- **Diagnóstico:** O carregamento do dump `data/leeds_campo_grande.sql.gz` demorava entre 30 e 60 segundos em discos convencionais.
- **Causa Raiz:** O SQLite operava com os parâmetros padrão de integridade transacional (`PRAGMA synchronous = FULL` e `PRAGMA journal_mode = DELETE`), realizando `fsync()` em disco a cada lote de `INSERT`.
- **Benchmark Realizado:**
  - *Pandas (`df.to_sql`):* Rejeitado porque adicionaria ~50 MB de dependências compiladas (`pandas`, `numpy`) ao `requirements.txt`, aumentando em 30s o tempo de instalação no `setup.sh`, além de gastar 4s só na carga.
  - *SQLite Otimizado:* Aplicação de PRAGMAs de alta velocidade (`synchronous=OFF`, `journal_mode=MEMORY`, `cache_size=100000`) e envelopamento em transação única (`BEGIN TRANSACTION`). O tempo de carga caiu de **45s para 1.68s** (redução superior a 90%).
- Suporte híbrido implementado em `scripts/restaurar_rfb.py` para formatos `.sql.gz` e `.csv.gz`.

### Fase 5: Experiência Visual do Radar (Nós de Fibra, Fullscreen e Sidebar Retrátil)
- Menu lateral colapsável com persistência de estado via `localStorage` (`.sidebar-collapsed`).
- Botão de tela cheia (Fullscreen) para o mapa Leaflet com recálculo automático de viewport (`map.invalidateSize()`).
- Nós de rede interativos (`cluster_fibra`): ao clicar no nó de fibra óptica de um cliente ativo, o sistema dispara um hook que carrega as empresas comerciais do mesmo quarteirão em uma gaveta lateral (*Bootstrap Offcanvas*).

### Fase 6: Controle de Acesso por Perfis (RBAC) e Painel Administrativo
- Implementação dos modelos [`Grupo`](app/models/user.py) e tabela associativa `usuario_grupos`.
- Três papéis definidos:
  - **Administrador:** Acesso total, incluindo `/admin/usuarios`, `/admin/grupos`, `/admin/planos` e exclusões.
  - **Líder Técnico:** Supervisão técnica e comercial, gestão de clientes/pedidos e permissão para exclusões críticas.
  - **Agente:** Prospecção, atendimento comercial e cadastros (sem acesso ao admin nem permissão de exclusão).
- Decorators de autorização em `app/utils/auth_decorators.py` (`@admin_required`, `@lider_required`, `@perfil_required`).
- Regras de segurança atômica: autodesativação e autoexclusão da conta do administrador conectado são bloqueadas; revogação de perfil do último administrador ativo do sistema é impedida.

### Fase 7: DataTables Responsive & Child Rows Aninhadas
- Integração da biblioteca DataTables 2 com extensão Responsive em [Clientes](app/templates/clientes/index.html) e [Leads](app/templates/leads/index.html).
- Subtabelas aninhadas (*Child Rows*):
  - *Clientes:* Exibição de dossiê cadastral, atalho para WhatsApp e histórico completo de pedidos vinculados.
  - *Leads:* Acordeão com dados territoriais da CTO, script anti-ban e botão de conversão direta.

### Fase 8: Catálogo de Planos DigitalNet & Blindagem do Setup
- Criação do modelo [`Plano`](app/models/plano.py) cobrindo planos Residenciais (PF) e Corporativos (PJ), com migração Alembic `batch_alter_table`.
- Seeding inicial com os planos oficiais da operadora (Fibra 500, 700, 900, DigiCorp e Link Dedicado Pro).
- Auto-preenchimento no formulário de pedidos: integração via `<datalist id="planosCatalog">` que preenche a descrição e o valor unitário de tabela automaticamente ao selecionar um plano.
- Script de gravação automatizada em vídeo com Playwright ([`scripts/gravar_demonstracao.py`](scripts/gravar_demonstracao.py)).
- Regeneração e checagem contínua da integridade do instalador autônomo [`setup.sh`](setup.sh).

---

## 3. Decisões Arquiteturais e Lições Aprendidas

### 3.1 Por que Evitar Pandas e Bibliotecas Pesadas no Setup
- **Decisão:** Manter o `requirements.txt` enxuto (~24 pacotes essenciais de Flask, SQLAlchemy e WTForms).
- **Justificativa:** O `setup.sh` foi desenhado para ser executado em ambientes Linux limpos (Ubuntu) em menos de 30 segundos durante apresentações e POCs. A inclusão de bibliotecas como Pandas e NumPy duplicaria o tempo de `pip install` e aumentaria o consumo de memória, sem ganho de velocidade em relação à biblioteca padrão `csv` e SQLite puro.

### 3.2 Isolamento de Conexões em Testes com SQLite `:memory:`
- **Regra:** Nunca utilizar `inspect(db.engine)` dentro de métodos de teste unitário com SQLite em memória.
- **Motivo:** No SQLAlchemy, chamar o inspector no SQLite `:memory:` aloca uma conexão separada do pool que não enxerga as tabelas criadas na sessão do teste. Todas as verificações de schema devem ser feitas via `db.session` ou consultas diretas.

### 3.3 Segurança no Registro de Usuários (RBAC)
- **Vulnerabilidade Identificada:** O atributo `perfil` da tabela `usuarios` continha `default='administrador'`, fazendo com que autocadastros na rota `/auth/register` virassem administradores automaticamente.
- **Solução:** O valor padrão foi alterado para `agente`, tanto no modelo quanto explicitamente na rota de registro, preservando o princípio do menor privilégio (*Least Privilege*).

### 3.4 Prevenção de Consultas N+1 com `selectinload`
- **Problema:** Na listagem de usuários e grupos do painel administrativo, a iteração de relacionamentos many-to-many em templates gerava dezenas de queries individuais.
- **Solução:** Utilização de `query.options(selectinload(User.grupos))` e `query.options(selectinload(Grupo.usuarios))`, reduzindo as viagens ao banco para consultas únicas pré-carregadas.

---

## 4. Catálogo de Modelos de Dados e Tabelas

```
app_clientes.db (SQLite)
├── Tabelas Transacionais
│   ├── usuarios (id, nome, username, email, password_hash, perfil, ativo, created_at)
│   ├── grupos (id, nome, descricao, papel, created_at)
│   ├── usuario_grupos (usuario_id, grupo_id) [associativa N:N]
│   ├── clientes (id, nome, email, telefone, documento, cep, logradouro, numero, bairro, cidade, estado, ativo, observacoes, created_at)
│   ├── pedidos (id, numero_pedido, cliente_id, data_pedido, status, metodo_pagamento, valor_total, descricao, observacoes, created_at)
│   ├── itens_pedido (id, pedido_id, descricao, quantidade, valor_unitario, valor_total, created_at)
│   ├── leads (id, nome, empresa, cargo, telefone, email, documento, niche, cep, logradouro, numero, bairro, cidade, estado, operadora_atual, plano_sugerido, valor_mensal_sugerido, lead_score, dor_principal, icebreaker_optin, dossie_comercial, status, optin_status, cliente_convertido_id, created_at)
│   └── planos (id, nome, tipo, velocidade_download, velocidade_upload, valor_mensal, valor_cheio, fidelidade_meses, roteador_wifi, beneficios, aplicativos_inclusos, sla_horas, linhas_simultaneas, pabx_virtual, ip_fixo, ativo, destaque, descricao, created_at)
├── Base de Inteligência Comercial
│   └── leeds_campo_grande (177.614 registros de empresas da RFB com CNPJ, CNAE, endereço e telefone)
└── Camadas Geoespaciais SISGRAN
    ├── geo_bairros & geo_bairros_rtree (74 polígonos de bairros)
    ├── geo_imoveis & geo_imoveis_rtree (20.000 cadastros imobiliários urbanos)
    ├── geo_parcelamentos & geo_parcelamentos_rtree (894 loteamentos urbanos)
    └── geo_pd_macrozonas_urbanas & geo_pd_macrozonas_urbanas_rtree (Zoneamento urbano)
```

---

## 5. Ferramental CLI e Automação

| Comando / Script | Função e Objetivo |
| :--- | :--- |
| `setup.sh` | Instalador autônomo bash. Recria o projeto, venv, migrações, sementes e testes em pasta limpa. |
| `python scripts/gerar_setup.py` | Empacota os arquivos rastreados pelo Git no `setup.sh` (com suporte a `--check`). |
| `python scripts/setup_agents.py` | Sincroniza `AGENTS.md`, `README.md` e espelha as SKILLs do workspace. |
| `python scripts/restaurar_rfb.py` | Carrega os 177k registros da RFB no SQLite via PRAGMAs de alta velocidade (suporta local ou download online). |
| `python scripts/carregar_geojson_sqlite.py --execute` | Carrega os GeoJSONs urbanos no SQLite com índices espaciais R*Tree. |
| `python scripts/enriquecer_clientes_rfb.py --limit 150` | Vincula empresas comerciais reais da RFB como clientes de teste ativos. |
| `python scripts/gerar_perfis_sisgran.py` | Gera o dicionário de bairros em `app/data/perfis_sisgran.py`. |
| `python scripts/gravar_demonstracao.py` | Grava vídeo automatizado Full HD (1080p) do fluxo completo com Playwright e FFmpeg. |
| `.venv/bin/python -m unittest discover -s tests -v` | Executa a suíte de 53 testes automatizados de validação. |

---

## 6. Cobertura da Suíte de Testes (53 testes)

1. **`tests/test_app.py` (18 testes):**
   - Autenticação: login com sucesso, logout, senha inválida, proteção contra open redirect.
   - Autocadastro seguro com atribuição do perfil de Agente.
   - CRUD de clientes com formatação documental brasileira.
   - CRUD de pedidos com totalização de itens e limites de 1 a 10 itens.
   - Isolamento de chaves secretas de produção e integridade de senhas aleatórias de seed.
2. **`tests/test_leads.py` (8 testes):**
   - Endpoints da API REST de leads e camadas GeoJSON.
   - Mocks de provedores de IA (AIsa e Gemini) com failover para o motor local.
   - Deduplicação estrita de empresas prospectadas no mesmo bairro.
   - Conversão em 1-clique de lead para cliente com pedido de ativação.
3. **`tests/test_rbac_admin.py` (15 testes):**
   - Acesso restrito a rotas `/admin/` para administradores.
   - Bloqueio de Agentes e Líderes Técnicos com retorno HTTP 403.
   - Criação, edição e exclusão de grupos de acesso.
   - Herança de papéis operacionais atribuídos por grupo.
   - Proteção de integridade: bloqueio de autoexclusão e autodesativação do admin conectado, e trava do último admin ativo.
   - Permissão de exclusão de clientes/pedidos exclusiva para Líder Técnico e Administrador.
4. **`tests/test_planos_admin.py` (12 testes):**
   - Acesso administrativo ao catálogo de planos.
   - Criação e validação de planos residenciais (PF) e corporativos (PJ).
   - Bloqueio de nomes duplicados e alternância de status ativo/inativo.
   - Seeding dos 9 planos oficiais da DigitalNet MS.
   - Navegação integrada entre as abas de Usuários, Grupos e Planos no painel.

---

## 7. Recomendações e Próximos Passos

1. **Exportação de Propostas Comerciais em PDF:** Utilizar `weasyprint` ou templates HTML limpos para gerar contratos e propostas comerciais formatadas diretamente da ficha do Lead ou Pedido.
2. **Webhook de Retorno WhatsApp:** Integrar webhook da Evolution API ou Z-API para registrar automaticamente no banco de dados quando o lead responde com opt-in ("SIM", "QUERO SABER MAIS").
3. **Faturamento Automático com PIX:** Integração com APIs bancárias para geração de QR Code PIX dinâmico diretamente na conclusão do pedido.
