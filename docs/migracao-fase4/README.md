# Kit de Migração DPSjur - Fase 4 (Supabase Self-Hosted no VPS)

Este diretório contém o kit completo e auditado para implantação do **Supabase Self-Hosted** no VPS Hostinger do escritório (IP: `2.25.181.69`) gerenciado via **EasyPanel**, substituindo o serviço de nuvem pago com custo zero adicional.

---

## 📁 Estrutura dos Arquivos Deste Kit

| Arquivo | Descrição |
| :--- | :--- |
| **`01-schema-ddl-sbjur.sql`** | DDL completo das 17 tabelas do schema `public`, extensões, foreign keys, índices, triggers e funções plpgsql. |
| **`02-rls-policies-sbjur.sql`** | Consolidação das 57 políticas de Row Level Security (RLS) para proteção e isolamento dos dados. |
| **`03-auth-users-sbjur.sql`** | Restauração dos 7 usuários do escritório no schema `auth` com hashes bcrypt reais e identidades GoTrue preservadas (senhas intactas). |
| **`04-auditoria-pos-importacao.sql`** | Script de conferência automatizado que valida contagens exatas das 17 tabelas, status de RLS, FKs, índices e integridade de usuários. |
| **`05-importar-no-supabase-local.sh`** | Script bash automatizado para aplicar DDL, RLS e usuários locais no contêiner do Supabase no VPS. |
| **`RUN-NO-VPS.md`** | **Guia rápido para leigo com comando único:** como colar no terminal do VPS sem precisar de git clone nem login GitHub. |
| **`bootstrap-vps.sh`** | Script de bootstrap automático que baixa o kit completo para `/root/sbjur-migracao/` com 1 comando. |
| **`06-exportar-e-importar-dados.sh`** | Script unificado (Plano A) v0.0.504 e 100% autônomo que roda no terminal do VPS via conexão PostgreSQL direta / pooler (`aws-1-us-east-1.pooler.supabase.com:6543 / :5432`), exportando via `pg_dump` e importando atomicamente. |
| **`06b-exportar-via-rest-api.sh`** | **Script unificado (Plano B - v0.0.507)**: contorna 100% bloqueios de portas PostgreSQL (5432/6543). Opera estritamente via **REST API HTTPS (porta 443)** usando PostgREST `Accept: text/csv` com paginação em lotes de 1000 linhas, descoberta automática de tabelas via OpenAPI, localização dinâmica de contêiner db (suporte a `sbjur-local_supabase-db-1`), alinhamento automático de esquema (relaxamento de NOT NULL não-PK), **casamento dinâmico de colunas pelo nome no `\copy`** (evitando erros de ordem de colunas entre nuvem e banco local), importação atômica e auditoria completa. |
| **`07-completar-pendencias.sh`** | **Script de fechamento de pendências (v0.0.508)**: 100% local no VPS. Restaura `auth.users` e `auth.identities` (7 usuários com hashes reais de senha), reimporta `settings` e `document_templates` com mapeamento dinâmico de colunas por nome, trunca `user_sessions` (descartadas por design pois são efêmeras) e executa auditoria final consolidada com regras ajustadas. |
| **`06-sync-storage-assets.ts`** | Script Node.js/TypeScript para baixar os 32 arquivos essenciais de Storage (avatares, modelos DOCX, ícones de sistemas judiciais). |
| **`07-guia-instalacao-supabase-easypanel.md`** | Manual passo a passo em linguagem simples para leigo: instalação do template Supabase no EasyPanel, configuração de SMTP e obtenção das chaves. |
| **`08-procedimento-exportacao-sbjur.md`** | Procedimento detalhado de exportação fresca do projeto SBJur, analisando opções viáveis com e sem a service_role key. |
| **`09-runbook-virada-e-rollback.md`** | Instruções de cutover para alternar o frontend `dpsjur-web` para o backend local e procedimento de rollback de emergência em 1 minuto. |

---

## 📊 Dimensões Oficiais Auditadas (Projeto SBJur `cpcafthwnqazopqftemj`)

- **Clientes cadastrados:** 345
- **Processos jurídicos:** 550
- **Tarefas e prazos:** 836
- **Compromissos e audiências:** 258
- **Lançamentos financeiros:** 941
- **Vínculos transação x processo:** 471
- **Fornecedores:** 26
- **Sistemas judiciais:** 8
- **Modelos de petições:** 11
- **Modelos Word/DOCX:** 1
- **Usuários operadores:** 7
- **Sessões registradas:** 3.722
- **Tabelas do Schema Public:** 17
- **Políticas de RLS:** 57
- **Arquivos no Storage:** 32 objetos essenciais (~13 MB)

---

## 🚀 Como Executar a Migração Rapidamente

1. **Instalar o Supabase:** Siga o passo a passo em `07-guia-instalacao-supabase-easypanel.md` no EasyPanel.
2. **Aplicar Estrutura (DDL + RLS + Usuários):** No terminal do VPS, execute:
   ```bash
   bash docs/migracao-fase4/05-importar-no-supabase-local.sh
   ```
3. **Exportar e Importar Dados Frescos da Nuvem (Passo Final):**
   - **Se a porta 5432/6543 estiver inacessível (Plano B - Recomendado):**
     ```bash
     mkdir -p /root/sbjur-migracao && cd /root/sbjur-migracao && \
     curl -sSf -L -H "Cache-Control: no-cache" https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/migracao-fase4/06b-exportar-via-rest-api.sh -o 06b-exportar-via-rest-api.sh && \
     bash 06b-exportar-via-rest-api.sh
     ```
     Ele solicita a `SERVICE_ROLE_KEY` da nuvem (Settings > API) e a `POSTGRES_PASSWORD` local de forma segura via `read -s`. Usa apenas HTTPS 443!
   - **Fechar Pendências da Auditoria (auth.users + settings + templates + user_sessions):**
     ```bash
     cd /root/sbjur-migracao && \
     curl -sSf -L -H "Cache-Control: no-cache" https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/migracao-fase4/03-auth-users-sbjur.sql -o 03-auth-users-sbjur.sql && \
     curl -sSf -L -H "Cache-Control: no-cache" https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/migracao-fase4/07-completar-pendencias.sh -o 07-completar-pendencias.sh && \
     bash 07-completar-pendencias.sh
     ```
   - **Se a porta 5432/6543 estiver liberada (Plano A):**
     ```bash
     cd /root/sbjur-migracao && bash 06-exportar-e-importar-dados.sh
     ```
Consulte **`RUN-NO-VPS.md`** para colar o comando único no terminal do VPS.4. **Auditar os Dados:** A auditoria com contagens exatas roda automaticamente ao final.
5. **Sincronizar Arquivos do Storage (em paralelo):**
   ```bash
   node docs/migracao-fase4/06-sync-storage-assets.ts ./storage-local
   ```
6. **Fazer a Virada:** Siga o runbook `09-runbook-virada-e-rollback.md` atualizando a URL e chave na aba Environment do serviço `dpsjur-web` no EasyPanel.
