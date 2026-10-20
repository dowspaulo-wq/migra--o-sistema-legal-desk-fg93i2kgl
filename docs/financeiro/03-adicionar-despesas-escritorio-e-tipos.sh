#!/usr/bin/env bash
# ==============================================================================
# 03-adicionar-despesas-escritorio-e-tipos.sh
# Adiciona:
#   1. Coluna "supplier_group" (text) na tabela "transactions"
#   2. Coluna "expenseTypes" (jsonb) na tabela "settings"
#   3. Preenche retroativamente "supplier_group" a partir de suppliers
#
# Padrão: auto-detecção do contêiner Postgres, do usuário do banco,
# aplicação idempotente de migration e reload do PostgREST.
#
# Uso no VPS:
#   cd /root/sbjur-migracao || cd /root
#   bash 03-adicionar-despesas-escritorio-e-tipos.sh
# ==============================================================================

set -euo pipefail

echo "=================================================================="
echo "DPSjur: Adicionando Despesas do Escritório, Tipos de Despesa e Grupo"
echo "=================================================================="

# 1. Detectar contêiner Postgres
echo "→ 1. Detectando contêiner do Postgres..."
CONTAINER_PG=$(docker ps --format '{{.Names}}' | grep -E '(supabase.*db|postgres|db)' | head -n 1 || true)

if [ -z "$CONTAINER_PG" ]; then
    echo "ERRO: Contêiner do Postgres não encontrado via 'docker ps'."
    exit 1
fi
echo "✓ Contêiner Postgres encontrado: $CONTAINER_PG"

# 2. Detectar usuário e banco
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
    -- 1. Coluna supplier_group na tabela transactions
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'transactions' AND column_name = 'supplier_group'
    ) THEN
        ALTER TABLE public.transactions ADD COLUMN \"supplier_group\" TEXT;
        RAISE NOTICE 'Coluna supplier_group adicionada com sucesso na tabela transactions.';
    ELSE
        RAISE NOTICE 'Coluna supplier_group já existe na tabela transactions.';
    END IF;

    -- 2. Coluna expenseTypes na tabela settings
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'settings' AND column_name = 'expenseTypes'
    ) THEN
        ALTER TABLE public.settings ADD COLUMN \"expenseTypes\" JSONB DEFAULT '[\"Aluguel\", \"Bolsa de Estágio\", \"Contabilidade\", \"Custas e Emolumentos\", \"Energia Elétrica\", \"Impostos e Tributos\", \"Internet e Telefonia\", \"Marketing e Publicidade\", \"Material de Escritório\", \"Pró-labore\", \"Retirada de Lucros\", \"Seguros\", \"Software e Tecnologia\", \"Tarifas Bancárias\", \"Outros\"]'::jsonb;
        RAISE NOTICE 'Coluna expenseTypes adicionada com sucesso na tabela settings.';
    ELSE
        RAISE NOTICE 'Coluna expenseTypes já existe na tabela settings.';
    END IF;

    -- 3. Atualizar configurações vazias ou nulas com o default
    UPDATE public.settings
    SET \"expenseTypes\" = '[\"Aluguel\", \"Bolsa de Estágio\", \"Contabilidade\", \"Custas e Emolumentos\", \"Energia Elétrica\", \"Impostos e Tributos\", \"Internet e Telefonia\", \"Marketing e Publicidade\", \"Material de Escritório\", \"Pró-labore\", \"Retirada de Lucros\", \"Seguros\", \"Software e Tecnologia\", \"Tarifas Bancárias\", \"Outros\"]'::jsonb
    WHERE \"expenseTypes\" IS NULL;

    -- 4. Preencher supplier_group retroativo a partir dos fornecedores já vinculados
    UPDATE public.transactions t
    SET supplier_group = s.group_name
    FROM public.suppliers s
    WHERE t.\"supplierId\" = s.id 
      AND t.supplier_group IS NULL 
      AND s.group_name IS NOT NULL;

END \$\$;
"

docker exec -i "$CONTAINER_PG" psql -U "$DB_USER" -d "$DB_NAME" -c "$SQL"

# 4. Notificar PostgREST para recarregar o schema cache
echo "→ 3. Recarregando schema cache do PostgREST..."
docker exec -i "$CONTAINER_PG" psql -U "$DB_USER" -d "$DB_NAME" -c "NOTIFY pgrst, 'reload schema';" || true

CONTAINER_REST=$(docker ps --format '{{.Names}}' | grep -E '(rest|postgrest)' | head -n 1 || true)
if [ -n "$CONTAINER_REST" ]; then
    echo "✓ Notificando contêiner PostgREST: $CONTAINER_REST"
    docker kill --signal=SIGUSR1 "$CONTAINER_REST" 2>/dev/null || true
fi

# 5. Verificação final
echo "→ 4. Verificando se as colunas estão presentes..."
CHECK_TX=$(docker exec -i "$CONTAINER_PG" psql -U "$DB_USER" -d "$DB_NAME" -t -A -c "
    SELECT column_name || ' (' || data_type || ')'
    FROM information_schema.columns 
    WHERE table_schema = 'public' 
      AND table_name = 'transactions' 
      AND column_name = 'supplier_group';
")

CHECK_SET=$(docker exec -i "$CONTAINER_PG" psql -U "$DB_USER" -d "$DB_NAME" -t -A -c "
    SELECT column_name || ' (' || data_type || ')'
    FROM information_schema.columns 
    WHERE table_schema = 'public' 
      AND table_name = 'settings' 
      AND column_name = 'expenseTypes';
")

if [ -n "$CHECK_TX" ] && [ -n "$CHECK_SET" ]; then
    echo "=================================================================="
    echo "✓ [OK] Migration aplicada com sucesso!"
    echo "  transactions: $CHECK_TX"
    echo "  settings:     $CHECK_SET"
    echo "=================================================================="
else
    echo "=================================================================="
    echo "ERRO: Alguma coluna não foi encontrada após a execução."
    echo "=================================================================="
    exit 1
fi
