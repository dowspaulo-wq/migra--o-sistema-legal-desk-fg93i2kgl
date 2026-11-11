# Backup Independente dos DOIS PostgreSQL da VPS — Banco A (PG15) e Banco B (PG18)

**Projeto:** DPSjur / SBJur (VPS Hostinger, EasyPanel/Docker)
**Status:** PENDENTE DE VALIDAÇÃO / IMPLANTAÇÃO — autorização expressa de Douglas obrigatória antes de qualquer execução, agendamento ou alteração na VPS.
**Versão dos scripts:** v2.1.1 (correções pós-auditoria do commit 1f36a02 / v2.1.0)
**Escopo desta versão:** SOMENTE código e documentação do repositório. Nenhum comando foi executado na VPS; pg_hba.conf, usuários, permissões do PostgreSQL, contêineres, EasyPanel e crontab NÃO foram alterados.
**Auditoria independente da v2.1.0 (commit 1f36a02):** sintaxe aprovada (`bash -n`); 2 FALHAS funcionais apontadas e corrigidas nesta v2.1.1 — ver seção 2.1.

## 1. Visão geral — dois bancos DISTINTOS, duas rotinas INDEPENDENTES

|                              | Banco A                                                | Banco B                                                                        |
| ---------------------------- | ------------------------------------------------------ | ------------------------------------------------------------------------------ |
| Projeto                      | `sbjur-local` (EasyPanel, compose)                     | `dpsjur` (EasyPanel, Docker **Swarm**)                                         |
| Contêiner                    | `sbjur-local_supabase-db-1` (NOME FIXO)                | resolvido via serviço Swarm `dpsjur_dpsjur-db` (NÃO é nome literal)            |
| PostgreSQL                   | **15.8** (major 15)                                    | **18** (não presumido como banco principal — confirmação operacional pendente) |
| Usuário                      | `postgres`                                             | `Doug`                                                                         |
| Banco                        | `postgres`                                             | `dpsjur`                                                                       |
| Script                       | `docs/vps/22-backup-banco-a-sbjur-local.sh`            | `docs/vps/23-backup-banco-b-dpsjur.sh`                                         |
| Lib comum                    | `docs/vps/lib/backup-lib.sh` (fonte única das funções) | idem                                                                           |
| Base de destino              | `/root/sbjur-backups-dupla/banco-a`                    | `/root/sbjur-backups-dupla/banco-b`                                            |
| .pgpass (host)               | `$HOME/.pgpass-bk-banco-a` (chmod 600)                 | `$HOME/.pgpass-bk-banco-b` (chmod 600)                                         |
| .pgpass (contêiner, efêmero) | `/tmp/.pgpass-bk-banco-a-<sessão-exclusiva>`           | `/tmp/.pgpass-bk-banco-b-<sessão-exclusiva>`                                   |
| Lock                         | `<base>/.lock-banco-a`                                 | `<base>/.lock-banco-b`                                                         |

**A rotina antiga `/root/sbjur-backups/backup.sh` (Banco A, diária 03h) permanece
intocada.** Nenhum script desta solução lê, altera, move ou exclui seus arquivos:
os destinos são diretórios NOVOS (`sbjur-backups-dupla/`), com prefixos próprios
(`sbsjur-*` / `dpsjur-*`), e a retenção só considera esses prefixos.

## 2. Correções da auditoria (d510fd9) — onde cada uma está

| #   | Correção obrigatória                                                      | Implementação                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| --- | ------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A   | Conexão psql EXPLÍCITA em todas as verificações; Banco B sem nome literal | `bk_psql_in_container` sempre roda com `-U <usuário> -d <banco> -p <porta>`; Banco B resolve o contêiner por `bk_resolve_swarm_container` (serviço Swarm, igualdade exata, recusa ausente/ambíguo)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| B   | Credenciais disponíveis AO pg_dump (dentro do contêiner)                  | `bk_stage_pgpass_into_container`: caminho interno EXCLUSIVO por execução (`/tmp/.pgpass-bk-banco-<a\|b>-<data>-<pid>-<aleatório>`, caminho preexistente é RECUSADO, nada é sobrescrito) + `chmod 600` VERIFICADO por stat (permissão errada é FATAL) + `chown <usuário>`; pg_dump/psql rodam com `env PGPASSFILE=<caminho da sessão>` no `docker exec`. **Não se presume que o PGPASSFILE do host chega ao docker exec — ele NÃO chega.** A limpeza remove SOMENTE o caminho registrado na sessão (`bk_remove_pgpass` recusa caminho divergente) e falha de limpeza é comunicada (stderr + log), nunca silenciosa. Nada é alterado no PostgreSQL (pg_hba.conf, usuários, permissões — proibido nesta etapa) |
| C   | Captura de erro SEM inversão                                              | `rc=0; if bk_run_dump_pipeline "${OUT_FILE}"; then :; else rc=$?; fi` — o `!` original invertia o status (rc=0 na falha)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| D   | Sem sobrescrita; publicação atômica                                       | dump em temporário EXCLUSIVO (mktemp no MESMO diretório do destino, chmod 600), validação (`bk_validate_dump`) e publicação por `mv -n` no mesmo filesystem com PROVA posterior (`bk_publish_dump` distingue recusa por corrida TOCTOU de publicação bem-sucedida; destino existente NUNCA sobrescrito, inclusive em concorrência); `chmod 600` do publicado é VERIFICADO e FATAL em falha (nenhum `chmod ... \|\| true`); limpeza só remove o nome próprio (`bk_tmp_cleanup`)                                                                                                                                                                                                                              |
| K   | pg_dump/psql — compatibilidade de opções entre PG15 e PG18                | `-X` REMOVIDA do pg_dump (mecanismo obsoleto que EXIGE nome de opção como argumento — `-X -p` consumiria o `-p` e abortaria); `psql -X` (= `--no-psqlrc`) mantida, válida e idêntica em PG15 e PG18. Demais opções (`-A -t -q -p -U -d -c` do psql; `-p -U -d` do pg_dump) estáveis nas duas versões. Escolha documentada nos comentários de cada comando                                                                                                                                                                                                                                                                                                                                                   |
| E   | Lock sem corrida; fallback mkdir coerente                                 | flock REUTILIZÁVEL: o arquivo de lock permanece no disco e é aberto em modo APPEND (nunca trunca lock alheio); a exclusividade vem do flock (não da existência do arquivo) — a execução seguinte adquire normalmente. Fallback mkdir com recuperação de stale APENAS quando o PID registrado não existe mais (kill -0), com quarentena por mv atômico antes da remoção; `bk_release_lock` só remove com PID próprio registrado                                                                                                                                                                                                                                                                              |
| F   | Retenção honesta e restrita                                               | MODO OBSERVAÇÃO por padrão; com `--aplicar-retencao`: apenas arquivos REGULARES do prefixo do PRÓPRIO banco no diretório correspondente, sem links simbólicos, validação individual (gzip -t + tamanho) antes de remover, rotina antiga nunca tocada                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| G   | Falhas produzem FALHA final                                               | `set -o pipefail` + `PIPESTATUS` separados p/ pg_dump e gzip; traps EXIT/INT/TERM/HUP; veredito SUCESSO/FALHA no log (`bk_finalize_session`); códigos de saída distintos por etapa                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |

## 2.1 Correções da auditoria da v2.1.0 (commit 1f36a02) — FALHAS 1 e 2

| #       | Falha apontada pela auditoria                                                                                                                                                                         | Correção nesta v2.1.1                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| ------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| FALHA 1 | Compatibilidade ID×nome no Banco B: `bk_resolve_swarm_container` retorna o ID do contêiner, mas `bk_verify_container` comparava esse identificador com NOMES de `docker ps` — o casamento nunca batia | correção **M** do backup-lib.sh: `bk_verify_container` agora aceita o IDENTIFICADOR propagado pelo chamador (ID OU nome), comprovado por IGUALDADE EXATA contra a coluna ID ou a coluna Names de `docker ps`. O Banco B chega com o ID (saída de `bk_resolve_swarm_container`); o Banco A continua com o nome fixo. Mais de uma correspondência é FATAL; sem regex genérica, sem casamento parcial. Continuam exigidos: serviço `dpsjur_dpsjur-db` exclusivo, exatamente 1 contêiner elegível, versão major 18, usuário `Doug`, banco `dpsjur`; ausente/incorreto/ambíguo é rejeitado.                  |
| FALHA 2 | Código de saída original perdido: `bk_finalize_session` lia `$?` APÓS as operações de limpeza do cleanup — podia registrar SUCESSO com falha anterior                                                 | correção **N** (lib + scripts A e B): o código ORIGINAL é capturado NO INÍCIO do cleanup (`cleanup $?` no trap EXIT) e transmitido EXPLICITAMENTE por argumento a `bk_finalize_session` (junto com flag dedicada `cleanup_failed` de falha de limpeza). SUCESSO só é registrado quando o código original é 0 E a limpeza integral concluiu; falha de limpeza é comunicada em stderr+log SEM ocultar nem substituir o erro original; o script sai com o código ORIGINAL — e com `BK_EXIT_CLEANUP_FAIL=29` quando o backup concluiu mas a limpeza falhou (falha de limpeza nunca é mascarada por exit 0). |

**Três verificações NÃO equivalentes (nunca confundir no relatório):**

1. **Integridade gzip** (`gzip -t`) — o ARQUIVO está íntegro como bytes comprimidos;
2. **Consistência do dump** — o CONTEÚDO é um dump pleno e coerente do banco (não é provado por gzip);
3. **Sucesso de restauração isolada** — o dump restaura num PostgreSQL limpo e as contagens conferem (seção 6).

`gzip -t` OK + veredito SUCESSO do backup **NÃO** significam backup restaurável. O pré-requisito para considerar a solução pronta é a restauração isolada de CADA banco (seção 6).

## 3. Pré-requisitos antes da primeira execução

**Lição do projeto (registrar sempre):** NÃO usar `curl | bash` — baixar o
arquivo e rodar via SSH com comando.

### 3.1 Implantação dos arquivos (sem executar ainda)

```bash
# Na VPS, copiar os três arquivos (ex.: scp a partir do repositório clonado,
# ou baixar via URL raw — nunca curl | bash):
#   docs/vps/22-backup-banco-a-sbjur-local.sh  -> /root/
#   docs/vps/23-backup-banco-b-dpsjur.sh       -> /root/
#   docs/vps/lib/backup-lib.sh                 -> /root/sbjur-backups-dupla/lib/
chmod 700 /root/22-backup-banco-a-sbjur-local.sh /root/23-backup-banco-b-dpsjur.sh
chmod 600 /root/sbjur-backups-dupla/lib/backup-lib.sh
```

### 3.2 Credenciais — o que precisa existir DENTRO de cada contêiner

A solução NÃO altera `pg_hba.conf`, usuários ou permissões do PostgreSQL. Ela
EXIGE que o cenário abaixo já exista (conferir na VPS ANTES da primeira
execução — passo de implantação, não automatizado):

1. **Formato do .pgpass do host:** 5 campos separados por `:` —
   `localhost:5432:<banco>:<usuário>:<senha>`; senha NÃO pode conter `:` sem
   escape (`\:`); chmod 600 obrigatório (o script recusa outras permissões).
   - Banco A: `localhost:5432:postgres:postgres:<senha do postgres>`
   - Banco B: `localhost:5432:dpsjur:Doug:<senha do Doug>`
2. **O pg_hba.conf de cada contêiner precisa AUTORIZAR a forma de conexão
   usada pelo pg_dump/psql:** conexão TCP local dentro do contêiner
   (`127.0.0.1` ou o socket local do contêiner) para o usuário/banco do
   respectivo banco, com método compatível com `.pgpass` (md5/scram). **Conferir
   manualmente em cada contêiner** (cat no pg_hba.conf efetivo) durante a
   implantação — se a autenticação falhar, o script aborta com exit 13/28 e
   NADA é gravado; ajuste no PostgreSQL é decisão futura de Douglas.
3. **O usuário da conexão precisa poder executar pg_dump** (Banco A: `postgres`
   já é superusuário; Banco B: `Doug` precisa de permissão de leitura sobre
   todas as tabelas do banco `dpsjur` — conferir na implantação).
4. **A senha é copiada para DENTRO do contêiner na hora do dump** (`docker cp`
   para `/tmp/.pgpass-bk-banco-{a,b}-<data>-<pid>-<aleatório>` — caminho
   EXCLUSIVO de cada execução; um caminho preexistente é RECUSADO, nunca
   sobrescrito; chmod 600 verificado por stat, dono = usuário da conexão) e
   REMOVIDA ao final da sessão (inclusive em falha, pelo trap; somente o
   caminho registrado na sessão é removido). Ela nunca aparece em argumento de
   comando, log ou arquivo versionado.

### 3.3 Banco B — Docker Swarm

- O nó onde o cron roda precisa ser **manager** do Swarm (os comandos
  `docker service ls` / `docker service ps` exigem). Se o nó não for manager,
  o script aborta com exit 13 — sem adivinhação.
- O contêiner é resolvido a CADA execução por `bk_resolve_swarm_container`:
  serviço `dpsjur_dpsjur-db` por igualdade exata → tarefas `desired-state=running`
  → cruzamento com `docker ps` deste nó (o nome da tarefa em `docker service ps`
  inclui sufixo de tarefa, ex. `dpsjur_dpsjur-db.1.<id>`; o contêiner local é
  casado por nome exato ou por ID — o ID da tarefa Swarm é o mesmo do contêiner)
  → prova final `docker ps --filter id=<id>` → exatamente UM contêiner elegível.
  A função escreve SOMENTE o identificador no stdout (logs/diagnósticos em
  stderr). Ausência, ambiguidade (mais de uma réplica Running neste nó) ou
  divergência entre `docker service ps` e `docker ps` é FATAL (exit 13).

## 4. Validação de contêiner — o que é PROVADO (Requisito A)

Antes de qualquer dump, `bk_verify_container` exige TUDO:

1. O contêiner EXATO está em execução (Banco A: igualdade de nome; Banco B: o
   ID retornado pela resolução Swarm da seção 3.3, comprovado por igualdade
   exata contra a coluna ID de `docker ps` — correção M) — sem regex genérica;
2. `SHOW server_version` no contêiner retorna major **15** (A) ou **18** (B) —
   divergência é FATAL;
3. O banco esperado (`postgres` no A; `dpsjur` no B) EXISTE em `pg_database`;
4. O usuário esperado (`postgres` no A; `Doug` no B) EXISTE em `pg_roles`;
5. `pg_dump` está disponível dentro do contêiner.

Todas as consultas psql dos passos 2–4 usam conexão EXPLÍCITA
(`-U <usuário> -d <banco> -p <porta>`, PGPASSFILE interno). Qualquer divergência
aborta com `exit 13` ANTES de gravar qualquer arquivo.

## 5. Retenção — modo observação e como autorizar exclusões (Requisito F)

- **Padrão: MODO OBSERVAÇÃO.** A retenção apenas LISTA no log o que SERIA
  removido. NADA é apagado. A rotina atual do Banco A
  (`/root/sbjur-backups/backup.sh`, diária 03h) continua rodando normalmente
  durante toda a sobreposição.
- **Para habilitar exclusões (SÓ APÓS validação e autorização de Douglas):**
  rodar o script com `--aplicar-retencao`. Mesmo então:
  - candidatos são APENAS arquivos REGULARES com o PREFIXO do próprio banco
    (`sbsjur-*` / `dpsjur-*`) no diretório correspondente (`diario`/`semanal`/
    `mensal` do próprio banco) — links simbólicos e outros arquivos NUNCA são
    considerados;
  - cada candidato é VALIDADO individualmente (gzip -t + tamanho mínimo) antes
    da exclusão — arquivo que não valida NÃO é removido e a retenção termina
    em FALHA (exit 27);
  - backups da rotina antiga (qualquer outro prefixo, ex. `backup-*`) NUNCA são
    tocados;
  - falha de backup NUNCA provoca exclusão: a retenção só roda APÓS publicação
    bem-sucedida do dump do dia.
- Políticas atuais nos scripts: diário 7, semanal 4, mensal 12 (ajustáveis).

## 6. Restauração isolada — NUNCA em banco de produção

**REGRA DE OURO:** o destino da restauração é SEMPRE um contêiner/diretório
TEMPORÁRIO e ISOLADO (rede `none`/`--internal`, volume descartável, nome único
com timestamp). Jamais `sbjur-local_supabase-db-1`, jamais o serviço
`dpsjur_dpsjur-db`. **Pré-requisito para declarar a solução pronta: restauração
isolada de AMBOS os bancos com verificação pós-restauração aprovada.**

### 6.1 Restauração isolada do Banco A (PG15)

Este é o fluxo OFICIAL já coberto pelo auditor `docs/vps/20-auditar-backup.sh`
(v2.1.2, executado em máquina de teste / WSL2 / Docker Desktop isolado — a
guarda anti-VPS impede rodá-lo na VPS de produção):

```bash
bash docs/vps/20-auditar-backup.sh \
    --arquivo /caminho/backup.sql.gz \
    --inventario /caminho/inventario.json
```

Pré-requisito: gerar o inventário estrutural na VPS com
`docs/vps/21-gerar-inventario.sh` (somente leitura, fora do expediente) e
copiar o JSON para a máquina de teste. Os dumps desta solução ficam em
`/root/sbjur-backups-dupla/banco-a/<modo>/sbsjur-<modo>-<TS>.sql.gz`.

### 6.2 Restauração isolada do Banco B (PG18) — passo a passo

O auditor 20-auditar-backup.sh é calibrado para o Banco A (imagem
supabase/postgres, usuário postgres). Para o Banco B use o procedimento manual
abaixo em máquina de teste (NUNCA na VPS):

```bash
TS=$(date +%Y%m%d-%H%M%S)
LAB_NAME="dpsjur-b-lab-${TS}"
LAB_VOL="dpsjur-b-vol-${TS}"

# 1. Rede isolada (sem saída para internet)
docker network create --internal "dpsjur-b-net-${TS}" || true

# 2. Subir PostgreSQL 18 isolado (rede interna, senha efêmera)
docker run -d --name "${LAB_NAME}" \
    --network "dpsjur-b-net-${TS}" \
    -v "${LAB_VOL}:/var/lib/postgresql/data" \
    -e POSTGRES_PASSWORD=lab_tmp_password \
    -e POSTGRES_USER=labadmin \
    -e POSTGRES_DB=labdb \
    postgres:18-alpine

# 3. Aguardar pronto
for i in $(seq 1 40); do
    docker exec "${LAB_NAME}" pg_isready -U labadmin -d labdb && break
    sleep 1
done

# 4. Criar o usuário Doug e o banco dpsjur (destino isolado, nomes iguais à
#    produção para o restore casar, mas DENTRO do laboratório)
docker exec "${LAB_NAME}" psql -U labadmin -d labdb -c "CREATE ROLE \"Doug\" LOGIN PASSWORD 'lab_tmp_password';"
docker exec "${LAB_NAME}" psql -U labadmin -d labdb -c "CREATE DATABASE dpsjur OWNER \"Doug\";"

# 5. Copiar o dump para dentro do laboratório
docker cp /root/sbjur-backups-dupla/banco-b/diario/dpsjur-diario-<TS>.sql.gz "${LAB_NAME}":/tmp/dump.sql.gz

# 6. Restaurar com verificação de erros
docker exec "${LAB_NAME}" sh -c 'gunzip -c /tmp/dump.sql.gz | psql -U "Doug" -d dpsjur -v ON_ERROR_STOP=1' > restore-b.log 2>&1
grep -E 'ERROR:|FATAL:' restore-b.log   # deve retornar VAZIO

# 7. Verificação pós-restauração (contagens essenciais)
docker exec "${LAB_NAME}" psql -U "Doug" -d dpsjur -c '\dt'        # tabelas presentes
docker exec "${LAB_NAME}" psql -U "Doug" -d dpsjur -c 'SELECT count(*) FROM clients;'
docker exec "${LAB_NAME}" psql -U "Doug" -d dpsjur -c 'SELECT count(*) FROM cases;'
docker exec "${LAB_NAME}" psql -U "Doug" -d dpsjur -c 'SELECT count(*) FROM transactions;'

# 8. Destruição do laboratório (obrigatório ao final)
docker rm -f "${LAB_NAME}"
docker volume rm "${LAB_VOL}"
docker network rm "dpsjur-b-net-${TS}"
```

**Verificação pós-restauração mínima (AMBOS os bancos):**

- `gzip -t` do arquivo de dump (integridade do arquivo em si — seção 2);
- contagem de tabelas em `public` e `auth` (Banco A) / `public` (Banco B);
- contagens de `clients`, `cases`, `transactions` iguais ou compatíveis com o
  inventário (diferenças = INCONCLUSIVO, nunca presumir crescimento);
- `psql -c 'SELECT version();'` retorna a versão esperada (15.x / 18.x).

### 6.3 Banco B — diferenças documentadas em relação ao auditor 20-auditar-backup.sh

- Imagem: `postgres:18-alpine` (não supabase/postgres:15).
- Usuário de restauração: `Doug` (entre aspas em psql por causa da maiúscula).
- Banco: `dpsjur` (criado antes do restore, owner Doug).
- Auditoria formal (com veredito APROVADO/REPROVADO) só existe hoje para o
  Banco A. Para o Banco B, a validação é a lista de verificações da seção 6.2
  — status PENDENTE DE VALIDAÇÃO até ser executada em laboratório.

## 7. Testes de sintaxe e análise estática

Nesta rodada (plataforma de desenvolvimento SEM Bash):

- `bash -n` nos três scripts: **NÃO VALIDADO nesta rodada** — a plataforma de
  desenvolvimento desta sessão não tem Bash disponível; executar no
  WSL2 de Douglas antes de qualquer uso:
  ```bash
  bash -n docs/vps/22-backup-banco-a-sbjur-local.sh
  bash -n docs/vps/23-backup-banco-b-dpsjur.sh
  bash -n docs/vps/lib/backup-lib.sh
  ```
- `shellcheck` nos três scripts: **NÃO VALIDADO** — idem:
  ```bash
  shellcheck -S style docs/vps/lib/backup-lib.sh \
      docs/vps/22-backup-banco-a-sbjur-local.sh docs/vps/23-backup-banco-b-dpsjur.sh
  ```
- Testes locais com mocks: **NÃO VALIDADO nesta rodada** (plataforma de
  desenvolvimento SEM Bash). O harness `docs/vps/tests/testes-backup-dupla-v211.sh`
  FOI ENTREGUE pronto (mock de `docker`/`psql` à frente do PATH; NADA real é
  executado) e cobre os cenários obrigatórios desta v2.1.1: contêiner do serviço
  `dpsjur_dpsjur-db` identificado por ID é ACEITO por `bk_verify_container`
  (versão 18/`Doug`/`dpsjur` confirmados); contêiner incorreto é REJEITADO;
  contêiner ambíguo é REJEITADO; serviço/tarefa Swarm ausente é REJEITADA;
  pg_dump falhando → FALHA (exit 20); publicação recusada por destino
  existente → FALHA (exit 25, destino NÃO sobrescrito); SUCESSO só com código 0
  e limpeza integral; FALHA preserva o código original; FALHA DE LIMPEZA
  distinta quando só a limpeza falha; e a mecânica do trap EXIT preserva o
  código original após a limpeza (exit 20 sobrevive; 0+limpeza falha → 29;
  0+limpeza ok → 0). Executar na máquina com Bash ANTES da VPS:
  ```bash
  bash docs/vps/tests/testes-backup-dupla-v211.sh   # exit 0 = todos passaram
  ```
- Concorrência (dois processos disputando o lock) e tentativa de sobrescrita
  além do cenário T6 do harness: NÃO VALIDADO — requerem Bash; executar na
  máquina de teste antes da VPS.

## 8. Cron sugerido (SÓ documentado — NÃO instalar sem autorização)

A instalação no crontab é PASSO DE IMPLANTAÇÃO FUTURA, autorizada por Douglas.

```cron
# Banco A (sbjur-local, PG15) — complementa a rotina atual, sem removê-la
# (conferir TZ do host com `date`; preferir /etc/cron.d com CRON_TZ=America/Sao_Paulo)
0 3 * * * root /bin/bash /root/22-backup-banco-a-sbjur-local.sh --diario >> /root/sbjur-backups-dupla/banco-a/logs/cron-a.log 2>&1
0 4 * * 0 root /bin/bash /root/22-backup-banco-a-sbjur-local.sh --semanal >> /root/sbjur-backups-dupla/banco-a/logs/cron-a.log 2>&1
0 5 1 * * root /bin/bash /root/22-backup-banco-a-sbjur-local.sh --mensal >> /root/sbjur-backups-dupla/banco-a/logs/cron-a.log 2>&1

# Banco B (dpsjur, PG18) — nova rotina (não existe hoje)
0 3 * * * root /bin/bash /root/23-backup-banco-b-dpsjur.sh --diario >> /root/sbjur-backups-dupla/banco-b/logs/cron-b.log 2>&1
0 4 * * 0 root /bin/bash /root/23-backup-banco-b-dpsjur.sh --semanal >> /root/sbjur-backups-dupla/banco-b/logs/cron-b.log 2>&1
0 5 1 * * root /bin/bash /root/23-backup-banco-b-dpsjur.sh --mensal >> /root/sbjur-backups-dupla/banco-b/logs/cron-b.log 2>&1
```

**Atenção à sobreposição no Banco A:** às 03h a rotina antiga e a nova rodam
juntas (deliberado — períodos independentes, destinos independentes, lock
próprio de cada script). Se Douglas preferir escalonar, mover a nova para 03h30
no momento da implantação.

Recomendação: usar `/etc/cron.d/` com `CRON_TZ=America/Sao_Paulo` (padrão já
adotado nas rotinas de e-mail do projeto).

## 9. Rollback / reversão

- **Desativar a nova rotina do Banco A:** remover a linha do cron e nada mais —
  a rotina atual `/root/sbjur-backups/backup.sh` NUNCA foi desligada; a
  sobreposição garante que sempre houve backup ativo.
- **Desativar a nova rotina do Banco B:** remover a linha do cron; não havia
  rotina anterior.
- **Backups existentes:** NENHUM arquivo da rotina atual é renomeado, movido
  ou excluído por estes scripts (destinos e prefixos distintos + retenção em
  modo observação por padrão).
- **Arquivos da nova solução:** podem ser removidos da VPS a qualquer momento
  (`/root/22-*.sh`, `/root/23-*.sh`, `/root/sbjur-backups-dupla/`) sem afetar a
  rotina antiga — decisão de Douglas.

## 10. Cópia externa à VPS (possibilidade futura — NÃO implementado)

Os dumps finais ficam em `/root/sbjur-backups-dupla/<banco>/<modo>/`, estrutura
regular adequada a uma cópia futura para fora da VPS (Google Drive do escritório
via `rclone`, como já decidido para os demais backups do projeto). A implantação
dessa cópia EXTERNA é etapa futura separada, com autorização de Douglas, e não
faz parte desta solução.

## 11. Status e pendências

**Status: PENDENTE DE VALIDAÇÃO / IMPLANTAÇÃO.** NÃO declarar pronto para
produção até que:

1. `bash -n` e `shellcheck` sejam executados nos três scripts (WSL2 de
   Douglas — plataforma de desenvolvimento sem Bash NÃO VALIDOU; seção 7);
2. testes locais com mocks (`docs/vps/tests/testes-backup-dupla-v211.sh`,
   entregue nesta v2.1.1 e NÃO EXECUTADO nesta rodada) rodem SEM falhas em
   máquina de teste, junto com concorrência e tentativa de sobrescrita
   (seção 7);
3. um backup de teste de CADA banco seja executado manualmente na VPS e os logs
   mostrem `VEREDITO: SUCESSO`;
4. uma restauração isolada de CADA banco seja executada (seção 6) com
   verificação pós-restauração aprovada;
5. Douglas confirme operacionalmente qual banco é o principal (o PostgreSQL 18
   NÃO é presumido principal nesta solução);
6. Douglas autorize expressamente a instalação das linhas de cron (seção 8).
