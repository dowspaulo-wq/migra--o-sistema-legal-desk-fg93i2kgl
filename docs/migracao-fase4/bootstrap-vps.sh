#!/usr/bin/env bash
# ==============================================================================
# DPSjur - Bootstrap Autônomo de Migração (Executar no Terminal do VPS)
# ==============================================================================
# Versão: v0.0.508
# Servidor: VPS Hostinger KVM 1 (srv1737667 - IP 2.25.181.69)
# Função: Baixa o kit completo da Fase 4 sem precisar de git clone nem login GitHub,
#         organiza os arquivos em /root/sbjur-migracao/ e deixa tudo pronto para executar.
# ==============================================================================
set -euo pipefail

BOOTSTRAP_VERSION="0.0.508"
DEST_DIR="/root/sbjur-migracao"
REPO_RAW_BASE="https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/migracao-fase4"

echo "====================================================================="
echo "   DPSjur - PREPARAÇÃO DO KIT DE MIGRAÇÃO NO VPS (BOOTSTRAP)        "
echo "   Versão: v${BOOTSTRAP_VERSION}                                              "
echo "====================================================================="
echo "Destino: $DEST_DIR"
echo "Origem: Repositório GitHub DPSjur"
echo "Data: $(date '+%Y-%m-%d %H:%M:%S')"
echo "---------------------------------------------------------------------"
echo ""

# 1. Cria diretório de trabalho dedicado no VPS
mkdir -p "$DEST_DIR"
cd "$DEST_DIR"

# 2. Lista de arquivos essenciais do kit de migração (inclui Plano A e Plano B)
FILES=(
    "01-schema-ddl-sbjur.sql"
    "02-rls-policies-sbjur.sql"
    "03-auth-users-sbjur.sql"
    "04-auditoria-pos-importacao.sql"
    "05-importar-no-supabase-local.sh"
    "06-exportar-e-importar-dados.sh"
    "06b-exportar-via-rest-api.sh"
    "06-sync-storage-assets.ts"
    "07-completar-pendencias.sh"
)

echo "⏳ Baixando os arquivos do kit de migração..."
DOWNLOAD_SUCCESS=0
for f in "${FILES[@]}"; do
    printf "   ➜ Baixando %s... " "$f"
    # Cache buster de cabeçalho para garantir download da versão mais recente
    if curl -sSf -L -H "Cache-Control: no-cache" -H "Pragma: no-cache" "$REPO_RAW_BASE/$f" -o "$f" 2>/dev/null; then
        echo "✅"
        ((DOWNLOAD_SUCCESS++)) || true
    elif wget -q --no-cache -O "$f" "$REPO_RAW_BASE/$f" 2>/dev/null; then
        echo "✅ (via wget)"
        ((DOWNLOAD_SUCCESS++)) || true
    elif curl -sSf -L "$REPO_RAW_BASE/$f" -o "$f" 2>/dev/null; then
        echo "✅"
        ((DOWNLOAD_SUCCESS++)) || true
    else
        echo "⚠️ (falha ao baixar)"
    fi
done

# Permissão de execução nos scripts
chmod +x ./*.sh 2>/dev/null || true

echo ""
if [ "$DOWNLOAD_SUCCESS" -ge 4 ]; then
    echo "====================================================================="
    echo "🎉 Kit de migração preparado com sucesso em: $DEST_DIR"
    echo "====================================================================="
    echo ""
    echo "Para executar a migração agora, escolha uma das opções:"
    echo ""
    echo "👉 PLANO B (RECOMENDADO SE A PORTA 5432/6543 ESTIVER BLOQUEADA):"
    echo "   cd $DEST_DIR && bash 06b-exportar-via-rest-api.sh"
    echo "   (Usa HTTPS 443 via REST API PostgREST, contornando bloqueios de porta)"
    echo ""
    echo "👉 FECHAR PENDÊNCIAS DA AUDITORIA (auth.users + settings + document_templates + user_sessions):"
    echo "   cd $DEST_DIR && bash 07-completar-pendencias.sh"
    echo ""
    echo "👉 PLANO A (CONEXÃO POSTGRESQL NATIVA):"
    echo "   cd $DEST_DIR && bash 06-exportar-e-importar-dados.sh"
    echo ""
    echo "👉 APLICAR APENAS ESTRUTURA BASE (DDL, RLS e Usuários Auth):"
    echo "   cd $DEST_DIR && bash 05-importar-no-supabase-local.sh"
    echo "====================================================================="
else
    echo "❌ Falha ao baixar arquivos do GitHub. Verifique a conexão com a internet."
    exit 1
fi
