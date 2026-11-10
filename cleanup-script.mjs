import fs from 'node:fs'

const filePath = 'docs/vps/20-auditar-backup.sh'
const content = fs.readFileSync(filePath, 'utf8')
const lines = content.split('\n')

console.log(`Total lines: ${lines.length}`)

// Find where report generation starts
const startIdx = lines.findIndex((l) =>
  l.includes('if [ "${CRIT_A}" = "OK" ] && [ "${CRIT_B}" = "OK" ]'),
)
console.log(`Consolidation check startIdx: ${startIdx}`)

// The clean report block:
const cleanTail = `if [ "\${CRIT_A}" = "OK" ] && [ "\${CRIT_B}" = "OK" ] && [ "\${CRIT_C}" = "OK" ] && [ "\${CRIT_D_OK}" -eq 1 ] && [ "\${CRIT_E_OK}" -eq 1 ] && [ "\${DIVERGENCES_COUNT}" -eq 0 ] && [ "\${INVENTORY_COMPARISON_VALID}" = "SIM" ]; then
    VEREDITO="APROVADO"
    MOTIVO_VEREDITO="Todos os critérios técnicos passaram sem exceção (restauração física original, pg_graphql, estrutural exaustivo, comparação bidirecional integral jq, integridade de catálogo/dados e zero divergências)."
else
    VEREDITO="REPROVADO"
    MOTIVO_VEREDITO="O backup apresentou divergências ou falhas técnicas não resolvidas (CRIT_A_ORIGINAL: \${CRIT_A}, DIVERGÊNCIAS: \${DIVERGENCES_COUNT}, COMPARAÇÃO_VÁLIDA: \${INVENTORY_COMPARISON_VALID}, QUERIES_FALHAS: \${QUERY_FAILURES_COUNT})."
fi

# ------------------------------------------------------------------------------
# GRAVAÇÃO DO RELATÓRIO TÉCNICO COM CHMOD 600
# ------------------------------------------------------------------------------

cat <<EOF > "\${REPORT_FILE}"
================================================================================
 DPSjur / SBJur — RELATÓRIO DE AUDITORIA DE BACKUP (\${SCRIPT_VERSION})
 Data de emissão: \$(date '+%F %T %Z')
 Sessão de auditoria: \${SESSION_ID}
================================================================================

1. ARQUIVOS E AMBIENTE
   Arquivo de backup: \${BACKUP_FILE}
   Inventário oficial: \${INVENTORY_FILE:-Nenhum informado}
   Contêiner de teste: \${LAB_NAME}
   Label da sessão: \${SESSION_LABEL}
   Volume isolado: \${LAB_VOLUME}
   Imagem PostgreSQL: \${CHOSEN_IMAGE}

2. SEÇÃO TÉCNICA SEPARADA: RESTAURAÇÃO ORIGINAL vs RECUPERAÇÃO ASSISTIDA
   (a) Restauração Original (psql -X -v ON_ERROR_STOP=1): \${RESTORE_ORIGINAL_STATUS}
       - Código gunzip .................: \${GZIP_EXIT} (exigido 0)
       - Código psql ...................: \${PSQL_EXIT} (exigido 0)
       - Erros SQL brutos ..............: \${RESTORE_RAW_ERRORS_COUNT} (exigido 0)
       - Avaliação Restauração Original : \${CRIT_A}
   (b) Recuperação Assistida (Post-Restore):
       - Extensão pg_graphql ...........: \${GRAPHQL_FINAL_STATUS}
       - Tentativa de recuperação ......: \${GRAPHQL_REC_STATUS}
       - Observação de isolamento ......: A recuperação assistida NÃO mascara falha na restauração original.

3. RESULTADOS DOS DEMAIS CRITÉRIOS TÉCNICOS
   Critério 3 - Inventário estrutural do laboratório: \${CRIT_C}
       - Tabelas public: \${TOTAL_TABELAS_LAB}
       - Tabelas auth: \${TOTAL_TABELAS_AUTH_LAB}
       - Constraints: \${TOTAL_CONSTRAINTS_LAB}
       - Funções: \${TOTAL_FUNCOES_LAB}
       - Triggers: \${TOTAL_TRIGGERS_LAB}
       - Extensões: \${TOTAL_EXTENSOES_LAB}
   Critério 4 - Comparação estrutural e bidirecional com inventário oficial (jq): \$([ "\${CRIT_D_OK}" -eq 1 ] && echo "CONFORME" || echo "NAO_CONFORME")
       - Validação JSON semântica com jq: \${INVENTORY_COMPARISON_VALID}
       - Bidirecionalidade avaliada: \$([ "\${INVENTORY_BIDIRECTIONAL_CHECK_PASSED}" -eq 1 ] && echo "SIM" || echo "NAO")
       - Amostragem aplicada: NENHUMA (conferência integral de constraints e funções)
   Critério 5 - Integridade parcial do PostgreSQL restaurado: \${OP_CRITERION_STATUS}
       - Integridade referencial (FKs órfãs): \${FK_ORPHANS_CNT}
       - Consistência auth.users: \${USERS_TOTAL} usuários, \${USERS_DUP_COUNT} duplicidades
       - Planos de execução EXPLAIN: \${EXPLAIN_STATUS}
       - Bloco transacional com ROLLBACK: \${TX_STATUS}
       - Escopo delimitado: Prova unicamente a saúde do PostgreSQL restaurado;
         não atesta recuperação funcional completa da aplicação CRM (Kong/GoTrue/PostgREST fora do escopo do teste).

4. DIVERGÊNCIAS E DIFERENÇAS DE CONTAGEM INCONCLUSIVAS
   Total de divergências impeditivas: \${DIVERGENCES_COUNT}
   Total de diferenças de contagem inconclusivas: \${TEMPORAL_DIFFS_COUNT}
EOF

if [ -s "\${DIVERGENCES_FILE}" ]; then
    printf '\\n--- ITENS DE DIVERGÊNCIA REGISTRADOS ---\\n' >> "\${REPORT_FILE}"
    sed 's/^/   [DIVERGÊNCIA] /' "\${DIVERGENCES_FILE}" >> "\${REPORT_FILE}"
fi

if [ -s "\${TEMPORAL_DIFFS_FILE}" ]; then
    printf '\\n--- DIFERENÇAS DE CONTAGEM INCONCLUSIVAS (SEM PRESUNÇÃO DE CRESCIMENTO) ---\\n' >> "\${REPORT_FILE}"
    sed 's/^/   [INCONCLUSIVO] /' "\${TEMPORAL_DIFFS_FILE}" >> "\${REPORT_FILE}"
fi

cat <<EOF >> "\${REPORT_FILE}"

5. VEREDITO FINAL DA AUDITORIA
   Veredito: \${VEREDITO}
   Motivo: \${MOTIVO_VEREDITO}

6. RASTREABILIDADE E SEGURANÇA
   Rede do contêiner de laboratório: --network none (isolamento de rede estrito)
   Arquivo do relatório: \${REPORT_FILE} (chmod 600)
   Log técnico restrito: \${LOG_FILE} (chmod 600)
   Log de erros do restore: \${RESTORE_ERRORS_FILE} (chmod 600)
   Recursos rastreados da sessão: \${TRACKED_RESOURCES_FILE} (chmod 600)
================================================================================
EOF

if ! chmod 600 "\${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "\${EXIT_FS_FAIL}"
fi
REPORT_PERM="\$(stat -c '%a' "\${REPORT_FILE}" 2>/dev/null || stat -f '%Lp' "\${REPORT_FILE}" 2>/dev/null || echo "")"
if [ -z "\${REPORT_PERM}" ] || [ "\${REPORT_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de relatório inválida (\${REPORT_PERM})." "\${EXIT_FS_FAIL}"
fi

# Exibição no terminal
say ""
say "================================================================================"
say " VEREDITO FINAL DA AUDITORIA DE BACKUP: \${VEREDITO}"
say "================================================================================"
say " Motivo: \${MOTIVO_VEREDITO}"
say ""
say " Resumo dos 5 Critérios Técnicos:"
say "   1. Restauração original estrita ........: \${CRIT_A}"
say "   2. Extensão pg_graphql operacional .....: \${CRIT_B}"
say "   3. Validação estrutural do schema public : \${CRIT_C}"
say "   4. Comparação bidirecional com inventário: \$([ "\${CRIT_D_OK}" -eq 1 ] && echo "CONFORME" || echo "NAO_CONFORME")"
say "   5. Integridade parcial do PostgreSQL ...: \${OP_CRITERION_STATUS} (CRM fora de escopo)"
say ""
say " Divergências impeditivas : \${DIVERGENCES_COUNT}"
say " Diferenças inconclusivas : \${TEMPORAL_DIFFS_COUNT}"
say ""
say " Arquivos gerados:"
say "   Relatório técnico ......: \${REPORT_FILE} (chmod 600)"
say "   Log de execução ........: \${LOG_FILE} (chmod 600)"
say "   Log de erros do restore .: \${RESTORE_ERRORS_FILE} (chmod 600)"
say "================================================================================"

if [ "\${VEREDITO}" = "APROVADO" ]; then
    exit "\${EXIT_OK}"
else
    exit "\${EXIT_STRUCTURE_FAIL}"
fi
`

const cleanContent = lines.slice(0, startIdx).join('\n') + '\n' + cleanTail
fs.writeFileSync(filePath, cleanContent, 'utf8')
console.log('Successfully cleaned up docs/vps/20-auditar-backup.sh')
