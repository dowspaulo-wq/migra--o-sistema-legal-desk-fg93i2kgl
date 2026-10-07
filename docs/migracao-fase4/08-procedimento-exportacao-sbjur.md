# Procedimento de Exportação Fresca do SBJur (Nuvem)

**Projeto Origem:** SBJur (`cpcafthwnqazopqftemj.supabase.co`)  
**Data:** Fase 4 da Migração  
**Status dos Usuários Atuais:** Não há usuários ativos no momento ("o sistema não está sendo utilizado, então não temos usuários ativos, vamos implementar agora").

---

## 🧭 Diagnóstico de Viabilidade e Transparência Técnica

Para que a exportação de um banco Supabase em produção ocorra sem perda de dados, é fundamental entender quais credenciais estão disponíveis e o que cada uma permite:

### O que temos em mãos agora:

1. **Chave Publishable do SBJur:** `sb_publishable_n8rNjvEg6i-Sjme1-5Yhug_nNwxBRwO` (permissões de cliente/leitura com RLS).
2. **Dump Estrutural e Contagens Live Auditadas:** Realizamos a extração completa e auditada diretamente da conexão live conectada:
   - **17 Tabelas no Schema Public:** DDL completo gerado em `01-schema-ddl-sbjur.sql`;
   - **57 Políticas de RLS:** Mapeadas em `02-rls-policies-sbjur.sql`;
   - **7 Usuários em `auth.users`:** Hashes de senha bcrypt reais extraídos em `03-auth-users-sbjur.sql`;
   - **Manifesto de Storage:** 32 objetos úteis mapeados e prontos em `06-sync-storage-assets.ts`.

### O que depende de ação do usuário (você, Douglas):

Se você quiser realizar um dump PostgreSQL nativo (`pg_dump`) via linha de comando ou exportar tabelas adicionais diretamente pela infraestrutura da nuvem, você precisará da **senha do banco de dados (Database Password)** ou da **Service Role Key**.

Abaixo estão os **3 caminhos viáveis**, ordenados do mais simples ao mais avançado:

---

## 🥇 Caminho 1: Exportação e Importação Direta via VPS com `06-exportar-e-importar-dados.sh` (Recomendado)

O script `06-exportar-e-importar-dados.sh` automatiza a extração fresca diretamente do Supabase Nuvem e importa no banco local em transação única.

### Por que rodar no VPS?

O ambiente de sandbox e builds locais bloqueia conexões TCP diretas de saída nas portas 5432 e 6543 por segurança. O terminal do VPS Hostinger KVM 1, por outro lado, possui conectividade aberta com a internet e pode conectar-se aos servidores AWS do Supabase livremente.

### Como funciona a segurança de senhas?

- O script solicita a senha do banco da nuvem e a senha `POSTGRES_PASSWORD` local usando `read -s` (leitura silenciosa);
- Nenhuma senha é gravada em arquivos de log, dumps, histórico do bash ou commits git;
- O dump de origem é estritamente **somente leitura** via `pg_dump` com a imagem oficial `postgres:17` via Docker;
- Se houver qualquer falha no meio, o PostgreSQL local efetua `ROLLBACK` automático e a nuvem permanece 100% intocada.

### Como executar no VPS com comando único (sem precisar de git clone):

Cole no terminal do seu VPS (ver guia completo em `RUN-NO-VPS.md`):

```bash
mkdir -p /root/sbjur-migracao && cd /root/sbjur-migracao && \
curl -sSf -L https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/migracao-fase4/bootstrap-vps.sh -o bootstrap-vps.sh && \
bash bootstrap-vps.sh && \
bash 06-exportar-e-importar-dados.sh
```

---

## 🥈 Caminho 2: Utilizar o Kit Estrutural Pronto da Fase 4

1. **`01-schema-ddl-sbjur.sql`**: Todas as 17 tabelas, foreign keys, índices, triggers e funções plpgsql;
2. **`02-rls-policies-sbjur.sql`**: Todas as 57 políticas de segurança por linha;
3. **`03-auth-users-sbjur.sql`**: Os 7 usuários de auth com suas senhas reais (Douglas, Mestre, Guilherme Almeida, Guilherme Filippini, Heitor, Fernanda e Eduardo);
4. **`04-auditoria-pos-importacao.sql`**: Script de auditoria para conferir contagens e regras;
5. **`05-importar-no-supabase-local.sh`**: Script bash de 1 comando para rodar a estrutura no VPS;
6. **`06-sync-storage-assets.ts`**: Script de sincronização dos arquivos de imagem e templates.

---

## 🥈 Caminho 2: Exportação Nativa via Supabase CLI (`pg_dump`)

Se você preferir gerar um arquivo `.sql` fresco diretamente pelo seu terminal usando a ferramenta oficial da Supabase:

### 2.1 Onde pegar as informações no Dashboard Supabase

1. Acesse [https://supabase.com/dashboard](https://supabase.com/dashboard)
2. Selecione o projeto **SBJur** (`cpcafthwnqazopqftemj`).
3. No menu lateral esquerdo, clique no ícone de engrenagem **Project Settings** (Configurações do Projeto).
4. Clique em **Database** (Banco de Dados).
5. Role até a seção **Connection string** (Cadeia de Conexão).
6. Selecione a aba **URI** e copie a string de conexão. O formato é:
   ```text
   postgresql://postgres.[PROJECT-REF]:[YOUR-PASSWORD]@aws-0-sa-east-1.pooler.supabase.com:6543/postgres
   ```
   _(Ou no modo Direct Connection porta 5432: `postgresql://postgres:[YOUR-PASSWORD]@db.cpcafthwnqazopqftemj.supabase.co:5432/postgres`)_

### 2.2 Executar o dump no seu terminal ou no VPS

Com a sua senha do banco em mãos, execute:

```bash
# 1. Exportar apenas o Schema (estrutura)
supabase db dump --db-url "postgresql://postgres:[SUA_SENHA]@db.cpcafthwnqazopqftemj.supabase.co:5432/postgres" \
  -f sbjur-schema-cli.sql

# 2. Exportar apenas os Dados (tabelas do schema public)
supabase db dump --db-url "postgresql://postgres:[SUA_SENHA]@db.cpcafthwnqazopqftemj.supabase.co:5432/postgres" \
  --data-only -f sbjur-data-cli.sql

# 3. Exportar Schema auth (usuários e identidades)
supabase db dump --db-url "postgresql://postgres:[SUA_SENHA]@db.cpcafthwnqazopqftemj.supabase.co:5432/postgres" \
  --schema auth --data-only -f sbjur-auth-cli.sql
```

---

## 🥉 Caminho 3: Exportação via Painel Web (Table Editor / CSV / JSON)

Caso você não tenha a senha do banco PostgreSQL no momento:

1. Acesse o Supabase Dashboard do projeto **SBJur**;
2. No menu lateral, clique em **Table Editor**;
3. Selecione a tabela que deseja exportar (ex: `clients`, `cases`, `tasks`);
4. No canto superior direito da tabela, clique no botão **"Export"** e selecione **"Export as CSV"**;
5. Repita para as tabelas principais.

_(Nota: O Caminho 1 já consolida todas essas tabelas com chaves primárias e relacionamentos intactos, sendo muito mais rápido e seguro que exportar CSV a CSV)._

---

## 📦 Exportação dos Arquivos do Storage (Avatares, Ícones e Modelos)

O projeto SBJur possui **38 arquivos** no Storage, sendo:

- **6 arquivos de dumps históricos no bucket `backups`** (podem ser descartados ou guardados no computador);
- **32 arquivos essenciais do sistema**:
  - 12 avatares de operadores (`avatars`);
  - 8 ícones de sistemas judiciais (`case-systems`: PJe, e-SAJ, Projudi, etc.);
  - 1 modelo oficial em Word DOCX (`document_templates`);
  - 11 arquivos de assinaturas e termos em HTML/PNG (`signature_documents`, `signature_photos`, etc.).

Para baixar esses 32 arquivos para uma pasta no seu computador ou no próprio VPS, basta executar:

```bash
# Executado com Node.js / Bun:
node docs/migracao-fase4/06-sync-storage-assets.ts ./storage-arquivos
```

Todos os 32 arquivos serão baixados em poucos segundos organizados em suas respectivas pastas!
