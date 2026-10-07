# Como Executar a Migração no Terminal do VPS (Guia Direto para Leigos)

**Servidor:** VPS Hostinger KVM 1 (`srv1737667` — IP `2.25.181.69`)  
**Acesso:** Terminal do EasyPanel ou SSH como `root`  
**Objetivo:** Trazer os dados frescos da nuvem Supabase (`cpcafthwnqazopqftemj`) para o Supabase próprio instalado no EasyPanel com **apenas 1 comando colado no terminal**.  
**Versão do Kit:** `v0.0.503` (com varredura automática multirregião AWS, resolução IPv4 e diagnóstico detalhado)

---

## ❓ Por que o comando anterior deu erro?

Quando você digitou `cd /root/dpsjur` ou tentou rodar `bash docs/migracao-fase4/06-exportar-e-importar-dados.sh`, o Linux respondeu:

> `No such file or directory` (Arquivo ou pasta não encontrada)

Isso acontece porque o VPS **não possui os arquivos do código clonados em `/root/dpsjur`** — o EasyPanel roda o aplicativo via contêineres Docker isolados, então a pasta não existia no diretório `/root`.

---

## 🚀 Como Fazer Agora (Passo Único e Garantido)

Você não precisa instalar Git, nem configurar senhas do GitHub, nem clonar nada manualmente.

### Passo 1: Abrir o Terminal do VPS

Abra o terminal preto do seu VPS (via **EasyPanel** ou via **SSH**). Você já está como `root@srv1737667:~#`.

### Passo 2: Copiar e Colar o Comando Abaixo

Copie o bloco inteiro abaixo de uma vez só e cole no terminal:

```bash
mkdir -p /root/sbjur-migracao && cd /root/sbjur-migracao && \
curl -sSf -L -H "Cache-Control: no-cache" https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/migracao-fase4/bootstrap-vps.sh -o bootstrap-vps.sh && \
bash bootstrap-vps.sh && \
bash 06-exportar-e-importar-dados.sh
```

> 💡 **Nota da versão 0.0.503**: O script agora executa uma **varredura automática multirregião AWS** (17 regiões x poolers `aws-0` e `aws-1`) para localizar o tenant `cpcafthwnqazopqftemj`, superando o erro de _"tenant not found"_ caso o projeto esteja em outra região (ex: `us-east-1`, `us-west-2`, etc.):
>
> - Teste leve preliminar de conexão (`SELECT 1`) com timeout ágil de 6s (`PGCONNECT_TIMEOUT=6`) exibindo o status em linha única compacta;
> - O primeiro endpoint que responder com sucesso é eleito e utilizado no `pg_dump` com timeout estendido de 15s;
> - Para conexão direta (`db.cpcafthwnqazopqftemj.supabase.co`), resolve o registro IPv4 (registro A) para evitar que VPSs IPv4-only falhem com _"Network is unreachable"_ ao tentar IPv6;
> - Diagnóstico inteligente: se algum host aceitar o tenant mas rejeitar a senha (`password authentication failed`), o script avisa com destaque que o servidor correto foi encontrado e orienta o reset de senha no painel da Supabase.

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
4. **Pressionar Enter nas opções padrão**:
   - Região AWS: apenas dê `Enter` (já vem `sa-east-1` configurada).
   - Porta: apenas dê `Enter` (já vem `5432` configurada).
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
