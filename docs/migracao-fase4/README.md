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
| **`05-importar-no-supabase-local.sh`** | Script bash automatizado para aplicar todo o banco no contêiner do Supabase no VPS com 1 comando. |
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
2. **Importar o Banco:** No terminal do seu VPS, execute:
   ```bash
   bash docs/migracao-fase4/05-importar-no-supabase-local.sh
   ```
3. **Auditar os Dados:** O próprio script já executa a auditoria `04-auditoria-pos-importacao.sql` e exibe o relatório na tela.
4. **Fazer a Virada:** Siga o runbook `09-runbook-virada-e-rollback.md` atualizando a URL e chave na aba Environment do serviço `dpsjur-web` no EasyPanel.
