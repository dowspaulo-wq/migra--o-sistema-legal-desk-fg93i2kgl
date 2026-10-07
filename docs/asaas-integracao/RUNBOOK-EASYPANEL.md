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

### Etapa 4: Cadastrar a chave de API do Asaas no Supabase

1. Obtenha sua chave no painel do **Asaas** (https://www.asaas.com > _Minha Conta_ > _Configurações da Conta_ > _Integrações_ > _Chaves de API_).
2. No EasyPanel, no serviço do **Supabase** (ou no container de edge-runtime/functions):
3. Na aba **Environment**, adicione:
   ```env
   ASAAS_API_KEY=$aact_sua_chave_real_do_asaas_aqui
   ASAAS_API_URL=https://api.asaas.com/v3
   ```
   _(Caso utilize o ambiente de testes sandbox do Asaas: `ASAAS_API_URL=https://api-sandbox.asaas.com/v3`)_
4. Clique em **Salvar** e **Restart**.

---

### Etapa 5: Teste Final no VPS

Acesse o terminal do VPS via SSH (`ssh root@2.25.181.69`) e rode o script de teste passando a nova URL da API:

```bash
bash /root/sbjur-asaas/02-testar-endpoints.sh https://api.advdouglaspsantos.com.br
```

**Resultado esperado:**

- ✅ Kong interno respondeu com sucesso;
- ✅ Conexão externa com o Kong e Edge Function BEM-SUCEDIDA (retornando JSON válido, sem erro 405 do nginx).

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
