# Runbook de Virada (Cutover) & Rollback de Emergência

**Sistema:** DPSjur  
**Ambiente de Produção Atual:** EasyPanel (`dpsjur-web` em `https://sistema.advdouglaspsantos.com.br`)  
**Backend Atual:** Supabase Nuvem SBJur (`cpcafthwnqazopqftemj.supabase.co`)  
**Novo Backend Destino:** Supabase Self-Hosted no VPS (`http://2.25.181.69:8000` ou subdomínio dedicado)  
**Tempo Estimado de Virada:** Menos de 3 minutos (sem recompilação de código!)  
**Tempo Estimado de Rollback:** Menos de 1 minuto

---

## 🏗️ Como Funciona a Arquitetura de Runtime do DPSjur

Diferente de sistemas web comuns que exigem recompilar o projeto inteiro via Docker a cada alteração de URL, o DPSjur foi construído com **injeção dinâmica de variáveis de ambiente em runtime**.

O contêiner executa o script `docker-entrypoint.sh` no momento da inicialização. Esse script:

1. Lê as variáveis de ambiente cadastradas na aba **"Environment"** do EasyPanel;
2. Gera o arquivo `/usr/share/nginx/html/env.js`;
3. O frontend no navegador lê instantaneamente `window.__ENV__.VITE_SUPABASE_URL` e `window.__ENV__.VITE_SUPABASE_PUBLISHABLE_KEY`.

Portanto, **nenhuma linha de código do aplicativo precisa ser alterada ou recompilada** para trocar de backend!

---

## 🚀 Procedimento de Virada (Cutover Passo a Passo)

### Etapa 1: Garantir que o Supabase Self-Hosted está Operacional

1. No EasyPanel, verifique se o serviço `supabase` está com status verde **"Running"**.
2. Execute o script de importação e auditoria:
   ```bash
   bash docs/migracao-fase4/05-importar-no-supabase-local.sh
   ```
3. Confirme que a auditoria retornou todas as 17 tabelas e 7 usuários com status **OK EXATO**.

### Etapa 2: Obter a URL e a Anon Key do Supabase Local

Na aba **Environment** do serviço Supabase no EasyPanel:

- Copie a URL pública (ex: `http://2.25.181.69:8000` ou `https://api.advdouglaspsantos.com.br`);
- Copie o valor da variável `ANON_KEY`.

### Etapa 3: Atualizar o App `dpsjur-web` no EasyPanel

1. No EasyPanel, abra o serviço do frontend: **`dpsjur-web`** (ou `app`);
2. Vá para a aba **"Environment"**;
3. Altere apenas as duas variáveis:
   - `VITE_SUPABASE_URL` ➔ `http://2.25.181.69:8000` (ou sua URL local);
   - `VITE_SUPABASE_PUBLISHABLE_KEY` ➔ Cole o valor da `ANON_KEY` local.
4. Clique no botão azul **"Save"** (Salvar);
5. No topo da página, clique em **"Restart"** (ou faça um **"Deploy"** rápido).

### Etapa 4: Validação no Navegador

1. Abra uma aba anônima no navegador;
2. Acesse: `https://sistema.advdouglaspsantos.com.br`;
3. Pressione `F12` > aba **Console**:
   - Digite `window.__ENV__` e confirme se a nova URL local está impressa;
4. Faça login com seu e-mail:
   - E-mail: `advdouglaspsantos@gmail.com`
   - Senha: sua senha habitual do escritório;
5. Verifique se os 345 clientes, 550 processos e 941 lançamentos financeiros aparecem instantaneamente na tela!

---

## 🛟 Plano de Rollback de Emergência (Retorno à Nuvem em 1 Minuto)

Se por qualquer motivo inesperado o Supabase local falhar ou você preferir voltar imediatamente ao backend da nuvem:

### Passo 1: Abrir o EasyPanel

1. Acesse o EasyPanel no navegador (`http://2.25.181.69:3000`);
2. Clique no serviço **`dpsjur-web`**;
3. Vá para a aba **"Environment"**.

### Passo 2: Restaurar as Credenciais da Nuvem

Substitua os valores exatamente pelos valores de backup abaixo:

| Variável                        | Valor de Rollback (Nuvem SBJur)                  |
| :------------------------------ | :----------------------------------------------- |
| `VITE_SUPABASE_URL`             | `https://cpcafthwnqazopqftemj.supabase.co`       |
| `VITE_SUPABASE_PUBLISHABLE_KEY` | `sb_publishable_n8rNjvEg6i-Sjme1-5Yhug_nNwxBRwO` |

### Passo 3: Salvar e Reiniciar

1. Clique em **"Save"**;
2. Clique em **"Restart"** (ou **"Deploy"**);
3. O sistema volta a operar 100% na nuvem Supabase em menos de 60 segundos!

---

## 🛡️ Fallback de Segurança Embutido no Código

Mesmo se alguém deletar por engano as variáveis de ambiente na aba Environment do EasyPanel, o arquivo `src/lib/env.ts` e o script `docker-entrypoint.sh` contêm o fallback seguro para o SBJur:

- `DEFAULT_FALLBACKS.VITE_SUPABASE_URL = 'https://cpcafthwnqazopqftemj.supabase.co'`
- `DEFAULT_FALLBACKS.VITE_SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_n8rNjvEg6i-Sjme1-5Yhug_nNwxBRwO'`

Isso garante que o sistema **nunca fica com tela em branco** nem quebra por falta de configuração.
