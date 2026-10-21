                      RESUMO DA CORREÇÃO

=====================================================================

1. Banco Real Identificado:
   - Contêiner: dpsjur_dpsjur-db.1...
   - Usuário: postgres (ou usuário configurado no EasyPanel)
   - Banco: postgres
2. Status 'Realizado':
   - Registros restantes: 0 [OK] (100% extinto e unificado como 'Pago')
3. Webhook Asaas & Edge Runtime:
   - Gravação de status: 'Pago' (padrão único)
   - Casamento resiliente: Ativo (une cobrança à parcela existente)
   - # Edge containers: atualizado(s) e reiniciado(s)

# ✅ OPERAÇÃO CONCLUÍDA COM SUCESSO! [OK]

=====================================================================
RESUMO DA CORREÇÃO
=====================================================================

1. Banco Real Identificado:
   - Contêiner: sbjur-local_supabase-db-1
   - Usuário: postgres (ou usuário configurado no EasyPanel)
   - Banco: postgres
2. Status 'Realizado':
   - Registros restantes: 0 [OK] (100% extinto e unificado como 'Pago')
3. Webhook Asaas & Edge Runtime:
   - Gravação de status: 'Pago' (padrão único)
   - Casamento resiliente: Ativo (une cobrança à parcela existente)
   - # Edge containers: 1 atualizado(s) e reiniciado(s)

✅ OPERAÇÃO CONCLUÍDA COM SUCESSO! [OK]# DPSjur / SBJur — Runbook: Correção de Status 'Realizado' -> 'Pago' & Webhook Asaas no VPS

Guia prático para o Douglas executar no VPS Hostinger (EasyPanel / Docker) para corrigir o status do módulo financeiro e o webhook do Asaas.

---

## 1. O que este script faz

O script **`04-consertar-realizado-vps.sh`**:

1. **Auto-descobre** o contêiner real do PostgreSQL no VPS e o usuário/superusuário autêntico via variáveis de ambiente (`POSTGRES_USER`) com fallback testado dinamicamente (`postgres`, `supabase_admin`, etc.), eliminando o erro `FATAL: role "supabase_admin" does not exist`.
2. Converte retroativamente qualquer lançamento com status **"Realizado"** ou **"Paga"** para **"Pago"** (status unificado consolidado no financeiro).
3. **Unifica duplicatas** criadas pelo webhook Asaas quando casam com parcelas existentes do parcelamento (atualiza a parcela original para "Pago" com seu respectivo `asaas_id` e data de pagamento, removendo a duplicata avulsa).
4. Garante as colunas `lastAsaasSyncAt` e `lastSicoobImportAt` na tabela `settings`.
5. Atualiza o código fonte da Edge Function `asaas-webhook` no host e dentro dos contêineres do Edge Runtime (`edge-runtime` / `functions`) do VPS para que novas notificações Asaas continuem gravando **"Pago"** e casando parcelas existentes por padrão.
6. Notifica o PostgREST (`NOTIFY pgrst, 'reload schema'`) e reinicia os serviços do PostgREST e Edge Runtime.
7. Exibe a conferência detalhada dos status na tela, certificando que a contagem de "Realizado" restante é **0**.
8. É **totalmente idempotente**: pode ser reexecutado com segurança a qualquer momento sem efeitos colaterais.

---

## 2. Como executar no terminal do VPS

Acesse seu terminal VPS via SSH como **root**:

```bash
ssh root@2.25.181.69
```

### Comando Único Recomendado (baixa e executa com bash, sem pipe direto):

Cole a linha abaixo no terminal e aperte **Enter**:

```bash
curl -sSL "https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/financeiro/04-consertar-realizado-vps.sh" -o /root/04-consertar-realizado-vps.sh && bash /root/04-consertar-realizado-vps.sh
```

> **Nota:** Como padrão em todo o projeto DPSjur no VPS, **nunca** utilize o pipe direto `curl ... | bash`. Baixar com `-o /root/...` e executar com `bash /root/...` evita que o stdin seja consumido e garante execução completa.

---

## 3. Resultado esperado no terminal

O script exibirá um relatório dividido em 5 etapas finalizando com:

```text
=====================================================================
                      RESUMO DA CORREÇÃO
=====================================================================
1. Banco Real Identificado:
   - Contêiner:          dpsjur_dpsjur-db.1...
   - Usuário:            postgres (ou usuário configurado no EasyPanel)
   - Banco:              postgres
2. Status 'Realizado':
   - Registros restantes: 0 [OK] (100% extinto e unificado como 'Pago')
3. Webhook Asaas & Edge Runtime:
   - Gravação de status:  'Pago' (padrão único)
   - Casamento resiliente: Ativo (une cobrança à parcela existente)
   - Edge containers:     atualizado(s) e reiniciado(s)
=====================================================================

✅ OPERAÇÃO CONCLUÍDA COM SUCESSO! [OK]
```

---

## 4. Conferência no Sistema

1. Abra o sistema no navegador: **https://sistema.advdouglaspsantos.com.br/financeiro**
2. Se necessário, pressione `Ctrl + F5` para atualizar o cache do navegador.
3. Observe que todos os lançamentos pagos exibem o status **Pago** e as duplicatas de parcelamento foram devidamente unificadas.
