# Como Executar a Migração no Terminal do VPS (Guia Direto para Leigos)

**Servidor:** VPS Hostinger KVM 1 (`srv1737667` — IP `2.25.181.69`)  
**Acesso:** Terminal do EasyPanel ou SSH como `root`  
**Objetivo:** Trazer os dados frescos da nuvem Supabase (`cpcafthwnqazopqftemj`) para o Supabase próprio instalado no EasyPanel com **apenas 1 comando colado no terminal**.  
**Versão do Kit:** `v0.0.505` (com Plano B via REST API HTTPS 443 — dispensa portas PostgreSQL 5432/6543)

---

## 🌐 Por que o Plano B (`06b`) é a solução definitiva para o VPS?

No teste do script 06 (Plano A), vimos que:

1. O host direto do banco `db.cpcafthwnqazopqftemj.supabase.co` só publica endereço IPv6 (`2600:1f18...`), mas o VPS da Hostinger opera em rede IPv4-only (`Network is unreachable`);
2. Os poolers (`aws-1-us-east-1.pooler.supabase.com` nas portas 6543 e 5432) dão timeout de dentro do VPS ou respondem `tenant not found`;
3. **Porém a API REST HTTPS na porta 443 responde perfeitamente!**

O **Plano B (`06b-exportar-via-rest-api.sh`)** utiliza a própria API REST HTTPS da nuvem (`https://cpcafthwnqazopqftemj.supabase.co/rest/v1/`) com a sua **`service_role` key** para exportar todas as tabelas em formato CSV com paginação e importá-las via `\copy` atômico no PostgreSQL local.

**Vantagem crucial:** Não precisa de nenhuma porta de banco aberta nem de IPv6 — trafega tudo por HTTPS 443 padrão da web!

---

## 🔑 Onde pegar a SERVICE_ROLE KEY no Painel Supabase?

O Plano B precisa da **Service Role Key** para conseguir ler todas as tabelas do banco contornando o RLS:

1. Acesse: [https://supabase.com/dashboard/project/cpcafthwnqazopqftemj/settings/api](https://supabase.com/dashboard/project/cpcafthwnqazopqftemj/settings/api)
2. Na seção **Project API keys**:
   - Procure a chave chamada **`service_role` (secret)**;
   - Clique em **Reveal** (ou no ícone de cópia) e copie esse token longo (`eyJhbGci...`);
   - ⚠️ **Importante**: Copie a chave `service_role` e NÃO a `anon/public`.

---

## 🚀 Como Executar o Plano B no VPS (Passo Único)

Abra o terminal do seu VPS (via **EasyPanel** ou **SSH**) e cole este comando único:

```bash
cd /root/sbjur-migracao && \
curl -sSf -L -H "Cache-Control: no-cache" https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/migracao-fase4/06b-exportar-via-rest-api.sh -o 06b-exportar-via-rest-api.sh && \
bash 06b-exportar-via-rest-api.sh
```

Ou, se a pasta `/root/sbjur-migracao` ainda não existir:

```bash
mkdir -p /root/sbjur-migracao && cd /root/sbjur-migracao && \
curl -sSf -L -H "Cache-Control: no-cache" https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/migracao-fase4/bootstrap-vps.sh -o bootstrap-vps.sh && \
bash bootstrap-vps.sh && \
bash 06b-exportar-via-rest-api.sh
```

---

## 🛡️ O que vai acontecer na sua tela no Plano B?

O script executa de forma 100% automatizada e transparente:

1. **Pede a SERVICE_ROLE KEY da Nuvem**:
   - `👉 Digite ou cole a SERVICE_ROLE KEY da NUVEM Supabase: `
   - Cole a chave e aperte `Enter` (leitura oculta via `stty -echo`, nada é gravado em disco).
2. **Pede a POSTGRES_PASSWORD Local**:
   - `👉 Digite a senha POSTGRES_PASSWORD do Supabase LOCAL (EasyPanel): `
   - Cole a senha configurada no seu serviço `supabase` do EasyPanel e aperte `Enter`.
3. **Descobre as tabelas automaticamente**:
   - Consulta o catálogo OpenAPI da nuvem (`/rest/v1/`) e lista as tabelas (`clients`, `cases`, `tasks`, etc.).
4. **Exporta página por página em CSV**:
   - Mostra o progresso tabela por tabela:
     - `⏳ Exportando clients ... ✅ 345 linhas`
     - `⏳ Exportando cases ... ✅ 550 linhas`
     - `⏳ Exportando tasks ... ✅ 836 linhas`
     - `...`
5. **Importa no PostgreSQL local com integridade garantida**:
   - Limpeza prévia idempotente (`TRUNCATE ... RESTART IDENTITY CASCADE`);
   - Desativação transitória de FKs e triggers (`SET session_replication_role = 'replica'`);
   - Carga atômica de cada CSV via `\copy` em uma única transação (`BEGIN / COMMIT`).
6. **Auditoria comparativa instantânea**:
   - Exibe a tabela verde conferindo cada uma das 17 tabelas (esperado vs importado no VPS).

---

## 🔁 E o Script 06 (Plano A via PostgreSQL nativo)?

O script `06-exportar-e-importar-dados.sh` continua disponível e intacto para quem possuir conectividade TCP direta liberada:

```bash
cd /root/sbjur-migracao && bash 06-exportar-e-importar-dados.sh
```

---

## 🛡️ O que vai acontecer na sua tela?

O script fará todo o trabalho pesado sozinho em 6 etapas claras:

1. **Baixar o kit oficial** para a pasta `/root/sbjur-migracao/`;
2. **Pedir a Senha da Nuvem Supabase (SBJur)**:
   - Aparecerá na tela: `👉 Digite a SENHA do banco de dados da NUVEM Supabase (SBJur): `
   - Digite ou cole a sua senha do banco da nuvem e pressione `Enter`.
   - _(Dica de segurança do Linux: o cursor não se mexe e nada aparece na tela enquanto você digita a senha — isso é normal para proteger sua senha de quem estiver olhando)._
3. **Pedir a Senha Local (`POSTGRES_PASSWORD`)**:
   - Aparecerá: `👉 Digite a senha POSTGRES_PASSWORD do Supabase LOCAL (EasyPanel): `
   - Digite ou cole a senha configurada no seu serviço `supabase` do EasyPanel e dê `Enter`.
4. **Endpoint Oficial Supabase Automático**:
   - O script já utiliza de fábrica o endpoint oficial `aws-1-us-east-1.pooler.supabase.com` (testando primeiro porta 6543 e depois 5432).
   - Não requer digitar host, região ou porta: vai direto ao ponto.
5. **Localização automática do contêiner**:
   - O script descobre o contêiner do PostgreSQL local sozinho via `docker ps`.
6. **Exportação da nuvem e importação local segura**:
   - Os dados são extraídos da nuvem em modo somente leitura (sem risco algum de apagar nada da nuvem);
   - São inseridos no banco local em transação única (`session_replication_role = 'replica'`);
7. **Auditoria automática de contagens**:
   - Ao final, uma tabela comparativa verde aparecerá conferindo:
     - 345 clientes (`public.clients`);
     - 550 processos (`public.cases`);
     - 836 tarefas (`public.tasks`);
     - 258 compromissos (`public.appointments`);
     - 941 lançamentos (`public.transactions`);
     - 471 vínculos processo-transação (`public.transaction_cases`);
     - 7 usuários e perfis com senhas intactas (`auth.users` e `public.profiles`).

---

## 🔁 Opção Alternativa (Se o GitHub Raw falhar ou bloquear)

Caso o terminal do VPS tenha algum bloqueio temporário de rede com o GitHub, use este comando equivalente autocontido (ele baixa diretamente o script 06 autônomo):

```bash
mkdir -p /root/sbjur-migracao && cd /root/sbjur-migracao && \
curl -sSf -L -H "Cache-Control: no-cache" https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/migracao-fase4/06-exportar-e-importar-dados.sh -o 06-exportar-e-importar-dados.sh && \
chmod +x 06-exportar-e-importar-dados.sh && \
bash 06-exportar-e-importar-dados.sh
```

_(O script 06 foi projetado para rodar 100% autônomo: mesmo sem nenhum outro arquivo na pasta, ele realiza a extração fresca, importa em transação e roda a auditoria embutida)._

---

## 🔒 Segurança Garantida

- **Nenhuma senha é salva em disco ou no histórico**: a leitura é feita com `stty -echo` silencioso.
- **A nuvem nunca é alterada**: a operação na nuvem é estritamente de leitura (`pg_dump`).
- **Rollback instantâneo**: se a senha local estiver errada ou a conexão cair, o banco local desfaz a transação automaticamente (`ROLLBACK`).

---

## 🏁 O que fazer após ver o sucesso da auditoria?

Depois que aparecer `🎉 EXPORTAÇÃO E IMPORTAÇÃO DOS DADOS CONCLUÍDAS COM SUCESSO!`:

1. Abra o EasyPanel no navegador (`http://2.25.181.69:3000`);
2. Vá no serviço **`dpsjur-web`** > aba **Environment**;
3. Atualize apenas:
   - `VITE_SUPABASE_URL` = URL do seu Supabase local (ex: `http://2.25.181.69:8000`);
   - `VITE_SUPABASE_PUBLISHABLE_KEY` = o valor da `ANON_KEY` do Supabase local;
4. Clique em **Save** e depois em **Restart**.
5. Acesse `https://sistema.advdouglaspsantos.com.br` e faça login normalmente com seu e-mail `advdouglaspsantos@gmail.com`!
