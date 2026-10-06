#!/bin/sh
set -e

# Gera o arquivo /usr/share/nginx/html/env.js dinamicamente em runtime
# com base nas variáveis de ambiente injetadas no contêiner (ex: pelo EasyPanel)
TARGET_DIR="/usr/share/nginx/html"
TARGET_FILE="$TARGET_DIR/env.js"

mkdir -p "$TARGET_DIR"

# Função utilitária para sanitizar valores JS (escapar barras invertidas e aspas)
sanitize_val() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

SAFE_SUPABASE_URL=$(sanitize_val "${VITE_SUPABASE_URL:-https://cpcafthwnqazopqftemj.supabase.co}")
SAFE_SUPABASE_KEY=$(sanitize_val "${VITE_SUPABASE_PUBLISHABLE_KEY:-sb_publishable_n8rNjvEg6i-Sjme1-5Yhug_mNwxBRwO}")

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
