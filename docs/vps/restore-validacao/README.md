# DPSjur — Validação de restauração de desastre (local, Windows + Docker Desktop)

Guia em ETAPAS para validar que um backup `.sql.gz` da VPS consegue ser
restaurado num PostgreSQL limpo e lido por completo — SEM tocar na VPS, no
EasyPanel, na rotina das 03h ou em nenhum backup existente. Tudo roda na
máquina local do Douglas (Docker Desktop), com os `.sh` executados via WSL2
ou dentro do próprio contêiner.

**Status: PENDENTE DE VALIDAÇÃO.** A restauração só deixa de ser "pendente"
quando o log REAL do passo 3 for colado de volta na conversa e analisado.
Nada aqui declara recuperação validada.

## Backup-alvo desta rodada

- Arquivo: `C:\Users\dowsp\DPSJUR-Backup-Teste\sbjur_backup_2026-11-11_030001.sql.gz`
  (no WSL2: `/mnt/c/Users/dowsp/DPSJUR-Backup-Teste/sbjur_backup_2026-11-11_030001.sql.gz`)
- 676.047 bytes, gzip íntegro, origem VPS `/root/sbjur-backups/diario/`.

## Já COMPROVADO — não repetir estes testes

1. **Download** do arquivo a partir da VPS: feito.
2. **Integridade gzip** (`gzip -t`): OK.
3. **Acesso administrativo** à imagem `supabase/postgres:15.8.1.085` como
   `supabase_admin` via `psql -h 127.0.0.1 -U supabase_admin -d postgres`: OK.
4. **Lição da tentativa anterior**: restaurar como `postgres` falha com
   `ERROR: must be owner of event trigger pgrst_drop_watch` (o gatilho
   pertence a `supabase_admin`, único superusuário da imagem); PostgreSQL 15
   convencional falha por faltar o papel `supabase_admin` e a extensão
   `pg_net`. O passo 2 resolve os dois: restaura como `supabase_admin` em
   imagem Supabase, com papéis e extensões preparados antes do restore.

## Regras que valem para TODAS as etapas

- A restauração é SEMPRE em contêiner NOVO e ISOLADO, na máquina local.
  **Nunca reutilizar** o contêiner parcial `dpsjur-restore-supabase` (nem o
  `dpsjur-restore-test`): eles ficam preservados, intocados.
- Nada na VPS. Nada em banco de produção. Nenhum backup é apagado ou
  modificado. Nenhuma credencial de produção é usada.
- Cada comando abaixo é um **BLOCO ÚNICO**: copie o bloco inteiro de uma vez
  no PowerShell 5.1 (ou no WSL2) e execute.
- Ao fim de cada etapa, o script grava um arquivo de relatório — **abra o
  arquivo, copie o conteúdo e COLE DE VOLTA NA CONVERSA** para análise antes
  de seguir para a etapa seguinte.
- Os `.sh` rodam no WSL2 (`bash ./nome-do-script.sh ...`) ou dentro do
  contêiner (`docker exec ...`). No PowerShell puro, use `wsl -e bash -lc
  "cd /mnt/c/Users/dowsp/DPSJUR-Backup-Teste && bash ./nome-do-script.sh ..."`
  — os blocos abaixo já trazem as duas formas onde importa.

---

## ETAPA 1 — Diagnóstico do backup (somente leitura, sem banco)

**Script:** `01-diagnostico-backup.sh` · **Finalidade:** extrair do próprio
`.sql.gz` as versões de origem, extensões exigidas, papéis, donos, presença
do event trigger `pgrst_drop_watch`, contagens de DDL e tabelas com dados
(COPY). Não abre banco nem restaura nada.

**Resultado esperado:** arquivo
`diagnostico-backup-<data>.txt` ao lado do `.sql.gz`, com a seção
`--- COPY (tabelas com dados) ---` preenchida (é dela que o passo 3 extrai a
lista de comparação) e o aviso de `pgrst_drop_watch` PRESENTE.

Bloco único (PowerShell 5.1, chamando o WSL2):

```powershell
wsl -e bash -lc "cd /mnt/c/Users/dowsp/DPSJUR-Backup-Teste && bash /mnt/c/Users/dowsp/DPSJUR-Backup-Teste/01-diagnostico-backup.sh /mnt/c/Users/dowsp/DPSJUR-Backup-Teste/sbjur_backup_2026-11-11_030001.sql.gz && ls -l diagnostico-backup-*.txt"
```

(Ou, direto no WSL2: `cd /mnt/c/Users/dowsp/DPSJUR-Backup-Teste && bash ./01-diagnostico-backup.sh ./sbjur_backup_2026-11-11_030001.sql.gz`)

**Ao terminar:** cole o conteúdo do `diagnostico-backup-*.txt` na conversa.
Guarde o caminho dele — a ETAPA 3 usa este arquivo na comparação.

### Etapa 1 via DPSJUR-Etapa1.ps1 (automático, Windows PowerShell 5.1)

Alternativa aos blocos acima: o arquivo `DPSJUR-Etapa1.ps1` faz a ETAPA 1
inteira sem copiar comandos.

- Arquivo: `docs/vps/restore-validacao/DPSJUR-Etapa1.ps1` — **versão atual:
  v1.1.0** (corrige a falha "Não é possível localizar uma sobrecarga para
  'FromBase64String' e a contagem de argumentos: '2'" na etapa [2/5], que
  ocorria no PowerShell 5.1 quando o campo base64 da API do GitHub chegava
  como array de strings; nenhuma verificação de integridade foi removida).

#### SUBSTITUIR a versão anterior (v1.0.0) — obrigatório antes de reexecutar

Se você já tem `DPSJUR-Etapa1.ps1` em
`C:\Users\dowsp\DPSJUR-Backup-Teste\`, substitua o arquivo **por cima** (não
precisa apagar nem editar nada):

1. Baixe a nova versão do commit fixado (raw), salvando **como**
   `DPSJUR-Etapa1.ps1` **em cima do arquivo existente** em
   `C:\Users\dowsp\DPSJUR-Backup-Teste\DPSJUR-Etapa1.ps1`:
   `https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/<commit>/docs/vps/restore-validacao/DPSJUR-Etapa1.ps1`
   (no navegador: Ctrl+S e escolha essa pasta e esse nome; confirme a
   substituição quando o Windows perguntar).
2. Confira no topo do arquivo baixado: deve dizer `Versao: v1.1.0`.
3. Reexecute **o mesmo comando único de sempre** (o bypass vale só para esta
   invocação):

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\DPSJUR-Etapa1.ps1
   ```

   (rode com a pasta `C:\Users\dowsp\DPSJUR-Backup-Teste` como atual, como da
   primeira vez; nada mais muda).

Nenhuma edição manual de código é necessária — só baixar por cima e rodar.

#### O que o .ps1 faz

O próprio `.ps1` baixa `01-diagnostico-backup.sh` pela API do GitHub no commit
`b19a532bffe6ae0e069ad9f19e0fae4a9d09db07`, confere o identificador de blob Git
(`884cf88d8bcf1299c5cd81accbde9d92efaacadd`, 8966 bytes) e o SHA-256 contra o
download bruto, faz `bash -n`, executa o diagnóstico (somente leitura sobre o
`.sql.gz`), exibe o relatório e o abre no Bloco de Notas. Se alguma verificação
falhar, ele para sem executar nada e pede para colar a saída no chat.

---

## ETAPA 2 — Restauração LIMPA (contêiner NOVO)

**Script:** `02-restaurar-limpo.sh` (v1.0.1) · **Finalidade:** criar o contêiner
`dpsjur-restore-final` (imagem `supabase/postgres:15.8.1.085`, porta local
15433 vinculada a 127.0.0.1), criar papéis e extensões, copiar o dump e
restaurar como `supabase_admin` com `ON_ERROR_STOP=0` — o objetivo é a LISTA
COMPLETA de erros, não parar no primeiro. O script ABORTA se o nome do
contêiner já existir (não reutiliza, não remove).

Na restauração, o `.sql.gz` é descomprimido pelo `gunzip` e o SQL é lido pelo
`psql` da entrada padrão (`gunzip -c /tmp/backup.sql.gz | psql ...`, sem `-f`
sobre o arquivo comprimido); os heredocs de preparação (papéis, extensões)
usam `docker exec -i` para o stdin chegar ao `psql`.

**Resultado esperado:** terminal mostra os 6 passos (`[1/6]` a `[6/6]`), um
resumo de erros do log (alguns `ERRO` de objetos de sistema Supabase são
ESPERADOS e serão analisados no log), e a linha
`Próximo passo: ./03-validar-restauracao.sh dpsjur-restore-final`.

Bloco único (PowerShell 5.1, chamando o WSL2):

```powershell
wsl -e bash -lc "cd /mnt/c/Users/dowsp/DPSJUR-Backup-Teste && bash ./02-restaurar-limpo.sh /mnt/c/Users/dowsp/DPSJUR-Backup-Teste/sbjur_backup_2026-11-11_030001.sql.gz dpsjur-restore-final && ls -l restauracao-dpsjur-restore-final-*.log"
```

- Se já existir um `dpsjur-restore-final` de tentativa anterior, use OUTRO
  nome no final do comando (ex.: `dpsjur-restore-final-2`). Nunca remova nem
  reinicie contêineres existentes por conta própria.
- Opcional: `export SUPABASE_RESTORE_OWNERS="authenticator service_role ..."`
  antes do bloco (a lista exata sai do passo 01, seção "DONOS ÚNICOS").

**Ao terminar:** cole o trecho final do log (o resumo de erros impresso) na
conversa. O log completo fica em
`restauracao-dpsjur-restore-final-<data>.log`, ao lado do `.sql.gz`.

---

## ETAPA 3 — Validação do banco restaurado (somente leitura)

**Script:** `03-validar-restauracao.sh` · **Finalidade:** conferir o que
realmente ficou no banco do contêiner do passo 2: versão do PostgreSQL do
destino, schemas, tabelas por schema e lista completa, contagem de registros
por tabela (`count(*)` exato), sequências e valores, funções por schema,
políticas RLS e tabelas com RLS habilitado, extensões instaladas, papéis
presentes — e, passando `--diagnostico`, comparar com o passo 1 (tabelas com
dados no dump AUSENTES no destino + extensões exigidas não instaladas).
Grava log + resumo em arquivo. Tudo somente leitura (SELECT/catálogo).

**Resultado esperado:** arquivo `validacao-restauracao-dpsjur-restore-final-
<data>.txt`, com a seção `OK: TODAS as tabelas com dados (COPY) no dump
existem no destino` (ou a lista de AUSENTES, se houver) e as extensões do
dump todas instaladas. A restauração SÓ é declarada validada após este
relatório ser analisado na conversa.

Bloco único (PowerShell 5.1, chamando o WSL2 — ajuste o nome do
`diagnostico-backup-*.txt` para o arquivo real gerado na ETAPA 1):

```powershell
wsl -e bash -lc "cd /mnt/c/Users/dowsp/DPSJUR-Backup-Teste && bash ./03-validar-restauracao.sh dpsjur-restore-final --diagnostico /mnt/c/Users/dowsp/DPSJUR-Backup-Teste/diagnostico-backup-AAAA-MM-DD_HHMMSS.txt && ls -l validacao-restauracao-*.txt"
```

**Ao terminar:** copie TODO o conteúdo do `validacao-restauracao-*.txt` e
cole de volta na conversa — é este log que fecha (ou não) a validação.

---

## Códigos de saída (todos os três scripts)

| Código | Significado |
|--------|-------------|
| 0      | concluído |
| 64     | uso incorreto (argumento) |
| 66     | arquivo/contêiner não encontrado (ou contêiner parado) |
| 69     | comando obrigatório ausente (docker/gzip) |
| 70     | PostgreSQL não aceitou conexão / consulta falhou |
| 73     | contêiner alvo já existe (passo 02 — escolha outro nome) |

## O que NÃO fazer em nenhuma hipótese

- Nada na VPS (nem SSH "só para olhar"); nada no EasyPanel, crontab ou rotina
  das 03h; nada nos scripts de backup `22/23` e `lib`.
- Apagar, mover ou renomear qualquer backup (`/root/sbjur-backups/...` ou a
  cópia local `DPSJUR-Backup-Teste`).
- Reutilizar/remover os contêineres `dpsjur-restore-supabase` e
  `dpsjur-restore-test` (preservados para inspeção).
- Alterar senhas, credenciais, `pg_hba.conf` ou permissões de qualquer banco.
- Declarar a recuperação "validada" sem o log real do passo 3 analisado.
- A chave SSH adicionada em `/root/.ssh/authorized_keys` na VPS permanece
  PRESERVADA — nada aqui a remove ou substitui.
