# Backup Independente dos DOIS PostgreSQL da VPS — Banco A (PG15) e Banco B (PG18)

**Projeto:** DPSjur / SBJur (VPS Hostinger, EasyPanel/Docker)
**Status:** PENDENTE DE VALIDAÇÃO / IMPLANTAÇÃO — autorização expressa de Douglas obrigatória antes de qualquer execução ou agendamento na VPS.
**Versão dos scripts:** v1.0.0

## 1. Visão geral — dois bancos DISTINTOS, duas rotinas INDEPENDENTES

|                 | Banco A                                              | Banco B                                                |
| --------------- | ---------------------------------------------------- | ------------------------------------------------------ |
| Projeto         | `sbjur-local` (EasyPanel)                            | `dpsjur` (EasyPanel)                                   |
| Contêiner       | `sbjur-local_supabase-db-1`                          | `dpsjur-db`                                            |
| PostgreSQL      | **15.8** (major 15)                                  | **18**                                                 |
| Usuário         | `postgres`                                           | `Doug`                                                 |
| Banco           | `postgres`                                           | `dpsjur`                                               |
| Script          | `docs/vps/22-backup-banco-a-sbjur-local.sh`          | `docs/vps/23-backup-banco-b-dpsjur.sh`                 |
| Base de destino | `/root/sbjur-backups/`                               | `/root/dpsjur-backups/`                                |
| Log diário      | `/root/sbjur-backups/logs/bk-a-sbjur15-AAAAMMDD.log` | `/root/dpsjur-backups/logs/bk-b-dpsjur18-AAAAMMDD.log` |
| .pgpass         | `/root/.pgpass-sbjur-a`                              | `/root/.pgpass-dpsjur-b`                               |
| Lock            | `/root/sbjur-backups/.lock-bk-a`                     | `/root/dpsjur-backups/.lock-bk-b`                      |

Nenhum script toca o contêiner/banco do outro: cada um tem identificação FIXA
(contêiner, usuário, banco) e PROVA obrigatória (equalidade exata de nome +
versão major confere + banco existe + usuário existe + pg_dump disponível)
antes de qualquer dump — sem regex genérica.

## 2. Requisitos de Douglas — onde cada um está atendido

| #   | Requisito                                              | Onde está                                                              |
| --- | ------------------------------------------------------ | ---------------------------------------------------------------------- |
| 1   | Rotinas independentes PG15.8 / PG18                    | Um script por banco (22 e 23) + lib compartilhada                      |
| 2   | Contêiner/usuário/banco explícitos, sem regex genérica | `bk_verify_container` na lib (usada por ambos)                         |
| 3   | Senha fora de argumento/log                            | `.pgpass` com chmod 600 validado; pg_dump com `-w` (nunca pedir senha) |
| 4   | pipefail + verificação de pg_dump E compactação        | `bk_run_dump_pipeline` (PIPESTATUS)                                    |
| 5   | gzip -t + tamanho mínimo                               | `bk_validate_dump` (mín. 1024 bytes configurável)                      |
| 6   | Diretórios separados diário/semanal/mensal             | `bk_setup_dirs`                                                        |
| 7   | Logs independentes, sem /dev/null                      | Cada banco tem `logs/` próprio; pipeline vai para o log                |
| 8   | Retenção sem excluir na migração                       | `bk_apply_retention` em modo OBSERVAÇÃO por padrão                     |
| 9   | Lock + proteção contra sobrescrita                     | `bk_acquire_lock` (flock com fallback mkdir) + `noclobber` + timestamp |
| 10  | Restauração isolada por banco                          | Seção 6 deste documento                                                |

## 3. Pré-requisitos antes da primeira execução

**Lição do projeto (registrar sempre):** NÃO usar `curl | bash` — baixar o
arquivo e rodar via SSH com comando.

### 3.1 Banco A (sbjur-local, PG15)

1. Copiar o dump do repositório para a VPS (ou baixar via URL raw do Git):

   ```bash
   curl -fsSL -o /root/22-backup-banco-a-sbjur-local.sh   <URL_RAW>/docs/vps/22-backup-banco-a-sbjur-local.sh
   curl -fsSL -o /root/23-backup-banco-b-dpsjur.sh        <URL_RAW>/docs/vps/23-backup-banco-b-dpsjur.sh
   mkdir -p /root/sbjur-backups/lib
   curl -fsSL -o /root/sbjur-backups/lib/backup-lib.sh    <URL_RAW>/docs/vps/lib/backup-lib.sh
   ```

2. Criar o .pgpass do Banco A (senha do usuário `postgres` do Supabase
   self-hosted):
   ```bash
   printf 'localhost:5432:postgres:postgres:SENHA_DO_POSTGRES\n' > /root/.pgpass-sbjur-a
   chmod 600 /root/.pgpass-sbjur-a
   ```
   Obs.: o script também funciona com o TRUST local do socket (padrão do
   Supabase self-hosted), pois o pg_dump conecta com `-w` (nunca pede senha)
   pelo socket Unix dentro do contêiner.

### 3.2 Banco B (dpsjur, PG18)

1. Criar o .pgpass do Banco B — a senha é a do usuário `Doug` no PostgreSQL 18:

   ```bash
   printf 'localhost:5432:dpsjur:Doug:SENHA_DO_Doug\n' > /root/.pgpass-dpsjur-b
   chmod 600 /root/.pgpass-dpsjur-b
   ```

   **Atenção:** a senha precisa estar no formato de 5 campos separados por `:`
   (o próprio `.pgpass` do PostgreSQL valida; não usar `:` na senha, ou escapar
   com `\:`).

2. O script do Banco B copia o `.pgpass` para DENTRO do contêiner
   (`/tmp/.pgpass-bk-b`, chmod 600) na hora do dump e remove ao final. Para
   isso funcionar, a senha precisa valer para conexão TCP em `127.0.0.1:5432`
   dentro do contêiner. Se o `pg_hba.conf` do Banco B não aceitar essa forma,
   ajustar o `pg_hba.conf` OU (preferível) usar a forma de socket local com
   `local all Doug md5` — a sessão de implantação deve conferir no contêiner.

## 4. Validação de contêiner — o que é PROVADO (Requisito 2)

Antes de qualquer dump, `bk_verify_container` exige TUDO:

1. O contêiner com o NOME EXATO (`sbjur-local_supabase-db-1` OU `dpsjur-db`)
   está em execução (igualdade de string, nunca regex genérica).
2. `SHOW server_version` no contêiner retorna major **15** (Banco A) ou
   **18** (Banco B) — a versão divergente é FATAL.
3. O banco esperado (`postgres` no A; `dpsjur` no B) EXISTE em `pg_database`.
4. O usuário esperado (`postgres` no A; `Doug` no B) EXISTE em `pg_roles`.
5. `pg_dump` está disponível dentro do contêiner.

Qualquer divergência aborta com `exit 13` ANTES de gravar qualquer arquivo.

## 5. Retenção — período de sobreposição e como autorizar exclusões

- **Padrão:** MODO OBSERVAÇÃO. A retenção apenas LISTA no log o que SERIA
  removido. Nada é apagado. A rotina atual do Banco A
  (`/root/sbjur-backups/backup.sh`, diário 03h) continua rodando normalmente
  durante toda a sobreposição.
- **Para habilitar exclusões (SÓ APÓS validação e autorização de Douglas):**
  rodar o script com `--aplicar-retencao`. A retenção só remove arquivos com
  o PREFIXO do próprio banco (`bk-a-sbjur15-A-*` ou `bk-b-dpsjur18-B-*`),
  nunca backups da rotina antiga (`backup-*` ou outros prefixos).
- Políticas iniciais (ajustáveis): diário 14, semanal 8, mensal 12.

## 6. Restauração isolada — NUNCA em banco de produção (Requisito 10)

**REGRA DE OURO:** o destino da restauração é SEMPRE um contêiner/diretório
TEMPORÁRIO e ISOLADO (rede `none`, volume descartável, nome único com
timestamp). Jamais `sbjur-local_supabase-db-1` nem `dpsjur-db`.

### 6.1 Restauração isolada do Banco A (PG15)

Este é o fluxo OFICIAL já coberto pelo auditor `docs/vps/20-auditar-backup.sh`
(v2.1.3, executado em máquina de teste / WSL2 / Docker Desktop isolado — a
guarda anti-VPS impede rodá-lo na VPS de produção):

```bash
bash docs/vps/20-auditar-backup.sh \
    --arquivo /caminho/backup.sql.gz \
    --inventario /caminho/inventario.json
```

Pré-requisito: gerar o inventário estrutural na VPS com
`docs/vps/21-gerar-inventario.sh` (somente leitura, fora do expediente) e
copiar o JSON para a máquina de teste.

### 6.2 Restauração isolada do Banco B (PG18) — passo a passo

O auditor 20-auditar-backup.sh é calibrado para o Banco A (imagem
supabase/postgres, usuário postgres). Para o Banco B use o procedimento
manual abaixo em máquina de teste (NUNCA na VPS):

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
docker cp /caminho/bk-b-dpsjur18-B-diario-<TS>.sql.gz "${LAB_NAME}":/tmp/dump.sql.gz

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

**Verificação pós-restauração mínima (ambos os bancos):**

- `gzip -t` do arquivo de dump (integridade do arquivo em si);
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

## 7. Cron sugerido (SÓ documentado — NÃO instalar sem autorização)

A instalação no crontab é PASSO DE IMPLANTAÇÃO FUTURA, autorizada por Douglas.

```cron
# Banco A (sbjur-local, PG15) — supre a rotina atual, sem removê-la
# (mesmo horário 03h BSB = 06h UTC; conferir TZ do host com `date`)
# A rotina ATUAL /root/sbjur-backups/backup.sh continua agendada e é preservada.
0 3 * * * root /bin/bash /root/22-backup-banco-a-sbjur-local.sh --diario >> /root/sbjur-backups/logs/cron-a.log 2>&1
0 4 * * 0 root /bin/bash /root/22-backup-banco-a-sbjur-local.sh --semanal >> /root/sbjur-backups/logs/cron-a.log 2>&1
0 5 1 * * root /bin/bash /root/22-backup-banco-a-sbjur-local.sh --mensal >> /root/sbjur-backups/logs/cron-a.log 2>&1

# Banco B (dpsjur, PG18) — nova rotina (não existe hoje)
0 3 * * * root /bin/bash /root/23-backup-banco-b-dpsjur.sh --diario >> /root/dpsjur-backups/logs/cron-b.log 2>&1
0 4 * * 0 root /bin/bash /root/23-backup-banco-b-dpsjur.sh --semanal >> /root/dpsjur-backups/logs/cron-b.log 2>&1
0 5 1 * * root /bin/bash /root/23-backup-banco-b-dpsjur.sh --mensal >> /root/dpsjur-backups/logs/cron-b.log 2>&1
```

Recomendação: usar `/etc/cron.d/` com `CRON_TZ=America/Sao_Paulo` (padrão já
adotado nas rotinas de e-mail do projeto).

## 8. Rollback / reversão

- **Desativar a nova rotina do Banco A:** remover a linha do cron e nada mais —
  a rotina atual `/root/sbjur-backups/backup.sh` NUNCA foi desligada; a
  sobreposição garante que sempre houve backup ativo.
- **Desativar a nova rotina do Banco B:** remover a linha do cron; não havia
  rotina anterior.
- **Backups existentes:** NENHUM arquivo da rotina atual é renomeado, movido
  ou excluído por estes scripts (prefixos distintos + retenção em modo
  observação por padrão).

## 9. Status e pendências

**Status: PENDENTE DE VALIDAÇÃO / IMPLANTAÇÃO.** Não declarar pronto para
produção até que:

1. `bash -n` e `shellcheck` sejam executados nos três scripts (WSL2 de
   Douglas — plataforma de desenvolvimento sem Bash não validou);
2. um backup de teste de CADA banco seja executado manualmente na VPS e os
   logs `bk-a-*` / `bk-b-*` mostrem VEREDITO: SUCESSO;
3. uma restauração isolada de CADA banco seja executada (seção 6) com
   verificação pós-restauração aprovada;
4. Douglas autorize expressamente a instalação das linhas de cron (seção 7).
