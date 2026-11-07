# DPSjur - Ativação do Módulo de Gestão de Leads no VPS Hostinger

Este guia documenta a aplicação das tabelas, políticas de segurança, índices e colunas configuráveis do **Módulo de Gestão de Leads** no banco de dados de produção do VPS (Hostinger - EasyPanel / Supabase Self-Hosted).

---

## 🔍 Contexto do Problema e Causa Raiz

Ao acessar a aba **Leads** (`https://sistema.advdouglaspsantos.com.br/leads`), o frontend tenta consultar:

1. `public.leads`
2. `public.lead_interactions`
3. As colunas de listas configuráveis da tabela `public.settings` (`leadAreas`, `leadSubjects`, `leadOrigins`, `leadStages`, `leadInteractionTypes`)

Como as migrations foram homologadas na nuvem durante o desenvolvimento, essas tabelas e colunas ainda **não haviam sido aplicadas no PostgreSQL do VPS de produção**. Por conta disso, o PostgREST retornou erro de tabela inexistente e o app exibiu o toast:

> _"Erro ao carregar leads — Não foi possível buscar os leads. Verifique sua conexão."_

O script `docs/vps/12-modulo-leads-vps.sh` resolve esse problema de ponta a ponta de forma **100% segura, não destrutiva e estritamente idempotente**.

---

## 🛡️ O que o script `12-modulo-leads-vps.sh` executa

1. **Varredura e Eleição Automática**:
   - Varre todos os contêineres Docker do VPS e descobre o contêiner e o banco que possuem o maior número de processos (`cases`) e clientes (`clients`).
   - Evita bancos de template ou contêineres secundários vazios (ex: Doug/dpsjur).
2. **Tabelas do Módulo de Leads**:
   - `public.leads`: cadastro de potenciais clientes, dados de contato, etapa do funil, prioridade, responsável, campanha e rastreio de conversão.
   - `public.lead_interactions`: histórico de ligações, reuniões, mensagens, tentativas e mudanças de etapa.
3. **Índices de Performance e Prevenção de Duplicidade**:
   - `idx_leads_stage`, `idx_leads_next_contact`, `idx_leads_responsible`, `idx_leads_created_at`
   - `idx_lead_interactions_lead`, `idx_lead_interactions_occurred`
   - Índices únicos parciais contra duplicidade por telefone e e-mail: `uq_leads_phone_not_empty` e `uq_leads_email_not_empty`
4. **Trigger e Função**:
   - `handle_leads_updated_at()` e trigger `trg_leads_updated_at` para manutenção automática da coluna `updated_at`.
5. **Políticas de Acesso (RLS)**:
   - Row Level Security ativado em `leads` e `lead_interactions`.
   - Políticas para role `authenticated` (SELECT, INSERT, UPDATE, DELETE) e permissões completas para `service_role`.
6. **Listas Configuráveis em `public.settings`**:
   - Remoção defensiva de eventuais colunas em minúsculas legadas (`leadorigins`, `leadstages`, `leadinteractiontypes`).
   - Criação das 5 colunas oficiais em **camelCase**: `"leadAreas"`, `"leadSubjects"`, `"leadOrigins"`, `"leadStages"`, `"leadInteractionTypes"`.
   - Inicialização segura com `COALESCE` para os valores padrão de áreas, assuntos, origens, etapas do funil e tipos de interação (não altera valores caso o usuário já os tenha configurado).
7. **Recarga do PostgREST**:
   - Dispara `NOTIFY pgrst, 'reload schema';` e reinicia o contêiner do PostgREST para reconstruir o cache de tabelas e colunas.
8. **Conferência Rigorosa**:
   - Valida 8 itens com relatório honesto em tela `[OK] / [FALHA]`.

---

## 🚀 Como Executar no VPS (Passo a Passo)

> **Importante (Regra do Projeto):** Não use `curl ... | bash` direto pelo terminal, pois scripts interativos ou complexos podem falhar por falta de pipe buffer. Baixe primeiro o arquivo para `/root/` e execute com `bash`.

### 1. Conecte-se ao VPS via SSH

```bash
ssh root@2.25.181.69
```

### 2. Baixe o script para `/root`

```bash
cd /root
curl -fsSL -o 12-modulo-leads-vps.sh "https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/vps/12-modulo-leads-vps.sh"
```

_(Alternativa via Git, caso o repositório já esteja clonado no VPS: `cd /root/migra--o-sistema-legal-desk-fg93i2kgl && git pull && bash docs/vps/12-modulo-leads-vps.sh`)_

### 3. Execute o script

```bash
bash /root/12-modulo-leads-vps.sh
```

---

## ✅ O que esperar na tela de sucesso

Ao finalizar a execução, você verá o checklist com todos os 8 itens marcados como **[OK]**:

```text
[4/4] Conferência do schema no PostgreSQL:
   - 1. Tabela 'leads':                  EXISTE [OK]
   - 2. Tabela 'lead_interactions':      EXISTE [OK]
   - 3. Colunas em 'leads':              28/28 colunas verificadas [OK]
   - 4. Colunas em 'lead_interactions':  9/9 colunas verificadas [OK]
   - 5. Row Level Security (RLS):        HABILITADO EM AMBAS AS TABELAS [OK]
   - 6. Políticas RLS aplicadas:         4 em leads + 4 em interações [OK]
   - 7. Índices e restrições únicas:     8/8 índices verificados [OK]
   - 8. Colunas de listas em settings:   5/5 colunas camelCase verificadas [OK]

=====================================================================
🎉 MÓDULO DE LEADS E LISTAS CONFIGURÁVEIS PRONTOS NO VPS! [OK]
=====================================================================
```

---

## 🔄 Teste de Idempotência

O script foi projetado para ser executado quantas vezes forem necessárias. Se você rodar o comando:

```bash
bash /root/12-modulo-leads-vps.sh
```

uma segunda vez consecutiva, ele irá detectar que todas as estruturas já existem, não duplicará nenhum dado nem gerará erro, concluindo novamente com status **[OK]**.

---

## 🌐 Verificação no Navegador

1. Acesse o sistema de produção: `https://sistema.advdouglaspsantos.com.br/leads`
2. Pressione `Ctrl + F5` (ou `Cmd + Shift + R`) para limpar cache do navegador.
3. O toast de erro desaparecerá e o painel exibirá as métricas do funil zeradas, pronto para o cadastro do primeiro lead ou importação de campanhas!
