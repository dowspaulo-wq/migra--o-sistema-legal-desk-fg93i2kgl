#!/usr/bin/env bash
# ==============================================================================
# DPSjur — VALIDAÇÃO DE RESTAURAÇÃO · PASSO 5 (ORQUESTRADOR)
# Script: docs/vps/restore-validacao/05-auditoria-completa.sh
# Versão: v1.0.0
#
# FINALIDADE: UM único comando que executa, EM ORDEM, os três passos já
# existentes do kit — 01 (diagnóstico do dump), 02 (restauração em contêiner
# NOVO) e 03 (validação somente leitura) — e consolida tudo em UM relatório
# (relatorio-auditoria-<data>.txt) com veredito automático fundamentado:
# RECUPERÁVEL / PARCIALMENTE RECUPERÁVEL / NÃO COMPROVADO.
#
# O 05 NÃO duplica a lógica dos passos: chama os scripts existentes e apenas
# analisa os relatórios e logs que ELES produzem. Ele próprio só faz
# verificações preliminares, leitura de arquivos e classificação de erros.
#
# Uso:
#   bash ./05-auditoria-completa.sh CAMINHO_DO_BACKUP.sql.gz \
#        [NOME_DO_CONTAINER] [--graphql] [--out DIRETORIO]
#
#   Exemplo (Windows, chamando o WSL2):
#     wsl -e bash -lc "cd /mnt/c/Users/dowsp/DPSJUR-Backup-Teste && \
#       bash ./05-auditoria-completa.sh ./sbjur_backup_2026-11-11_030001.sql.gz \
#       dpsjur-restore-final"
#
# Flags:
#   --graphql   restauração ADICIONAL da cópia de trabalho corrigida de GraphQL
#               (/tmp/dpsjur_restore_trabalho.sql), em contêiner NOVO próprio
#               (<container>-graphql, porta local +1). NUNCA acontece por
#               padrão. Os erros dessa cópia são apenas INFORMATIVOS e NÃO
#               VALIDAM nada — não afetam o veredito do backup ORIGINAL e não
#               podem melhorá-lo (a correção não é presumida correta).
#   --out DIR   diretório onde os relatórios são gravados (padrão: ao lado do
#               .sql.gz, mesma convenção dos passos 01–03).
#
# ORDEM E GARANTIAS:
#   1. PRÉLIMINARES antes de QUALQUER restore: dentro de WSL2 (/proc/version),
#      docker disponível com endpoint LOCAL (nunca tcp://, ssh://, npipe:// —
#      guarda anti-VPS), scripts 01–03 presentes, legíveis e executáveis,
#      `bash -n` nos 4 scripts (barreira inicial, NÃO prova funcionamento),
#      `gzip -t` no .sql.gz, SHA-256 anotado no relatório e contêiner alvo
#      NOVO (se o nome já existir: exit 73, padrão do kit, SEM tocar em
#      nada). Qualquer falha preliminar ABORTA antes de criar contêiner.
#   2. O contêiner alvo é SEMPRE NOVO: o 05 não reutiliza, não para e não
#      apaga contêiner existente (o 02 também aborta com exit 73 se o nome
#      já existir — o código é repassado sem alterar nada).
#   3. Nunca conectar a nada além de 127.0.0.1: todas as conexões psql são
#      internas ao contêiner, nos scripts 02/03. Nada na VPS, nada em
#      produção, nada em banco remoto.
#   4. O backup original NUNCA é modificado (a cópia GraphQL, quando pedida,
#      é uma cópia nova compactada à parte). O fluxo é bash puro no WSL2.
#   5. NENHUM .ps1 é gerado ou alterado (o anterior foi sinalizado pelo
#      Windows Defender e está BANIDO deste kit).
#
# VEREDITO (critérios objetivos, aplicados na ordem):
#   NÃO COMPROVADO se qualquer etapa (01/02/03) falhar — relatando exatamente
#     qual etapa e o código; se QUALQUER erro do restore não puder ser
#     classificado como ambiental; se a comparação dump×destino não pôde ser
#     feita; ou se qualquer tabela essencial estiver ausente ou com contagem
#     divergente (núcleo de negócio não comprovado).
#   PARCIALMENTE RECUPERÁVEL se o núcleo de negócio (clients, cases, tasks,
#     transactions, leads, settings) está íntegro (presente e com contagens
#     iguais ao dump) e há apenas perdas PONTUAIS — listadas por NOME de
#     objeto (tabelas não essenciais ausentes, contagens divergentes,
#     extensões exigidas não instaladas).
#   RECUPERÁVEL somente se: todas as tabelas com COPY no dump existem no
#     destino + extensões exigidas instaladas + contagens consistentes
#     (dump = destino em todas) + todos os erros restantes classificados como
#     "ambientais" COM EVIDÊNCIA (objetos de sistema Supabase, extensões de
#     nuvem tipo pg_net/pgrst_drop_watch/pgsodium/pgjwt/pg_graphql, papéis
#     exclusivos da nuvem). Erro ambíguo NUNCA vira RECUPERÁVEL.
#
# RELATÓRIO: contém APENAS nomes de objetos, contagens e códigos de saída —
# sem dados de linhas, sem e-mails, sem credenciais. Valores longos entre
# aspas em linhas de erro são redigidos; o log completo do 02 fica no disco
# do usuário e pode conter trechos de dados (não é copiado para o relatório).
#
# Códigos de saída do 05:
#   0  auditoria concluída (veredito no relatório e no stdout)
#   64 uso incorreto (argumento) · 66 arquivo não encontrado · 69 comando
#   ausente · 70 ambiente (fora de WSL / Docker indisponível / endpoint
#   Docker remoto) · 71 verificação preliminar (bash -n / gzip -t) ·
#   73 contêiner alvo já existe · e, se uma etapa 01/02/03 falhar, o código
#   DELA é repassado (o relatório é gerado mesmo assim).
#
# ⚠ NÃO VALIDADO: este script NÃO foi executado e NÃO passou por `bash -n`
# nem por ShellCheck — a plataforma não executa Bash. O primeiro `bash -n` e
# o primeiro uso real acontecem na máquina do usuário (WSL2). Nenhum teste
# foi alegado como aprovado.
# ==============================================================================

set -o errexit
set -o nounset
set -o pipefail
umask 077

readonly SCRIPT_NAME="05-auditoria-completa.sh"
readonly SCRIPT_VERSION="v1.0.0"
readonly SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(dirname "${SELF}")"

readonly S01="${SCRIPT_DIR}/01-diagnostico-backup.sh"
readonly S02="${SCRIPT_DIR}/02-restaurar-limpo.sh"
readonly S03="${SCRIPT_DIR}/03-validar-restauracao.sh"

readonly DEFAULT_CONTAINER="dpsjur-restore-final"
readonly IMAGE="supabase/postgres:15.8.1.085"
readonly GRAPHQL_WORK_SQL="/tmp/dpsjur_restore_trabalho.sql"
# Tabelas essenciais (schema public) destacadas no relatório — SOMENTE nomes
# e contagens, nunca dados de linhas.
readonly ESSENTIALS="clients cases tasks transactions leads settings"

# Evidência de erro AMBIENTAL: somente padrões com objeto conhecido de
# sistema/nuvem Supabase. Qualquer linha de erro fora destes padrões é
# tratada como NÃO CLASSIFICADA (e força veredito NÃO COMPROVADO).
readonly AMBIENT_RE='pgrst_drop_watch|must be owner of event trigger|pg_net|pg_graphql|pgsodium|pgjwt|pg_plan_filter|supautils|pgaudit|supabase_auth_admin|supabase_storage_admin|supabase_realtime_admin|supabase_read_only_user|supabase_functions_admin|supabase_read_replica|role "authenticator"|role "service_role"|role "anon"|role "authenticated"|role "pgbouncer"|schema "net"|extension "[A-Za-z_]+" already exists'

usage() {
    printf 'Uso: %s CAMINHO_DO_BACKUP.sql.gz [NOME_DO_CONTAINER] [--graphql] [--out DIRETORIO]\n' "${SCRIPT_NAME}"
    printf '\nOrquestra 01 (diagnóstico) → 02 (restauração em contêiner NOVO) → 03 (validação)\n'
    printf 'e gera UM relatório com veredito: RECUPERÁVEL / PARCIALMENTE RECUPERÁVEL / NÃO COMPROVADO.\n'
    printf '  NOME_DO_CONTAINER  default: %s (precisa ser um nome NOVO)\n' "${DEFAULT_CONTAINER}"
    printf '  --graphql          restauração ADICIONAL (nunca por padrão) da cópia corrigida\n'
    printf '                     de GraphQL em %s, em contêiner próprio\n' "${GRAPHQL_WORK_SQL}"
    printf '                     (<container>-graphql); resultado apenas informativo.\n'
    printf '  --out DIRETORIO    onde gravar os relatórios (padrão: ao lado do .sql.gz)\n'
    printf '\nNada toca na VPS, em produção, em contêiner existente ou no backup original.\n'
}

die() { # $1=código  rest=mensagem
    local CODE="$1"; shift
    printf 'ERRO: %s\n' "$*" >&2
    exit "${CODE}"
}

as_int() {
    case "$1" in
        ''|*[!0-9]*) printf '0' ;;
        *) printf '%s' "$1" ;;
    esac
}

REDIGE='s/"[^"]{65,}"/"<valor-redigido>"/g'

# ==============================================================================
# Argumentos
# ==============================================================================

BACKUP_FILE=""
CONTAINER="${DEFAULT_CONTAINER}"
OUT_DIR=""
FLAG_GRAPHQL=0

while [ $# -gt 0 ]; do
    case "$1" in
        --graphql) FLAG_GRAPHQL=1 ;;
        --out)     shift; OUT_DIR="${1:?--out requer um diretório}" ;;
        --help|-h) usage; exit 0 ;;
        -*)        printf 'Argumento desconhecido: %s\n' "$1" >&2; usage >&2; exit 64 ;;
        *)
            if [ -z "${BACKUP_FILE}" ]; then
                BACKUP_FILE="$1"
            elif [ "${CONTAINER}" = "${DEFAULT_CONTAINER}" ]; then
                CONTAINER="$1"
            else
                printf 'Argumento inesperado: %s\n' "$1" >&2; usage >&2; exit 64
            fi
            ;;
    esac
    shift
done

[ -n "${BACKUP_FILE}" ] || { printf 'ERRO: informe o caminho do .sql.gz como primeiro argumento.\n' >&2; usage >&2; exit 64; }
[ -f "${BACKUP_FILE}" ] || die 66 "arquivo de backup não encontrado: ${BACKUP_FILE}"

BACKUP_ABS="$(cd "$(dirname "${BACKUP_FILE}")" && pwd)/$(basename "${BACKUP_FILE}")"
[ -r "${BACKUP_ABS}" ] || die 66 "arquivo de backup sem permissão de leitura: ${BACKUP_ABS}"
[ -z "${OUT_DIR}" ] && OUT_DIR="$(dirname "${BACKUP_ABS}")"
mkdir -p "${OUT_DIR}"

STAMP="$(date +%Y-%m-%d_%H%M%S)"
REPORT="${OUT_DIR}/relatorio-auditoria-$(date +%Y-%m-%d).txt"
WORK="${OUT_DIR}/.auditoria-${STAMP}"
mkdir -p "${WORK}"
trap 'rm -rf "${WORK}"' EXIT

HOST_PORT="${SUPABASE_RESTORE_PORT:-15433}"
GRAPHQL_CONTAINER="${CONTAINER}-graphql"
GRAPHQL_PORT=$((HOST_PORT + 1))

: > "${WORK}/erros-nao-classificados.txt"
: > "${WORK}/erros-ambientais.txt"
: > "${WORK}/divergencias.txt"
: > "${WORK}/ausentes.txt"
: > "${WORK}/essenciais.txt"
: > "${WORK}/ext-ausentes.txt"

# ==============================================================================
# PRÉLIMINARES — nada de restore antes de tudo isto passar
# ==============================================================================

printf '=================================================================\n'
printf 'AUDITORIA COMPLETA DE RESTAURAÇÃO — %s %s\n' "${SCRIPT_NAME}" "${SCRIPT_VERSION}"
printf 'Backup     : %s\n' "${BACKUP_ABS}"
printf 'Contêiner  : %s (NOVO — aborta se já existir)\n' "${CONTAINER}"
printf 'Imagem     : %s\n' "${IMAGE}"
printf 'Relatório  : %s\n' "${REPORT}"
printf '=================================================================\n\n'
printf '[P] Verificações preliminares (nenhum contêiner é criado nesta fase)...\n'

PRELIM_NOTAS=""

# 1) Dentro de WSL?
if [ ! -r /proc/version ] || ! grep -qi 'microsoft' /proc/version; then
    die 70 "este orquestrador destina-se ao WSL2 (/proc/version sem 'microsoft'). Ambiente não reconhecido como WSL — abortando antes de qualquer restore."
fi
PRELIM_NOTAS="${PRELIM_NOTAS}WSL2: OK | "

# 2) Comandos obrigatórios
for CMD_NEEDED in docker gzip sha256sum bash awk grep sed; do
    command -v "${CMD_NEEDED}" >/dev/null 2>&1 || die 69 "comando obrigatório ausente: ${CMD_NEEDED}"
done
PRELIM_NOTAS="${PRELIM_NOTAS}comandos: OK | "

# 3) Docker com endpoint LOCAL (guarda anti-VPS: nunca tcp/ssh/http/npipe)
DOCKER_EP="${DOCKER_HOST:-}"
if [ -z "${DOCKER_EP}" ]; then
    DOCKER_EP="$(docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null || true)"
fi
case "${DOCKER_EP}" in
    tcp://*|ssh://*|http://*|https://*|npipe://*)
        die 70 "endpoint do Docker NÃO é local (${DOCKER_EP}). Este kit só opera com socket Unix local — abortando."
        ;;
esac
docker info >/dev/null 2>&1 || die 70 "Docker não respondeu (daemon parado?). Abra o Docker Desktop e rode novamente."
PRELIM_NOTAS="${PRELIM_NOTAS}Docker local: OK | "

# 4) Scripts 01–03: existem, legíveis, executáveis
for S in "${S01}" "${S02}" "${S03}"; do
    [ -f "${S}" ] || die 66 "script do kit não encontrado: ${S}"
    [ -r "${S}" ] || die 66 "script do kit sem permissão de leitura: ${S}"
    [ -x "${S}" ] || die 66 "script do kit sem permissão de execução: ${S} (corrija com: chmod +x ${S})"
done
PRELIM_NOTAS="${PRELIM_NOTAS}scripts 01–03: OK | "

# 5) bash -n nos 4 scripts (barreira inicial — NÃO prova funcionamento)
for S in "${S01}" "${S02}" "${S03}" "${SELF}"; do
    if ! bash -n "${S}" 2> "${WORK}/bashn.err"; then
        printf 'ERRO: bash -n falhou em %s:\n' "${S}" >&2
        cat "${WORK}/bashn.err" >&2
        die 71 "erro de sintaxe em ${S} — corrija antes de qualquer restauração."
    fi
done
PRELIM_NOTAS="${PRELIM_NOTAS}bash -n (4 scripts): OK | "

# 6) Integridade do backup: gzip -t + SHA-256
if ! gzip -t "${BACKUP_ABS}" 2> "${WORK}/gzip.err"; then
    printf 'ERRO: gzip -t indicou arquivo corrompido:\n' >&2
    cat "${WORK}/gzip.err" >&2
    die 71 "backup .sql.gz NÃO passou na verificação de integridade gzip — restauração cancelada."
fi
BACKUP_SHA256="$(sha256sum "${BACKUP_ABS}" | awk '{print $1}')"
BACKUP_BYTES="$(wc -c < "${BACKUP_ABS}" | tr -d ' ')"
PRELIM_NOTAS="${PRELIM_NOTAS}gzip -t: OK | SHA-256: anotado"

# 7) Contêiner alvo deve ser NOVO (mesma regra do 02 — falha aqui ANTES de
#    qualquer coisa, sem tocar nos contêineres existentes)
if docker ps -a --format '{{.Names}}' | grep -Fxq "${CONTAINER}"; then
    printf 'ERRO: já existe um contêiner chamado "%s" — este kit NÃO reutiliza nem remove contêineres.\n' "${CONTAINER}" >&2
    printf 'Escolha outro nome (ex.: %s-2). Código 73 (padrão do kit).\n' "${CONTAINER}" >&2
    exit 73
fi
if [ "${FLAG_GRAPHQL}" -eq 1 ] && docker ps -a --format '{{.Names}}' | grep -Fxq "${GRAPHQL_CONTAINER}"; then
    printf 'ERRO: já existe um contêiner chamado "%s" (restauração GraphQL).\n' "${GRAPHQL_CONTAINER}" >&2
    printf 'Escolha outro nome de contêiner base. Código 73 (padrão do kit).\n' >&2
    exit 73
fi
PRELIM_NOTAS="${PRELIM_NOTAS} | contêiner alvo: NOVO"

# 8) Cópia GraphQL (opcional, explícita): precisa existir ANTES de qualquer restore
GRAPHQL_GZ=""
if [ "${FLAG_GRAPHQL}" -eq 1 ]; then
    [ -f "${GRAPHQL_WORK_SQL}" ] || die 66 "cópia de trabalho GraphQL não encontrada: ${GRAPHQL_WORK_SQL} (flag --graphql exige este arquivo)"
    GRAPHQL_GZ="${OUT_DIR}/.graphql-trabalho-${STAMP}.sql.gz"
    gzip -c "${GRAPHQL_WORK_SQL}" > "${GRAPHQL_GZ}" || die 71 "falha ao compactar a cópia de trabalho GraphQL (o arquivo /tmp NÃO foi alterado)"
    gzip -t "${GRAPHQL_GZ}" || die 71 "cópia GraphQL compactada falhou em gzip -t (abortando; /tmp intacto)"
    PRELIM_NOTAS="${PRELIM_NOTAS} | cópia GraphQL: OK (informação, não validação)"
fi

printf '[P] Preliminares OK: %s\n\n' "${PRELIM_NOTAS}"

# ==============================================================================
# ETAPA 1 — diagnóstico do dump (script 01 existente)
# ==============================================================================

printf '[1/3] Executando 01-diagnostico-backup.sh (somente leitura do .sql.gz)...\n'
RC01=0
set +o errexit
bash "${S01}" "${BACKUP_ABS}" --out "${OUT_DIR}"
RC01=$?
set -o errexit
printf '      01 terminou com código %s\n' "${RC01}"

DIAG_REPORT=""
if [ "${RC01}" -eq 0 ]; then
    DIAG_REPORT="$(ls -1t "${OUT_DIR}"/diagnostico-backup-*.txt 2>/dev/null | head -1 || true)"
    if [ -z "${DIAG_REPORT}" ]; then
        printf 'AVISO: relatório do 01 não localizado em %s — comparação dump×destino ficará indisponível.\n' "${OUT_DIR}" >&2
    fi
fi

# ==============================================================================
# ETAPA 2 — restauração em contêiner NOVO (script 02 existente)
# ==============================================================================

RC02=0
RESTORE_LOG=""
if [ "${RC01}" -eq 0 ]; then
    printf '[2/3] Executando 02-restaurar-limpo.sh (contêiner NOVO "%s")...\n' "${CONTAINER}"
    set +o errexit
    bash "${S02}" "${BACKUP_ABS}" "${CONTAINER}"
    RC02=$?
    set -o errexit
    printf '      02 terminou com código %s\n' "${RC02}"
    RESTORE_LOG="$(ls -1t "${OUT_DIR}"/restauracao-"${CONTAINER}"-*.log 2>/dev/null | head -1 || true)"
    if [ "${RC02}" -eq 73 ]; then
        printf 'ERRO: o contêiner "%s" passou a existir no meio da auditoria — nada foi tocado (padrão do kit: exit 73).\n' "${CONTAINER}" >&2
    fi
else
    printf '[2/3] PULADO: o passo 01 falhou (código %s) — nenhum contêiner será criado.\n' "${RC01}"
fi

# ==============================================================================
# ETAPA 3 — validação somente leitura (script 03 existente)
# ==============================================================================

RC03=0
VALID_REPORT=""
if [ "${RC02}" -eq 0 ]; then
    printf '[3/3] Executando 03-validar-restauracao.sh (somente leitura)...\n'
    set +o errexit
    bash "${S03}" "${CONTAINER}" --diagnostico "${DIAG_REPORT}" --out "${OUT_DIR}"
    RC03=$?
    set -o errexit
    printf '      03 terminou com código %s\n' "${RC03}"
    VALID_REPORT="$(ls -1t "${OUT_DIR}"/validacao-restauracao-"${CONTAINER}"-*.txt 2>/dev/null | head -1 || true)"
else
    printf '[3/3] PULADO: a restauração não concluiu (02 código %s) — nada para validar.\n' "${RC02}"
fi

# ==============================================================================
# Cópia GraphQL (opcional) — restauração ADICIONAL, apenas informativa
# ==============================================================================

G_RC_GZ=0; G_RC02=0; G_RC03=0; G_LOG=""; G_REPORT=""; G_ERRORS=0
if [ "${FLAG_GRAPHQL}" -eq 1 ] && [ "${RC02}" -eq 0 ]; then
    printf '[G] Restauração ADICIONAL da cópia GraphQL em contêiner NOVO "%s" (porta %s)...\n' "${GRAPHQL_CONTAINER}" "${GRAPHQL_PORT}"
    set +o errexit
    SUPABASE_RESTORE_PORT="${GRAPHQL_PORT}" bash "${S02}" "${GRAPHQL_GZ}" "${GRAPHQL_CONTAINER}"
    G_RC02=$?
    set -o errexit
    printf '      02 (GraphQL) terminou com código %s\n' "${G_RC02}"
    if [ "${G_RC02}" -eq 0 ]; then
        G_LOG="$(ls -1t "${OUT_DIR}"/restauracao-"${GRAPHQL_CONTAINER}"-*.log 2>/dev/null | head -1 || true)"
        set +o errexit
        bash "${S03}" "${GRAPHQL_CONTAINER}" --out "${OUT_DIR}"
        G_RC03=$?
        set -o errexit
        printf '      03 (GraphQL) terminou com código %s\n' "${G_RC03}"
        G_REPORT="$(ls -1t "${OUT_DIR}"/validacao-restauracao-"${GRAPHQL_CONTAINER}"-*.txt 2>/dev/null | head -1 || true)"
    fi
    if [ -n "${G_LOG}" ] && [ -f "${G_LOG}" ]; then
        G_ERRORS="$(as_int "$(grep -cE '^(psql:|ERRO|ERROR)' "${G_LOG}" || true)")"
    fi
elif [ "${FLAG_GRAPHQL}" -eq 1 ]; then
    printf '[G] PULADO: a restauração principal não concluiu — a cópia GraphQL NÃO será testada.\n'
fi
rm -f "${GRAPHQL_GZ}" 2>/dev/null || true

# ==============================================================================
# Classificação de erros do restore PRINCIPAL (log do 02)
# ==============================================================================

ERR_TOTAL=0; ERR_AMBIENT=0; ERR_UNCLASS=0
if [ -n "${RESTORE_LOG}" ] && [ -f "${RESTORE_LOG}" ]; then
    ERR_TOTAL="$(as_int "$(grep -cE '^(psql:|ERRO|ERROR)' "${RESTORE_LOG}" || true)")"
    grep -E '^(psql:|ERRO|ERROR)' "${RESTORE_LOG}" | sed -E "${REDIGE}" > "${WORK}/erros-sanitizados.txt" || true
    while IFS= read -r LINE; do
        [ -z "${LINE}" ] && continue
        if printf '%s\n' "${LINE}" | grep -iqE "${AMBIENT_RE}"; then
            ERR_AMBIENT=$((ERR_AMBIENT + 1))
            printf '%s\n' "${LINE}" >> "${WORK}/erros-ambientais.txt"
        else
            ERR_UNCLASS=$((ERR_UNCLASS + 1))
            printf '%s\n' "${LINE}" >> "${WORK}/erros-nao-classificados.txt"
        fi
    done < "${WORK}/erros-sanitizados.txt"
fi

# ==============================================================================
# Comparação dump (COPY no 01) × destino (contagens no 03)
# ==============================================================================

COMP_OK=0   # 1 = comparação possível
DUMP_COPY_TABLES=0
TOTAL_MISSING=0
TOTAL_DIVERG=0
ESSENTIAL_MISSING=0
ESSENTIAL_DIVERG=0

if [ -n "${VALID_REPORT}" ] && [ -f "${VALID_REPORT}" ]; then
    if grep -q 'Comparação de tabelas pulada' "${VALID_REPORT}"; then
        COMP_OK=0
    else
        COMP_OK=1
        # Tabelas com COPY no dump (seção do relatório do 01): "354 public.clients"
        if [ -n "${DIAG_REPORT}" ]; then
            awk '/^--- COPY \(tabelas com dados\)/{f=1;next} f && /^$/{exit} f && NF>0 {print}' \
                "${DIAG_REPORT}" | sed -E 's/^[[:space:]]+//; s/"//g' > "${WORK}/copy-dump.txt" || true
        fi
        # Contagens no destino (seção do relatório do 03): "public.clients | 354"
        awk '/^--- Registros por tabela \(count\(\*\) exato\)/{f=1;next} f && /^--- /{exit} f && /\|/ && $0 !~ /^schema\.tabela/ {print}' \
            "${VALID_REPORT}" | tr -d '\r' > "${WORK}/contagens-destino.txt" || true
        # Ausentes / extensões, conforme o próprio 03 apontou
        grep -E '^AUSENTE NO DESTINO: ' "${VALID_REPORT}" | grep -v 'extensão' | sed 's/^AUSENTE NO DESTINO: //' > "${WORK}/ausentes.txt" || true
        grep -E '^AUSENTE NO DESTINO: extensão ' "${VALID_REPORT}" | sed 's/^AUSENTE NO DESTINO: extensão //' > "${WORK}/ext-ausentes.txt" || true

        while read -r CNT TBL; do
            [ -z "${TBL:-}" ] && continue
            DUMP_COPY_TABLES=$((DUMP_COPY_TABLES + 1))
            IS_ESSENTIAL=0
            for E in ${ESSENTIALS}; do
                if [ "${TBL}" = "public.${E}" ]; then IS_ESSENTIAL=1; fi
            done
            DEST_CNT="$(awk -F ' \\| ' -v t="${TBL}" '$1==t{print $2; exit}' "${WORK}/contagens-destino.txt" || true)"
            if [ -z "${DEST_CNT}" ]; then
                TOTAL_MISSING=$((TOTAL_MISSING + 1))
                printf '%s (tabela com COPY no dump, ausente no destino)\n' "${TBL}" >> "${WORK}/divergencias.txt"
                if [ "${IS_ESSENTIAL}" -eq 1 ]; then ESSENTIAL_MISSING=$((ESSENTIAL_MISSING + 1)); fi
            elif [ "${CNT}" != "${DEST_CNT}" ]; then
                TOTAL_DIVERG=$((TOTAL_DIVERG + 1))
                printf '%s | dump(COPY)=%s | destino=%s\n' "${TBL}" "${CNT}" "${DEST_CNT}" >> "${WORK}/divergencias.txt"
                if [ "${IS_ESSENTIAL}" -eq 1 ]; then ESSENTIAL_DIVERG=$((ESSENTIAL_DIVERG + 1)); fi
            fi
        done < "${WORK}/copy-dump.txt"
    fi
fi

MISSING_EXTS="$(as_int "$(wc -l < "${WORK}/ext-ausentes.txt" 2>/dev/null || true)")"

# ==============================================================================
# Tabelas essenciais — presença, contagens e RLS (somente nomes e números)
# ==============================================================================

if [ -n "${VALID_REPORT}" ] && [ -f "${VALID_REPORT}" ]; then
    awk '/^--- Tabelas com RLS HABILITADO/{f=1;next} f && /^--- /{exit} f' \
        "${VALID_REPORT}" | tr -d '\r' > "${WORK}/rls-destino.txt" || true
fi
for E in ${ESSENTIALS}; do
    TBL="public.${E}"
    DUMP_CNT="$(awk -v t="${TBL}" '$2==t{print $1; exit}' "${WORK}/copy-dump.txt" 2>/dev/null || true)"
    DEST_CNT="$(awk -F ' \\| ' -v t="${TBL}" '$1==t{print $2; exit}' "${WORK}/contagens-destino.txt" 2>/dev/null || true)"
    RLS_STS="não listada com RLS habilitado (ou comparação indisponível)"
    if grep -Fq "${TBL} |" "${WORK}/rls-destino.txt" 2>/dev/null; then
        RLS_STS="RLS habilitado no destino"
    fi
    if [ -z "${DUMP_CNT}" ]; then
        printf '%s | não está no dump (sem COPY) | — | — | — | %s\n' "${TBL}" "${RLS_STS}" >> "${WORK}/essenciais.txt"
    elif [ -z "${DEST_CNT}" ]; then
        printf '%s | %s | AUSENTE no destino | %s | — | %s\n' "${TBL}" "sim" "${DUMP_CNT}" "${RLS_STS}" >> "${WORK}/essenciais.txt"
    else
        printf '%s | %s | %s | %s | %s | %s\n' "${TBL}" "sim" "sim" "${DUMP_CNT}" "${DEST_CNT}" "${RLS_STS}" >> "${WORK}/essenciais.txt"
    fi
done

# ==============================================================================
# VEREDITO
# ==============================================================================

VERDICT=""
BASIS=""

add_div_list() {
    if [ "${TOTAL_MISSING}" -gt 0 ] || [ "${TOTAL_DIVERG}" -gt 0 ]; then
        sed 's/^/       /' "${WORK}/divergencias.txt"
    fi
}

if [ "${RC01}" -ne 0 ]; then
    VERDICT="NÃO COMPROVADO"
    BASIS="a ETAPA 1 (diagnóstico) falhou com código ${RC01} — nenhuma restauração foi tentada. Verifique a saída do 01 acima."
elif [ "${RC02}" -ne 0 ]; then
    VERDICT="NÃO COMPROVADO"
    BASIS="a ETAPA 2 (restauração) terminou com código ${RC02} — o passo 03 não foi executado. Verifique o log do 02: $( [ -n "${RESTORE_LOG}" ] && printf '%s' "${RESTORE_LOG}" || printf '(não localizado)' )."
elif [ "${RC03}" -ne 0 ]; then
    VERDICT="NÃO COMPROVADO"
    BASIS="a ETAPA 3 (validação) terminou com código ${RC03} — a restauração aconteceu mas a validação não pôde ser concluída."
elif [ "${COMP_OK}" -ne 1 ]; then
    VERDICT="NÃO COMPROVADO"
    BASIS="a comparação dump×destino não pôde ser feita (relatório do 03 sem comparação, ou diagnóstico do 01 indisponível) — sem ela não é possível comprovar a recuperação."
elif [ "${DUMP_COPY_TABLES}" -eq 0 ]; then
    VERDICT="NÃO COMPROVADO"
    BASIS="nenhuma tabela com COPY foi extraída do diagnóstico do dump — a base de comparação está vazia (formato inesperado do relatório do 01?)."
elif [ "${ERR_UNCLASS}" -gt 0 ]; then
    VERDICT="NÃO COMPROVADO"
    BASIS="${ERR_UNCLASS} erro(s) do restore NÃO puderam ser classificados como ambientais (lista no relatório, seção 2). Erro ambíguo ou não reconhecido impede o veredito RECUPERÁVEL."
elif [ "${ESSENTIAL_MISSING}" -gt 0 ] || [ "${ESSENTIAL_DIVERG}" -gt 0 ]; then
    VERDICT="NÃO COMPROVADO"
    BASIS="tabela(s) essencial(is) de negócio ausente(s) ou com contagem divergente (clients/cases/tasks/transactions/leads/settings) — o núcleo de negócio NÃO está comprovado como íntegro:"
elif [ "${TOTAL_MISSING}" -gt 0 ] || [ "${TOTAL_DIVERG}" -gt 0 ] || [ "${MISSING_EXTS}" -gt 0 ]; then
    VERDICT="PARCIALMENTE RECUPERÁVEL"
    BASIS="o núcleo de negócio (essenciais) está íntegro (presente e com contagens iguais ao dump), mas há perdas PONTUAIS listadas por nome de objeto:"
else
    VERDICT="RECUPERÁVEL"
    BASIS="todas as ${DUMP_COPY_TABLES} tabela(s) com COPY no dump existem no destino; extensões exigidas instaladas; contagens dump=destino em todas; e os ${ERR_AMBIENT} erro(s) restante(s) do restore foram todos classificados como ambientais COM evidência (objetos de sistema/nuvem Supabase: event trigger pgrst_drop_watch, extensões de nuvem pg_net/pgsodium/pgjwt/pg_graphql, papéis exclusivos da nuvem)."
fi

# ==============================================================================
# RELATÓRIO CONSOLIDADO
# ==============================================================================

{
    printf '=================================================================\n'
    printf 'RELATÓRIO DE AUDITORIA COMPLETA DE RESTAURAÇÃO — DPSjur\n'
    printf 'Script   : %s %s (orquestrador dos passos 01 → 02 → 03)\n' "${SCRIPT_NAME}" "${SCRIPT_VERSION}"
    printf 'Gerado em: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    printf 'Backup   : %s\n' "${BACKUP_ABS}"
    printf 'Tamanho  : %s bytes | SHA-256: %s\n' "${BACKUP_BYTES}" "${BACKUP_SHA256}"
    printf 'Contêiner: %s (NOVO) | Imagem: %s | Porta host: 127.0.0.1:%s\n' "${CONTAINER}" "${IMAGE}" "${HOST_PORT}"
    printf 'Ambiente : WSL2 + Docker local (endpoint Unix; nenhuma conexão além de 127.0.0.1)\n'
    printf '=================================================================\n'
    printf '\n'
    printf '--- 0. Verificações preliminares (antes de qualquer restore) -----\n'
    printf '%s\n' "${PRELIM_NOTAS}"
    printf 'bash -n nos 4 scripts: barreira inicial de sintaxe — NÃO prova funcionamento.\n'
    printf 'O backup original NÃO foi modificado. Nenhum contêiner existente foi tocado.\n'
    printf '\n'
    printf '--- 1. Diagnóstico do dump (passo 01) ----------------------------\n'
    printf 'Código de saída : %s\n' "${RC01}"
    printf 'Relatório       : %s\n' "${DIAG_REPORT:-não gerado}"
    if [ -n "${DIAG_REPORT}" ] && [ -f "${DIAG_REPORT}" ]; then
        grep -E '^-- Dumped (from|by) ' "${DIAG_REPORT}" || true
        printf 'pgrst_drop_watch : %s\n' "$(grep -E '^(PRESENTE|AUSENTE):' "${DIAG_REPORT}" | grep -i pgrst | head -1 | cut -d: -f1 || printf '(não determinado)')"
        printf 'CREATE TABLE (aprox.) : %s\n' "$(grep -E '^CREATE TABLE[[:space:]]*:' "${DIAG_REPORT}" | awk -F': ' '{print $2}' | head -1 || printf '0')"
        printf 'Tabelas com COPY      : %s\n' "${DUMP_COPY_TABLES}"
    fi
    printf '\n'
    printf '--- 2. Restauração (passo 02) ------------------------------------\n'
    printf 'Código de saída : %s\n' "${RC02}"
    printf 'Log completo    : %s\n' "${RESTORE_LOG:-não gerado}"
    printf 'Erros no log    : total=%s | ambientais (com evidência)=%s | NÃO classificados=%s\n' \
        "${ERR_TOTAL}" "${ERR_AMBIENT}" "${ERR_UNCLASS}"
    if [ "${ERR_UNCLASS}" -gt 0 ]; then
        printf 'Erros NÃO classificados (valores longos redigidos; análise manual necessária):\n'
        cut -c1-200 "${WORK}/erros-nao-classificados.txt" | sed 's/^/  /'
        printf '>> Estes erros FORÇAM o veredito NÃO COMPROVADO.\n'
    fi
    if [ "${ERR_AMBIENT}" -gt 0 ]; then
        printf 'Objetos citados nos erros ambientais (somente nomes):\n'
        grep -oE '"[A-Za-z_][A-Za-z0-9_.]*"' "${WORK}/erros-ambientais.txt" | sort -u | head -20 | sed 's/^/  /' || true
    fi
    printf '\n'
    printf '--- 3. Validação (passo 03) --------------------------------------\n'
    printf 'Código de saída : %s\n' "${RC03}"
    printf 'Relatório       : %s\n' "${VALID_REPORT:-não gerado}"
    if [ "${COMP_OK}" -eq 1 ]; then
        printf 'Tabelas com COPY no dump : %s\n' "${DUMP_COPY_TABLES}"
        printf 'Ausentes no destino      : %s\n' "${TOTAL_MISSING}"
        printf 'Contagens divergentes    : %s\n' "${TOTAL_DIVERG}"
        printf 'Extensões exigidas ausentes: %s\n' "${MISSING_EXTS}"
        if [ -s "${WORK}/ext-ausentes.txt" ]; then
            printf '  extensões: '; tr '\n' ' ' < "${WORK}/ext-ausentes.txt"; printf '\n'
        fi
    else
        printf 'Comparação dump×destino: INDISPONÍVEL (ver seção 2/3 dos passos 01/03).\n'
    fi
    printf '\n'
    printf '--- 4. Tabelas essenciais (dump × destino; somente contagens) ----\n'
    printf 'tabela | no dump | no destino | contagem dump (COPY) | contagem destino | RLS\n'
    cat "${WORK}/essenciais.txt"
    printf '\n'
    printf '>> Integridade estrutural ao nível de colunas NÃO é coberta pelos\n'
    printf '>> relatórios 01–03; o que se comprova aqui é existência, contagem e RLS.\n'
    printf '\n'
    if [ "${FLAG_GRAPHQL}" -eq 1 ]; then
        printf '--- 5. Cópia de trabalho GraphQL (OPCIONAL, NÃO VALIDADA) --------\n'
        printf 'Status: NÃO VALIDADO — restauração adicional apenas INFORMATIVA.\n'
        printf 'Origem copiada : %s (arquivo /tmp NÃO alterado)\n' "${GRAPHQL_WORK_SQL}"
        printf 'Contêiner novo : %s (porta 127.0.0.1:%s) | 02 código=%s | 03 código=%s\n' \
            "${GRAPHQL_CONTAINER}" "${GRAPHQL_PORT}" "${G_RC02}" "${G_RC03}"
        printf 'Erros no log   : %s | Log: %s\n' "${G_ERRORS}" "${G_LOG:-não gerado}"
        printf 'Relatório      : %s\n' "${G_REPORT:-não gerado}"
        printf '>> A correção GraphQL NÃO é presumida correta: os resultados dela\n'
        printf '>> NÃO afetam o veredito do backup ORIGINAL e não podem melhorá-lo.\n'
        printf '\n'
    fi
    printf '--- %s. VEREDITO --------------------------------------------------\n' \
        "$([ "${FLAG_GRAPHQL}" -eq 1 ] && printf '6' || printf '5')"
    printf 'VEREDITO: %s\n' "${VERDICT}"
    printf 'Fundamentação: %s\n' "${BASIS}"
    if [ "${VERDICT}" = "PARCIALMENTE RECUPERÁVEL" ]; then
        printf 'Perdas pontuais (nome do objeto | dump | destino):\n'
        add_div_list || true
        if [ "${MISSING_EXTS}" -gt 0 ]; then
            printf '       extensões ausentes: '; tr '\n' ' ' < "${WORK}/ext-ausentes.txt"; printf '\n'
        fi
    fi
    if [ "${VERDICT}" = "NÃO COMPROVADO" ] && [ "${ESSENTIAL_MISSING}" -gt 0 -o "${ESSENTIAL_DIVERG}" -gt 0 ]; then
        printf 'Divergências em essenciais:\n'
        grep -E '^public\.(clients|cases|tasks|transactions|leads|settings) ' "${WORK}/divergencias.txt" | sed 's/^/       /' || true
    fi
    printf '\n'
    printf '--- %s. Pendências / próximos passos -----------------------------\n' \
        "$([ "${FLAG_GRAPHQL}" -eq 1 ] && printf '7' || printf '6')"
    printf ' 1. Analise os erros NÃO classificados (se houver) no log completo do 02\n'
    printf '    ANTES de declarar qualquer recuperação; este veredito é automático.\n'
    printf ' 2. Cole este relatório de volta na conversa para análise final.\n'
    printf ' 3. O contêiner "%s" foi PRESERVADO para inspeção (nada foi removido).\n' "${CONTAINER}"
    printf ' 4. Nada foi alterado na VPS, em produção, nos contêineres existentes\n'
    printf '    ou no backup original.\n'
    printf '=================================================================\n'
} > "${REPORT}"

# ==============================================================================
# Resumo no stdout
# ==============================================================================

printf '\n=================================================================\n'
printf 'RELATÓRIO CONSOLIDADO: %s\n' "${REPORT}"
if [ "${RC01}" -ne 0 ] || [ "${RC02}" -ne 0 ] || [ "${RC03}" -ne 0 ]; then
    printf 'Etapa com falha: 01=%s 02=%s 03=%s (código original repassado)\n' "${RC01}" "${RC02}" "${RC03}"
fi
printf 'Erros do restore: total=%s ambientais=%s não classificados=%s\n' "${ERR_TOTAL}" "${ERR_AMBIENT}" "${ERR_UNCLASS}"
printf 'Dump×destino: tabelas COPY=%s ausentes=%s contagens divergentes=%s extensões ausentes=%s\n' \
    "${DUMP_COPY_TABLES}" "${TOTAL_MISSING}" "${TOTAL_DIVERG}" "${MISSING_EXTS}"
printf '\nVEREDITO: %s\n' "${VERDICT}"
printf '%s\n' "${BASIS}"
printf '=================================================================\n'

# Propaga o código de uma etapa que falhou (o relatório já foi gerado)
if [ "${RC01}" -ne 0 ]; then exit "${RC01}"; fi
if [ "${RC02}" -ne 0 ]; then exit "${RC02}"; fi
if [ "${RC03}" -ne 0 ]; then exit "${RC03}"; fi
exit 0
