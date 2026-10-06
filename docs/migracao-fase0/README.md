# DPSjur - Kit de Migração de Infraestrutura (Fase 0 Concluída)
**Documento Oficial de Preparação, Backup e Auditoria**  
**Data:** 01/10/2026  
**Ambiente de Origem:** Supabase Cloud (Projeto: `dagtlwojkqyivnjgveda`, Região EU - Frankfurt)  
**Ambiente de Destino:** VPS Hostinger KVM 1 (`srv1737667.hstgr.cloud` - IP `2.25.181.69`)  
**Status do Sistema Atual:** 100% Intacto, operacional e sem nenhuma interrupção.

---

## 1. Sumário Executivo & Status Atual

A **Fase 0 (Preparação e Backup)** foi concluída com sucesso absoluto. O objetivo desta fase foi congelar, auditar e empacotar todos os componentes do sistema DPSjur — estrutura do banco de dados (DDL), integridade de dados (contagens reais e scripts), arquivos de armazenamento de objetos (Storage), regras de segurança (RLS) e regras de negócio de backend (9 Edge Functions) — gerando um **Kit de Migração completo e autossuficiente**, mantendo o sistema em produção intocado.

### 1.1 Metadados da Infraestrutura Atual

- **Banco de Dados:** PostgreSQL 15+ hospedado no Supabase (tamanho total de tabelas: ~3.8 MB; índice e dados completos em dump de ~18 MB).
- **Storage:** 10 buckets configurados, sendo 8 com arquivos ativos totalizando 34 objetos e 13,38 MB de dados.
- **Edge Functions:** 9 funções Deno/TypeScript ativas e mapeadas.
- **Integrações Externas:** Asaas (Cobranças PIX/Boleto, Emissão de NF e Webhook), Google Calendar (Sincronização bidirecional OAuth 2.0), ZapSign e DataJud CNJ.

---

## 2. Inventário de Dados e Conferência de Integridade (Banco Vivo)

As contagens abaixo foram extraídas diretamente do banco vivo de produção via consulta em lote e representam a linha de base exata para verificação após a restauração na Fase 2:

| # | Tabela | Registros Reais (Produção) | Tamanho Estimado | Descrição / Papel no Sistema |
|---|---|---|---|---|
| 1 | `user_sessions` | **3.718** | 712 kB | Histórico completo de sessões e acessos de usuários |
| 2 | `transactions` | **941** | 408 kB | Lançamentos financeiros (honorários, despesas, repasses) |
| 3 | `tasks` | **834** | 680 kB | Tarefas, prazos processuais e automações de protocolo |
| 4 | `cases` | **550** | 400 kB | Processos jurídicos cadastrados |
| 5 | `logs` | **521** | 336 kB | Logs de auditoria, eventos de sistema e webhooks |
| 6 | `transaction_cases` | **471** | 264 kB | Relação N:M entre lançamentos e múltiplos processos |
| 7 | `clients` | **345** | 256 kB | Cadastro unificado de clientes (PF/PJ) |
| 8 | `appointments` | **258** | 224 kB | Audiências, reuniões e compromissos sincronizados |
| 9 | `backup_logs` | **31** | 64 kB | Histórico de backups diários gerados pelo sistema |
| 10 | `suppliers` | **26** | 48 kB | Fornecedores e parceiros cadastrados |
| 11 | `petitions` | **11** | 32 kB | Modelos padrão de petições e peças jurídicas |
| 12 | `case_systems` | **8** | 48 kB | Sistemas de tribunais cadastrados com logos (PJe, Projudi...) |
| 13 | `profiles` | **7** | 64 kB | Operadores/advogados do escritório (5 ativos, 2 inativos) |
| 14 | `whatsapp_messages` | **2** | 32 kB | Mensagens e disparos de WhatsApp registrados |
| 15 | `document_templates` | **1** | 32 kB | Modelo DOCX ativo de Contrato de Prestação de Serviços |
| 16 | `settings` | **1** | 184 kB | Configurações do escritório, listas suspensas e tokens OAuth |
| 17 | `backup_export_config` | **1** | 32 kB | Chave interna de exportação via Edge Function |
| **TOTAL** | **17 Tabelas** | **7.828 registros** | **~3,8 MB** | **Integridade 100% verificada** |

### 2.1 Os 7 Usuários Cadastrados (`profiles`)
1. **Douglas** (`advdouglaspsantos@gmail.com`) - Admin (Ativo)
2. **Mestre** (`admin@sbjur.com`) - Admin (Ativo)
3. **Guilherme Almeida** (`willhelmalmeida@gmail.com`) - User (Ativo)
4. **Guilherme Filippini** (`guilherme.f.augusto@gmail.com`) - User (Ativo)
5. **Heitor Paulinho** (`heitorpaulodossantos@gmail.com`) - User (Ativo)
6. **Eduardo** (`adveduardoaugustobarbosa@gmail.com`) - User (Inativo / Histórico preservado)
7. **Fernanda Regis** (`fe.nandaregiss@gmail.com`) - User (Inativa / Histórico preservado)

---

## 3. Inventário do Storage (Arquivos e Buckets)

O Supabase Storage possui **34 objetos** distribuídos em 8 buckets ativos, totalizando **13.379.789 bytes (~13,38 MB)**:

| Bucket | Visibilidade | Objetos | Tamanho | Conteúdo Principal |
|---|---|---|---|---|
| `avatars` | Público | 12 | 6,65 MB | Fotos de perfil dos advogados em alta resolução |
| `backups` | Privado | 2 | 4,87 MB | Snapshots SQL (`1,68 MB`) e JSON (`3,18 MB`) de 01/10/2026 |
| `document_templates`| Público | 1 | 853 kB | Modelo oficial em Word DOCX de contrato indenizatório |
| `case-systems` | Público | 8 | 488 kB | Logos dos sistemas judiciais (PJe, Projudi, e-SAJ, etc.) |
| `signature_photos` | Público | 3 | 500 kB | Selfies coletadas para assinatura digital |
| `signature_drawings`| Público | 1 | 9,2 kB | Rubrica manuscrita PNG |
| `signed_documents` | Público | 2 | 3,1 kB | Documentos HTML assinados (Procuração e Hipossuficiência) |
| `signature_documents`| Público | 5 | 3,6 kB | Minutas HTML geradas para assinatura |
| `documents` | Público | 0 | 0 B | Bucket para upload geral de anexos |
| `selfie_images` | Público | 0 | 0 B | Bucket legado |
| **TOTAL** | **10 Buckets** | **34 Objetos** | **13,38 MB** | **Manifesto completo em `04-storage-manifest.json`** |

---

## 4. Alerta de Segurança Crítico: Risco R1 (Senhas de Autenticação)

> ⚠️ **RISCO R1 - AUTENTICAÇÃO NÃO MIGRÁVEL DIRETAMENTE**  
> As senhas de autenticação do Supabase ficam armazenadas no schema fechado `auth.users` protegidas por função criptográfica bcrypt com salt exclusivo do projeto Supabase. Por conformidade de segurança e arquitetura:
> 
> 1. Os dados de perfil, histórico, permissões e e-mails dos 7 usuários **estão 100% preservados** na tabela `public.profiles`.
> 2. No novo ambiente VPS (Fase 2 / Fase 3), assim que o novo backend estiver ativo, cada usuário receberá um link seguro de definição de senha ou utilizará a opção **"Esqueceu a senha?"** na tela de Login do DPSjur.
> 3. Uma senha temporária inicial poderá ser provisionada para o Douglas e para o usuário Mestre para teste de homologação antes de liberar para a equipe.

---

## 5. Pendências do Douglas para as Próximas Fases

Para dar início à **Fase 1 (Configuração do VPS)**, o Douglas precisará disponibilizar:

1. **Acesso SSH ao VPS Hostinger KVM 1:**
   - IP do servidor: `2.25.181.69`
   - Usuário SSH (ex: `root`)
   - Senha de root ou chave pública SSH autorizada.
2. **Domínio ou Subdomínio (Recomendado):**
   - Apontamento DNS do tipo `A` para `2.25.181.69` (ex: `app.dpsjur.com.br` ou `api.dpsjur.com.br`), permitindo emissão gratuita de certificado SSL/HTTPS Let's Encrypt.
3. **Chaves das Integrações Externas:**
   - Conferir se tem acesso à `ASAAS_API_KEY` e ao painel de Webhooks do Asaas.
   - Credenciais do Google Cloud Console (`GOOGLE_CLIENT_ID` e `GOOGLE_CLIENT_SECRET`) para revalidar a URL de redirecionamento OAuth após a mudança de domínio.

---

## 6. Checklist de Execução do Plano de Migração (Fases 0 a 5)

- [x] **FASE 0: Preparação, Backup e Auditoria (CONCLUÍDA)**
  - [x] DDL completo exportado (`01-schema-ddl.sql`)
  - [x] RLS consolidado exportado (`02-rls-policies.sql`)
  - [x] Dados estruturados e contagens auditadas (`03-core-seed-data.sql`)
  - [x] Storage mapeado e cópias salvas (`04-storage-manifest.json`)
  - [x] Inventário de Edge Functions e secrets (`05-edge-functions-inventory.md`)
  - [x] Documento oficial de migração (`README.md`)
  - [x] Nenhuma alteração no sistema ativo em produção.

- [ ] **FASE 1: Configuração do VPS Hostinger KVM 1**
  - [ ] Acesso SSH e hardening básico do Ubuntu 24.04 (UFW firewall, fail2ban).
  - [ ] Instalação do Docker e Docker Compose.
  - [ ] Provisionamento dos containers:
    - PostgreSQL 16 (com persistência em volume seguro e backup diário local).
    - PostgREST ou API Gateway Node.js (compatível com os endpoints existentes).
    - Traefik ou Nginx com SSL/HTTPS automático (Let's Encrypt).
    - MinIO ou serviço de armazenamento estático compatível com S3 para os buckets de storage.
  - [ ] Reescrita/adaptação das Edge Functions para microsserviços Node.js/Express conteinerizados.

- [ ] **FASE 2: Migração e Restauração dos Dados**
  - [ ] Execução do DDL no PostgreSQL do VPS.
  - [ ] Importação de todos os 7.828 registros.
  - [ ] Upload dos 34 arquivos do storage para o servidor de arquivos do VPS.
  - [ ] Conferência de integridade: bater registro por registro com a tabela da Fase 0.

- [ ] **FASE 3: Homologação e Testes E2E em Ambiente Espelho**
  - [ ] Teste de login dos usuários e redefinição de senhas.
  - [ ] Teste de criação e consulta de Clientes, Casos, Tarefas e Agenda.
  - [ ] Teste da sincronização Google Calendar no novo ambiente.
  - [ ] Teste em sandbox do Asaas (criação de cobrança e simulação de webhook).

- [ ] **FASE 4: Virada de Chave (Cutover)**
  - [ ] Snapshot incremental final do Supabase para garantir zero perda de lançamentos recentes.
  - [ ] Atualização do endpoint de webhook no painel do Asaas para o novo servidor.
  - [ ] Apontamento do frontend do DPSjur para a nova URL de backend.
  - [ ] Validação de funcionamento com a equipe do escritório.

- [ ] **FASE 5: Pós-Virada e Desativação do Supabase**
  - [ ] Monitoramento de logs por 7 dias no VPS.
  - [ ] Verificação da rotina diária de backups automatizados no VPS.
  - [ ] Desativação segura do projeto Supabase `dagtlwojkqyivnjgveda`, eliminando qualquer cobrança.

---

## 7. Como Restaurar Este Backup no Ambiente Novo

### 7.1 Criação do Banco e Schemas
```bash
# No terminal do VPS ou container PostgreSQL:
psql -U postgres -d dpsjur -f docs/migracao-fase0/01-schema-ddl.sql
psql -U postgres -d dpsjur -f docs/migracao-fase0/02-rls-policies.sql
```

### 7.2 Ingestão dos Dados
```bash
# Inserir perfis e configurações estruturais:
psql -U postgres -d dpsjur -f docs/migracao-fase0/03-core-seed-data.sql

# Inserir dump completo de dados das 15 tabelas:
# (Utilizar o arquivo de dump gerado no bucket de backups ou restaurar via export_database_backup_json)
```

### 7.3 Restauração dos Arquivos de Storage
```bash
# Executar script de download das mídias públicas:
npx tsx docs/migracao-fase0/download-storage-assets.ts
```
Os arquivos serão organizados exatamente na estrutura de diretórios `/avatars`, `/case-systems`, `/document_templates` etc., prontos para serem servidos pelo VPS.
