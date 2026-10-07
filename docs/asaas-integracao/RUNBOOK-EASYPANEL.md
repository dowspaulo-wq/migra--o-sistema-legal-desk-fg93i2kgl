# Runbook EasyPanel: Configuração do Subdomínio da API e Ativação do Asaas

Este guia destina-se ao Douglas para configurar o subdomínio dedicado da API Supabase/Kong no VPS (`api.advdouglaspsantos.com.br`), cadastrar a chave de API do Asaas e habilitar os botões de sincronização financeira no DPSjur/SBJur.

---

## 📌 Por que precisamos do subdomínio `api.advdouglaspsantos.com.br`?

No diagnóstico realizado no VPS, constatou-se que requisições enviadas para:
`https://sistema.advdouglaspsantos.com.br/functions/v1/...`
recebiam resposta **"405 Not Allowed" do nginx/1.27.5**.

Isso acontecia porque o domínio `sistema.` aponta exclusivamente para o contêiner do aplicativo frontend. O gateway Kong (que responde na porta 8000 e atende Auth, Banco REST, Storage e Edge Functions) nunca recebia essas requisições.

A solução definitiva e recomendada pela arquitetura do Supabase é criar um subdomínio dedicado:
👉 **`api.advdouglaspsantos.com.br`** apontando diretamente para o Kong (porta 8000) com HTTPS.

> 💡 **Fique tranquilo:** Login, banco de dados, cadastros e anexos continuam funcionando 100%, pois o Kong é o gateway central que já roteia tudo. Além disso, **nada muda no domínio `sistema.advdouglaspsantos.com.br`**, que continua sendo o endereço que você e seu time usam para acessar o app no navegador.

---

## 🚀 Passo a Passo de Configuração (Linguagem Simples)

### Etapa 1: Apontar o subdomínio no Registro.br

1. Acesse o painel do **Registro.br** (https://registro.br) com seu login.
2. Clique no domínio **`advdouglaspsantos.com.br`**.
3. Na seção de **DNS / Editar Zona**, clique em **Adicionar Entrada**:
   - **Tipo**: `A`
   - **Nome**: `api`
   - **Dados / IP**: `2.25.181.69` (IP do seu VPS Hostinger)
4. Clique em **Salvar Alterações**.  
   _(A propagação no Registro.br costuma levar de 2 a 15 minutos)._

---

### Etapa 2: Adicionar o domínio no Cartão Supabase do EasyPanel

1. Abra o EasyPanel no seu navegador (`http://2.25.181.69:3000`).
2. Entre no projeto **`sbjur-local`**.
3. Clique no serviço/cartão do **Supabase** (tipo Compose, onde roda o Kong e os serviços de backend).
4. Vá até a aba **Domains** (Domínios):
   - Adicione o domínio: **`api.advdouglaspsantos.com.br`**
   - Porta: **`8000`** (porta do gateway Kong)
   - HTTPS: **Ativado / Habilitado** (o EasyPanel gera o certificado SSL Let's Encrypt automaticamente).
5. Clique em **Salvar**.

---

### Etapa 3: Atualizar a URL no serviço do Frontend no EasyPanel

1. Ainda no EasyPanel, vá para o serviço do app frontend: **`dpsjur-web`**.
2. Abra a aba **Environment** (Variáveis de Ambiente).
3. Localize (ou crie) a variável `VITE_SUPABASE_URL`:
   ```env
   VITE_SUPABASE_URL=https://api.advdouglaspsantos.com.br
   ```
4. Clique em **Salvar** e depois em **Implantar / Deploy** (ou Restart).
   > ⚡ **Aplicação imediata:** O app conta com script dinâmico (`env.js` via `docker-entrypoint.sh`). A alteração entra em vigor imediatamente ao reiniciar o contêiner, **sem necessidade de recompilar o código**.

---

### Etapa 4: Cadastrar a chave de API do Asaas diretamente no SBJur (Recomendado)

> ✨ **Novidade (sem mexer no Compose/EasyPanel):** A configuração da chave agora é feita diretamente dentro do sistema web! As chamadas passam a chave com segurança para as Edge Functions através de headers protegidos por HTTPS.

> ⚠️ **Atenção — Se a chave não persistir e o badge voltar a "Chave ausente":**
> Em termos leigos: o app web guarda sua chave dentro de uma gaveta da tabela `settings` no banco PostgreSQL. No banco do seu VPS essa gaveta (`asaasApiKey`) ainda não havia sido criada.  
> Para criar essa gaveta com 1 comando, execute via SSH no terminal do VPS:
>
> ```bash
> mkdir -p /root/sbjur-asaas && cd /root/sbjur-asaas && \
> curl -sSf -L -H "Accept: application/vnd.github.v3.raw" -H "User-Agent: DPSjur" https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/docs/asaas-integracao/03-aplicar-migracao-asaas.sh?ref=main -o 03-aplicar-migracao-asaas.sh && \
> bash 03-aplicar-migracao-asaas.sh
> ```
>
> O script é rápido (leva menos de 5 segundos), totalmente seguro e idempotente (não apaga dados). Ele detecta o contêiner do banco do Supabase, cria as colunas `asaasApiKey` e `asaasApiUrl` e confirma o resultado na tela com `✅`.

1. Obtenha sua chave no painel do **Asaas** (https://www.asaas.com > _Minha Conta_ > _Configurações da Conta_ > _Integrações_ > _Chaves de API_).
2. Acesse o **SBJur no navegador**: `https://sistema.advdouglaspsantos.com.br`.
3. No menu lateral, clique em **Configurações**.
4. Clique na aba **Integrações**.
5. No campo **Chave da API do Asaas (API Key)**, cole sua chave (`$aact_...`).
6. O campo **URL da API do Asaas** já vem preenchido com `https://api.asaas.com/v3` (padrão de produção). Caso queira usar sandbox futuramente, basta alterar para `https://api-sandbox.asaas.com/v3`.
7. Clique em **Salvar Configurações do Asaas**.
8. O badge mudará para **"Configurada"** em verde e permanecerá salvo.

> 💡 **Nota sobre EasyPanel / Compose (OPCIONAL / Não Necessário):** Como o editor `docker-compose.yaml` do Compose no EasyPanel aparece vazio (configuração gerada por template Git), você **NÃO precisa editar o arquivo docker-compose.yaml nem cadastrar variáveis de ambiente no painel do EasyPanel**. O sistema lê a chave salva no banco de dados do SBJur e injeta automaticamente nas requisições. O suporte a variáveis de ambiente no container (`ASAAS_API_KEY`) foi mantido apenas como fallback.

---

### Etapa 5: Teste Final no VPS

1. **Pelo terminal do VPS (verificação de infraestrutura e conectividade):**
   Acesse o terminal do VPS via SSH (`ssh root@2.25.181.69`) e rode o script de teste:

   ```bash
   bash /root/sbjur-asaas/02-testar-endpoints.sh https://api.advdouglaspsantos.com.br
   ```

   **Resultado esperado no terminal:**
   - ✅ Kong interno respondeu com sucesso;
   - ✅ Conexão externa com o Kong e Edge Function BEM-SUCEDIDA (retornando JSON válido, sem erro 405 do nginx).

2. **Pelo sistema SBJur no navegador (teste fim-a-fim de sincronização):**
   - Acesse **Clientes** no menu lateral e abra a ficha de um cliente real.
   - Clique no botão **"Sincronizar com Asaas"**.
   - O cliente será criado/atualizado no Asaas imediatamente e o badge/status indicará sucesso.
   - Acesse **Financeiro > Conciliação** e clique em **"Importar Extrato Asaas"** para conferir as movimentações do período.

---

## 💼 Como Usar a Integração no DPSjur (100% Manual, Sem Custos e Sem IA)

No sistema (`https://sistema.advdouglaspsantos.com.br`):

1. **Sincronizar Cliente**: na ficha de qualquer cliente, clique no botão para sincronizar com Asaas. O cliente será criado com o CPF e endereço cadastrados.
2. **Sincronizar Cobrança**: ao lançar honorários a receber no Financeiro, o botão "Enviar para Asaas" gera o Boleto/PIX no Asaas.
3. **Importar Extrato do Asaas**: na tela **Financeiro > Conciliação**, clique em **"Importar Extrato Asaas"**, selecione o período desejado (mês corrente por padrão) e confirme.
   - Entradas e saídas (contas a pagar) serão trazidas do Asaas.
   - O sistema fará o pré-casamento automático por regras simples (valor, data e cliente).
   - O que precisar de conferência fica destacado na fila de conciliação para você revisar com 1 clique.
4. **Importar Extrato em PDF**: no botão **"Importar Extrato (PDF)"**, envie o PDF da sua outra conta bancária (Sicoob, Caixa, etc.), visualize as linhas detectadas e importe diretamente para a mesma fila.
