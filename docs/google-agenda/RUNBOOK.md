# Runbook: Integração Google Agenda no Supabase Self-Hosted (VPS)

## Diagnóstico do Problema Original

Ao tentar salvar as credenciais no painel de **Configurações → Integrações → Google Agenda**, o PostgREST retornava o seguinte erro:

> _"Erro ao salvar credenciais do Google — Could not find the 'googleClientId' column of 'settings' in the schema cache"_

E, ao tentar clicar em "Conectar Conta Google", ocorria:

> _"Erro ao conectar Google Agenda — Edge Function returned a non-2xx status code"_

### Causas e Diagnósticos Resolvidos:

1. **Credenciais e Variáveis de Ambiente no VPS**:
   - No EasyPanel, contêineres de Edge Functions não recebem variáveis de ambiente do `.env` do Compose automaticamente.
   - **Correção aplicada**: A Edge Function lê prioritariamente da tabela `public.settings` do banco Postgres local como fonte de verdade primária e segura (`googleClientId` e `googleClientSecret`).

2. **Janela de Sincronização e Busca dos Lançamentos**:
   - A função limitava a busca do Google e não consultava os compromissos sem `googleEventId` diretamente no banco de dados com abrangência para datas futuras distantes (ex.: audiências marcadas para novembro de 2026).
   - **Correção aplicada**:
     - Janela de busca no Google ampliada para **3 anos à frente** (`timeMax` até fim de 2029) e paginação completa de resultados (`pageToken`).
     - A ação `sync` busca todos os compromissos sem `googleEventId` diretamente da tabela `public.appointments` do banco de dados (além de aceitar a lista do frontend), garantindo que audiências como as de 17/11/2026 sejam sempre exportadas para o Google Calendar primário.
     - Enriquecimento com o nome do cliente associado no resumo do evento e na descrição (`Aud.conciliação - LIZIANE SILVA DE BRIT...`).
     - Criação do evento na agenda primária (`primary`) com timezone de Brasília (`America/Sao_Paulo`) e persistência imediata do ID do Google na coluna `googleEventId` para idempotência.

3. **Garantia de Offline Access e Refresh Token**:
   - No fluxo OAuth, o parâmetro `access_type=offline&prompt=consent` foi reforçado tanto na Edge Function quanto nos fallbacks diretos do frontend.
   - O escopo foi padronizado para:
     `https://www.googleapis.com/auth/calendar https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/calendar.readonly`
   - O `exchange_code` preserva o `refresh_token` prévio caso o Google omita em reautorizações.
   - A função renova o token automaticamente se necessário antes das chamadas à API do Google.

---

## 🚀 Como Executar o Script no VPS (Passo Único)

Acesse o terminal SSH do VPS (Hostinger IP `2.25.181.69`) como `root`:

### Passo 1: Atualizar o Banco de Dados (Já executado pelo Douglas com sucesso)

```bash
curl -sSf -L -H "Accept: application/vnd.github.v3.raw" \
  "https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/docs/google-agenda/01-adicionar-colunas-settings.sh?ref=main" \
  -o /root/01-adicionar-colunas-settings.sh && bash /root/01-adicionar-colunas-settings.sh
```

### Passo 2: Atualizar a Edge Function no Edge-Runtime do VPS (Executar agora)

Execute o comando abaixo como `root` no terminal SSH do VPS para atualizar os arquivos da função no contêiner e garantir o índice no Postgres:

```bash
curl -sSf -L -H "Accept: application/vnd.github.v3.raw" \
  "https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/docs/google-calendar/01-atualizar-google-calendar-vps.sh?ref=main" \
  -o /root/01-atualizar-google-calendar-vps.sh && bash /root/01-atualizar-google-calendar-vps.sh
```

Ou, se desejar apenas reiniciar o contêiner do Edge Runtime imediatamente via Docker:

```bash
docker ps --format '{{.Names}}' | grep -iE 'functions|edge-runtime' | xargs -r docker restart
```

> **Dica**: O script é totalmente **idempotente** e **não interativo**. Ele copia o código novo da função `google-calendar` para dentro do contêiner do runtime (`/home/deno/functions`), copia os módulos compartilhados de CORS e reinicia o contêiner de forma limpa.

---

## 📋 Passos Seguintes no Sistema (Douglas / Equipe)

Após a execução do script:

1. **Acessar o DPSjur**:
   - Abra o navegador em: [https://sistema.advdouglaspsantos.com.br](https://sistema.advdouglaspsantos.com.br)
   - Vá no menu lateral em **Configurações** → aba **Integrações**.

2. **Salvar as Credenciais do Google**:
   - No cartão **Google Agenda (Google Calendar)**:
     - Cole o **Google Client ID** (ex: `1017839822210-...apps.googleusercontent.com`).
     - Cole o **Google Client Secret** (ex: `GOCSPX-...`).
   - Clique no botão **"Salvar Credenciais do Google"**.
   - ✅ O toast verde de confirmação aparecerá: _"Client ID e Secret do Google salvos com sucesso!"_.

3. **Conectar a Conta Google**:
   - Clique no botão verde **"Conectar Conta Google"**.
   - Você será redirecionado para a tela oficial de consentimento do Google.
   - Selecione a conta do escritório Google / Gmail e confirme as permissões de leitura e gravação da Agenda.
   - Ao finalizar, o Google redireciona de volta para `https://sistema.advdouglaspsantos.com.br/google-callback`.
   - O sistema salvará automaticamente os tokens (`access_token` e `refresh_token`) e exibirá _"Google Calendar Conectado!"_.

4. **Sincronizar a Agenda**:
   - Vá para a tela **Agenda** (`/agenda`).
   - Clique no botão **"Sincronizar"**.
   - Os compromissos existentes no Google Calendar serão importados para o DPSjur e os agendamentos cadastrados no DPSjur serão sincronizados de volta para o Google.

---

## 🛠️ Diagnóstico e Solução de Falhas (Troubleshooting)

### Se o PostgREST ainda reclamar do schema cache:

Caso o comando `NOTIFY pgrst, 'reload schema'` não seja capturado imediatamente pelo PostgREST no EasyPanel, reinicie o contêiner do PostgREST manualmente no terminal:

```bash
docker ps --format '{{.Names}}' | grep -E 'rest|postgrest' | xargs -r docker restart
```

### Se a Edge Function `google-calendar` retornar erro não-2xx ao conectar:

Certifique-se de que a Edge Function no VPS está com o código atualizado. Você pode atualizar os arquivos da função no VPS executando:

```bash
curl -sSf -L -H "Accept: application/vnd.github.v3.raw" \
  "https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/docs/google-calendar/01-atualizar-google-calendar-vps.sh?ref=main" \
  -o /root/01-atualizar-google-calendar-vps.sh && bash /root/01-atualizar-google-calendar-vps.sh
```

### Verificação no Google Cloud Console:

- O **URI de redirecionamento autorizado** configurado no Google Cloud Console deve ser exatamente:
  `https://sistema.advdouglaspsantos.com.br/google-callback`
- A API do **Google Calendar API** deve estar habilitada no projeto do Google Cloud.
