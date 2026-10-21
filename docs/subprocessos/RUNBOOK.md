# DPSjur / SBJur — Runbook: Correção da Coluna noFees (Subprocessos) no VPS

Guia prático para o Douglas executar no VPS e resolver de forma definitiva o erro:
`Could not find the 'noFees' column of 'cases' in the schema cache` ao cadastrar processos/subprocessos.

---

## 1. Por que este erro aconteceu?

No ambiente VPS (Hostinger / EasyPanel / Docker), existem múltiplos contêineres e bancos de dados (ex.: contêiner padrão do Postgres vs `sbjur-local_supabase-db-1` onde estão os dados reais do escritório).

O primeiro script (`01-adicionar-no-fees-subprocessos-vps.sh`) selecionava apenas o primeiro contêiner encontrado via `docker ps | head -n 1`, podendo aplicar a alteração no contêiner errado — o mesmo padrão que ocorreu anteriormente com a coluna `googleServiceAccount` em `settings`.

O novo script **`02-diagnostico-coluna-no-fees-vps.sh`**:

1. Varre **todos** os contêineres PostgreSQL do VPS.
2. Identifica com precisão o banco **real** da aplicação (aquele que contém a tabela `cases` com os processos do escritório).
3. Cria a coluna `noFees` de forma idempotente (`boolean NOT NULL DEFAULT false`).
4. Concede as permissões (`GRANT`) nas roles da API (`authenticated`, `anon`, `service_role`) e garante RLS.
5. Aplica de forma preventiva em qualquer outro banco que contenha a tabela `cases`.
6. Força a recarga imediata do schema cache no PostgREST (`NOTIFY pgrst` e `docker restart` em todos os contêineres REST).
7. Faz um **teste HTTP real** contra a API do PostgREST confirmando que a coluna já é servida.
8. Exibe um resumo consolidado legível com `[OK]`.

---

## 2. Como executar no terminal do VPS

Conecte no terminal do seu VPS como **root** via SSH:

```bash
ssh root@2.25.181.69
```

### Opção A: Comando em linha única (Recomendado)

Cole o comando abaixo no terminal e aperte **Enter**:

```bash
curl -sSL "https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/subprocessos/02-diagnostico-coluna-no-fees-vps.sh" -o /root/02-diagnostico-coluna-no-fees-vps.sh && bash /root/02-diagnostico-coluna-no-fees-vps.sh
```

---

### Opção B: Em dois passos separados

Se preferir baixar antes e conferir:

**Passo 1 — Baixar o script:**

```bash
curl -sSL "https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/subprocessos/02-diagnostico-coluna-no-fees-vps.sh" -o /root/02-diagnostico-coluna-no-fees-vps.sh
```

**Passo 2 — Executar o diagnóstico e correção:**

```bash
bash /root/02-diagnostico-coluna-no-fees-vps.sh
```

---

## 3. Resultado esperado no terminal

O script imprimirá um relatório em 5 etapas finalizando com:

```
=====================================================================
                      RESUMO DO DIAGNÓSTICO
=====================================================================
1. Contêineres PostgreSQL examinados:
   - Contêiner: sbjur-local_supabase-db-1 | Banco: postgres | Cases: sim | Clients: 354 ⭐ (BANCO REAL)

2. Banco Real Identificado:
   - Contêiner: sbjur-local_supabase-db-1
   - Banco:     postgres
   - Processos: 550 registros
   - Coluna no Postgres: EXISTE [OK]

3. Contêineres PostgREST / REST Reiniciados:
   - sbjur-local_supabase-rest-1 (reiniciado com sucesso)

4. Teste HTTP via API REST:
   - Resultado: COLUNA SERVIDA NO SCHEMA CACHE [OK]
   - Endpoint:  http://127.0.0.1:8000/rest/v1/cases?select=id,noFees&limit=1
=====================================================================

✅ DIAGNÓSTICO E CORREÇÃO CONCLUÍDOS COM SUCESSO!
A coluna 'noFees' está criada, configurada com permissões ativas e recarregada no schema cache.
```

---

## 4. Teste no navegador após executar o script

1. Abra o navegador em: **https://sistema.advdouglaspsantos.com.br/processos**
2. Se necessário, pressione `Ctrl + F5` para atualizar o cache do navegador.
3. Clique em **"+ Novo Processo"** ou cadastre um subprocesso em um processo existente.
4. Salve o cadastro. O erro **"Could not find the 'noFees' column of 'cases' in the schema cache"** não voltará a ocorrer.
