---
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
