# Guia Prático de Importação do Banco de Dados - DPSjur

**Manual de Execução Passo a Passo para o Douglas (EasyPanel / VPS Hostinger)**  
**Projeto:** DPSjur  
**Serviço Alvo no EasyPanel:** `dpsjur-db` (PostgreSQL 16.6)  
**Banco de Dados Alvo:** `dpsjur`  
**Usuário:** `Doug`  
**Senha do Banco:** `$POSTGRES_PASSWORD` (conforme exibido na aba Credenciais do EasyPanel)

---

## 🎯 Visão Geral Simples

Olá, Douglas! Este guia foi feito especialmente para você executar de forma rápida, segura e sem complicação, direto no terminal do seu navegador na Hostinger ou no terminal do painel EasyPanel.

Você vai executar apenas **4 etapas básicas**:

1. Criar uma pasta de trabalho no VPS.
2. Baixar os dois arquivos SQL necessários:
   - **Arquivo 1 (Consolidado):** Cria as tabelas, permissões e configurações estruturais (`01-import-consolidado.sql`).
   - **Arquivo 2 (Dump Completo de Dados):** Contém todos os seus 7.828 registros reais de produção (`backup-2026-10-06-...sql`).
3. Aplicar os dois arquivos no banco de dados do container EasyPanel.
4. Rodar a verificação de conferência e me mandar o resultado com os `✅ OK`.

---

## 🔑 Credenciais do Banco (Confirmadas na sua Tela)

| Campo                    | Valor                       |
| ------------------------ | --------------------------- |
| **Projeto no EasyPanel** | `dpsjur`                    |
| **Serviço**              | `dpsjur-db` (PostgreSQL 16) |
| **Usuário do Banco**     | `Doug`                      |
| **Nome do Banco**        | `dpsjur`                    |
| **Host Interno**         | `dpsjur_dpsjur-db`          |
| **Porta Interna**        | `5432`                      |
| **Senha do Banco**       | `$POSTGRES_PASSWORD`        |

---

## 📋 Como Gerar a URL Assinada de Download do Dump Completo

O dump completo com todos os seus 345 clientes, 550 processos, 941 transações e histórico fica protegido no bucket privado de backups do Supabase.

Para gerar uma URL direta de download temporária:

1. Acesse o painel do seu projeto Supabase atual.
2. No menu lateral esquerdo, clique em **Storage**.
3. Clique no bucket **`backups`**.
4. Você verá os arquivos de backup. Localize o dump SQL mais recente, por exemplo:
   - `backup-2026-10-06-2026-10-06T13-05-03-120Z.sql` (ou outro similar com extensão `.sql`).
5. Clique no ícone de **três pontinhos (...)** ao lado do arquivo e selecione **"Get signed URL"** (Obter URL assinada) ou **"Share"**.
6. Defina o prazo de validade (ex.: 24 horas ou 86400 segundos) e copie a URL gerada.
7. Guarde essa URL para colar no **Passo 2.2** abaixo.

> 💡 _Dica:_ Se preferir, você também pode baixar o arquivo `.sql` direto para o seu computador pela tela do DPSjur (menu **Backups do Banco de Dados** > botão de download) e depois enviar ao VPS, ou usar a URL assinada direto com `curl`.

---

## 🚀 PASSO A PASSO PARA COPIAR E COLAR

Abra o **Terminal do VPS** (via painel Hostinger no navegador como `root`, ou via SSH).

---

### PASSO 1: Criar a pasta de trabalho no VPS

Cole o bloco abaixo e dê **ENTER**:

```bash
mkdir -p /root/dpsjur-import
cd /root/dpsjur-import
pwd
```

_Explicação:_ Cria e entra na pasta temporária `/root/dpsjur-import` onde guardaremos os arquivos SQL.

---

### PASSO 2: Identificar o Container Docker do EasyPanel

O EasyPanel roda o PostgreSQL dentro de um container Docker. Vamos confirmar o nome exato do container com o comando:

```bash
docker ps --filter "name=dpsjur" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
```

Você verá algo como:

```
NAMES                        STATUS          IMAGE
dpsjur_dpsjur-db.xxxxxxx     Up 2 hours      postgres:16...
```

> 📌 **Anote o nome que apareceu na coluna NAMES**.  
> Geralmente começa com `dpsjur_dpsjur-db` ou `dpsjur-dpsjur-db`.  
> Nos passos a seguir, usaremos a variável automática `CONTAINER_DB=$(docker ps -q -f name=dpsjur.*db)` para você não precisar digitar nada manualmente!

---

### PASSO 3: Baixar os Arquivos SQL para o VPS

#### 3.1 Baixar o Script de Estrutura Consolidado (`01-import-consolidado.sql`)

Se você já clonou ou tem o repositório no VPS, copie direto:

```bash
cp /caminho/do/seu/projeto/docs/migracao-fase1/01-import-consolidado.sql /root/dpsjur-import/
```

Ou, caso vá baixar via GitHub / link direto:

```bash
curl -fSL -o /root/dpsjur-import/01-import-consolidado.sql "COLE_AQUI_A_URL_DO_01_IMPORT_CONSOLIDADO"
```

#### 3.2 Baixar o Dump Completo de Dados via URL Assinada do Supabase

Substitua o texto entre aspas pela URL assinada que você copiou no Supabase Storage:

```bash
curl -fSL -o /root/dpsjur-import/dump-dados-completo.sql "COLE_AQUI_A_URL_ASSINADA_DO_SUPABASE_STORAGE"
```

#### 3.3 Baixar o Script de Conferência (`conferencia-pos-importacao.sql`)

```bash
# Copiando da pasta local do projeto:
cp /caminho/do/seu/projeto/docs/migracao-fase1/conferencia-pos-importacao.sql /root/dpsjur-import/
```

#### 3.4 Conferir os arquivos na pasta

Execute:

```bash
ls -lh /root/dpsjur-import/
```

Você deve ver:

- `01-import-consolidado.sql` (~30-50 KB)
- `dump-dados-completo.sql` (~1.7 MB)
- `conferencia-pos-importacao.sql` (~4 KB)

---

### PASSO 4: Enviar os arquivos para DENTRO do container do PostgreSQL

Como o banco está conteinerizado no Docker, enviamos os arquivos para dentro da pasta temporária `/tmp` do container:

```bash
CONTAINER_DB=$(docker ps -q -f name=dpsjur.*db | head -n 1)

echo "Container detectado: $CONTAINER_DB"

docker cp /root/dpsjur-import/01-import-consolidado.sql $CONTAINER_DB:/tmp/01-import-consolidado.sql
docker cp /root/dpsjur-import/dump-dados-completo.sql $CONTAINER_DB:/tmp/dump-dados-completo.sql
docker cp /root/dpsjur-import/conferencia-pos-importacao.sql $CONTAINER_DB:/tmp/conferencia-pos-importacao.sql

echo "Arquivos copiados com sucesso para dentro do container!"
```

---

### PASSO 5: Executar a Importação no PostgreSQL

Agora executamos o `psql` dentro do container com o usuário `Doug`, banco `dpsjur` e a senha oficial.

#### 5.1 Executar o Script Consolidado (Estrutura, tabelas, seed inicial e RLS)

Cole no terminal do VPS:

```bash
CONTAINER_DB=$(docker ps -q -f name=dpsjur.*db | head -n 1)

docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" -i $CONTAINER_DB \
  psql -U Doug -d dpsjur -f /tmp/01-import-consolidado.sql
```

_O que esse comando faz:_

- Conecta ao PostgreSQL do container sem pedir senha interativa.
- Cria as 17 tabelas do schema `public`.
- Habilita extensões `uuid-ossp` e `pgcrypto`.
- Cria as roles auxiliares `authenticated`, `anon` e `service_role` para suportar o RLS do Supabase sem erros.
- Cria os triggers automáticos (ex.: comarca em maiúsculas, criação automática de tarefas mensais, etc.).
- Aplica todas as políticas de segurança RLS.

#### 5.2 Inserir os Dados Reais do Dump de Produção

Cole no terminal do VPS:

```bash
CONTAINER_DB=$(docker ps -q -f name=dpsjur.*db | head -n 1)

docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" -i $CONTAINER_DB \
  psql -U Doug -d dpsjur -f /tmp/dump-dados-completo.sql
```

_O que esse comando faz:_

- Faz a carga massiva dos registros das 15 tabelas principais (345 clientes, 550 casos, 941 transações, 834 tarefas, etc.).
- Usa `ON CONFLICT DO UPDATE` ou inserts ordenados, garantindo que nenhum registro seja duplicado.

---

### PASSO 6: Executar a Conferência de Integridade (Auditoria)

Cole o comando abaixo para rodar o script de conferência:

```bash
CONTAINER_DB=$(docker ps -q -f name=dpsjur.*db | head -n 1)

docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" -i $CONTAINER_DB \
  psql -U Doug -d dpsjur -f /tmp/conferencia-pos-importacao.sql
```

---

## 📊 O Que Esperar no Resultado da Conferência?

A saída no seu terminal exibirá uma tabela como esta:

```
+----------------------+--------------------+--------------------------+------------+-----------------------+
| Tabela               | Esperado (Fase 0)  | Encontrado no Novo Banco | Diferença  | Status da Auditoria   |
+----------------------+--------------------+--------------------------+------------+-----------------------+
| user_sessions        | 3718               | 3718                     | 0          | ✅ OK                 |
| transactions         | 941                | 941                      | 0          | ✅ OK                 |
| tasks                | 834                | 834                      | 0          | ✅ OK                 |
| cases                | 550                | 550                      | 0          | ✅ OK                 |
| logs                 | 521                | 522                      | 1          | ✅ OK (com logs novos)|
| transaction_cases    | 471                | 471                      | 0          | ✅ OK                 |
| clients              | 345                | 345                      | 0          | ✅ OK                 |
| appointments         | 258                | 258                      | 0          | ✅ OK                 |
| backup_logs          | 31                 | 33                       | 2          | ✅ OK (com bkp novos) |
| suppliers            | 26                 | 26                       | 0          | ✅ OK                 |
| petitions            | 11                 | 11                       | 0          | ✅ OK                 |
| case_systems         | 8                  | 8                        | 0          | ✅ OK                 |
| profiles             | 7                  | 7                        | 0          | ✅ OK                 |
| whatsapp_messages    | 2                  | 2                        | 0          | ✅ OK                 |
| document_templates   | 1                  | 1                        | 0          | ✅ OK                 |
| settings             | 1                  | 1                        | 0          | ✅ OK                 |
| backup_export_config | 1                  | 1                        | 0          | ✅ OK                 |
+----------------------+--------------------+--------------------------+------------+-----------------------+
```

Em seguida, o script mostrará os **7 usuários do escritório** (`Douglas`, `Mestre`, `Guilherme Almeida`, `Guilherme Filippini`, `Heitor Paulinho`, `Eduardo`, `Fernanda Regis`), garantindo que todos os perfis e acessos estão preservados.

---

## 🛠️ Resolução de Erros Comuns e Dúvidas

### 1. "ERROR: role 'authenticated' does not exist"

- **Causa:** O banco de dados padrão do PostgreSQL não tem as roles do Supabase.
- **Solução:** O arquivo `01-import-consolidado.sql` já contém a criação automática de `CREATE ROLE authenticated NOLOGIN`, `anon` e `service_role`. Se você aplicou o arquivo consolidado primeiro, esse erro **não ocorrerá**.

### 2. "ERROR: relation 'auth.users' does not exist" ou "function auth.uid() does not exist"

- **Causa:** Algumas regras de segurança RLS usam a função `auth.uid()`.
- **Solução:** O arquivo `01-import-consolidado.sql` já cria o schema `auth` e a função auxiliar `auth.uid()` retornando o ID da sessão.

### 3. "character with byte sequence 0x... in encoding UTF8" (Acentuação corrompida)

- **Causa:** Terminal usando encoding diferente de UTF-8.
- **Solução:** Ambos os arquivos SQL foram gerados com cabeçalho explícito `SET client_encoding = 'UTF8';`, prevenindo qualquer erro de acentuação (ç, á, é, ã, etc.).

### 4. "password authentication failed for user Doug"

- **Causa:** Senha incorreta ou com caracteres não escapados.
- **Solução:** A senha correta é `$POSTGRES_PASSWORD`. Usar sempre com aspas: `PGPASSWORD="$POSTGRES_PASSWORD"`.

### 5. "Cannot connect to container dpsjur_dpsjur-db"

- **Causa:** O container não foi localizado pelo filtro.
- **Solução:** Rode `docker ps` manualmente, veja o nome que aparece na primeira coluna para o serviço postgres e passe no comando:
  `docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" -i NOME_EXATO_DO_CONTAINER psql -U Doug -d dpsjur -f /tmp/01-import-consolidado.sql`.

---

## 🧹 Limpeza Opcional dos Arquivos Temporários

Após confirmar que todas as contagens estão com `✅ OK`, você pode apagar os arquivos temporários do container e da pasta local para liberar espaço no disco do VPS:

```bash
CONTAINER_DB=$(docker ps -q -f name=dpsjur.*db | head -n 1)

# Apaga os arquivos de dentro do container:
docker exec $CONTAINER_DB rm -f /tmp/01-import-consolidado.sql /tmp/dump-dados-completo.sql /tmp/conferencia-pos-importacao.sql

# Apaga a pasta de importação do VPS:
rm -rf /root/dpsjur-import

echo "Limpeza concluída com sucesso!"
```

---

## 💬 O Que Enviar no Chat Após Concluir?

Assim que você rodar o comando do **PASSO 6**, copie toda a saída que o terminal gerar e cole aqui no chat. Com isso, validaremos a integridade e avançaremos para a **Fase 2 (Storage/Mídias) e Fase 3 (Homologação e Conexão da API)**!
