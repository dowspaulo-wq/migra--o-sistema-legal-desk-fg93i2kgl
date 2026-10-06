# Guia Passo a Passo: Instalação do Supabase no EasyPanel (VPS Hostinger)

**Projeto:** DPSjur  
**Servidor VPS:** Hostinger KVM 1 (`srv1737667.hstgr.cloud` - IP `2.25.181.69`)  
**Painel:** EasyPanel (`http://2.25.181.69:3000`)  
**Data:** Fase 4 da Migração

---

## 🎯 Objetivo Desta Etapa

Instalar uma instância completa do **Supabase Self-Hosted** dentro do seu VPS usando o template oficial do EasyPanel.  
Ao final desta instalação, você terá rodando no seu próprio servidor:

1. **PostgreSQL 15** otimizado com todas as extensões do Supabase;
2. **GoTrue (Auth)** para login de usuários e controle de sessões;
3. **PostgREST (REST API)** para comunicação ultrarrápida do frontend;
4. **Supabase Storage** para armazenar fotos de perfil, logotipos e documentos;
5. **Supabase Studio (Dashboard Web)** para você visualizar suas tabelas visualmente pelo navegador;
6. **Kong API Gateway** gerenciando todas as rotas e chaves de segurança.

Tudo isso com **custo zero adicional**, rodando no seu VPS que já está pago até junho/2027!

---

## 📋 Pré-requisitos & Planejamento de Recursos

- **VPS:** IP `2.25.181.69`
- **Subdomínio para a API / Studio (opcional ou recomendado):**  
  Você pode acessar pelo IP do VPS (porta 8000/3000) ou criar um subdomínio no Registro.br como `api.advdouglaspsantos.com.br` ou `supabase.advdouglaspsantos.com.br` apontando para o IP `2.25.181.69`.
- **Memória RAM:** O Supabase completo consome cerca de 1.2 GB a 1.8 GB de RAM em repouso. O VPS Hostinger KVM 1 possui 4 GB de RAM, o que atende perfeitamente ao DPSjur (app + banco + Supabase).

---

## 🛠️ Passo a Passo da Instalação no EasyPanel

### Passo 1: Acessar o EasyPanel

1. Abra seu navegador e acesse:  
   👉 `http://2.25.181.69:3000` (ou o domínio configurado para o seu EasyPanel).
2. Faça login com suas credenciais de administrador do painel.

### Passo 2: Criar ou Acessar o Projeto

1. Na lista de projetos, você pode:
   - Utilizar o projeto existente **`dpsjur`**; OU
   - Criar um projeto exclusivo chamado **`supabase`** (recomendado para organização visual).
2. Clique no projeto desejado.

### Passo 3: Adicionar o Serviço via Template

1. No canto superior direito, clique no botão azul **"+ Service"** (ou **"+ Adicionar Serviço"**).
2. Selecione a opção **"Templates"** (ou **"One-Click Apps"**).
3. Na barra de busca, digite: `supabase`.
4. Clique sobre o card do **Supabase**.
5. No campo **Service Name** (Nome do Serviço), mantenha `supabase` ou digite `dpsjur-supabase`.
6. Clique em **"Create"** (Criar).

---

## ⚙️ Passo 4: Configurar as Variáveis Essenciais (Environment)

O EasyPanel já preenche valores padrão aleatórios para as senhas e chaves. Vamos revisar os campos mais importantes na aba **"Environment"** do serviço:

### 1. Senha do Banco PostgreSQL

- Variável: `POSTGRES_PASSWORD`
- Defina uma senha forte (exemplo: uma sequência aleatória de 20 caracteres sem símbolos especiais problemáticos). Guarde esta senha em um local seguro.

### 2. Segredo JWT e Chaves da API

O template gera automaticamente:

- `JWT_SECRET`: chave secreta de no mínimo 32 caracteres;
- `ANON_KEY`: chave pública para uso no frontend (equivalente à publishable key);
- `SERVICE_ROLE_KEY`: chave com privilégio de administrador do backend.

> 💡 **Importante:** Copie e salve o valor da **`ANON_KEY`** gerada! Ela será a chave que colocaremos no app React do DPSjur quando fizermos a virada final.

### 3. URL Pública da API (API_EXTERNAL_URL / SUPABASE_PUBLIC_URL)

- Se você for usar subdomínio próprio:  
  `https://api.advdouglaspsantos.com.br`
- Se for usar direto com porta/IP:  
  `http://2.25.181.69:8000`
- Variável: `API_EXTERNAL_URL` = `http://2.25.181.69:8000` (ou o seu domínio).
- Variável: `SUPABASE_PUBLIC_URL` = `http://2.25.181.69:8000` (ou o seu domínio).

---

## ✉️ Passo 5: Configurar o SMTP (E-mails de Recuperação de Senha)

No Supabase self-hosted, para que a função _"Esqueci minha senha"_ e os convites de novos operadores funcionem por e-mail, é necessário preencher as variáveis do serviço **GoTrue (Auth)**.

Na aba **Environment** do serviço Supabase no EasyPanel, localize e preencha:

| Variável                   | Exemplo com Gmail / Google Workspace                | Exemplo com Hostinger / Brevo / Resend |
| :------------------------- | :-------------------------------------------------- | :------------------------------------- |
| `ENABLE_EMAIL_SIGNUP`      | `true`                                              | `true`                                 |
| `ENABLE_EMAIL_AUTOCONFIRM` | `true` _(recomendado: evita travar usuários novos)_ | `true`                                 |
| `SMTP_ADMIN_EMAIL`         | `advdouglaspsantos@gmail.com`                       | `contato@advdouglaspsantos.com.br`     |
| `SMTP_SENDER_NAME`         | `DPSjur - Advocacia`                                | `DPSjur`                               |
| `SMTP_HOST`                | `smtp.gmail.com`                                    | `smtp.hostinger.com`                   |
| `SMTP_PORT`                | `587`                                               | `465` (SSL) ou `587` (TLS)             |
| `SMTP_USER`                | `advdouglaspsantos@gmail.com`                       | `seu_email_smtp`                       |
| `SMTP_PASS`                | `sua-senha-de-app-16-digitos`                       | `sua-senha-smtp`                       |

> 🔑 **Dica para usar Gmail/Google:**  
> Se for usar sua conta Google, não use sua senha normal. Ative a verificação em duas etapas no Google e gere uma **"Senha de App"** (16 letras). Essa senha de app vai no `SMTP_PASS`.

---

## 🚀 Passo 6: Implantar (Deploy) e Iniciar os Serviços

1. No topo da página do serviço no EasyPanel, clique em **"Deploy"** (Implantar).
2. O EasyPanel fará o download das imagens Docker oficiais do Supabase (`db`, `kong`, `auth`, `rest`, `storage`, `studio`, `realtime`, etc.).
3. O primeiro deploy costuma levar de **2 a 5 minutos** dependendo da velocidade de download.
4. Quando o status mudar para **"Running"** (verde), a sua infraestrutura Supabase estará totalmente operacional!

---

## 🌐 Passo 7: Como Acessar o Supabase Studio (Dashboard Local)

O Supabase Studio é o painel de controle do banco (idêntico visualmente ao Supabase da nuvem).

1. No EasyPanel, vá na aba **"Domains"** do serviço Supabase.
2. O EasyPanel mapeia o Kong (porta 8000) e o Studio (porta 3000).
3. Caso queira acessar o Studio com segurança:
   - Adicione um domínio como `studio.advdouglaspsantos.com.br` apontando para a porta interna do serviço `studio` (normalmente 3000); OU
   - Acesse via IP direto se a porta estiver exposta: `http://2.25.181.69:3000` (com o usuário e senha definidos em `DASHBOARD_USERNAME` e `DASHBOARD_PASSWORD`).

---

## 🔑 Resumo das Informações para a Virada do DPSjur

Guarde estes dois dados em mãos quando o Supabase estiver rodando:

1. **`VITE_SUPABASE_URL`**:  
   Exemplo: `http://2.25.181.69:8000` ou `https://api.advdouglaspsantos.com.br`
2. **`VITE_SUPABASE_PUBLISHABLE_KEY` (ou ANON_KEY)**:  
   O hash JWT copiado da variável `ANON_KEY` na aba Environment.

Com esses dois valores em mãos, a virada do DPSjur no EasyPanel será feita em **menos de 2 minutos** apenas atualizando as variáveis de ambiente do app `dpsjur-web`!
