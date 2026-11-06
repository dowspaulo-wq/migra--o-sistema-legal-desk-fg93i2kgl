#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Rotinas automáticas de e-mail (véspera de compromissos e
# aniversariantes do dia).
# Script gerado em /root/sbjur-emails/rotinas-email.sh pelo instalador
# docs/vps/11-rotinas-email-vps.sh — NÃO editar a cópia do repositório esperando
# efeito no VPS: edite o instalador e rode-o novamente.
# ==============================================================================
#
# ROTINA 1 (--vespera): e-mail às 07:00 BSB com audiências e compromissos do
#   DIA SEGUINTE. Regra do fim de semana (decisão do Douglas): se o compromisso
#   é na segunda-feira, o aviso sai na sexta-feira — o e-mail de sexta cobre
#   sábado, domingo e segunda; sábado e domingo NÃO rodam.
# ROTINA 2 (--aniversarios): e-mail às 08:00 BSB com os clientes que fazem
#   aniversário NAQUELE dia, com telefone e link wa.me pronto para clique
#   manual (sem disparo automático — decisão registrada do usuário).
#
# Envio reutiliza o mecanismo do backup (docs/backup-fase6/04-configurar-email.sh):
# msmtp com /root/.msmtprc; sem msmtp, curl SMTP com as mesmas credenciais.
#
# Modo de teste (não envia nada, imprime o e-mail no terminal):
#   bash /root/sbjur-emails/rotinas-email.sh --vespera --dry-run
#   bash /root/sbjur-emails/rotinas-email.sh --aniversarios --dry-run
# ==============================================================================

set -u

WORK_DIR="/root/sbjur-emails"
LOGS_DIR="${WORK_DIR}/logs"
LOG_FILE="${LOGS_DIR}/rotinas-email.log"
MSMTP_CONF="/root/.msmtprc"
EMAIL_ENV_FILE="/root/sbjur-backups/config/email.conf"  # mesma fonte do backup
BASE_URL="https://sistema.advdouglaspsantos.com.br"
DEFAULT_TO="dowspaulo@gmail.com"

# Fuso de referência: horário de Brasília (UTC-3, sem horário de verão).
TZ="America/Sao_Paulo"
export TZ

LOG_MAX_BYTES=5242880
MAX_LOG_KEEP=500

# ------------------------------------------------------------------------------
# Utilidades
# ------------------------------------------------------------------------------

mkdir -p "${LOGS_DIR}" 2>/dev/null || true

log_msg() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "${msg}"
    echo "${msg}" >> "${LOG_FILE}" 2>/dev/null || true
}

rotate_log() {
    if [ -f "${LOG_FILE}" ]; then
        local size
        size=$(stat -c%s "${LOG_FILE}" 2>/dev/null || echo 0)
        if [ "${size}" -gt "${LOG_MAX_BYTES}" ]; then
            local tmp
            tmp=$(mktemp 2>/dev/null || echo "/tmp/rotinas-email-tmp.log")
            tail -n "${MAX_LOG_KEEP}" "${LOG_FILE}" > "${tmp}" 2>/dev/null || true
            mv -f "${tmp}" "${LOG_FILE}" 2>/dev/null || true
        fi
    fi
}

# Normaliza telefone para o padrão internacional do WhatsApp (55 + DDD + número).
normalize_phone_wa() {
    local raw="$1"
    local digits
    digits=$(echo "${raw}" | tr -cd '0-9')
    # Descarta valores sem sentido (ex.: "0", placeholder do cadastro).
    if [ "${#digits}" -lt 10 ]; then
        echo ""
        return
    fi
    # Remove prefixo 0 inicial herdado de cadastros antigos.
    digits=$(echo "${digits}" | sed 's/^0\{1,2\}//')
    if [ "${#digits}" -le 11 ]; then
        digits="55${digits}"
    fi
    echo "${digits}"
}

# URL-encode (apenas o necessário para texto de wa.me).
urlencode() {
    local s="$1"
    local out="" c i
    for ((i = 0; i < ${#s}; i++)); do
        c="${s:$i:1}"
        case "${c}" in
            [a-zA-Z0-9.~_-]) out+="${c}" ;;
            ' ') out+="%20" ;;
            *) printf -v c '%%%02X' "'${c}"; out+="${c}" ;;
        esac
    done
    echo "${out}"
}

primeiro_nome() {
    echo "$1" | awk '{print $1}'
}

# ------------------------------------------------------------------------------
# Banco: psql direto no Postgres do Supabase self-hosted (EasyPanel) do VPS.
# NÃO usa a base da nuvem Skip. Padrão dos demais scripts VPS do projeto.
# ------------------------------------------------------------------------------

DB_CONTAINER=""
DB_USER="postgres"
DB_NAME="postgres"
DB_PASSWORD=""

detect_db() {
    DB_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E 'supabase[-_]db' | head -n 1 || true)
    if [ -z "${DB_CONTAINER}" ]; then
        log_msg "[ERRO] Conteiner PostgreSQL do Supabase não encontrado (docker ps | grep supabase-db)."
        return 1
    fi

    # Senha: variável de ambiente do contêiner (POSTGRES_PASSWORD), padrão dos scripts VPS.
    DB_PASSWORD=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "${DB_CONTAINER}" 2>/dev/null \
        | grep -E '^POSTGRES_PASSWORD=' | head -n 1 | cut -d= -f2- || true)

    # Usuário: tenta postgres; cai para supabase_admin se necessário.
    if docker exec -e PGPASSWORD="${DB_PASSWORD}" "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -tAc "SELECT 1;" >/dev/null 2>&1; then
        return 0
    fi
    for u in supabase_admin; do
        if docker exec -e PGPASSWORD="${DB_PASSWORD}" "${DB_CONTAINER}" psql -U "${u}" -d "${DB_NAME}" -tAc "SELECT 1;" >/dev/null 2>&1; then
            DB_USER="${u}"
            return 0
        fi
    done
    log_msg "[ERRO] Não foi possível conectar ao PostgreSQL do contêiner ${DB_CONTAINER}."
    return 1
}

# Executa SQL e devolve a saída limpa (-tA). Em erro, registra no log.
run_sql() {
    local sql="$1"
    local out rc
    out=$(docker exec -e PGPASSWORD="${DB_PASSWORD}" "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -tA -c "${sql}" 2>&1)
    rc=$?
    if [ ${rc} -ne 0 ] || echo "${out}" | grep -qE '^(ERROR|FATAL|psql:)'; then
        log_msg "[ERRO] Falha SQL: ${out}"
        return 1
    fi
    echo "${out}"
}

# ------------------------------------------------------------------------------
# Envio de e-mail: msmtp (/root/.msmtprc do kit de backup) com fallback curl.
# ------------------------------------------------------------------------------

SMTP_FROM=""
SMTP_USER=""
SMTP_PASS=""

load_smtp() {
    if [ -f "${EMAIL_ENV_FILE}" ]; then
        # shellcheck disable=SC1090
        . "${EMAIL_ENV_FILE}" 2>/dev/null || true
        SMTP_FROM="${SMTP_USER:-}"
        SMTP_PASS="${SMTP_PASS:-}"
    fi
    if [ -z "${SMTP_FROM}" ] && [ -f "${MSMTP_CONF}" ]; then
        SMTP_FROM=$(awk '/^from /{print $2; exit}' "${MSMTP_CONF}" 2>/dev/null || true)
    fi
    if [ -z "${SMTP_FROM}" ]; then
        SMTP_FROM="${DEFAULT_TO}"
    fi
}

send_email() {
    local to="$1" subject="$2" body_file="$3"

    if [ "${DRY_RUN}" = "1" ]; then
        echo "----- DRY-RUN: e-mail NÃO enviado -----"
        echo "De:    ${SMTP_FROM}"
        echo "Para:  ${to}"
        echo "Assunto: ${subject}"
        echo "------------------------------------------------------"
        cat "${body_file}"
        echo "------------------------------------------------------"
        return 0
    fi

    local msg_file
    msg_file=$(mktemp 2>/dev/null || echo "/tmp/sbjur-email-msg-$$.txt")
    {
        echo "From: SBJur Avisos <${SMTP_FROM}>"
        echo "To: ${to}"
        echo "Subject: ${subject}"
        echo "Content-Type: text/plain; charset=UTF-8"
        echo "Content-Transfer-Encoding: 8bit"
        echo ""
        cat "${body_file}"
    } > "${msg_file}"

    local sent=0
    if command -v msmtp >/dev/null 2>&1; then
        if msmtp -a default "${to}" < "${msg_file}" 2>>"${LOG_FILE}"; then
            sent=1
        fi
    fi
    if [ ${sent} -eq 0 ] && command -v curl >/dev/null 2>&1 && [ -n "${SMTP_USER}" ] && [ -n "${SMTP_PASS}" ]; then
        if curl -sS --url "smtp://smtp.gmail.com:587" --ssl-reqd \
            --mail-from "${SMTP_USER}" --mail-rcpt "${to}" \
            --user "${SMTP_USER}:${SMTP_PASS}" \
            --upload-file "${msg_file}" >>"${LOG_FILE}" 2>&1; then
            sent=1
        fi
    fi
    rm -f "${msg_file}" 2>/dev/null || true

    if [ ${sent} -eq 1 ]; then
        log_msg "[OK] E-mail enviado para ${to} (assunto: ${subject})"
    else
        log_msg "[ERRO] Falha ao enviar e-mail para ${to} (assunto: ${subject})."
        log_msg "[ERRO] Verifique /root/.msmtprc e ${EMAIL_ENV_FILE} (senha de app do Gmail)."
    fi
    return $((1 - sent))
}

# ------------------------------------------------------------------------------
# ROTINA 1 — Véspera de audiências/compromissos
# ------------------------------------------------------------------------------
# Regra do fim de semana: no sábado e no domingo NÃO roda. Na sexta, cobre
# sábado, domingo e segunda (compromisso de segunda é avisado na sexta).

run_vespera() {
    local hoje dow
    hoje=$(date +%F)
    dow=$(date +%u)  # 1=segunda ... 5=sexta, 6=sábado, 7=domingo

    if [ "${dow}" = "6" ] || [ "${dow}" = "7" ]; then
        log_msg "[VESPERA] Fim de semana: envio pulado por decisão do usuário (avisos de 2a saem na sexta)."
        exit 0
    fi

    local datas="'$(date -d "${hoje} +1 day" +%F)'"
    local datas_label
    datas_label=$(date -d "${hoje} +1 day" '+%d/%m/%Y (%A)')
    export LC_ALL=C
    datas_label=$(echo "${datas_label}" | sed \
        -e 's/Monday/segunda-feira/' -e 's/Tuesday/terca-feira/' \
        -e 's/Wednesday/quarta-feira/' -e 's/Thursday/quinta-feira/' \
        -e 's/Friday/sexta-feira/' -e 's/Saturday/sabado/' -e 's/Sunday/domingo/')

    if [ "${dow}" = "5" ]; then
        local d1 d2 d3
        d1=$(date -d "${hoje} +1 day" +%F)   # sábado
        d2=$(date -d "${hoje} +2 days" +%F)  # domingo
        d3=$(date -d "${hoje} +3 days" +%F)  # segunda
        datas="'${d1}','${d2}','${d3}'"
        datas_label=$(printf '%s, %s e %s' \
            "$(date -d "${d1}" '+%d/%m (%A)')" \
            "$(date -d "${d2}" '+%d/%m (%A)')" \
            "$(date -d "${d3}" '+%d/%m (%A)')")
    fi
    datas_label=$(echo "${datas_label}" | sed \
        -e 's/Monday/segunda-feira/' -e 's/Tuesday/terca-feira/' \
        -e 's/Wednesday/quarta-feira/' -e 's/Thursday/quinta-feira/' \
        -e 's/Friday/sexta-feira/' -e 's/Saturday/sabado/' -e 's/Sunday/domingo/')

    local sql="
        SELECT
            a.date,
            COALESCE(NULLIF(a.time, ''), 'Horário não informado'),
            COALESCE(NULLIF(a.type, ''), 'Compromisso'),
            COALESCE(NULLIF(c.name, ''), 'Cliente não informado'),
            COALESCE(NULLIF(p.number, ''), '—'),
            COALESCE(NULLIF(p.court, ''), '—'),
            COALESCE(NULLIF(p.comarca, ''), '—'),
            a.id
        FROM public.appointments a
        LEFT JOIN public.cases p ON p.id = a.processId
        LEFT JOIN public.clients c ON c.id = a.clientId
        WHERE a.date IN (${datas})
          AND (COALESCE(a.status, '') NOT IN ('Concluído', 'Cancelado'))
        ORDER BY a.date, a.time NULLS LAST, c.name"
    local dados
    dados=$(run_sql "${sql}") || return 1

    local body_file
    body_file=$(mktemp 2>/dev/null || echo "/tmp/sbjur-vespera-$$.txt")

    if [ -z "${dados}" ]; then
        cat > "${body_file}" <<EOF
Ola, Douglas!

SEM AUDIENCIAS / COMPROMISSOS para ${datas_label}.

Nenhuma audiencia ou compromisso cadastrado no SBJur para esse(s) dia(s).
(E-mail enviado automaticamente para o silencio significar problema.)
EOF
        send_email "${EMAIL_TO}" "[SBJur] Sem audiencias/compromissos amanha (${datas_label})" "${body_file}"
        rm -f "${body_file}" 2>/dev/null || true
        return 0
    fi

    {
        echo "Ola, Douglas!"
        echo ""
        echo "Audiencias e compromissos de ${datas_label}:"
        echo ""
        local n=0
        while IFS='|' read -r data hora tipo cliente processo vara comarca aid; do
            n=$((n + 1))
            echo "---------------------------------------------"
            echo "${n}. ${data} as ${hora} — ${tipo}"
            echo "   Cliente:  ${cliente}"
            echo "   Processo: ${processo}"
            echo "   Vara:     ${vara}"
            echo "   Comarca:  ${comarca}"
            echo "   Abrir no sistema: ${BASE_URL}/agenda"
        done <<EOF2
${dados}
EOF2
        echo "---------------------------------------------"
        echo ""
        echo "Total: ${n} compromisso(s)."
        echo "Mensagem automatica do SBJur (VPS) - rotina de vespera (07:00 BSB)."
    } > "${body_file}"

    send_email "${EMAIL_TO}" "[SBJur] Amanha: ${n} compromisso(s) - ${datas_label}" "${body_file}"
    local rc=$?
    rm -f "${body_file}" 2>/dev/null || true
    return ${rc}
}

# ------------------------------------------------------------------------------
# ROTINA 2 — Aniversariantes do dia
# ------------------------------------------------------------------------------
# Regra 29/02 (documentada): em ano não bissexto, aniversariantes de 29/02 são
# lembrados em 01/03 (28/02 fica só de quem nasceu em 28/02).

run_aniversarios() {
    local hoje_mm_dd
    hoje_mm_dd=$(date +%m-%d)

    local cond_mmdd="substring(c.birthday from 6 for 5) = '${hoje_mm_dd}'"
    # 01/03 em ano NÃO bissexto inclui também os de 29/02.
    if [ "${hoje_mm_dd}" = "03-01" ] && ! date -d "$(date +%Y)-02-29" >/dev/null 2>&1; then
        cond_mmdd="substring(c.birthday from 6 for 5) IN ('03-01','02-29')"
    fi

    local sql="
        SELECT c.name, COALESCE(NULLIF(c.phone, ''), 'Sem telefone cadastrado'), c.id
        FROM public.clients c
        WHERE c.birthday ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
          AND c.birthday NOT LIKE '0001-%'
          AND c.birthday NOT LIKE '0000-%'
          AND ${cond_mmdd}
        ORDER BY c.name"
    local dados
    dados=$(run_sql "${sql}") || return 1

    local hoje_label
    hoje_label=$(date '+%d/%m/%Y')
    local body_file
    body_file=$(mktemp 2>/dev/null || echo "/tmp/sbjur-aniv-$$.txt")

    if [ -z "${dados}" ]; then
        cat > "${body_file}" <<EOF
Ola, Douglas!

SEM ANIVERSARIANTES hoje (${hoje_label}).
(E-mail enviado automaticamente para o silencio significar problema.)
EOF
        send_email "${EMAIL_TO}" "[SBJur] Sem aniversariantes hoje (${hoje_label})" "${body_file}"
        rm -f "${body_file}" 2>/dev/null || true
        return 0
    fi

    {
        echo "Ola, Douglas!"
        echo ""
        echo "Aniversariantes de hoje (${hoje_label}):"
        echo ""
        local n=0 nome fone cid msg enc_msg wa_num
        while IFS='|' read -r nome fone cid; do
            n=$((n + 1))
            msg="Parabens, $(primeiro_nome "${nome}")! O escritorio Douglas P. Santos Advocacia lhe deseja um feliz aniversario! Muitas felicidades e sucesso sempre."
            enc_msg=$(urlencode "${msg}")
            echo "---------------------------------------------"
            echo "${n}. ${nome}"
            echo "   Telefone: ${fone}"
            wa_num=$(normalize_phone_wa "${fone}")
            if [ -n "${wa_num}" ]; then
                echo "   WhatsApp: https://wa.me/${wa_num}?text=${enc_msg}"
            else
                echo "   WhatsApp: numero invalido ou ausente no cadastro (${fone}) - conferir no sistema."
            fi
            echo "   Abrir no sistema: ${BASE_URL}/clientes/${cid}"
        done <<EOF2
${dados}
EOF2
        echo "---------------------------------------------"
        echo ""
        echo "Total: ${n} aniversariante(s). Clique no link do WhatsApp para enviar o parabens (envio manual, sem automacao)."
        echo "Mensagem automatica do SBJur (VPS) - rotina de aniversariantes (08:00 BSB)."
    } > "${body_file}"

    send_email "${EMAIL_TO}" "[SBJur] ${n} aniversariante(s) hoje (${hoje_label})" "${body_file}"
    local rc=$?
    rm -f "${body_file}" 2>/dev/null || true
    return ${rc}
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------

rotate_log

MODE=""
DRY_RUN=0
EMAIL_TO="${SBJUR_EMAIL_TO:-${DEFAULT_TO}}"

for arg in "$@"; do
    case "${arg}" in
        --vespera) MODE="vespera" ;;
        --aniversarios) MODE="aniversarios" ;;
        --dry-run) DRY_RUN=1 ;;
        --to=*) EMAIL_TO="${arg#--to=}" ;;
        *) echo "Uso: $0 [--vespera|--aniversarios] [--dry-run] [--to=email@dominio]" >&2; exit 2 ;;
    esac
done

if [ -z "${MODE}" ]; then
    echo "Uso: $0 [--vespera|--aniversarios] [--dry-run] [--to=email@dominio]" >&2
    exit 2
fi

load_smtp

if [ "${DRY_RUN}" = "0" ]; then
    if ! command -v docker >/dev/null 2>&1; then
        log_msg "[ERRO] Docker não encontrado no VPS."
        exit 1
    fi
    detect_db || exit 1
fi

case "${MODE}" in
    vespera)
        log_msg "[VESPERA] Iniciando rotina de vespera (dry-run=${DRY_RUN}, destino=${EMAIL_TO})."
        run_vespera
        exit $?
        ;;
    aniversarios)
        log_msg "[ANIVERSARIOS] Iniciando rotina de aniversariantes (dry-run=${DRY_RUN}, destino=${EMAIL_TO})."
        run_aniversarios
        exit $?
        ;;
esac
