#!/usr/bin/env bash
# ==============================================================================
# DPSjur — VALIDAÇÃO DE RESTAURAÇÃO · KIT AUXILIAR
# Script: docs/vps/restore-validacao/04-hash-validacao.sh
# Versão: v1.0.0
#
# FINALIDADE: calcular o SHA-256 do CONTEÚDO EFETIVAMENTE VERSIONADO de
#   docs/vps/restore-validacao/01-diagnostico-backup.sh
# no commit b19a532 ("0.0.692"), direto do objeto Git, como controle duplo sobre
# a cópia de trabalho. O hash resultante (hexadecimal, 64 caracteres, minúsculas)
# é o valor a ser embedado num bloco PowerShell para validar o download do
# arquivo via GitHub raw nesse commit.
#
#   ./04-hash-validacao.sh           # a partir da raiz do repositório
#
# Passos executados (exatamente os exigidos):
#   1. git log -1 ... -- <arquivo>  → confirma que o último commit que alterou o
#      arquivo é b19a532; se for outro, informa e INTERROMPE (exit 65);
#   2. git cat-file blob b19a532:<arquivo> | sha256sum → hash do BLOB versionado
#      (garante que é o conteúdo do commit, não da cópia de trabalho);
#   3. sha256sum <arquivo> → hash da cópia de trabalho; os dois devem ser
#      idênticos (arquivo não modificado após o commit), senão exit 66.
#
# SAÍDA: os dois hashes em minúsculas + veredito. Nada é modificado: o script é
# SOMENTE LEITURA sobre o repositório.
#
# ⚠ NÃO VALIDADO: este script NÃO foi executado e NÃO passou por `bash -n` nem
# por ShellCheck — a plataforma de build não tem Bash. Rodar no WSL2 de Douglas.
# ==============================================================================

set -o errexit
set -o nounset
set -o pipefail
umask 077

readonly SCRIPT_NAME="04-hash-validacao.sh"
readonly SCRIPT_VERSION="v1.0.0"
readonly TARGET_PATH="docs/vps/restore-validacao/01-diagnostico-backup.sh"
readonly EXPECTED_COMMIT="b19a532"
readonly EXPECTED_SUBJECT="0.0.692"

usage() {
    printf 'Uso: %s\n' "${SCRIPT_NAME}"
    printf '\nCalcula o SHA-256 do blob Git e da cópia de trabalho de:\n  %s\n' "${TARGET_PATH}"
    printf 'Deve ser executado a partir da raiz do repositório.\n'
}

fail() {
    printf 'ERRO: %s\n' "$1" >&2
    exit "$2"
}

# Raiz do repositório (o script pode ser chamado de qualquer subdiretório)
GIT_ROOT="$(git rev-parse --show-toplevel)" || fail "não está dentro de um repositório Git" 64
cd "${GIT_ROOT}"

if [ ! -f "${TARGET_PATH}" ]; then
    fail "arquivo não encontrado no repositório: ${TARGET_PATH}" 66
fi

# ------------------------------------------------------------------------------
# Passo 1 — último commit que alterou o arquivo precisa ser b19a532
# ------------------------------------------------------------------------------

LAST_COMMIT_LINE="$(git log -1 --format='%H %s' -- "${TARGET_PATH}")"
LAST_COMMIT_HASH="${LAST_COMMIT_LINE%% *}"
LAST_COMMIT_SUBJECT="${LAST_COMMIT_LINE#* }"

printf '=================================================================\n'
printf 'PASSO 1 — último commit que alterou o arquivo\n'
printf '%s\n' "${LAST_COMMIT_LINE}"

case "${LAST_COMMIT_HASH}" in
    "${EXPECTED_COMMIT}"*)
        printf 'OK: commit confere (%s / "%s").\n' "${EXPECTED_COMMIT}" "${EXPECTED_SUBJECT}"
        ;;
    *)
        fail "o último commit que alterou o arquivo é ${LAST_COMMIT_HASH} (\"${LAST_COMMIT_SUBJECT}\"), não ${EXPECTED_COMMIT} — interrompendo conforme o protocolo" 65
        ;;
esac

# ------------------------------------------------------------------------------
# Passo 2 — SHA-256 do BLOB versionado (objeto Git do commit b19a532)
# ------------------------------------------------------------------------------

printf '=================================================================\n'
printf 'PASSO 2 — hash do BLOB versionado (git cat-file blob %s:%s)\n' "${EXPECTED_COMMIT}" "${TARGET_PATH}"
BLOB_HASH="$(git cat-file blob "${EXPECTED_COMMIT}:${TARGET_PATH}" | sha256sum | awk '{print $1}')"
printf 'git cat-file blob %s:%s | sha256sum\n=> %s  -\n' "${EXPECTED_COMMIT}" "${TARGET_PATH}" "${BLOB_HASH}"

# ------------------------------------------------------------------------------
# Passo 3 — controle duplo: hash da cópia de trabalho
# ------------------------------------------------------------------------------

printf '=================================================================\n'
printf 'PASSO 3 — hash da cópia de trabalho (sha256sum)\n'
WORK_HASH="$(sha256sum "${TARGET_PATH}" | awk '{print $1}')"
printf '=> %s  %s\n' "${WORK_HASH}" "${TARGET_PATH}"

# ------------------------------------------------------------------------------
# Veredito
# ------------------------------------------------------------------------------

printf '=================================================================\n'
if [ "${BLOB_HASH}" = "${WORK_HASH}" ]; then
    printf 'VEREDITO: hashes IDÊNTICOS — arquivo não modificado após o commit %s.\n' "${EXPECTED_COMMIT}"
    printf 'SHA-256 (hex, minúsculas) para embedar no bloco PowerShell:\n'
    printf '%s\n' "${BLOB_HASH}"
    printf '=================================================================\n'
    exit 0
else
    fail "hashes DIVERGEM: blob Git ${BLOB_HASH} != cópia de trabalho ${WORK_HASH} — o arquivo foi modificado após o commit; não embedar no PowerShell" 66
fi
