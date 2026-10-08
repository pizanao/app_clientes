# Gestão-NET - Sistema de Gestão de Clientes e Pedidos

Aplicação web desenvolvida em **Python 3 + Flask** com arquitetura moderna e interface completa em **HTML5, CSS3, JavaScript e Bootstrap 5.3**.

---

## 🚀 Funcionalidades

### 1. Controle de Acesso e Autenticação
- **Autenticação segura** com `Flask-Login` e senhas criptografadas (`werkzeug.security`).
- **Cadastro de novos usuários** com validações de unicidade de e-mail e usuário.
- **Sessões persistentes e seguras** com `Flask-Session` e `cachelib`.
- **Proteção de rotas** (`@login_required`) em todas as áreas internas do sistema.

### 2. Cadastro de Clientes (CRUD Completo)
- **Listagem** com busca dinâmica (nome, e-mail, CPF/CNPJ, telefone, cidade) e filtro por status (Todos, Ativos, Inativos).
- **Cadastro e Edição** com validação de campos obrigatórios e formato de e-mail.
- **Autocompletar de Endereço via CEP**: Integração automática com a API ViaCEP no front-end.
- **Máscaras de entrada em tempo real**: CPF/CNPJ, Telefone celular/fixo e CEP.
- **Visualização Detalhada**: Página de perfil com histórico de pedidos, métricas de faturamento e dados de contato.
- **Exclusão Segura**: Modal de confirmação com remoção em cascata dos pedidos associados.

### 3. Cadastro de Pedidos e Itens (CRUD Completo com Totalização Automática)
- **Vínculo relacional obrigatório** entre Pedido e Cliente (`cliente_id` com chave estrangeira).
- **Estrutura de Itens do Pedido (1 a 10 Itens)**:
  - Cada pedido possui de **1 a 10 itens** obrigatoriamente.
  - Para cada item é informado: *Descrição*, *Quantidade*, *Valor Unitário* e *Valor Total do Item*.
  - **Cálculo automático em tempo real**: O sistema calcula o valor total de cada item (`Quantidade * Valor Unitário`) e a totalização do pedido no formulário.
  - Interface dinâmica com botões de adicionar e remover itens, contador em tempo real (`X / 10 itens`), trava ao atingir 10 itens e impedimento de exclusão do único item restante.
- **Geração automática** de código do pedido no padrão `PED-YYYY-XXXX`.
- **Status do Pedido**: *Pendente*, *Em Processamento*, *Concluído* e *Cancelado* com identificadores visuais (badges coloridos).
- **Métodos de Pagamento**: PIX, Cartão de Crédito, Cartão de Débito, Boleto Bancário, Transferência / TED e Dinheiro.
- **Comprovante de Pedido**: Layout comercial com tabela detalhada de itens pronta para impressão (`window.print()`).
- **Filtros avançados**: Busca por número de pedido, descrição dos itens, cliente e status.


### 4. Dashboard Executivo em Tempo Real
- **KPIs**: Total de Clientes (e ativos), Total de Pedidos, Faturamento Concluído, Ticket Médio e Pedidos Pendentes.
- **Tabelas de últimos registros**: Acesso rápido aos 5 últimos pedidos e aos 5 clientes mais recentes.

---

## 🛠️ Tecnologias Utilizadas

- **Linguagem**: Python 3.11+
- **Framework Web**: [Flask](https://flask.palletsprojects.com/)
- **Autenticação**: [Flask-Login](https://flask-login.readthedocs.io/)
- **Sessões**: [Flask-Session](https://flask-session.readthedocs.io/) + [cachelib](https://github.com/pallets-eco/cachelib)
- **ORM / Banco de Dados**: [Flask-SQLAlchemy](https://flask-sqlalchemy.readthedocs.io/) (SQLite / PostgreSQL)
- **Migrações de Banco**: [Flask-Migrate](https://flask-migrate.readthedocs.io/) (Alembic)
- **Formulários e CSRF**: [Flask-WTF](https://flask-wtf.readthedocs.io/) e [WTForms](https://wtforms.readthedocs.io/)
- **Frontend**: HTML5, CSS3 personalizado, JavaScript Vanilla, [Bootstrap 5.3](https://getbootstrap.com/), [Bootstrap Icons](https://icons.getbootstrap.com/)
- **CLI**: [Flask CLI](https://flask.palletsprojects.com/en/stable/cli/)

---

## 📦 Estrutura do Projeto

```
c:/apps/app_clientes/
├── app/
│   ├── __init__.py          # Application Factory (create_app)
│   ├── config.py            # Configurações de ambiente, banco e sessões
│   ├── extensions.py        # Instâncias de db, migrate, login_manager, sess
│   ├── cli.py               # Comandos personalizados CLI (seed, create-admin, init-db)
│   ├── models/
│   │   ├── user.py          # Modelo de Usuários
│   │   ├── cliente.py       # Modelo de Clientes
│   │   └── pedido.py        # Modelo de Pedidos
│   ├── forms/
│   │   ├── auth_forms.py    # Formulários de Login e Cadastro
│   │   ├── cliente_forms.py # Formulário de Clientes
│   │   └── pedido_forms.py  # Formulário de Pedidos
│   ├── routes/
│   │   ├── auth.py          # Rotas de Autenticação (/auth)
│   │   ├── main.py          # Dashboard (/ e /dashboard)
│   │   ├── clientes.py      # CRUD de Clientes (/clientes)
│   │   └── pedidos.py       # CRUD de Pedidos (/pedidos)
│   ├── static/
│   │   ├── css/style.css    # Estilização moderna, glassmorphism e cores
│   │   └── js/main.js       # Máscaras de input, ViaCEP e modais
│   ├── templates/
│   │   ├── base.html        # Layout base com sidebar e navbar
│   │   ├── auth/            # login.html e register.html
│   │   ├── dashboard/       # index.html
│   │   ├── clientes/        # index.html, form.html, detail.html
│   │   ├── pedidos/         # index.html, form.html, detail.html
│   │   └── errors/          # 404.html e 500.html
│   └── utils/
│       └── filters.py       # Filtros Jinja2 (moeda BRL R$, data brasileira, máscaras)
├── migrations/              # Histórico de versões do Alembic/Flask-Migrate
├── instance/                # Banco SQLite local e sessões
├── tests/
│   └── test_app.py          # Testes automatizados com unittest
├── wsgi.py                  # Ponto de entrada da aplicação
├── requirements.txt         # Dependências do projeto
├── .env                     # Configurações de ambiente
└── README.md                # Documentação completa
```

---

## 🐧 Instalação e Execução Automatizada no Linux

Você pode recriar a aplicação inteira do zero em uma pasta vazia em qualquer ambiente Linux (Ubuntu, Debian, Fedora, CentOS, etc.) com um único comando.

### 1. Executar o Script Autônomo
Copie o arquivo `setup.sh` para uma pasta vazia e execute no terminal:
```bash
chmod +x setup.sh
./setup.sh
```

O script cuidará de:
1. Validar o ambiente Python 3;
2. Criar toda a estrutura de diretórios do projeto;
3. Gerar todos os arquivos fonte (Models, Forms, Routes, Templates, CSS, JS, Migrations, Testes);
4. Criar o arquivo `.env` com uma `SECRET_KEY` aleatória;
5. Criar o ambiente virtual `.venv` e instalar as dependências do `requirements.txt`;
6. Aplicar as migrações do banco (`flask db upgrade`);
7. Inserir dados de teste e o usuário `admin` com senha aleatória (`flask seed`);
8. Executar os testes automatizados para certificar a integridade do sistema.

> **Mantenedores:** o `setup.sh` é gerado a partir dos arquivos versionados. Após alterar o código, regenere-o com:
> ```bash
> python scripts/gerar_setup.py
> ```

### 2. Scripts Utilitários no Linux
Após a execução do `setup.sh`, os seguintes comandos ficam disponíveis na raiz:
- **`./run.sh`**: Inicia o servidor Flask na porta 5000 (`http://localhost:5000`).
- **`./test.sh`**: Executa a suíte de testes automatizados com `unittest`.
- **`./seed.sh`**: Popula novamente o banco com dados de teste e usuário admin.

---

### 1. Ativar o Ambiente Virtual
No terminal PowerShell ou CMD:
```powershell
.venv\Scripts\Activate.ps1
```

### 2. Instalar Dependências (caso necessário)
```powershell
pip install -r requirements.txt
```

### 3. Migrações e Inicialização do Banco
O banco já vem pré-configurado e com migrações prontas. Para recriar ou atualizar:
```powershell
flask db upgrade
```

### 4. Popular Dados de Exemplo (Seed)
Execute para criar o usuário administrador e clientes/pedidos de demonstração:
```powershell
flask seed
```

### 5. Iniciar o Servidor
```powershell
flask run --debug
# ou
python wsgi.py
```
Acesse no seu navegador: **`http://127.0.0.1:5000`**

---

## 🔑 Credenciais de Acesso

- **Usuário:** `admin` (ou `admin@exemplo.com`)
- **Senha:** gerada aleatoriamente pelo `flask seed` e exibida **uma única vez** no terminal.
  Para definir uma senha conhecida, exporte `SEED_ADMIN_PASSWORD` antes do seed.

Para criar outro administrador (a senha é solicitada de forma oculta):
```powershell
flask create-admin --username gerente --email gerente@empresa.com
```

*Você também pode criar novos usuários a qualquer momento pelo botão "Cadastre-se gratuitamente" na tela de login.*

## 🔒 Produção

- Defina `FLASK_DEBUG=0` e uma `SECRET_KEY` própria (`python -c "import secrets; print(secrets.token_hex(32))"`).
  Sem ela, a aplicação **se recusa a iniciar** fora do modo debug.
- Use um servidor WSGI (ex.: `gunicorn wsgi:app` ou `waitress-serve wsgi:app`) em vez de `python wsgi.py`.

---

## 🧪 Executando os Testes Automatizados

Para rodar os testes unitários e de integração:
```powershell
.venv\Scripts\python -m unittest tests/test_app.py
```
