#!/usr/bin/env bash
# ==============================================================================
# 01-adicionar-no-fees-subprocessos-vps.sh
# Adiciona a coluna "noFees" (boolean, default false) na tabela "cases"
# para permitir marcar subprocessos como "Não gera honorários".
#
# Padrão: auto-detecção do contêiner Postgres, do usuário do banco,
# aplicação idempotente de migration e reload do PostgREST.
#
# Uso no VPS:
#   cd /root/sbjur-migracao || cd /root
#   bash 01-adicionar-no-fees-subprocessos-vps.sh
# ==============================================================================

set -euo pipefail

echo "=================================================================="
echo "DPSjur: Adicionando coluna noFees na tabela cases (Subprocessos)"
echo "=================================================================="

# 1. Detectar contêiner Postgres
echo "→ 1. Detectando contêiner do Postgres..."
CONTAINER_PG=$(docker ps --format '{{.Names}}' | grep -E '(supabase.*db|postgres|db)' | head -n 1 || true)

if [ -z "$CONTAINER_PG" ]; then
    echo "ERRO: Contêiner do Postgres não encontrado via 'docker ps'."
    exit 1
fi
echo "✓ Contêiner Postgres encontrado: $CONTAINER_PG"

# 2. Detectar usuário do Postgres
DB_USER=$(docker exec "$CONTAINER_PG" env | grep -E '^POSTGRES_USER=' | cut -d'=' -f2 || true)
if [ -z "$DB_USER" ]; then
    DB_USER="postgres"
fi
DB_NAME=$(docker exec "$CONTAINER_PG" env | grep -E '^POSTGRES_DB=' | cut -d'=' -f2 || true)
if [ -z "$DB_NAME" ]; then
    DB_NAME="postgres"
fi
echo "✓ Conectando como usuário '$DB_USER' no banco '$DB_NAME'"

# 3. Executar SQL
echo "→ 2. Aplicando alteração de schema..."
SQL="
DO \$\$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'cases' 
          AND column_name = 'noFees'
    ) THEN
        ALTER TABLE public.cases ADD COLUMN \"noFees\" BOOLEAN NOT NULL DEFAULT false;
        RAISE NOTICE 'Coluna noFees adicionada com sucesso na tabela cases.';
    ELSE
        RAISE NOTICE 'Coluna noFees já existe na tabela cases.';
    END IF;
END \$\$;
"

docker exec -i "$CONTAINER_PG" psql -U "$DB_USER" -d "$DB_NAME" -c "$SQL"

# 4. Notificar PostgREST para recarregar o schema cache
echo "→ 3. Recarregando schema cache do PostgREST..."
docker exec -i "$CONTAINER_PG" psql -U "$DB_USER" -d "$DB_NAME" -c "NOTIFY pgrst, 'reload schema';" || true

# Se houver contêiner do PostgREST / rest, reiniciar ou enviar SIGHUP se necessário
CONTAINER_REST=$(docker ps --format '{{.Names}}' | grep -E '(rest|postgrest)' | head -n 1 || true)
if [ -n "$CONTAINER_REST" ]; then
    echo "✓ Notificando contêiner PostgREST: $CONTAINER_REST"
    docker kill --signal=SIGUSR1 "$CONTAINER_REST" 2>/dev/null || true
fi

# 5. Verificação final
echo "→ 4. Verificando se a coluna noFees está presente..."
CHECK_RESULT=$(docker exec -i "$CONTAINER_PG" psql -U "$DB_USER" -d "$DB_NAME" -t -A -c "
    SELECT column_name || ' (' || data_type || ')'
    FROM information_schema.columns 
    WHERE table_schema = 'public' 
      AND table_name = 'cases' 
      AND column_name = 'noFees';
")

if [ -n "$CHECK_RESULT" ]; then
    echo "=================================================================="
    echo "✓ [OK] Migration aplicada com sucesso!"
    echo "  Coluna confirmada: $CHECK_RESULT"
    echo "=================================================================="
else
    echo "=================================================================="
    echo "ERRO: Coluna noFees não foi encontrada após a execução."
    echo "=================================================================="
    exit 1
fi
