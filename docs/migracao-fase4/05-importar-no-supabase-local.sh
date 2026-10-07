#!/usr/bin/env bash
# ==============================================================================
# DPSjur - Script Unificado de Importação no Supabase Self-Hosted (EasyPanel)
# Gerado para: Fase 4 da Migração para VPS Hostinger (IP: 2.25.181.69)
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "====================================================================="
echo "  DPSjur - Importador Automatizado no Supabase Self-Hosted"
echo "====================================================================="
echo ""

# Localiza o contêiner de banco do Supabase no EasyPanel
echo "🔍 Localizando contêiner do PostgreSQL do Supabase..."
CONTAINER_DB="${DB_CONTAINER:-}"

if [ -z "$CONTAINER_DB" ]; then
    # 1. Procura primeiro contêiner que contenha supabase E db no nome (ex: sbjur-local_supabase-db-1)
    CONTAINER_DB=$(docker ps --format '{{.Names}}' | grep -i 'supabase' | grep -i 'db' | head -n 1 || true)
fi

if [ -z "$CONTAINER_DB" ]; then
    # 2. Tenta padrão regex supabase-db ou supabase.*db
    CONTAINER_DB=$(docker ps --format '{{.Names}}' | grep -E 'supabase.*db|supabase-db' | head -n 1 || true)
fi

if [ -z "$CONTAINER_DB" ]; then
    # 3. Fallback: qualquer contêiner com postgres ou db, exceto dpsjur-web e apps de frontend
    echo "⚠️ Contêiner com padrão 'supabase...db' não encontrado de imediato. Buscando contêiner postgres/db do Supabase..."
    CONTAINER_DB=$(docker ps --format '{{.Names}}' | grep -E 'postgres|db' | grep -v -E 'dpsjur-web|web|frontend' | head -n 1 || true)
fi

if [ -z "$CONTAINER_DB" ]; then
    echo "❌ Erro: Não foi possível localizar o contêiner PostgreSQL do Supabase!"
    echo "Execute 'docker ps' no terminal do VPS para verificar o nome do contêiner e execute manualmente:"
    echo "  DB_CONTAINER=sbjur-local_supabase-db-1 bash $0"
    exit 1
fi

echo "✅ Contêiner localizado: $CONTAINER_DB"
echo ""

# Pergunta ou utiliza senha informada no ambiente
DB_USER="${POSTGRES_USER:-postgres}"
DB_NAME="${POSTGRES_DB:-postgres}"

echo "Etapa 1/4: Aplicando Schema DDL e Triggers (01-schema-ddl-sbjur.sql)..."
docker exec -i "$CONTAINER_DB" psql -U "$DB_USER" -d "$DB_NAME" < "$SCRIPT_DIR/01-schema-ddl-sbjur.sql"
echo "✅ Schema DDL aplicado com sucesso!"
echo ""

echo "Etapa 2/4: Aplicando Políticas de RLS (02-rls-policies-sbjur.sql)..."
docker exec -i "$CONTAINER_DB" psql -U "$DB_USER" -d "$DB_NAME" < "$SCRIPT_DIR/02-rls-policies-sbjur.sql"
echo "✅ Políticas de RLS aplicadas com sucesso!"
echo ""

echo "Etapa 3/4: Restaurando Usuários de Auth com Senhas Reais (03-auth-users-sbjur.sql)..."
docker exec -i "$CONTAINER_DB" psql -U "$DB_USER" -d "$DB_NAME" < "$SCRIPT_DIR/03-auth-users-sbjur.sql"
echo "✅ Usuários e credenciais restaurados com sucesso!"
echo ""

if [ -f "$SCRIPT_DIR/sbjur-dados-completos.sql" ]; then
    echo "Etapa 4/4: Importando Dados das 17 Tabelas (sbjur-dados-completos.sql)..."
    docker exec -i "$CONTAINER_DB" psql -U "$DB_USER" -d "$DB_NAME" < "$SCRIPT_DIR/sbjur-dados-completos.sql"
    echo "✅ Dados importados com sucesso!"
else
    echo "ℹ️ Nota: Arquivo 'sbjur-dados-completos.sql' não encontrado nesta pasta."
    echo "Se você gerou o dump de dados via Supabase CLI ou pelo script de exportação, execute:"
    echo "  docker exec -i $CONTAINER_DB psql -U $DB_USER -d $DB_NAME < seu_dump_de_dados.sql"
fi
echo ""

echo "---------------------------------------------------------------------"
echo " Executando Auditoria Pós-Importação Automática..."
echo "---------------------------------------------------------------------"
docker exec -i "$CONTAINER_DB" psql -U "$DB_USER" -d "$DB_NAME" < "$SCRIPT_DIR/04-auditoria-pos-importacao.sql"

echo ""
echo "====================================================================="
echo "🎉 Importação e conferência concluídas no Supabase Self-Hosted!"
echo "====================================================================="
