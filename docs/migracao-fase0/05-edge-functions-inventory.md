# Inventário Completo de Edge Functions - DPSjur

Data: 2026-10-01 (Fase 0 - Preparação para Migração VPS)

O DPSjur conta com 9 Edge Functions implantadas no Supabase. Durante a Fase 1 (Configuração do VPS), essas funções serão adaptadas para serviços Node.js/Fastify/Express conteinerizados em Docker no VPS Hostinger KVM 1 ou gerenciadas via micro-serviços equivalentes.

---

## 1. Tabela Resumo das Edge Functions

| #   | Nome da Função         | Status                | JWT Verification | Endpoint Atual                          | Principais Variáveis de Ambiente                                                         |
| --- | ---------------------- | --------------------- | ---------------- | --------------------------------------- | ---------------------------------------------------------------------------------------- |
| 1   | `asaas-integration`    | Ativa                 | Desativada       | `.../functions/v1/asaas-integration`    | `ASAAS_API_KEY`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`                             |
| 2   | `asaas-webhook`        | Ativa                 | Desativada       | `.../functions/v1/asaas-webhook`        | `ASAAS_WEBHOOK_TOKEN`, `ASAAS_API_KEY`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`      |
| 3   | `google-calendar`      | Ativa                 | Desativada       | `.../functions/v1/google-calendar`      | `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`  |
| 4   | `create-user`          | Ativa                 | Desativada       | `.../functions/v1/create-user`          | `SUPABASE_URL`, `SUPABASE_ANON_KEY`                                                      |
| 5   | `database-backup`      | Ativa                 | Desativada       | `.../functions/v1/database-backup`      | `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`                                              |
| 6   | `backup-export`        | Ativa                 | Desativada       | `.../functions/v1/backup-export`        | `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` (Usa token da tabela `backup_export_config`) |
| 7   | `datajud-sync`         | Desativada / Opcional | Desativada       | `.../functions/v1/datajud-sync`         | `DATAJUD_API_KEY`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`                           |
| 8   | `electronic-signature` | Descontinuada (Stub)  | Desativada       | `.../functions/v1/electronic-signature` | Nenhuma (Retorna `{"message": "Deprecated"}`)                                            |
| 9   | `zapsign-integration`  | Descontinuada (Stub)  | Desativada       | `.../functions/v1/zapsign-integration`  | `ZAPSIGN_API_TOKEN` (Retorna `{"message": "Deprecated"}`)                                |

---

## 2. Catálogo Nominal de Segredos / Variáveis de Ambiente (SEM VALORES)

> **ATENÇÃO:** Nunca inclua chaves secretas ou senhas no repositório. A lista abaixo serve para o Douglas saber exatamente quais chaves ele precisa ter em mãos para configurar o arquivo `.env` do VPS na Fase 1.

### 2.1 Integração Financeira - Asaas

- `ASAAS_API_KEY`: Chave de API de produção gerada no painel Asaas (Menu Configurações > Integrações > Chaves de API).
- `ASAAS_WEBHOOK_TOKEN`: Token customizado configurado no webhook do Asaas para validar autenticidade das requisições recebidas.

### 2.2 Integração Agenda - Google Calendar

- `GOOGLE_CLIENT_ID`: ID do cliente OAuth 2.0 gerado no Google Cloud Console com permissões para o escopo `calendar.events`.
- `GOOGLE_CLIENT_SECRET`: Segredo do cliente OAuth 2.0 do Google Cloud Console.

### 2.3 Integração Judiciária - DataJud CNJ (Opcional / Futuro)

- `DATAJUD_API_KEY`: Chave pública de consulta da API do DataJud do Conselho Nacional de Justiça.

### 2.4 Integração ZapSign (Legado / Opcional)

- `ZAPSIGN_API_TOKEN`: Token de autenticação da ZapSign (caso o escritório decida reativar).

### 2.5 Credenciais Internas do Backend (Configuradas na Fase 1 no VPS)

- `DB_HOST`: Host do PostgreSQL (`localhost` ou nome do container Docker no VPS)
- `DB_PORT`: Porta do PostgreSQL (`5432`)
- `DB_NAME`: Nome do banco de dados (`dpsjur` ou `postgres`)
- `DB_USER`: Usuário do banco
- `DB_PASSWORD`: Senha forte gerada para o PostgreSQL
- `JWT_SECRET`: Chave secreta de assinatura dos tokens JWT da aplicação
- `API_BASE_URL`: URL pública ou domínio com HTTPS configurado no VPS (ex: `https://api.dpsjur.com.br` ou via IP com Traefik/Nginx)

---

## 3. Detalhamento de Cada Função

### 3.1 `asaas-integration`

- **Arquivo Fonte:** `supabase/functions/asaas-integration/index.ts`
- **Ações Implementadas:**
  - `syncClient`: Cria ou atualiza o cadastro de clientes no Asaas com CPF/CNPJ, telefone, e-mail e endereço normalizado, gravando o `asaas_id` gerado de volta na tabela `clients`.
  - `syncCharge`: Cria ou atualiza cobrança (PIX ou Boleto) vinculada ao cliente no Asaas, gerando `asaas_id` na transação financeira.
  - `cancelPayment`: Exclui cobrança pendente no Asaas.
  - `sync-history`: Varredura paginada de todos os pagamentos recebidos/pendentes do Asaas, conciliando automaticamente com clientes e registrando transações na tabela `transactions`.

### 3.2 `asaas-webhook`

- **Arquivo Fonte:** `supabase/functions/asaas-webhook/index.ts`
- **Objetivo:** Ponto de entrada chamado pelo Asaas quando ocorre mudança de status de pagamento:
  - Eventos mapeados: `PAYMENT_CONFIRMED`, `PAYMENT_RECEIVED` (marca como 'Paga'), `PAYMENT_OVERDUE` ('Vencida'), `PAYMENT_DELETED` ('Cancelada'), `PAYMENT_REFUNDED` ('Estornada').
  - Emite automaticamente Nota Fiscal no Asaas em `PAYMENT_CONFIRMED`.
  - Registra histórico de auditoria na tabela `logs`.
  - Tratamento de idempotência: ignora webhooks duplicados.

### 3.3 `google-calendar`

- **Arquivo Fonte:** `supabase/functions/google-calendar/index.ts`
- **Ações Implementadas:**
  - `getAuthUrl`: Gera URL de consentimento OAuth 2.0 do Google.
  - `callback`: Troca o authorization code temporário por tokens `access_token` e `refresh_token`, salvando na tabela `settings`.
  - `sync`: Sincronização bidirecional completa entre a tabela `appointments` do DPSjur e os eventos do Google Calendar primário (com renovação automática de refresh token).
  - `deleteEvent`: Remove evento no Google Calendar.

### 3.4 `create-user`

- **Arquivo Fonte:** `supabase/functions/create-user/index.ts`
- **Objetivo:** Cadastro de novos operadores do escritório disparando e-mail de ativação e vinculando dados de perfil.

### 3.5 `database-backup`

- **Arquivo Fonte:** `supabase/functions/database-backup/index.ts`
- **Objetivo:** Exportador automático com suporte a JSON e SQL INSERTs de todas as 15 tabelas públicas do sistema, retenção automática de 7 dias e registro na tabela `backup_logs`.

### 3.6 `backup-export`

- **Arquivo Fonte:** `supabase/functions/backup-export/index.ts`
- **Objetivo:** Endpoint HTTP seguro protegido por token em tempo constante para download externo direto de dumps JSON.

### 3.7 `datajud-sync`

- **Arquivo Fonte:** `supabase/functions/datajud-sync/index.ts`
- **Objetivo:** Consulta à API pública do CNJ/DataJud por tribunal (TJSP, TJMG, TRF, etc.) e extração de últimas movimentações do processo.

### 3.8 `electronic-signature` e `zapsign-integration`

- **Arquivos Fonte:** `supabase/functions/electronic-signature/index.ts` e `supabase/functions/zapsign-integration/index.ts`
- **Objetivo:** Marcados como _Deprecated_ após migração para assinatura simplificada e ZapSign direto.
