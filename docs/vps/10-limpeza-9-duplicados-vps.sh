#!/usr/bin/env bash
# Wrapper para compatibilidade com o nome do arquivo citado na aceitação
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${DIR}/10-limpeza-duplicados-origens-vps.sh" "$@"
