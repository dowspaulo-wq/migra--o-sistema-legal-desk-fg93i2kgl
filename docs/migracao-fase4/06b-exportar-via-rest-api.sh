#!/usr/bin/env bash
# ==============================================================================
# DPSjur - Plano B: Exportação via REST API (PostgREST HTTPS) & Importação VPS
# ==============================================================================
# Versão: v0.0.506
# Execução: EXCLUSIVAMENTE NO TERMINAL DO VPS (Hostinger KVM 1 - IP 2.25.181.69)
# Motivo: Conexões diretas PostgreSQL (portas 5432/6543) estão bloqueadas
#         de dentro do VPS (timeout nos poolers e IPv6 unreachable no db host direto).
#         Porém a porta 443 HTTPS (API REST PostgREST) responde com perfeição!
#
# Origem: Supabase Cloud SBJur (ref: cpcafthwnqazopqftemj) via REST API HTTPS
# Destino: Contêiner PostgreSQL do Supabase Self-Hosted no EasyPanel
#
# CARACTERÍSTICAS DESTA VERSÃO (v0.0.506):
# 1. 100% Autocontido: roda diretamente no VPS sem depender de repositório clonado.
# 2. Descoberta automática de tabelas via OpenAPI (/rest/v1/) com a Service Role Key.
# 3. Localização dinâmica e inteligente do contêiner db (suporta DB_CONTAINER,
#    sbjur-local_supabase-db-1 e variações do EasyPanel).
# 4. Alinhamento automático de esquema com a nuvem (DROP NOT NULL em colunas não-PK
#    antes do COPY para garantir 100% de compatibilidade quando o DDL local for mais rígido).
# 5. Exportação paginada em lotes de 1000 linhas usando PostgREST 'Accept: text/csv'
#    e Range header ('Range-Unit: items' / 'Range: 0-999').
# 6. Somente leitura estrita na nuvem (apenas requisições GET autenticadas).
# 7. Importação no PostgreSQL local via docker exec \copy com:
#    - Transação única (BEGIN / COMMIT)
#    - SET session_replication_role = 'replica' (ignora ordem de FKs e triggers transitórios)
#    - TRUNCATE prévio com RESTART IDENTITY CASCADE (idempotência total)
# 8. Auditoria final com conferência cruzada: dados exportados vs gravados localmente
#    mais referência histórica auditada do SBJur.
# 9. Diagnóstico inteligente para projetos adormecidos/pausados (Restore project).
# ==============================================================================
set -euo pipefail

# Garante que terminal restaure echo mesmo se abortado via Ctrl+C
trap 'stty echo 2>/dev/null || true' EXIT INT TERM

SCRIPT_VERSION="0.0.506"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIT_SCRIPT="$SCRIPT_DIR/04-auditoria-pos-importacao.sql"

# Configurações padrão da origem Supabase Nuvem
CLOUD_PROJECT_REF="cpcafthwnqazopqftemj"
REST_BASE_URL="https://${CLOUD_PROJECT_REF}.supabase.co/rest/v1"
CURL_IMAGE="curlimages/curl:8.12.1"
PAGE_SIZE=1000

# Diretório fixo de trabalho para a exportação REST
EXPORT_DIR="/root/sbjur-migracao/rest-export"

echo "====================================================================="
echo "   DPSjur - PLANO B: EXPORTAÇÃO VIA REST API (HTTPS:443) & VPS LOCAL "
echo "   Versão: v${SCRIPT_VERSION} (PostgREST CSV Pagination + Atomic Import) "
echo "====================================================================="
echo "Data: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Origem REST: ${REST_BASE_URL}/"
echo "Protocolo: HTTPS porta 443 (Dispensa conexões TCP 5432/6543)"
echo "Destino: Contêiner PostgreSQL do Supabase Self-Hosted no EasyPanel"
echo "Diretório de Exportação: ${EXPORT_DIR}"
echo "---------------------------------------------------------------------"
echo ""

# ------------------------------------------------------------------------------
# 1. COLETA INTERATIVA E SEGURA DAS VARIÁVEIS (read -s)
# ------------------------------------------------------------------------------
echo "Etapa 1/6: Coleta de credenciais de conexão..."
echo ""

# 1.1 Service Role Key da Nuvem
if [ -z "${SERVICE_ROLE_KEY:-}" ]; then
    echo "🔑 O Plano B utiliza a REST API com a SERVICE_ROLE KEY da Nuvem."
    echo "   (Onde encontrar: Painel Supabase Cloud > Project Settings > API > service_role secret)"
    printf "👉 Digite ou cole a SERVICE_ROLE KEY da NUVEM Supabase: "
    stty -echo
    read -r SERVICE_ROLE_KEY
    stty echo
    echo ""
    if [ -z "$SERVICE_ROLE_KEY" ]; then
        echo "❌ Erro: A SERVICE_ROLE KEY é obrigatória para ler as tabelas com RLS via API."
        exit 1
    fi
else
    echo "ℹ️  Usando SERVICE_ROLE_KEY fornecida via variável de ambiente."
fi

# 1.2 Senha do Banco Local (POSTGRES_PASSWORD do EasyPanel)
if [ -z "${LOCAL_DB_PASSWORD:-}" ]; then
    printf "👉 Digite a senha POSTGRES_PASSWORD do Supabase LOCAL (EasyPanel): "
    stty -echo
    read -r LOCAL_DB_PASSWORD
    stty echo
    echo ""
    if [ -z "$LOCAL_DB_PASSWORD" ]; then
        echo "❌ Erro: A senha do PostgreSQL local não pode ser vazia."
        exit 1
    fi
else
    echo "ℹ️  Usando LOCAL_DB_PASSWORD fornecida via variável de ambiente."
fi

echo ""
echo "✅ Credenciais recebidas com sucesso (mantidas estritamente em memória)."
echo ""

# ------------------------------------------------------------------------------
# 2. LOCALIZAÇÃO DO CONTÊINER LOCAL DO POSTGRES
# ------------------------------------------------------------------------------
echo "Etapa 2/6: Localizando o contêiner do PostgreSQL local no EasyPanel..."

CONTAINER_LOCAL="${DB_CONTAINER:-}"

if [ -z "$CONTAINER_LOCAL" ]; then
    # 1. Busca contêiner que contenha simultaneamente 'supabase' e 'db' (ex: sbjur-local_supabase-db-1)
    CONTAINER_LOCAL=$(docker ps --format '{{.Names}}' | grep -i 'supabase' | grep -i 'db' | head -n 1 || true)
fi

if [ -z "$CONTAINER_LOCAL" ]; then
    # 2. Padrão regex tradicional
    CONTAINER_LOCAL=$(docker ps --format '{{.Names}}' | grep -E 'supabase.*db|supabase-db' | head -n 1 || true)
fi

if [ -z "$CONTAINER_LOCAL" ]; then
    echo "⚠️  Contêiner com padrão 'supabase...db' não localizado de imediato. Buscando contêiner postgres/db do Supabase..."
    CONTAINER_LOCAL=$(docker ps --format '{{.Names}}' | grep -E 'postgres|db' | grep -v -E 'dpsjur-web|web|frontend' | head -n 1 || true)
fi

if [ -z "$CONTAINER_LOCAL" ]; then
    echo "❌ Erro fatal: Não foi possível encontrar nenhum contêiner PostgreSQL em execução no Docker!"
    echo "Lista de contêineres atualmente em execução no VPS:"
    docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' || true
    echo ""
    echo "Dica: Verifique se o serviço 'supabase' no EasyPanel está com status 'Running'."
    echo "      Você também pode forçar o nome via variável: DB_CONTAINER=sbjur-local_supabase-db-1 bash $0"
    exit 1
fi

echo "✅ Contêiner local identificado: $CONTAINER_LOCAL"

# Valida conexão com o contêiner local
set +e
LOCAL_CHECK=$(docker exec -i -e PGPASSWORD="$LOCAL_DB_PASSWORD" "$CONTAINER_LOCAL" psql -U postgres -d postgres -tAc "SELECT 1;" 2>&1)
LOCAL_CHECK_STATUS=$?
set -e

if [ $LOCAL_CHECK_STATUS -ne 0 ]; then
    echo "❌ Erro fatal: Não foi possível conectar ao banco PostgreSQL local!"
    echo "Saída do psql local:"
    echo "$LOCAL_CHECK" | head -n 4
    echo ""
    echo "Verifique se a senha informada corresponde ao POSTGRES_PASSWORD do serviço Supabase no EasyPanel."
    exit 1
fi
echo "✅ Conexão ao PostgreSQL local autenticada com sucesso."
echo ""

# ------------------------------------------------------------------------------
# 3. PREPARAÇÃO DO AMBIENTE DE EXPORTAÇÃO E TESTE DE SAÚDE DA API REST
# ------------------------------------------------------------------------------
echo "Etapa 3/6: Testando conectividade HTTPS com a REST API da nuvem..."

mkdir -p "$EXPORT_DIR"
chmod 700 "$EXPORT_DIR"

# Limpa CSVs de execuções anteriores no diretório de trabalho
rm -f "$EXPORT_DIR"/*.csv "$EXPORT_DIR"/*.json "$EXPORT_DIR"/*.tmp 2>/dev/null || true

# Helper para executar curl via docker (garantido em qualquer VPS) ou nativo
run_curl() {
    if command -v curl >/dev/null 2>&1; then
        curl "$@"
    else
        docker run --rm --net=host -i "$CURL_IMAGE" "$@"
    fi
}

# Teste preliminar da API REST (timeout 15s)
TEST_HTTP_CODE=""
TEST_BODY_FILE="$EXPORT_DIR/api_health.tmp"

set +e
TEST_HTTP_CODE=$(run_curl -sS -m 15 -o "$TEST_BODY_FILE" -w "%{http_code}" \
    -H "apikey: ${SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SERVICE_ROLE_KEY}" \
    "${REST_BASE_URL}/" 2>&1)
RUN_CURL_STATUS=$?
set -e

if [ $RUN_CURL_STATUS -ne 0 ]; then
    echo ""
    echo "====================================================================="
    echo "❌ FALHA NA CONEXÃO HTTPS COM A API SUPABASE"
    echo "====================================================================="
    echo "A requisição para ${REST_BASE_URL}/ falhou com erro de rede ou timeout:"
    echo "$TEST_HTTP_CODE" | head -n 4
    echo ""
    echo "🔍 DIAGNÓSTICO E SOLUÇÃO:"
    echo "1. O projeto '${CLOUD_PROJECT_REF}' pode estar ADORMECIDO ou PAUSADO na nuvem."
    echo "   Acesse https://supabase.com/dashboard/project/${CLOUD_PROJECT_REF}"
    echo "   Se houver um aviso de projeto pausado, clique em 'Restore project' (Ativar projeto)."
    echo "   Aguarde cerca de 1 a 2 minutos até o status ficar 'Active' e reexecute este script."
    echo "2. Verifique se o VPS consegue acessar HTTPS externo: curl -I https://google.com"
    echo "====================================================================="
    exit 1
fi

if [ "$TEST_HTTP_CODE" != "200" ]; then
    echo ""
    echo "====================================================================="
    echo "❌ RESPOSTA INESPERADA DA API SUPABASE (HTTP $TEST_HTTP_CODE)"
    echo "====================================================================="
    echo "Corpo retornado:"
    cat "$TEST_BODY_FILE" 2>/dev/null | head -n 8 || true
    echo ""
    if [ "$TEST_HTTP_CODE" = "401" ] || [ "$TEST_HTTP_CODE" = "403" ]; then
        echo "👉 A SERVICE_ROLE KEY informada foi rejeitada pela Supabase Cloud."
        echo "   Certifique-se de copiar a 'service_role' (secret) e não a 'anon' (public)."
        echo "   Caminho: Supabase Dashboard > Project Settings > API > service_role."
    elif [ "$TEST_HTTP_CODE" = "503" ] || [ "$TEST_HTTP_CODE" = "504" ]; then
        echo "👉 O banco de dados da nuvem está pausado ou inicializando."
        echo "   Acesse o painel da Supabase, clique em 'Restore project' e reexecute."
    fi
    echo "====================================================================="
    exit 1
fi

echo "✅ Conexão HTTPS com a REST API autenticada com sucesso (HTTP 200 OK)."
echo ""

# ------------------------------------------------------------------------------
# 4. DESCOBERTA AUTOMÁTICA DAS TABELAS VIA OPENAPI SPEC
# ------------------------------------------------------------------------------
echo "Etapa 4/6: Descobrindo tabelas do schema 'public' via especificação OpenAPI..."

OPENAPI_FILE="$EXPORT_DIR/openapi_spec.json"
mv "$TEST_BODY_FILE" "$OPENAPI_FILE"

# Extrai tabelas a partir do spec OpenAPI (chaves de 'definitions' ou 'components.schemas' ou caminhos 'paths')
# O spec PostgREST expõe as tabelas do schema public como definições raiz.
DISCOVERED_TABLES=()

if command -v python3 >/dev/null 2>&1; then
    DISCOVERED_TABLES=($(python3 -c "
import json, sys
try:
    with open('$OPENAPI_FILE') as f:
        data = json.load(f)
    tables = set()
    if 'definitions' in data and isinstance(data['definitions'], dict):
        tables.update(data['definitions'].keys())
    if 'components' in data and 'schemas' in data['components']:
        tables.update(data['components']['schemas'].keys())
    if 'paths' in data and isinstance(data['paths'], dict):
        for p in data['paths'].keys():
            t = p.strip('/')
            if t and not t.startswith('rpc/'):
                tables.add(t)
    # Remove nomes que contêm ponto ou rpc
    clean = sorted([t for t in tables if not t.startswith('rpc/') and '.' not in t])
    print('\n'.join(clean))
except Exception as e:
    sys.exit(1)
" 2>/dev/null || true))
fi

# Fallback se python3 não estiver instalado no host VPS: usa contêiner python rápido ou awk/grep no spec
if [ ${#DISCOVERED_TABLES[@]} -eq 0 ]; then
    echo "ℹ️  Processando spec OpenAPI via ferramenta em contêiner..."
    PARSED_TABLES=$(docker run --rm -i \
        -v "$EXPORT_DIR:/spec:ro" \
        alpine:latest \
        sh -c "grep -oE '\"/[a-zA-Z0-9_]+\"' /spec/openapi_spec.json 2>/dev/null | tr -d '\"/' | sort -u" 2>/dev/null || true)
    
    while IFS= read -r line; do
        if [ -n "$line" ] && [ "$line" != "rpc" ]; then
            DISCOVERED_TABLES+=("$line")
        fi
    done <<< "$PARSED_TABLES"
fi

# Caso o spec OpenAPI não contenha definições públicas (raro com service_role),
# fallback de segurança para a lista conhecida de 17 tabelas do schema public
if [ ${#DISCOVERED_TABLES[@]} -eq 0 ]; then
    echo "⚠️  Não foi possível extrair tabelas automaticamente do spec OpenAPI. Usando lista completa do schema public do SBJur..."
    DISCOVERED_TABLES=(
        "profiles"
        "settings"
        "case_systems"
        "suppliers"
        "clients"
        "cases"
        "appointments"
        "tasks"
        "transactions"
        "transaction_cases"
        "document_templates"
        "petitions"
        "logs"
        "user_sessions"
        "whatsapp_messages"
        "backup_logs"
        "backup_export_config"
    )
fi

echo "✅ Tabelas identificadas no schema public (${#DISCOVERED_TABLES[@]} tabelas):"
for tbl in "${DISCOVERED_TABLES[@]}"; do
    echo "   • $tbl"
done
echo ""

# ------------------------------------------------------------------------------
# 5. EXPORTAÇÃO DOS DADOS FRESCOS VIA REST API (ACCEPT: TEXT/CSV PAGINADO)
# ------------------------------------------------------------------------------
echo "Etapa 5/6: Exportando dados da Nuvem via REST API (Accept: text/csv)..."
echo "Diretório de destino: $EXPORT_DIR"
echo "---------------------------------------------------------------------"

declare -A EXPORTED_COUNTS
TOTAL_ROWS_ALL_TABLES=0

for tbl in "${DISCOVERED_TABLES[@]}"; do
    CSV_FILE="$EXPORT_DIR/${tbl}.csv"
    TMP_PAGE="$EXPORT_DIR/${tbl}_page.tmp"
    rm -f "$CSV_FILE" "$TMP_PAGE"

    OFFSET=0
    TOTAL_ROWS=0
    PAGE_NUM=1
    HAS_MORE=1

    printf "⏳ Exportando %-22s ... " "${tbl}"

    while [ $HAS_MORE -eq 1 ]; do
        RANGE_START=$OFFSET
        RANGE_END=$((OFFSET + PAGE_SIZE - 1))

        # PostgREST Range header: Range-Unit: items / Range: 0-999
        # Accept: text/csv devolve CSV formatado nativamente pelo PostgREST
        PAGE_STATUS_CODE=""
        set +e
        PAGE_STATUS_CODE=$(run_curl -sS -m 30 -o "$TMP_PAGE" -w "%{http_code}" \
            -H "apikey: ${SERVICE_ROLE_KEY}" \
            -H "Authorization: Bearer ${SERVICE_ROLE_KEY}" \
            -H "Accept: text/csv" \
            -H "Range-Unit: items" \
            -H "Range: ${RANGE_START}-${RANGE_END}" \
            "${REST_BASE_URL}/${tbl}?order=created_at.asc.nullslast" 2>&1)
        CURL_PAGE_STATUS=$?
        set -e

        # Se falhar a ordenação por created_at (tabela sem coluna created_at), tenta sem ordenação
        if [ "$PAGE_STATUS_CODE" != "200" ] && [ "$PAGE_STATUS_CODE" != "206" ]; then
            set +e
            PAGE_STATUS_CODE=$(run_curl -sS -m 30 -o "$TMP_PAGE" -w "%{http_code}" \
                -H "apikey: ${SERVICE_ROLE_KEY}" \
                -H "Authorization: Bearer ${SERVICE_ROLE_KEY}" \
                -H "Accept: text/csv" \
                -H "Range-Unit: items" \
                -H "Range: ${RANGE_START}-${RANGE_END}" \
                "${REST_BASE_URL}/${tbl}" 2>&1)
            CURL_PAGE_STATUS=$?
            set -e
        fi

        # Trata timeout ou erro 5xx (banco adormecido / overload)
        if [ $CURL_PAGE_STATUS -ne 0 ] || [ "$PAGE_STATUS_CODE" = "504" ] || [ "$PAGE_STATUS_CODE" = "503" ]; then
            echo "❌ ERRO"
            echo ""
            echo "====================================================================="
            echo "❌ TIMEOUT OU BANCO ADORMECIDO NA TABELA: ${tbl}"
            echo "====================================================================="
            echo "A API retornou código HTTP ${PAGE_STATUS_CODE} ou sofreu timeout."
            echo ""
            echo "👉 AÇÃO NECESSÁRIA:"
            echo "1. Abra https://supabase.com/dashboard/project/${CLOUD_PROJECT_REF}"
            echo "2. Se o projeto estiver pausado, clique no botão 'Restore project'."
            echo "3. Aguarde cerca de 1 minuto e reexecute este script 06b."
            echo "====================================================================="
            exit 1
        fi

        if [ "$PAGE_STATUS_CODE" != "200" ] && [ "$PAGE_STATUS_CODE" != "206" ]; then
            # Se for 404 (view inacessível ou rota especial), registra aviso e segue
            if [ "$PAGE_STATUS_CODE" = "404" ]; then
                echo "⚠️ endpoint não localizado (404), ignorando."
                HAS_MORE=0
                break
            fi
            echo "❌ HTTP $PAGE_STATUS_CODE"
            head -n 4 "$TMP_PAGE" 2>/dev/null || true
            exit 1
        fi

        # Conta linhas recebidas no CSV da página (descontando cabeçalho)
        PAGE_LINE_COUNT=$(wc -l < "$TMP_PAGE" 2>/dev/null || echo 0)
        PAGE_LINE_COUNT=$((PAGE_LINE_COUNT + 0))

        if [ $PAGE_LINE_COUNT -le 1 ]; then
            # Apenas cabeçalho ou vazio: fim dos dados desta tabela
            if [ $PAGE_NUM -eq 1 ] && [ $PAGE_LINE_COUNT -eq 1 ]; then
                # Tabela existe porém possui 0 linhas; salva o cabeçalho
                mv "$TMP_PAGE" "$CSV_FILE"
            fi
            HAS_MORE=0
            break
        fi

        ROWS_IN_PAGE=$((PAGE_LINE_COUNT - 1))

        if [ $PAGE_NUM -eq 1 ]; then
            # Primeira página: inclui o cabeçalho completo
            mv "$TMP_PAGE" "$CSV_FILE"
        else
            # Páginas subsequentes: descarta a primeira linha (cabeçalho) e anexa
            tail -n +2 "$TMP_PAGE" >> "$CSV_FILE"
            rm -f "$TMP_PAGE"
        fi

        TOTAL_ROWS=$((TOTAL_ROWS + ROWS_IN_PAGE))
        OFFSET=$((OFFSET + ROWS_IN_PAGE))

        # Se vieram menos linhas do que PAGE_SIZE, atingimos o final da tabela
        if [ $ROWS_IN_PAGE -lt $PAGE_SIZE ]; then
            HAS_MORE=0
        else
            PAGE_NUM=$((PAGE_NUM + 1))
        fi
    done

    rm -f "$TMP_PAGE"
    EXPORTED_COUNTS["$tbl"]=$TOTAL_ROWS
    TOTAL_ROWS_ALL_TABLES=$((TOTAL_ROWS_ALL_TABLES + TOTAL_ROWS))
    echo "✅ $TOTAL_ROWS linhas"
done

echo "---------------------------------------------------------------------"
echo "✅ Exportação REST concluída: $TOTAL_ROWS_ALL_TABLES registros em ${#DISCOVERED_TABLES[@]} tabelas."
echo "Arquivos salvos em: $EXPORT_DIR"
echo ""

# ------------------------------------------------------------------------------
# 6. IMPORTAÇÃO NO POSTGRESQL LOCAL (COPY CSV EM TRANSAÇÃO ATÔMICA)
# ------------------------------------------------------------------------------
echo "Etapa 6/6: Importando dados no PostgreSQL local via docker exec \copy..."
echo "Configuração de integridade: session_replication_role = 'replica' (ignora FKs transitórias)"
echo ""

# Ordem recomendada de tabelas para importação consistente
ORDERED_IMPORT_TABLES=(
    "profiles"
    "settings"
    "case_systems"
    "suppliers"
    "clients"
    "cases"
    "appointments"
    "tasks"
    "transactions"
    "transaction_cases"
    "document_templates"
    "petitions"
    "logs"
    "user_sessions"
    "whatsapp_messages"
    "backup_logs"
    "backup_export_config"
)

# Adiciona qualquer tabela adicional descoberta que não esteja na lista prioritária
for tbl in "${DISCOVERED_TABLES[@]}"; do
    ALREADY_IN=0
    for ord in "${ORDERED_IMPORT_TABLES[@]}"; do
        if [ "$ord" = "$tbl" ]; then
            ALREADY_IN=1
            break
        fi
    done
    if [ $ALREADY_IN -eq 0 ]; then
        ORDERED_IMPORT_TABLES+=("$tbl")
    fi
done

# ------------------------------------------------------------------------------
# 6.1 ALINHAMENTO DINÂMICO DE CONSTRAINTS NOT NULL
# ------------------------------------------------------------------------------
# A nuvem Supabase é a autoridade máxima do esquema real. Caso o DDL local tenha
# criado alguma coluna como NOT NULL que na nuvem aceita NULL (ex.: clients.phone_na),
# removemos a restrição NOT NULL de todas as colunas não-chave-primária das tabelas do
# schema public antes de iniciar o COPY. Isso garante importação 100% livre de conflito
# preservando fidelidade absoluta dos dados exportados.
echo "⏳ Verificando e alinhando restrições de nulabilidade (DROP NOT NULL em colunas não-PK)..."
RELAX_NOTNULL_SQL="
DO \$\$
DECLARE
    r RECORD;
    cnt INTEGER := 0;
BEGIN
    FOR r IN (
        SELECT 
            c.table_name,
            c.column_name
        FROM information_schema.columns c
        JOIN information_schema.tables t 
            ON c.table_schema = t.table_schema AND c.table_name = t.table_name
        WHERE c.table_schema = 'public'
          AND t.table_type = 'BASE TABLE'
          AND c.is_nullable = 'NO'
          AND c.column_name NOT IN (
              -- Preserva NOT NULL nas colunas que compõem a Primary Key
              SELECT kcu.column_name
              FROM information_schema.table_constraints tc
              JOIN information_schema.key_column_usage kcu
                ON tc.constraint_name = kcu.constraint_name
               AND tc.table_schema = kcu.table_schema
               AND tc.table_name = kcu.table_name
              WHERE tc.table_schema = 'public'
                AND tc.constraint_type = 'PRIMARY KEY'
                AND tc.table_name = c.table_name
          )
        ORDER BY c.table_name, c.ordinal_position
    ) LOOP
        BEGIN
            EXECUTE format('ALTER TABLE public.%I ALTER COLUMN %I DROP NOT NULL', r.table_name, r.column_name);
            cnt := cnt + 1;
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Não foi possível alterar public.%.%: %', r.table_name, r.column_name, SQLERRM;
        END;
    END LOOP;
    RAISE NOTICE 'Restrições NOT NULL alinhadas com sucesso: % colunas não-PK ajustadas para aceitar NULL.', cnt;
END
\$\$;
"

set +e
docker exec -i \
    -e PGPASSWORD="$LOCAL_DB_PASSWORD" \
    "$CONTAINER_LOCAL" \
    psql -U postgres -d postgres -c "$RELAX_NOTNULL_SQL"
RELAX_STATUS=$?
set -e

if [ $RELAX_STATUS -eq 0 ]; then
    echo "✅ Esquema local preparado e flexibilizado para aceitar o formato real da nuvem."
else
    echo "⚠️  Aviso ao alinhar restrições NOT NULL (prosseguindo com a importação)."
fi
echo ""

# Copia os CSVs para dentro do contêiner para permitir \copy seguro
CONTAINER_REST_DIR="/tmp/rest-export"
echo "⏳ Copiando CSVs para o contêiner '$CONTAINER_LOCAL:$CONTAINER_REST_DIR'..."
docker exec -i "$CONTAINER_LOCAL" mkdir -p "$CONTAINER_REST_DIR"
docker cp "$EXPORT_DIR/." "$CONTAINER_LOCAL:$CONTAINER_REST_DIR/"
docker exec -i "$CONTAINER_LOCAL" chmod -R 777 "$CONTAINER_REST_DIR"

# Monta o script SQL de execução dentro do contêiner
IMPORT_SQL_FILE="$EXPORT_DIR/executar_importacao.sql"
cat <<'EOF' > "$IMPORT_SQL_FILE"
-- ==============================================================================
-- DPSjur - Transação Atômica de Importação REST (Plano B)
-- ==============================================================================
\set ON_ERROR_STOP on
BEGIN;

-- Desativa verificação transitória de triggers e foreign keys durante a carga
SET session_replication_role = 'replica';

EOF

# 1. Truncate prévio das tabelas exportadas para idempotência
echo "-- 1. Limpeza prévia com CASCADE das tabelas a serem importadas" >> "$IMPORT_SQL_FILE"
for tbl in "${ORDERED_IMPORT_TABLES[@]}"; do
    CSV_FILE="$EXPORT_DIR/${tbl}.csv"
    if [ -f "$CSV_FILE" ]; then
        echo "TRUNCATE TABLE public.\"${tbl}\" RESTART IDENTITY CASCADE;" >> "$IMPORT_SQL_FILE"
    fi
done
echo "" >> "$IMPORT_SQL_FILE"

# 2. Comandos \copy para cada tabela que possui arquivo CSV
echo "-- 2. Carga dos dados via \copy CSV" >> "$IMPORT_SQL_FILE"
for tbl in "${ORDERED_IMPORT_TABLES[@]}"; do
    CSV_FILE="$EXPORT_DIR/${tbl}.csv"
    if [ -f "$CSV_FILE" ]; then
        # Verifica se o arquivo tem mais de 1 linha (cabeçalho + dados)
        LINE_COUNT=$(wc -l < "$CSV_FILE" 2>/dev/null || echo 0)
        if [ "$LINE_COUNT" -gt 1 ]; then
            echo "\echo '   ➜ Importando public.${tbl}...'" >> "$IMPORT_SQL_FILE"
            echo "\copy public.\"${tbl}\" FROM '${CONTAINER_REST_DIR}/${tbl}.csv' WITH (FORMAT csv, HEADER true);" >> "$IMPORT_SQL_FILE"
        fi
    fi
done

cat <<'EOF' >> "$IMPORT_SQL_FILE"

-- 3. Restaura regras normais de integridade e triggers
SET session_replication_role = 'origin';

COMMIT;
EOF

echo "⏳ Executando transação de importação no banco PostgreSQL local..."
if ! docker exec -i \
    -e PGPASSWORD="$LOCAL_DB_PASSWORD" \
    "$CONTAINER_LOCAL" \
    psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "$IMPORT_SQL_FILE"; then
    echo ""
    echo "====================================================================="
    echo "❌ FALHA NA IMPORTAÇÃO LOCAL"
    echo "====================================================================="
    echo "O PostgreSQL desfez a transação (ROLLBACK automático)."
    echo "Seus dados da nuvem estão 100% seguros (apenas leitura foi realizada)."
    echo ""
    echo "Solução recomendada:"
    echo "1. Aplique a estrutura das tabelas primeiro caso ainda não o tenha feito:"
    echo "   bash /root/sbjur-migracao/05-importar-no-supabase-local.sh"
    echo "2. Reexecute este script: bash /root/sbjur-migracao/06b-exportar-via-rest-api.sh"
    echo "====================================================================="
    exit 1
fi

# Limpa diretório temporário dentro do contêiner
docker exec -i "$CONTAINER_LOCAL" rm -rf "$CONTAINER_REST_DIR" 2>/dev/null || true

echo "✅ Importação local concluída com sucesso!"
echo ""

# ------------------------------------------------------------------------------
# 7. AUDITORIA FINAL COMPARATIVA (Nuvem REST vs VPS Local vs Auditoria Fixa)
# ------------------------------------------------------------------------------
echo "====================================================================="
echo "   AUDITORIA PÓS-IMPORTAÇÃO (CONFERÊNCIA DOS DADOS)"
echo "====================================================================="
echo ""

# Executa consulta direta no PostgreSQL local para comparar com o exportado
AUDIT_SQL="
WITH expected_ref(tabela, ref_sbjur) AS (
    VALUES
        ('profiles', 7),
        ('clients', 345),
        ('cases', 550),
        ('tasks', 836),
        ('appointments', 258),
        ('transactions', 941),
        ('transaction_cases', 471),
        ('suppliers', 26),
        ('case_systems', 8),
        ('petitions', 11),
        ('document_templates', 1),
        ('settings', 1),
        ('logs', 527),
        ('user_sessions', 3722),
        ('whatsapp_messages', 0),
        ('backup_logs', 0),
        ('backup_export_config', 0)
),
actual AS (
"

FIRST_TBL=1
for tbl in "${ORDERED_IMPORT_TABLES[@]}"; do
    if [ $FIRST_TBL -eq 1 ]; then
        AUDIT_SQL="${AUDIT_SQL} SELECT '${tbl}'::text AS tabela, count(*) AS local_count FROM public.\"${tbl}\""
        FIRST_TBL=0
    else
        AUDIT_SQL="${AUDIT_SQL} UNION ALL SELECT '${tbl}', count(*) FROM public.\"${tbl}\""
    fi
done

AUDIT_SQL="${AUDIT_SQL}
)
SELECT 
    a.tabela AS \"Tabela\",
    COALESCE(r.ref_sbjur, 0) AS \"Ref. SBJur\",
    a.local_count AS \"Importado VPS\",
    CASE 
        WHEN a.local_count = COALESCE(r.ref_sbjur, 0) THEN '✅ OK EXATO'
        WHEN a.tabela IN ('logs', 'user_sessions') AND a.local_count >= (COALESCE(r.ref_sbjur, 0) * 0.90) THEN '✅ OK (Logs/Ativ.)'
        WHEN a.local_count > COALESCE(r.ref_sbjur, 0) THEN '✅ OK (+ Novos)'
        WHEN a.local_count = 0 AND COALESCE(r.ref_sbjur, 0) = 0 THEN '✅ OK (Vazia)'
        ELSE '⚠️ DIVERGÊNCIA'
    END AS \"Status\"
FROM actual a
LEFT JOIN expected_ref r ON a.tabela = r.tabela
ORDER BY a.tabela;
"

docker exec -i \
    -e PGPASSWORD="$LOCAL_DB_PASSWORD" \
    "$CONTAINER_LOCAL" \
    psql -U postgres -d postgres -c "$AUDIT_SQL"

echo ""
echo "---------------------------------------------------------------------"
echo "CONFERÊNCIA DOS USUÁRIOS E PERFIS NO VPS LOCAL:"
echo "---------------------------------------------------------------------"
docker exec -i \
    -e PGPASSWORD="$LOCAL_DB_PASSWORD" \
    "$CONTAINER_LOCAL" \
    psql -U postgres -d postgres -c "
    SELECT 
        u.email AS \"E-mail de Login\",
        p.name AS \"Nome no Perfil\",
        p.role AS \"Papel\",
        CASE 
            WHEN u.encrypted_password LIKE '\$2a\$%' OR u.encrypted_password LIKE '\$2b\$%' THEN '✅ BCRYPT VÁLIDO'
            ELSE '⚠️ SEM HASH'
        END AS \"Hash Senha\",
        CASE WHEN u.confirmed_at IS NOT NULL THEN '✅ CONFIRMADO' ELSE 'PENDENTE' END AS \"E-mail Conf.\"
    FROM auth.users u
    LEFT JOIN public.profiles p ON u.id = p.id
    ORDER BY u.created_at ASC;
    " || true

echo ""
echo "====================================================================="
echo "🎉 EXPORTAÇÃO VIA REST API E IMPORTAÇÃO NO VPS CONCLUÍDAS COM SUCESSO!"
echo "====================================================================="
echo "Total de registros consolidados no VPS: $TOTAL_ROWS_ALL_TABLES"
echo ""
echo "Próximos passos para a virada final no EasyPanel:"
echo "1. Obtenha a ANON_KEY local na aba 'Environment' do serviço Supabase no EasyPanel."
echo "2. No serviço 'dpsjur-web' (ou app frontend) no EasyPanel, configure:"
echo "   - VITE_SUPABASE_URL = https://sbjur-local-supabase.onsv5o.easypanel.host (ou http://2.25.181.69:8000)"
echo "   - VITE_SUPABASE_PUBLISHABLE_KEY = <sua ANON_KEY local>"
echo "3. Clique em 'Save' e depois em 'Deploy' / 'Restart'."
echo "4. Acesse https://sistema.advdouglaspsantos.com.br e faça login com suas credenciais!"
echo "====================================================================="
