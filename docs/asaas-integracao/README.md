# Kit de Integração Asaas — DPSjur / SBJur (Supabase Self-Hosted no VPS)

Este kit fornece todas as instruções e scripts para disponibilizar e testar as **Edge Functions do Asaas** no Supabase Self-Hosted rodando no VPS Hostinger via **EasyPanel**, atendendo ao fluxo 100% manual por botões confirmado pelo Douglas.

---

## 🎯 O que este Kit entrega

1. **Deploy das Edge Functions no VPS**:
   - `asaas-integration`: sincronização de clientes, geração de cobranças (PIX/Boleto), cancelamento de pagamentos, sincronização de histórico e **importação de extrato financeiro (entradas e contas a pagar/saídas)** direto para a fila de conciliação.
   - `asaas-webhook`: pronto para quando o Douglas desejar baixa automática sem intervenção (por enquanto tudo pode ser operado via botões manuais).
2. **Sem IA e Sem Custos**: tudo roda no VPS Hostinger e no navegador, sem consumo de créditos ou modelos de IA.
3. **Ambiente Configurável**: suporta chave de produção ou sandbox via `ASAAS_API_KEY` e URL base configurável via `ASAAS_API_URL` (padrão: `https://api.asaas.com/v3`).

---

## 📁 Arquivos do Kit

| Arquivo | Função |
| :--- | :--- |
| **`01-implantar-funcoes-vps.sh`** | Script bash autônomo para baixar e copiar as funções para o contêiner de Edge Functions do Supabase no EasyPanel. |
| **`02-testar-endpoints.sh`** | Script de teste rápido com `curl` para checar CORS e status de execução dos endpoints. |
| **`RUNBOOK-EASYPANEL.md`** | Passo a passo com telas do EasyPanel para configurar variáveis de ambiente e testar. |

---

## 🚀 Como Executar no Terminal do VPS (1 Comando)

No terminal do VPS (`ssh root@2.25.181.69`), execute:

```bash
mkdir -p /root/sbjur-asaas && cd /root/sbjur-asaas && \
curl -sSf -L -H "Accept: application/vnd.github.v3.raw" -H "User-Agent: DPSjur" https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/docs/asaas-integracao/01-implantar-funcoes-vps.sh?ref=main -o 01-implantar-funcoes-vps.sh && \
curl -sSf -L -H "Accept: application/vnd.github.v3.raw" -H "User-Agent: DPSjur" https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/docs/asaas-integracao/02-testar-endpoints.sh?ref=main -o 02-testar-endpoints.sh && \
bash 01-implantar-funcoes-vps.sh
```

---

## ⚙️ Configuração de Variáveis de Ambiente no EasyPanel

Acesse o **EasyPanel** (`http://2.25.181.69:3000`), vá no projeto onde está o Supabase:

1. Clique no serviço do **Supabase** (ou especificamente no container de **functions/edge-runtime** se estiver em serviço separado).
2. Na aba **Environment**, adicione:
   ```env
   ASAAS_API_KEY=$aact_sua_chave_real_do_asaas_aqui
   ASAAS_API_URL=https://api.asaas.com/v3
   ```
   *(Caso queira testar em sandbox antes: use a chave do sandbox e `ASAAS_API_URL=https://api-sandbox.asaas.com/v3`)*
3. Clique em **Save & Restart**.

---

## 🧪 Testando os Endpoints

Após salvar e reiniciar, execute no terminal do VPS:

```bash
bash /root/sbjur-asaas/02-testar-endpoints.sh
```

A saída esperada indicará que o endpoint `/functions/v1/asaas-integration` está respondendo em JSON.

---

## 🔔 Ativação Futura do Webhook (Opcional)

Por enquanto, o Douglas confirmou que **prefere a sincronização 100% por botões manuais**.

Quando quiser ativar a baixa automática em tempo real:
1. Acesse o painel do Asaas > Configurações > Integrações > Webhooks.
2. Crie um Webhook apontando para:
   `https://sistema.advdouglaspsantos.com.br/functions/v1/asaas-webhook`
3. Eventos recomendados: `Cobrança recebida`, `Cobrança confirmada`, `Cobrança estornada`.
