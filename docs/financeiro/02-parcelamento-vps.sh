#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE INSTALAÇÃO DO RECURSO DE PARCELAMENTO COM REPASSE NO VPS (EASYPANEL)
# Versão: v0.0.569
# Alvo: VPS Hostinger 2.25.181.69 (EasyPanel / Supabase Self-Hosted)
#
# O QUE ESTE SCRIPT FAZ:
# 1. Localiza o contêiner do banco PostgreSQL no EasyPanel
# 2. Executa a migração SQL idempotente do Parcelamento com Repasse ao Cliente:
#    - Cria tabela public.payment_plans (se não existir)
#    - Habilita RLS e aplica políticas para authenticated e service_role
#    - Adiciona colunas em transactions: plan_id, pair_id, installment_number, installment_total
#    - Cria índices de performance
#    - Insere categoria "Repasse ao Cliente" nas configurações do sistema
# 3. Exibe conferência do schema pós-migração
#
# COMO EXECUTAR NO TERMINAL DO VPS (como root - NÃO INTERATIVO):
#   curl -sSL "https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/financeiro/02-parcelamento-vps.sh" -o /root/02-parcelamento-vps.sh
#   bash /root/02-parcelamento-vps.sh
# ==============================================================================

set -eo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}${BLUE}=== DPSjur - Recurso Parcelamento com Repasse ao Cliente (v0.0.569) ===${NC}"

# 1. Identificar contêiner Docker do PostgreSQL e credenciais de acesso
echo -e "\n${BOLD}[1/3] Procurando contêiner Docker do PostgreSQL no VPS...${NC}"

DB_CONTAINER="${DB_CONTAINER:-}"
if [ -z "$DB_CONTAINER" ]; then
    DB_CONTAINER=$(docker ps --format "{{.Names}}" | grep -E 'dpsjur.*db|supabase.*db|sbjur.*db' | head -n 1 || true)
fi
if [ -z "$DB_CONTAINER" ]; then
    DB_CONTAINER=$(docker ps --filter "name=db" --format "{{.Names}}" | head -n 1 || true)
fi
if [ -z "$DB_CONTAINER" ]; then
    DB_CONTAINER=$(docker ps --filter "name=postgres" --format "{{.Names}}" | head -n 1 || true)
fi

echo -e "Contêiner Banco Postgres: ${GREEN}${DB_CONTAINER:-'não encontrado'}${NC}"

if [ -z "$DB_CONTAINER" ]; then
    echo -e "${RED}Erro fatal: Contêiner do banco de dados não foi encontrado. Verifique se o EasyPanel/Supabase está rodando.${NC}"
    exit 1
fi

# Derivar variáveis de ambiente do contêiner via docker inspect (com fallback)
INSPECT_USER=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$DB_CONTAINER" 2>/dev/null | grep -E '^POSTGRES_USER=' | head -n 1 | cut -d= -f2- || true)
INSPECT_DB=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$DB_CONTAINER" 2>/dev/null | grep -E '^POSTGRES_DB=' | head -n 1 | cut -d= -f2- || true)
INSPECT_PASS=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$DB_CONTAINER" 2>/dev/null | grep -E '^POSTGRES_PASSWORD=' | head -n 1 | cut -d= -f2- || true)

# Detectar usuário funcional com fallback (supabase_admin superuser Supabase, postgres, INSPECT_USER, etc.)
CANDIDATE_USERS=()
[ -n "${POSTGRES_USER:-}" ] && CANDIDATE_USERS+=("${POSTGRES_USER}")
[ -n "$INSPECT_USER" ] && CANDIDATE_USERS+=("$INSPECT_USER")
CANDIDATE_USERS+=("supabase_admin" "postgres" "Doug")

# Deduplica usuários candidatos mantendo a ordem
UNIQUE_USERS=()
for u in "${CANDIDATE_USERS[@]}"; do
    [[ " ${UNIQUE_USERS[*]} " =~ " ${u} " ]] || UNIQUE_USERS+=("$u")
done

DETECTED_USER=""
DETECTED_DB=""

echo -e "Detectando usuário e banco de dados disponíveis..."

for test_u in "${UNIQUE_USERS[@]}"; do
    # Tenta listar bancos para este usuário
    DB_LIST=$(docker exec -i "$DB_CONTAINER" psql -U "$test_u" -At -c "SELECT datname FROM pg_database WHERE datistemplate = false;" 2>/dev/null || true)
    if [ -n "$DB_LIST" ]; then
        DETECTED_USER="$test_u"
        # Escolhe o melhor banco: POSTGRES_DB informado, ou banco da aplicação existente, ou 'postgres'
        for cand_db in "${POSTGRES_DB:-}" "$INSPECT_DB" "dpsjur" "postgres"; do
            if [ -n "$cand_db" ] && echo "$DB_LIST" | grep -qx "$cand_db"; then
                DETECTED_DB="$cand_db"
                break
            fi
        done
        # Se nenhum casou exatamente, pega o primeiro da lista que não seja template
        if [ -z "$DETECTED_DB" ]; then
            DETECTED_DB=$(echo "$DB_LIST" | head -n 1)
        fi
        break
    fi
done

# Fallback seguro caso 'pg_database' precise de banco específico para conectar
if [ -z "$DETECTED_USER" ]; then
    for test_u in "${UNIQUE_USERS[@]}"; do
        for test_d in "${POSTGRES_DB:-}" "$INSPECT_DB" "postgres" "dpsjur"; do
            [ -z "$test_d" ] && continue
            if docker exec -i "$DB_CONTAINER" psql -U "$test_u" -d "$test_d" -At -c "SELECT 1;" >/dev/null 2>&1; then
                DETECTED_USER="$test_u"
                DETECTED_DB="$test_d"
                break 2
            fi
        done
    done
fi

# Fallback final se nada respondeu
DB_USER="${DETECTED_USER:-supabase_admin}"
DB_NAME="${DETECTED_DB:-postgres}"

echo -e "Usuário PostgreSQL detectado: ${GREEN}${DB_USER}${NC}"
echo -e "Banco de Dados detectado:     ${GREEN}${DB_NAME}${NC}"

# 2. Aplicar script SQL idempotente
echo -e "\n${BOLD}[2/3] Aplicando migração SQL no PostgreSQL (usuário: ${DB_USER}, banco: ${DB_NAME})...${NC}"

docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" << 'EOSQL'
DO $$
BEGIN
    -- 1. Criar tabela payment_plans se não existir
    CREATE TABLE IF NOT EXISTS public.payment_plans (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        "clientId" UUID REFERENCES public.clients(id) ON DELETE CASCADE NOT NULL,
        "processId" UUID REFERENCES public.cases(id) ON DELETE SET NULL,
        title TEXT NOT NULL,
        "installmentAmount" NUMERIC NOT NULL DEFAULT 0,
        "installmentsCount" INTEGER NOT NULL DEFAULT 1,
        periodicity TEXT NOT NULL DEFAULT 'mensal',
        "firstDueDate" TEXT NOT NULL,
        "feePercentage" NUMERIC NOT NULL DEFAULT 0,
        "clientPercentage" NUMERIC NOT NULL DEFAULT 0,
        "feeInstallmentAmount" NUMERIC NOT NULL DEFAULT 0,
        "clientInstallmentAmount" NUMERIC NOT NULL DEFAULT 0,
        "totalAmount" NUMERIC NOT NULL DEFAULT 0,
        "totalFeeAmount" NUMERIC NOT NULL DEFAULT 0,
        "totalClientAmount" NUMERIC NOT NULL DEFAULT 0,
        "bankAccount" TEXT DEFAULT 'ASAAS',
        "paymentMethod" TEXT DEFAULT 'PIX',
        status TEXT NOT NULL DEFAULT 'Ativo',
        notes TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    -- Habilitar RLS
    ALTER TABLE public.payment_plans ENABLE ROW LEVEL SECURITY;

    -- Políticas RLS idempotentes
    DROP POLICY IF EXISTS "payment_plans_authenticated_all" ON public.payment_plans;
    CREATE POLICY "payment_plans_authenticated_all" ON public.payment_plans
        FOR ALL TO authenticated USING (true) WITH CHECK (true);

    DROP POLICY IF EXISTS "payment_plans_service_role_all" ON public.payment_plans;
    CREATE POLICY "payment_plans_service_role_all" ON public.payment_plans
        FOR ALL TO service_role USING (true) WITH CHECK (true);

    -- 2. Colunas em transactions
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'transactions' AND column_name = 'plan_id'
    ) THEN
        ALTER TABLE public.transactions ADD COLUMN "plan_id" UUID REFERENCES public.payment_plans(id) ON DELETE CASCADE;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'transactions' AND column_name = 'pair_id'
    ) THEN
        ALTER TABLE public.transactions ADD COLUMN "pair_id" UUID REFERENCES public.transactions(id) ON DELETE SET NULL;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'transactions' AND column_name = 'installment_number'
    ) THEN
        ALTER TABLE public.transactions ADD COLUMN "installment_number" INTEGER;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'transactions' AND column_name = 'installment_total'
    ) THEN
        ALTER TABLE public.transactions ADD COLUMN "installment_total" INTEGER;
    END IF;

    -- 3. Índices de busca
    CREATE INDEX IF NOT EXISTS idx_payment_plans_client_id ON public.payment_plans("clientId");
    CREATE INDEX IF NOT EXISTS idx_payment_plans_process_id ON public.payment_plans("processId");
    CREATE INDEX IF NOT EXISTS idx_transactions_plan_id ON public.transactions("plan_id");
    CREATE INDEX IF NOT EXISTS idx_transactions_pair_id ON public.transactions("pair_id");

    -- 4. Adicionar categoria 'Repasse ao Cliente' em settings
    UPDATE public.settings
    SET "transactionCategories" = (
        SELECT jsonb_agg(DISTINCT elem ORDER BY elem)
        FROM (
            SELECT elem
            FROM jsonb_array_elements("transactionCategories") AS elem
            UNION
            SELECT '"Repasse ao Cliente"'::jsonb AS elem
        ) sub
    )
    WHERE "transactionCategories" IS NOT NULL;

END $$;
EOSQL

echo -e "${GREEN}✓ Migração SQL aplicada no banco com sucesso!${NC}"

# 3. Conferência dos dados
echo -e "\n${BOLD}[3/3] Conferência do banco pós-migração (usuário: ${DB_USER}, banco: ${DB_NAME}):${NC}"
docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "\d public.payment_plans"
docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'transactions' AND column_name IN ('plan_id', 'pair_id', 'installment_number', 'installment_total');"

echo -e "\n${BOLD}${GREEN}=== ATUALIZAÇÃO CONCLUÍDA COM SUCESSO (v0.0.569) ===${NC}"
echo -e "Próximos passos para o Douglas:"
echo -e "1. No painel EasyPanel, vá no serviço de frontend ${BOLD}dpsjur${NC} e clique em ${BOLD}Implantar${NC} (Deploy)."
echo -e "2. No navegador, acesse https://sistema.advdouglaspsantos.com.br e aperte ${BOLD}Ctrl + F5${NC} para limpar o cache."
echo -e "3. Em Cliente ou Processo, use o botão 'Novo Parcelamento' para cadastrar planos longos com repasse!"
