# Runbook: Sincronização Google Agenda (Google Calendar) no DPSjur

## 1. O que causava o erro "Edge Function returned a non-2xx status code"?

Na tela da Agenda, ao clicar em "Sincronizar":

- Se a conta Google ainda não foi conectada (ou o token expirou), o sistema chama a Edge Function `google-calendar` com `action: 'getAuthUrl'` para gerar a URL de autorização OAuth do Google.
- A função no servidor tentava ler `Deno.env.get('GOOGLE_CLIENT_ID')`. No VPS self-hosted (EasyPanel), as variáveis de ambiente adicionadas no painel raiz do Compose nem sempre são repassadas para o contêiner interno do `edge-runtime` (exatamente como ocorreu antes com a `ASAAS_API_KEY`).
- Sem essas variáveis, a Edge Function respondia com status HTTP `400` ou `500` e mensagem JSON, que o cliente Supabase no navegador transformava no toast genérico: **"Edge Function returned a non-2xx status code"**.

## 2. O que foi corrigido no código da aplicação?

1. **Configuração direta pelo sistema (Configurações > Integrações)**:
   - Adicionado o cartão **"Google Agenda (Google Calendar)"** na aba _Configurações > Integrações_.
   - Criadas as colunas `googleClientId` e `googleClientSecret` na tabela `settings`.
   - Agora o Douglas pode salvar o **Google Client ID** e o **Google Client Secret** direto pelo sistema, sem depender obrigatoriamente de editar variáveis internas do EasyPanel.
2. **Edge Function `google-calendar` resiliente**:
   - Atualizada para buscar as credenciais em cascata: primeiro nas variáveis do servidor (`GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET`), e caso estejam vazias, busca automaticamente na tabela `settings` do banco de dados.
   - Suporte aos actions `exchange_code` e `callback` de forma retrocompatível.
   - Respostas de erro formatadas com status HTTP 200 e payload `{ success: false, error: '...' }`, evitando que o Supabase client estoure o erro genérico não-2xx.
   - Detecção automática de token expirado com tentativa transparente de renovação via `refresh_token`.
3. **Tratamento de erro humanizado na Agenda**:
   - Tratamento detalhado das exceções da Edge Function para exibir mensagens claras e em português no toast.
   - Se os tokens forem revogados ou expirarem, o sistema orienta a reconectar e limpa o estado pendente.

## 3. Onde obter as credenciais do Google Cloud Console?

Caso ainda não tenha o Client ID e Secret:

1. Acesse https://console.cloud.google.com/
2. Selecione o projeto do escritório.
3. No menu lateral, vá em **APIs e Serviços** > **Credenciais**.
4. Crie ou copie o **ID do cliente OAuth 2.0** (Aplicativo Web).
5. Certifique-se de que a **URI de redirecionamento autorizada** inclui:
   - `https://sistema.advdouglaspsantos.com.br/google-callback`
6. Copie:
   - **ID do cliente (Client ID)**: formato `...apps.googleusercontent.com`
   - **Chave secreta do cliente (Client Secret)**: formato `GOCSPX-...`

## 4. Onde configurar no sistema?

1. Abra o sistema em `https://sistema.advdouglaspsantos.com.br/configuracoes`.
2. Clique na aba **Integrações**.
3. No cartão **Google Agenda (Google Calendar)**:
   - Cole o **Google Client ID**.
   - Cole o **Google Client Secret**.
   - Clique em **"Salvar Credenciais do Google"**.
4. Em seguida, clique no botão verde **"Conectar Conta Google"** (ou vá na tela Agenda e clique em **"Sincronizar"**).
5. O Google solicitará que você faça login e autorize a permissão de leitura e gravação no calendário.
6. Ao retornar, o sistema exibirá o toast verde "Google Calendar Conectado!" e a sincronização funcionará perfeitamente.

## 5. (Opcional) Configuração via EasyPanel no VPS

Se preferir injetar diretamente nas variáveis de ambiente do contêiner do Edge Runtime no EasyPanel:

- Variável: `GOOGLE_CLIENT_ID`
- Variável: `GOOGLE_CLIENT_SECRET`
