# Kit de Integração Asaas — DPSjur / SBJur (Supabase Self-Hosted no VPS)

Este kit fornece todas as instruções e scripts para disponibilizar e testar as **Edge Functions do Asaas** no Supabase Self-Hosted rodando no VPS Hostinger via **EasyPanel**, atendendo ao fluxo 100% manual por botões confirmado pelo Douglas.

---

## 🎯 O que este Kit entrega

1. **Deploy das Edge Functions no VPS**:
   - `asaas-integration`: sincronização de clientes, geração de cobranças (PIX/Boleto), cancelamento de pagamentos, sincronização de histórico e **importação de extrato financeiro (entradas e contas a pagar/saídas)** direto para a fila de conciliação.
   - `asaas-webhook`: pronto para quando o Douglas desejar baixa automática sem intervenção (por enquanto tudo pode ser operado via botões manuais).
2. **Sem IA e Sem Custos**: tudo roda no VPS Hostinger e no navegador, sem consumo de créditos ou modelos de IA.
3. **Ambiente Configurável**: suporta chave de produção ou sandbox via `ASAAS_API_KEY` e URL base configurável via `ASAAS_API_URL` (padrão: `https://api.asaas.com/v3`).
4. **Arquitetura de Gateway com Subdomínio Dedicado**: documentação completa para criação do subdomínio `api.advdouglaspsantos.com.br` apontando ao gateway Kong (porta 8000), garantindo acesso unificado a Auth, REST, Storage e Functions.

---

## 📁 Arquivos do Kit

| Arquivo | Função |
| :--- | :--- |
| **`01-implantar-funcoes-vps.sh`** | Script bash autônomo para baixar e copiar as funções para o contêiner de Edge Functions do Supabase no EasyPanel. |
| **`02-testar-endpoints.sh`** | Script de teste avançado com `curl`: aceita URL externa como argumento (`$1`), testa Kong interno na porta 8000 e URL externa com diagnóstico automático de 405 do nginx do frontend. |
| **`03-aplicar-migracao-asaas.sh`** | Script bash idempotente para criar as colunas `asaasApiKey` e `asaasApiUrl` na tabela `public.settings` no PostgreSQL local do VPS. |
| **`RUNBOOK-EASYPANEL.md`** | Passo a passo completo para o Douglas: configuração no Registro.br, subdomínio no EasyPanel, configuração da chave no SBJur e teste final. |

---

## 🔑 Configuração da Chave da API do Asaas (Dentro do App)

O EasyPanel no VPS utiliza template Compose com editor `docker-compose.yaml` vazio, impedindo a injeção confiável de variáveis nos contêineres internos do stack Supabase. Por esse motivo, a chave da API agora é gerenciada **diretamente dentro do SBJur**:

1. Acesse `https://sistema.advdouglaspsantos.com.br`.
2. Abra **Configurações** no menu lateral.
3. Acesse a aba **Integrações**.
4. Cole sua **Chave de API do Asaas** (campo com visualização protegida e botão mostrar/ocultar).
5. Confirme a **URL da API** (`https://api.asaas.com/v3`).
6. Clique em **Salvar Configurações do Asaas**.

*O app enviará a chave automaticamente nas requisições às Edge Functions (`x-asaas-api-key`). O fallback para variáveis de ambiente locais (`ASAAS_API_KEY`) continua suportado, mas é estritamente opcional.*

---

## 🛠️ Se a chave não salvar no app: rode `03-aplicar-migracao-asaas.sh` no VPS

### Explicação simples:
O sistema web guarda a chave da API numa "gaveta" chamada `asaasApiKey` dentro da tabela `settings` do banco de dados. No banco de dados que roda dentro do seu VPS, essa gaveta ainda não existia. Por isso, ao tentar salvar a chave, o banco rejeitava a gravação e o valor não persistia (o badge voltava a "Chave ausente").

### Como resolver no VPS em 1 minuto:
Acesse o terminal do VPS via SSH (`ssh root@2.25.181.69`) e rode o comando:

```bash
mkdir -p /root/sbjur-asaas && cd /root/sbjur-asaas && \
curl -sSf -L -H "Accept: application/vnd.github.v3.raw" -H "User-Agent: DPSjur" https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/docs/asaas-integracao/03-aplicar-migracao-asaas.sh?ref=main -o 03-aplicar-migracao-asaas.sh && \
bash 03-aplicar-migracao-asaas.sh
```

O script:
- Localiza automaticamente o contêiner do PostgreSQL do Supabase no EasyPanel;
- Executa o comando seguro `ALTER TABLE public.settings ADD COLUMN IF NOT EXISTS "asaasApiKey" text;`;
- Executa o comando seguro `ALTER TABLE public.settings ADD COLUMN IF NOT EXISTS "asaasApiUrl" text DEFAULT 'https://api.asaas.com/v3';`;
- Confirma que as colunas existem e exibe `✅ MIGRAÇÃO CONCLUÍDA COM SUCESSO!`.

Após rodar o script, volte à tela de **Configurações → Integrações** no navegador, cole a chave e clique em **Salvar Configurações do Asaas**. O badge mudará para **Configurada** e o valor não sumirá mais.

---

## 🌐 Configuração do Subdomínio da API (`api.advdouglaspsantos.com.br`)

### Diagnóstico do erro "405 Not Allowed"
Quando o app tenta chamar `https://sistema.advdouglaspsantos.com.br/functions/v1/...`, a requisição atinge o **nginx do frontend**, que rejeita requisições POST com status 405 porque ele serve apenas arquivos estáticos do React e não conhece as rotas do Supabase/Kong.

Para resolver, o Kong deve possuir seu próprio subdomínio público:

1. **Registro.br**:
   - Entrar na zona de DNS de `advdouglaspsantos.com.br`;
   - Criar registro **A** com nome `api` apontando para o IP **`2.25.181.69`**.
2. **EasyPanel**:
   - Abrir o projeto `sbjur-local` > cartão **`supabase`** (tipo Compose);
   - Na aba **Domains**, adicionar **`api.advdouglaspsantos.com.br`**, definindo a porta **`8000`** e HTTPS ativado.
3. **Frontend dpsjur-web**:
   - No EasyPanel > serviço `dpsjur-web` > aba **Environment**;
   - Definir `VITE_SUPABASE_URL=https://api.advdouglaspsantos.com.br`;
   - Clicar em **Save** e **Restart** (o `docker-entrypoint.sh` atualiza o `/env.js` dinâmico em segundos, sem necessidade de rebuild).
4. **Impacto no sistema**:
   - **Login, banco (REST) e anexos (Storage)** continuam funcionando normalmente porque o Kong é o gateway que serve `/auth/v1`, `/rest/v1`, `/storage/v1` e `/functions/v1`.
   - **O domínio `sistema.advdouglaspsantos.com.br`** permanece inalterado para acesso ao app pelos advogados.

---

## 🚀 Como Executar no Terminal do VPS (Instalação das Funções)

No terminal do VPS (`ssh root@2.25.181.69`), execute:

```bash
mkdir -p /root/sbjur-asaas && cd /root/sbjur-asaas && \
curl -sSf -L -H "Accept: application/vnd.github.v3.raw" -H "User-Agent: DPSjur" https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/docs/asaas-integracao/01-implantar-funcoes-vps.sh?ref=main -o 01-implantar-funcoes-vps.sh && \
curl -sSf -L -H "Accept: application/vnd.github.v3.raw" -H "User-Agent: DPSjur" https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/docs/asaas-integracao/02-testar-endpoints.sh?ref=main -o 02-testar-endpoints.sh && \
bash 01-implantar-funcoes-vps.sh
```

---

## ⚙️ Configuração de Variáveis de Ambiente no EasyPanel (OPCIONAL / Não Necessário)

Como a chave agora é salva na interface do SBJur (em **Configurações → Integrações**), **não é necessário cadastrar variáveis de ambiente no Compose do EasyPanel**. Caso deseje manter um fallback local no container do edge-runtime, a variável `ASAAS_API_KEY` continuará sendo reconhecida pelas funções.

---

## 🧪 Testando os Endpoints

Após configurar o subdomínio e as variáveis, execute no terminal do VPS:

```bash
# Teste com a URL do subdomínio da API (recomendado):
bash /root/sbjur-asaas/02-testar-endpoints.sh https://api.advdouglaspsantos.com.br

# Ou teste padrão (caso ainda aponte para sistema., o script emitirá o diagnóstico exato):
bash /root/sbjur-asaas/02-testar-endpoints.sh
```

A saída esperada indicará que o endpoint `/functions/v1/asaas-integration` está respondendo em JSON com status 200/204.

---

## 🔔 Ativação Futura do Webhook (Opcional)

Por enquanto, o Douglas confirmou que **prefere a sincronização 100% por botões manuais**.

Quando quiser ativar a baixa automática em tempo real:
1. Acesse o painel do Asaas > Configurações > Integrações > Webhooks.
2. Crie um Webhook apontando para:
   `https://api.advdouglaspsantos.com.br/functions/v1/asaas-webhook`
3. Eventos recomendados: `Cobrança recebida`, `Cobrança confirmada`, `Cobrança estornada`.
