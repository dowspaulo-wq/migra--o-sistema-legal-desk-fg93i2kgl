# DPSjur / SBJur — Runbook: Espelhamento de Clientes no Google Sheets

Guia prático para Douglas configurar e operar a rotina de espelhamento automático de clientes na planilha Google Sheets do Google Ads (Customer Match).

---

## 1. Visão Geral da Rotina

- **Planilha Destino:** `Clientes DPS — lista Google Ads (Customer Match)`
- **ID da Planilha:** `181rftkYO4nVnAVsc-mKuYjBqDsm-_YnoiGWtEqf2Ahw`
- **Aba Utilizada:** `Página1` (mantém outras abas 100% intactas)
- **Estrutura das Colunas:**
  - **A:** `ID do cliente` (UUID do banco)
  - **B:** `Nome`
  - **C:** `Email` (sempre em minúsculas)
  - **D:** `Telefone` (replicado exatamente como está no cadastro, sem alteração)
  - **E:** `Aniversário` (formato `YYYY-MM-DD`; vazio se placeholder `0001-01-01` ou ausente)
  - **F:** `Data da última atualização` (data e hora no fuso de Brasília)
- **Regras do Espelho Completo:**
  1. **Lê TODOS os clientes** da base (`public.clients`), sem filtro de e-mail.
  2. **Cliente novo no banco:** adiciona uma nova linha na planilha.
  3. **Cliente existente alterado:** atualiza os dados correspondentes e carimba a coluna F.
  4. **Cliente removido do banco:** remove a respectiva linha da planilha.
  5. **Sem escrita no banco:** a rotina realiza estritamente `SELECT` em `clients`.
  6. **Horário de execução automática:** todo dia às **06:00 (horário de Brasília)** via cron no host VPS.

---

## 2. Passo a Passo de Configuração

### Passo 1: Criar Service Account no Google Cloud

1. Acesse o [Google Cloud Console](https://console.cloud.google.com/).
2. Selecione seu projeto (ou crie um novo projeto, ex: `DPSjur Integracoes`).
3. No menu lateral, acesse **IAM e administração** → **Contas de serviço** (Service Accounts).
4. Clique em **+ Criar conta de serviço**.
5. Dê um nome, ex: `dpsjur-sheets-sync`, e clique em **Criar e continuar**.
6. Em permissões de projeto, não é obrigatório conceder papel amplo de projeto (a permissão de edição será dada diretamente na planilha). Clique em **Concluir**.
7. Anote o e-mail da conta de serviço criada (algo como: `dpsjur-sheets-sync@seu-projeto.iam.gserviceaccount.com`).

### Passo 2: Ativar a Google Sheets API

1. No Google Cloud Console, vá em **APIs e Serviços** → **Biblioteca**.
2. Pesquise por **Google Sheets API**.
3. Clique em **Google Sheets API** e clique no botão azul **Ativar** (Enable).

### Passo 3: Gerar e Baixar a Chave JSON da Service Account

1. Volte em **IAM e administração** → **Contas de serviço**.
2. Clique na Service Account criada (`dpsjur-sheets-sync`).
3. Acesse a aba **Chaves** (Keys).
4. Clique em **Adicionar chave** → **Criar nova chave**.
5. Selecione o tipo **JSON** e clique em **Criar**.
6. Um arquivo `.json` será baixado no seu computador.
7. Abra o arquivo com o Bloco de Notas ou VS Code e **copie todo o seu conteúdo** (inclusive as chaves `{` e `}`).

### Passo 4: Compartilhar a Planilha com a Service Account

1. Abra a planilha no seu navegador:
   [https://docs.google.com/spreadsheets/d/181rftkYO4nVnAVsc-mKuYjBqDsm-\_YnoiGWtEqf2Ahw](https://docs.google.com/spreadsheets/d/181rftkYO4nVnAVsc-mKuYjBqDsm-_YnoiGWtEqf2Ahw)
2. Clique no botão verde **Compartilhar** (canto superior direito).
3. No campo de convite, cole o e-mail da sua Service Account:
   `dpsjur-sheets-sync@seu-projeto.iam.gserviceaccount.com`
4. Defina o papel como **Editor**.
5. Desmarque a opção "Notificar pessoas" (pois é uma conta de serviço) e clique em **Compartilhar / Salvar**.
   > **Atenção:** a planilha NÃO precisa e NÃO deve ficar pública! O compartilhamento exclusivo com o e-mail da Service Account é o método mais seguro e recomendado pelo Google.

### Passo 5: Atualizar o Banco de Dados no VPS (Executar Script SQL)

Como o Supabase roda self-hosted no VPS via EasyPanel, as migrations do banco precisam ser adicionadas na base de produção antes de salvar novas colunas no schema cache do PostgREST.

Conecte no terminal do VPS via SSH e execute o script automatizado:

```bash
curl -sSL "https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/integracoes/02-adicionar-coluna-service-account.sh" -o /root/02-adicionar-coluna-service-account.sh
bash /root/02-adicionar-coluna-service-account.sh
```

_(Ou direto via pipe curl + bash):_

```bash
curl -sSf -L https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/integracoes/02-adicionar-coluna-service-account.sh | bash
```

**O que este script realiza:**

1. Detecta automaticamente o contêiner do Postgres (`sbjur...db`, `supabase...db` ou `postgres`) e suas credenciais.
2. Executa de forma idempotente o comando:
   `ALTER TABLE public.settings ADD COLUMN IF NOT EXISTS "googleServiceAccount" TEXT;`
3. Garante políticas de RLS ativas para usuários autenticados e service role.
4. Emite `NOTIFY pgrst, 'reload schema'` e reinicia os serviços internos para recarregar o schema cache instantaneamente.
5. Imprime conferência com status `[OK]`.

---

### Passo 6: Salvar o JSON em Configurações no DPSjur/SBJur

1. Acesse o sistema no navegador:
   `https://sistema.advdouglaspsantos.com.br`
2. Vá em **Configurações** no menu lateral.
3. Clique na aba **Integrações**.
4. Localize o card **Espelhamento de Clientes (Google Sheets)**.
5. Cole o JSON completo no campo **Google Service Account (JSON)**.
6. Clique no botão **"Salvar Service Account"** (agora salvará com sucesso!).
7. Clique no botão **"Sincronizar Planilha Agora"** para fazer um primeiro teste manual. Uma notificação com o total de clientes inseridos/atualizados deve aparecer na tela.

---

## 3. Instalar o Agendamento Cron no VPS (06:00 Brasília)

Para que a sincronização ocorra todo dia às **06:00 (Brasília)** sem intervenção manual, instale o script no servidor VPS via SSH:

### Conectar via SSH:

```bash
ssh root@2.25.181.69
```

### Executar o script de instalação do Cron:

```bash
bash docs/integracoes/01-instalar-cron-sheets.sh
```

_(Ou se estiver fora da pasta do repositório no VPS, pode executar diretamente o comando abaixo):_

```bash
curl -sSf -L https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/integracoes/01-instalar-cron-sheets.sh | bash
```

### O que o instalador faz:

1. Cria a pasta `/root/sbjur-sheets-sync/` e o script `/root/sbjur-sheets-sync/run-sync-sheets.sh`.
2. Identifica a chave de API e a porta 8000 do Kong interno (com fallback para a URL externa HTTPS).
3. Insere a entrada no `crontab` do root:
   `0 9 * * * /root/sbjur-sheets-sync/run-sync-sheets.sh >/dev/null 2>&1 # SBJur Google Sheets Sync Diário 06:00 BRT`
   _(Nota: 09:00 UTC corresponde exatamente a 06:00 no fuso de Brasília)._
4. É **idempotente**: se você rodar o script novamente, ele não duplica linhas no cron.

---

## 4. Teste Manual e Diagnóstico

### A. Testar disparo manual pelo terminal do VPS:

```bash
bash /root/sbjur-sheets-sync/run-sync-sheets.sh
```

### B. Verificar os logs das últimas execuções:

```bash
tail -n 50 /root/sbjur-sheets-sync/logs/sync-sheets.log
```

Saída esperada de sucesso:

```
[2026-10-18 06:00:02] Iniciando chamada à rotina de espelhamento Google Sheets...
[2026-10-18 06:00:03] ✅ Sucesso via Kong interno (HTTP 200)
[2026-10-18 06:00:03] Resposta da Edge Function:
{"success":true,"message":"Espelhamento de clientes com Google Sheets concluído com sucesso.","timestamp":"2026-10-18 06:00:03","spreadsheetId":"181rftkYO4nVnAVsc-mKuYjBqDsm-_YnoiGWtEqf2Ahw","sheetTitle":"Página1","totalProcessed":345,"inserted":0,"updated":3,"unchanged":342,"removed":0,"durationMs":1420}
```

### C. Teste manual via curl de qualquer lugar:

```bash
curl -X POST https://sbjur.advdouglaspsantos.com.br/functions/v1/sync-clients-sheets \
  -H "Content-Type: application/json" \
  -H "apikey: SUA_CHAVE_AQUI"
```

---

## 5. Resolução de Problemas Comuns

| Sintoma                                              | Causa Mais Provável                                                                              | Solução                                                                                                                          |
| :--------------------------------------------------- | :----------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------- |
| **HTTP 400: Service Account não configurada**        | O JSON ainda não foi salvo nas configurações                                                     | Abra Configurações → Integrações e salve o JSON da Service Account                                                               |
| **HTTP 403: The caller does not have permission**    | A planilha não foi compartilhada com a Service Account                                           | Abra a planilha e compartilhe com o e-mail da Service Account (`client_email`) como **Editor**                                   |
| **HTTP 403: Google Sheets API has not been used...** | A API não foi ativada no projeto do Google Cloud                                                 | Acesse APIs & Serviços → Biblioteca → busque por Google Sheets API → Ativar                                                      |
| **HTTP 404: Requested entity was not found**         | ID da planilha incorreto ou inexistente                                                          | Verifique se o ID `181rftkYO4nVnAVsc-mKuYjBqDsm-_YnoiGWtEqf2Ahw` está acessível pela conta                                       |
| **405 Not Allowed assinado por Nginx**               | A chamada foi feita em `sistema...` (frontend) em vez de `sbjur...` (gateway das Edge Functions) | O script já tenta automaticamente a porta 8000 interna e a URL `sbjur...`. Nunca aponte para `sistema...` pois é apenas frontend |
