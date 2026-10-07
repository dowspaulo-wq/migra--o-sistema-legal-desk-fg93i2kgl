# Runbook EasyPanel: Ativação das Funções Asaas no VPS

Este guia destina-se ao Douglas para cadastrar a chave de API do Asaas e habilitar os botões de sincronização financeira no DPSjur/SBJur.

---

### Passo 1: Obter a Chave de API no Asaas

1. Acesse sua conta no **Asaas** (https://www.asaas.com).
2. Vá em **Minha Conta** (menu superior direito) > **Configurações da Conta** > **Integrações**.
3. Na seção **Chaves de API**, gere uma nova chave de API (ou copie uma existente).
4. Guarde essa chave em local seguro (ela começa geralmente com `$aact_`).

---

### Passo 2: Configurar no EasyPanel do VPS

1. Acesse o painel **EasyPanel** no seu navegador:
   `http://2.25.181.69:3000` (ou o domínio do EasyPanel configurado).
2. Abra o projeto do **Supabase** (onde estão os containers de banco, auth, kong e functions).
3. Selecione o serviço que roda o **Supabase** (ou o container de functions).
4. Clique na aba **Environment**:
   - Adicione a linha:
     ```env
     ASAAS_API_KEY=$aact_sua_chave_aqui
     ```
   - (Opcional) Adicione a linha:
     ```env
     ASAAS_API_URL=https://api.asaas.com/v3
     ```
5. Clique no botão **Save** e em seguida em **Restart** no serviço.

---

### Passo 3: Executar a Implantação no VPS

Abra o terminal do VPS via SSH (`ssh root@2.25.181.69`) e cole:

```bash
mkdir -p /root/sbjur-asaas && cd /root/sbjur-asaas && \
curl -sSf -L -H "Accept: application/vnd.github.v3.raw" -H "User-Agent: DPSjur" https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/docs/asaas-integracao/01-implantar-funcoes-vps.sh?ref=main -o 01-implantar-funcoes-vps.sh && \
curl -sSf -L -H "Accept: application/vnd.github.v3.raw" -H "User-Agent: DPSjur" https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/docs/asaas-integracao/02-testar-endpoints.sh?ref=main -o 02-testar-endpoints.sh && \
bash 01-implantar-funcoes-vps.sh
```

---

### Passo 4: Como usar no DPSjur (Sem IA e Sem Custos)

No sistema (`https://sistema.advdouglaspsantos.com.br`):

1. **Sincronizar Cliente**: na ficha de qualquer cliente, clique no botão para sincronizar com Asaas. O cliente será criado com o CPF e endereço cadastrados.
2. **Sincronizar Cobrança**: ao lançar honorários a receber no Financeiro, o botão "Enviar para Asaas" gera o Boleto/PIX no Asaas.
3. **Importar Extrato do Asaas**: na tela **Financeiro > Conciliação**, clique em **"Importar Extrato Asaas"**, selecione o período desejado (mês corrente por padrão) e confirme.
   - Entradas e saídas (contas a pagar) serão trazidas do Asaas.
   - O sistema fará o pré-casamento automático por regras simples (valor, data e cliente).
   - O que precisar de conferência fica destacado na fila de conciliação para você revisar com 1 clique.
4. **Importar Extrato em PDF**: no botão **"Importar Extrato (PDF)"**, envie o PDF da sua outra conta bancária (Sicoob, Caixa, etc.), visualize as linhas detectadas e importe diretamente para a mesma fila.
