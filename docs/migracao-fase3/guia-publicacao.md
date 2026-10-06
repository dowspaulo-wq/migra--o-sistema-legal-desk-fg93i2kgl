# Guia de Publicação do App DPSjur & Configuração de Domínio (Fase 3)

**Manual Passo a Passo para o Douglas (EasyPanel / VPS Hostinger / Registro.br)**  
**Projeto:** DPSjur  
**Servidor VPS:** Hostinger KVM 1 (`srv1737667.hstgr.cloud` - IP `2.25.181.69`)  
**Domínio Oficial:** `advdouglaspsantos.com.br` (Registro.br)  
**Subdomínio do DPSjur:** `sistema.advdouglaspsantos.com.br`  
**Status do Banco:** PostgreSQL 16.6 importado e conferido 17/17 OK no EasyPanel

---

## 🎯 Parabéns e Visão Geral da Fase 3

Parabéns, Douglas! A auditoria do banco de dados na Fase 2 foi um sucesso completo: todas as 17 tabelas e os 7.828 registros estão íntegros no seu VPS.

Agora vamos para a **Fase 3: Publicar o sistema no ar com o seu domínio próprio e cadeado de segurança (HTTPS)**.

Neste guia, você fará apenas 4 etapas principais:

1. **No Registro.br:** Criar o apontamento DNS do subdomínio `sistema.advdouglaspsantos.com.br` para o IP do seu VPS (`2.25.181.69`). **O seu site institucional continuará 100% no ar e intacto.**
2. **No PostgreSQL do VPS:** Executar um comando rápido no terminal para preparar as permissões de acesso da API (`01-preparacao-auth-roles.sql`).
3. **No EasyPanel:** Publicar o aplicativo React/Vite com o Dockerfile de produção, configurando as variáveis de ambiente necessárias.
4. **Vincular o domínio no EasyPanel:** Ativar o certificado SSL gratuito (Let's Encrypt) com um clique e testar o acesso!

---

## 🏛️ Entendendo a Arquitetura (Transparência Total)

O sistema DPSjur foi construído utilizando a biblioteca `@supabase/supabase-js` no frontend para:

1. Autenticação e sessões de usuários;
2. Leitura e escrita de dados em tempo real (PostgREST);
3. Upload e visualização de documentos e fotos de perfil (Storage).

### Como manter o sistema funcionando sem pagar US$ 25/mês?

Para não quebrar a aplicação e manter o custo em **zero reais adicionais**, o app React/Vite pode funcionar de duas maneiras no seu VPS:

- **Estratégia Homologação Segura (Recomendada para esta Fase):**  
  Publicamos o frontend compilado no EasyPanel apontando para o seu subdomínio oficial `sistema.advdouglaspsantos.com.br`. Durante os testes iniciais, você pode manter as chaves públicas atuais ou conectar aos serviços complementares no próprio VPS.
- **Estratégia 100% Autônoma no VPS (Fase Final de Cutover):**  
  No mesmo projeto `dpsjur` do EasyPanel, é possível adicionar os serviços leves complementares (PostgREST e GoTrue) conectados diretamente ao seu PostgreSQL `dpsjur_dpsjur-db`.

O script `docs/migracao-fase3/01-preparacao-auth-roles.sql` já deixa o seu banco 100% pronto para qualquer um dos dois caminhos!

---

## 🌐 ETAPA 1: Configurar o Subdomínio no Registro.br

> ⚠️ **Atenção:** Seu site institucional em `advdouglaspsantos.com.br` ou `www.advdouglaspsantos.com.br` **NÃO SERÁ ALTERADO**. Criaremos apenas uma nova entrada exclusiva chamada `sistema`.

### 1.1 Acessar o Registro.br

1. Acesse o site oficial: [https://registro.br](https://registro.br)
2. Faça login com seu usuário (ID) e senha.
3. No painel principal, clique em **DOMÍNIOS** e depois clique sobre o seu domínio: `advdouglaspsantos.com.br`.

### 1.2 Acessar a Zona DNS

1. Role a página até encontrar a seção chamada **DNS**.
2. Clique no link ou botão **"Editar Zona"** (ou **"Configurar Zona DNS"** / **"Gerenciar Registros"**).
   - _Nota:_ Se aparecer uma mensagem informando que os servidores DNS são externos (ex.: Cloudflare ou Hostinger), você fará essa mesma configuração no painel onde o DNS estiver delegado. Se o DNS for do próprio Registro.br, os passos abaixo são exatos.

### 1.3 Adicionar o Registro A para o Subdomínio

1. Clique no botão verde ou link **"+ Registro"** (ou **"Adicionar Registro"**).
2. Preencha os campos exatamente assim:
   - **Tipo:** Selecione `A` (endereço IPv4).
   - **Nome:** Digite apenas `sistema` (o Registro.br adiciona automaticamente `.advdouglaspsantos.com.br`).
   - **IP / Dados / Destino:** Digite o IP do seu VPS: `2.25.181.69`
   - **TTL:** Mantenha o padrão sugerido (ex.: `Auto` ou `86400` / `3600`).
3. Clique em **"Adicionar"** e depois no botão **"Salvar Alterações"** (ou **"Salvar"**).

### 1.4 O que acontece agora?

A propagação do DNS do Registro.br costuma levar entre **15 minutos e 2 horas** (raramente até 24 horas). Enquanto o DNS propaga, faremos as próximas etapas no EasyPanel tranquilamente!

---

## 🗄️ ETAPA 2: Preparar Permissões e Roles no PostgreSQL do VPS

Para que o backend e as chamadas do app tenham permissão total sobre os dados e sobre os usuários, criamos o script `01-preparacao-auth-roles.sql`.

Esse script cria a role `authenticator` (necessária para APIs REST), cria a tabela `auth.users` compatível e provisiona o acesso para os 7 operadores do escritório com uma senha temporária inicial: `DPSjur@2026`.

### 2.1 Como aplicar no Terminal do VPS

Abra o Terminal do seu VPS (via navegador na Hostinger ou via SSH):

Cole o bloco abaixo e dê **ENTER**:

```bash
mkdir -p /root/dpsjur-import
cd /root/dpsjur-import

# Baixar o script de roles e auth da Fase 3
curl -fSL -o /root/dpsjur-import/01-preparacao-auth-roles.sql \
  https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/migracao-fase3/01-preparacao-auth-roles.sql

# Identificar o container do banco de dados no EasyPanel
CONTAINER_DB=$(docker ps -q -f name=dpsjur.*db | head -n 1)

# Copiar para dentro do container
docker cp /root/dpsjur-import/01-preparacao-auth-roles.sql $CONTAINER_DB:/tmp/01-preparacao-auth-roles.sql

# Executar a preparação com o usuário Doug
docker exec -e PGPASSWORD='4585d780134654a88ae7' -i $CONTAINER_DB \
  psql -U Doug -d dpsjur -f /tmp/01-preparacao-auth-roles.sql
```

_Resultado esperado:_ O terminal exibirá mensagens de `CREATE ROLE`, `GRANT` e `INSERT 0 7`, confirmando que os 7 operadores estão sincronizados com permissões ativas.

---

## 🚀 ETAPA 3: Publicar o App DPSjur no EasyPanel

Agora vamos criar o serviço da aplicação web no seu painel EasyPanel.

### 3.1 Acessar o Projeto no EasyPanel

1. Acesse o seu painel EasyPanel no navegador (ex.: `http://2.25.181.69:3000` ou pelo domínio do painel).
2. Faça login.
3. No painel inicial, clique no projeto **`dpsjur`** (onde já está o serviço `dpsjur-db`).

### 3.2 Criar um Novo Serviço do Tipo "App"

1. No canto superior direito da tela do projeto `dpsjur`, clique no botão azul **"+ Service"** (ou **"+ Adicionar Serviço"**).
2. Na lista de tipos de serviço, selecione **"App"** (serviço padrão para aplicações web).
3. No campo **Service Name** (Nome do Serviço), digite:  
   `dpsjur-web`  
   _(pode ser `app` ou `dpsjur-web` — sugerimos `dpsjur-web` para ficar bem organizado ao lado de `dpsjur-db`)_.
4. Clique em **Create** (Criar).

### 3.3 Configurar a Origem do Código (Aba "Source")

Você será direcionado para as configurações do serviço `dpsjur-web`.

1. Clique na aba **"Source"** (Fonte / Origem).
2. Selecione a opção **"Git"** (ou GitHub).
3. Preencha os campos:
   - **Repository:** `dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl` (ou a URL HTTPS completa: `https://github.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl.git`)
   - **Branch:** `main`
   - **Build Type:** Selecione **"Dockerfile"**
   - **Dockerfile Path:** Digite `Dockerfile` (já está na raiz do projeto)
4. Clique em **"Save"** (Salvar).

### 3.4 Configurar as Variáveis de Ambiente (Aba "Environment")

Como o Vite compila o React no momento da construção da imagem, as variáveis de ambiente devem ser preenchidas na aba **"Environment"** do EasyPanel:

1. Clique na aba **"Environment"** (Variáveis de Ambiente).
2. Adicione as seguintes variáveis:

| Variável                        | Onde pegar / Valor                         | Descrição                                          |
| ------------------------------- | ------------------------------------------ | -------------------------------------------------- |
| `VITE_SUPABASE_URL`             | `https://dagtlwojkqyivnjgveda.supabase.co` | URL da API do projeto                              |
| `VITE_SUPABASE_PUBLISHABLE_KEY` | _(sua chave anon atual do Supabase)_       | Chave pública do app para autenticação e consultas |
| `NODE_ENV`                      | `production`                               | Modo de produção do build                          |

> 🔒 **Dica de onde pegar a chave:**  
> No painel do Supabase atual, em **Settings > API**, copie a chave **`anon public`**. Cole no campo `VITE_SUPABASE_PUBLISHABLE_KEY`.  
> _Nota de segurança:_ Chaves com prefixo `VITE_` são públicas por definição, feitas para rodar no navegador do cliente com proteção garantida pelas regras RLS do banco.

3. Clique em **"Save"** (Salvar).

### 3.5 Configurar as Portas e Recursos

1. Vá para a aba **"General"** ou **"Networking"**:
   - Verifique se a porta interna está definida como **`80`** (o Nginx do Dockerfile roda na porta 80).
2. Clique em **"Save"**.

---

## 🔒 ETAPA 4: Vincular o Subdomínio e Ativar o HTTPS

Agora vamos conectar o subdomínio `sistema.advdouglaspsantos.com.br` diretamente a este serviço `dpsjur-web` com certificado SSL gratuito e renovação automática!

### 4.1 Adicionar o Domínio no EasyPanel

1. No serviço `dpsjur-web`, clique na aba **"Domains"** (Domínios).
2. Clique no botão **"+ Add Domain"** (ou **"Add"**).
3. No campo **Host / Domain**, digite exatamente:  
   `sistema.advdouglaspsantos.com.br`
4. No campo **Port**, certifique-se de que está **`80`**.
5. Deixe marcada a opção **HTTPS / SSL** (o EasyPanel usa o Let's Encrypt automaticamente para emitir o certificado).
6. Clique em **"Save"** (Salvar).

### 4.2 Fazer o Deploy (Publicação)

1. No topo da página do serviço `dpsjur-web`, clique no botão **"Deploy"** (Implantar).
2. O EasyPanel começará a baixar o código do GitHub, instalar os pacotes, compilar o app React via Vite e inicializar o container Nginx.
3. Você pode acompanhar a compilação clicando na aba **"Deployments"** ou **"Logs"**.
4. Quando aparecer o status verde **"Running"** (Rodando), o aplicativo estará online!

---

## 🧪 ETAPA 5: Como Testar e Validar

### 5.1 Teste 1: Propagação de DNS

Abra o terminal do seu computador (ou use sites como [dnschecker.org](https://dnschecker.org/#A/sistema.advdouglaspsantos.com.br)) e verifique se `sistema.advdouglaspsantos.com.br` aponta para `2.25.181.69`.

No terminal:

```bash
ping sistema.advdouglaspsantos.com.br
```

Se a resposta mostrar o IP `2.25.181.69`, a propagação está concluída!

### 5.2 Teste 2: Acesso com HTTPS no Navegador

1. Abra uma nova aba no seu navegador.
2. Acesse:  
   👉 **`https://sistema.advdouglaspsantos.com.br`**
3. Verifique se o cadeado de segurança aparece ao lado do endereço.
4. Você deverá ver a tela de login oficial do **DPSjur** com a identidade visual do seu escritório!

### 5.3 Teste 3: Login no Sistema

1. Digite seu e-mail de administrador: `advdouglaspsantos@gmail.com`
2. Digite sua senha habitual ou a senha temporária inicial `DPSjur@2026`.
3. Navegue pelos menus:
   - **Clientes:** Verifique a lista com os 345 clientes.
   - **Processos:** Verifique os 550 casos e seus históricos.
   - **Tarefas e Agenda:** Verifique seus prazos e compromissos.
   - **Financeiro:** Verifique os 941 lançamentos.

---

## ⚠️ Problemas Comuns e Como Resolver

### 1. "Não é possível acessar esse site" / Erro de DNS (`ERR_NAME_NOT_RESOLVED`)

- **Causa:** O apontamento no Registro.br ainda não propagou pelos servidores de internet.
- **O que fazer:** Aguarde de 30 minutos a 1 hora. Limpe o cache do seu navegador (Ctrl + Shift + R) ou teste em uma janela anônima / celular via 4G.

### 2. "Sua conexão não é privada" / Erro SSL (`ERR_CERT_COMMON_NAME_INVALID`)

- **Causa:** O EasyPanel tentou emitir o certificado Let's Encrypt antes do DNS terminar de propagar.
- **O que fazer:** Quando o DNS já estiver respondendo ao ping, vá na aba **Domains** do serviço `dpsjur-web` no EasyPanel, clique nos três pontinhos ao lado do domínio e clique em **"Re-issue Certificate"** (ou faça um novo Deploy).

### 3. Tela em branco após carregar o site

- **Causa:** Alguma variável de ambiente do Supabase (`VITE_SUPABASE_URL` ou `VITE_SUPABASE_PUBLISHABLE_KEY`) não foi configurada na aba Environment ou foi digitada com erro/espaços extras.
- **O que fazer:** O sistema possui suporte a injeção em runtime via `/env.js`. Confira na aba **Environment** do serviço no EasyPanel se `VITE_SUPABASE_URL` e `VITE_SUPABASE_PUBLISHABLE_KEY` estão cadastradas corretamente, sem aspas e sem espaços extras. Não é necessário configurar build-args. Após salvar ou conferir as variáveis, basta reiniciar ou clicar em **Deploy**.

### 4. O site institucional `advdouglaspsantos.com.br` pode cair?

- **Resposta:** **Não.** O site institucional fica apontado para o IP da sua hospedagem atual. Nós adicionamos apenas um subdomínio (`sistema`), que funciona como uma via totalmente separada e independente na internet.

---

## 📋 Resumo das Informações para Guardar

| Item                            | Valor                                      |
| ------------------------------- | ------------------------------------------ |
| **URL de Acesso ao Sistema**    | `https://sistema.advdouglaspsantos.com.br` |
| **IP do VPS**                   | `2.25.181.69`                              |
| **Tipo de Registro DNS**        | `A`                                        |
| **Nome no Registro.br**         | `sistema`                                  |
| **Destino do DNS**              | `2.25.181.69`                              |
| **Porta Interna do EasyPanel**  | `80`                                       |
| **Serviço Web no EasyPanel**    | `dpsjur-web`                               |
| **Banco de Dados no EasyPanel** | `dpsjur-db` (`dpsjur_dpsjur-db:5432`)      |

---

## 💬 O Que Fazer Após Concluir

Assim que você criar o registro no Registro.br e fizer o Deploy no EasyPanel, me dê um aviso aqui no chat! Nós validaremos juntos o acesso, as rotas e o login para avançar para a integração dos webhooks do Asaas e automações da Fase 4.
