#!/bin/sh
set -e

# Gera o arquivo /usr/share/nginx/html/env.js dinamicamente em runtime
# com base nas variáveis de ambiente injetadas no contêiner (ex: pelo EasyPanel)
TARGET_DIR="/usr/share/nginx/html"
TARGET_FILE="$TARGET_DIR/env.js"

mkdir -p "$TARGET_DIR"

# Função utilitária para sanitizar valores JS de forma defensiva:
# 1. Remove espaços e quebras de linha nas extremidades
# 2. Remove aspas ou crases nas extremidades ("...", '...', `...`)
# 3. Remove prefixos colados por engano (ANON_KEY=, VITE_SUPABASE_PUBLISHABLE_KEY=, VITE_SUPABASE_URL=)
# 4. Remove barra final caso seja URL
# 5. Escapa barras invertidas e aspas duplas para o JSON
sanitize_val() {
  raw="$1"
  is_url="$2"

  # Trim de espaços/tabs
  cleaned=$(printf '%s' "$raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

  # Remove aspas externas repetidamente
  while :; do
    orig="$cleaned"
    cleaned=$(printf '%s' "$cleaned" | sed -e 's/^["'\''`]*//' -e 's/["'\''`]*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [ "$orig" = "$cleaned" ] && break
  done

  # Remove prefixos acidentais
  while :; do
    orig="$cleaned"
    cleaned=$(printf '%s' "$cleaned" | sed -E -e 's/^(ANON_KEY|VITE_SUPABASE_PUBLISHABLE_KEY|VITE_SUPABASE_URL|SUPABASE_ANON_KEY|SUPABASE_URL)[[:space:]]*[:=][[:space:]]*//I' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    cleaned=$(printf '%s' "$cleaned" | sed -e 's/^["'\''`]*//' -e 's/["'\''`]*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [ "$orig" = "$cleaned" ] && break
  done

  # Se for URL, remove barras finais
  if [ "$is_url" = "1" ]; then
    cleaned=$(printf '%s' "$cleaned" | sed -e 's|/*$||')
  fi

  # Escapar para JSON seguro
  printf '%s' "$cleaned" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

RAW_URL="${VITE_SUPABASE_URL:-https://cpcafthwnqazopqftemj.supabase.co}"
RAW_KEY="${VITE_SUPABASE_PUBLISHABLE_KEY:-sb_publishable_n8rNjvEg6i-Sjme1-5Yhug_nNwxBRwO}"

SAFE_SUPABASE_URL=$(sanitize_val "$RAW_URL" "1")
SAFE_SUPABASE_KEY=$(sanitize_val "$RAW_KEY" "0")

cat <<EOF > "$TARGET_FILE"
window.__ENV__ = {
  "VITE_SUPABASE_URL": "$SAFE_SUPABASE_URL",
  "VITE_SUPABASE_PUBLISHABLE_KEY": "$SAFE_SUPABASE_KEY"
};
window.env = window.__ENV__;
EOF

echo "[DPSjur Entrypoint] env.js gerado com sucesso em $TARGET_FILE"
if [ -n "$VITE_SUPABASE_URL" ]; then
  echo "[DPSjur Entrypoint] VITE_SUPABASE_URL obtida do ambiente: $SAFE_SUPABASE_URL"
else
  echo "[DPSjur Entrypoint] VITE_SUPABASE_URL vazia no ambiente; usando fallback padrão: $SAFE_SUPABASE_URL"
fi

if [ -n "$VITE_SUPABASE_PUBLISHABLE_KEY" ]; then
  echo "[DPSjur Entrypoint] VITE_SUPABASE_PUBLISHABLE_KEY obtida do ambiente (tamanho: ${#SAFE_SUPABASE_KEY} chars)"
else
  echo "[DPSjur Entrypoint] VITE_SUPABASE_PUBLISHABLE_KEY vazia no ambiente; usando fallback padrão (tamanho: ${#SAFE_SUPABASE_KEY} chars)"
fi

# Executa o comando passado como argumento (ex: nginx -g "daemon off;")
exec "$@"
