# Runbook: Integração Google Agenda no Supabase Self-Hosted (VPS)

## Diagnóstico do Problema Original

Ao tentar salvar as credenciais no painel de **Configurações → Integrações → Google Agenda**, o PostgREST retornava o seguinte erro:

> _"Erro ao salvar credenciais do Google — Could not find the 'googleClientId' column of 'settings' in the schema cache"_

E, ao tentar clicar em "Conectar Conta Google", ocorria:

> _"Erro ao conectar Google Agenda — Edge Function returned a non-2xx status code"_

### Causa raiz:

1. O banco PostgreSQL do VPS self-hosted (EasyPanel) não possuía as colunas `"googleClientId"` e `"googleClientSecret"` na tabela `public.settings` (elas haviam sido aplicadas somente no ambiente Skip/nuvem). Como as migrações do Git/Skip não chegam sozinhas ao banco do VPS, é necessário rodar o DDL diretamente no contêiner Postgres.
2. O PostgREST do VPS mantinha em cache o schema antigo sem essas colunas, bloqueando requisições REST `PATCH /settings`.
3. A Edge Function `google-calendar` no servidor precisava da ação `getAuthUrl` para retornar a URL de consentimento OAuth do Google para o frontend redirecionar o usuário sem lançar erro `non-2xx`.

---

## 🚀 Como Executar o Script no VPS (Passo Único)

Acesse o terminal SSH do VPS (Hostinger IP `2.25.181.69`) como `root`:

```bash
curl -sSf -L -H "Accept: application/vnd.github.v3.raw" \
  "https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/docs/google-agenda/01-adicionar-colunas-settings.sh?ref=main" \
  -o /root/01-adicionar-colunas-settings.sh && bash /root/01-adicionar-colunas-settings.sh
```

> **Dica**: O script é totalmente **idempotente** e **não interativo**. Pode ser rodado múltiplas vezes com total segurança. Ele cria as colunas com os nomes exatos esperados pelo app (`"googleClientId"` e `"googleClientSecret"` em `camelCase`), adiciona a coluna `"googleEventId"` na tabela `appointments`, envia o `NOTIFY pgrst, 'reload schema'` e reinicia os contêineres do PostgREST e Edge Runtime se presentes.

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
