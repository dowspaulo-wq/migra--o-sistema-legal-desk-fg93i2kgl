#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur — Auditoria Independente de Integridade de Backup
# Script: docs/vps/20-auditar-backup.sh
# Versão: v2.1.2
# Destino de execução: MÁQUINA DE TESTE / WSL2 / DOCKER DESKTOP ISOLADO
#
# GUARDA DE SEGURANÇA MÁXIMA (ANTI-VPS) E CONTROLE ESTRITO DE SESSÃO DOCKER:
#   ESTE SCRIPT EXECUTA A GUARDA ANTI-VPS NO TOPO ABSOLUTO DO CÓDIGO, ANTES DE
#   QUALQUER CRIAÇÃO DE DIRETÓRIO, TOUCH, ARQUIVO OU ESCRITA EM DISCO.
#   NENHUMA LIMPEZA OU OPERAÇÃO DOCKER É ACIONADA ANTES DA GUARDA DE SEGURANÇA.
#   QUALQUER DETECÇÃO DE AMBIENTE OU CONTÊINER DE PRODUÇÃO (HOSTINGER,
#   srv1737667, 2.25.181.69, sbljur-local_supabase-db-1, sbjur-local_supabase-db-1)
#   ABORTA IMEDIATAMENTE A EXECUÇÃO COM EXIT 11, SEM QUALQUER EFEITO COLATERAL.
#   ADICIONALMENTE (v1.8.0), A GUARDA RESOLVE O ENDPOINT EFETIVO DA CLI DOCKER —
#   DOCKER_HOST QUANDO DEFINIDO, CASO CONTRÁRIO O ENDPOINT DO CONTEXTO ATUAL VIA
#   docker context inspect — E DECIDE PELO ENDPOINT (NUNCA PELO NOME DO CONTEXTO),
#   EXIGINDO SOCKET UNIX EXISTENTE E ABORTANDO DIANTE DE tcp://, ssh://, http(s)://
#   OU npipe://. O CONTÊINER DE LABORATÓRIO UTILIZA OBRIGATORIAMENTE --network none.
#   v2.1.0: O ENDPOINT COMPROVADO PELA GUARDA É FIXADO (export DOCKER_HOST +
#   unset DOCKER_CONTEXT) PARA TODAS AS INVOCAÇÕES DOCKER SUBSEQUENTES DO SCRIPT,
#   eliminando a re-resolução implícita do endpoint a cada chamada (janela TOCTOU).
#   APENAS RECURSOS DOCKER COMPROVADAMENTE CRIADOS PELA SESSÃO ATUAL
#   (IDENTIFICADOS POR LABEL ESPECÍFICO E REGISTRADOS EM ARQUIVO DE SESSÃO) PODEM
#   SER REMOVIDOS NO TRAP/CLEANUP.
#
# CORREÇÕES v1.8.0 (auditoria externa independente — 8 pontos, correção cirúrgica):
#   1. Validação jq do inventário termina em `true` (nunca `else empty`), com
#      campos numéricos obrigatórios exigidos como inteiros não negativos.
#   2. Guarda Docker decide pelo ENDPOINT EFETIVO (DOCKER_HOST ou endpoint do
#      contexto atual via docker context inspect + existência do socket), nunca
#      pelo nome do contexto.
#   3. Contagem de erros SQL produz SEMPRE um único inteiro válido (wc -l sobre
#      arquivo temporário + validação de inteiro; grep exit 1 não é fatal).
#   4. Corpos de funções comparados via pg_get_functiondef quando o inventário
#      traz a definição efetiva (inclui_corpo=true), além da identidade.
#   5. INVENTORY_COMPARISON_VALID=SIM somente sem divergências nesta etapa,
#      com extrações jq completas (nada INCONCLUSIVO pendente).
#   6. pg_graphql verificado em pg_extension/pg_available_extensions (extname +
#      extversion), nunca pela existência de função homônima.
#   7. INT/TERM com handler próprio: limpeza restrita aos recursos da sessão e
#      término imediato (128+n), sem retomar a execução.
#   8. Identificadores do inventário (schema/tabela/constraint/função) validados
#      com regex estrita ^[a-zA-Z_][a-zA-Z0-9_]*$ antes de qualquer interpolação
#      SQL; inválidos geram DIVERGÊNCIA e recusa da interpolação.
#
# CORREÇÕES v1.9.0 (auditoria externa independente — 5 pontos, correção cirúrgica):
#   1. Guarda Docker: falha ou host vazio de `docker context inspect` NÃO é mais
#      presumido como socket local padrão — endpoint não comprovado aborta (exit 11).
#   2. Funções PostgreSQL comparadas por schema + nome + identidade de argumentos
#      (pg_get_function_identity_arguments) + tipo de retorno; sobrecargas comparadas
#      individualmente (sem concatenação) e pg_get_functiondef pelo OID exato da
#      sobrecarga casada (nunca homônima).
#   3. Extrações jq com exit code efetivamente verificado (sem `|| echo ""` mascarando
#      falha); extração incompleta/inválida/ambígua impede INVENTORY_COMPARISON_VALID=SIM;
#      arrays vazios legítimos (exit 1 de -e) continuam aceitos.
#   4. Normalização de definições (constraints e funções) NÃO destrutiva e IDÊNTICA
#      dos dois lados: quebras viram espaço, espaços colapsados — nunca remoção pura.
#   5. pg_graphql instalado por recuperação assistida NÃO satisfaz o critério B
#      (CRIT_B=FALHA): veredito NUNCA é APROVADO quando houve intervenção
#      pós-restauração; evidências da restauração original e da recuperação assistida
#      permanecem separadas na seção 2 do relatório.
#
# CORREÇÕES v2.0.0 (auditoria externa independente — 8 pontos, correção cirúrgica):
#   1. QUERY_FAILURES_COUNT contabilizada em ARQUIVO privativo da sessão: falhas
#      registradas dentro de $(...) não persistem em variáveis do processo Bash
#      principal; a contagem usada pelo veredito é lida do arquivo na consolidação
#      (as falhas SQL inline de identidade/pg_get_functiondef também são contadas).
#   2. Guarda Docker explicita a precedência REAL da CLI (DOCKER_HOST sobrepõe o
#      endpoint de qualquer contexto ativo; sem DOCKER_HOST vale o contexto ativo,
#      resolvido pela CLI via DOCKER_CONTEXT e então docker context show) e aborta
#      com exit 11 quando o endpoint local seguro não é comprovável — ANTES de
#      qualquer operação que modifique recursos Docker.
#   3. Conferência estrutural de constraints e funções é BIDIRECIONAL também no
#      sentido backup restaurado -> inventário: objetos ADICIONAIS presentes no
#      banco restaurado e ausentes do inventário geram DIVERGÊNCIA (escopo
#      documentado: schema public).
#   4. Consulta de identidade de funções SEM delimitador textual colidível: a
#      identidade é embutida por dollar-quoting com etiqueta única (conteúdo que
#      contenha a etiqueta é recusado) e a resposta vem como UM ÚNICO documento
#      JSON decodificado por jq — elimina '|RET:'/'|OID:' e a ambiguidade do sed.
#   5. Extração de funções e constraints em JSON-lines: campos íntegros (aspas,
#      quebras de linha e caracteres especiais escapados pelo codificador JSON,
#      sem colisão de separador), decodificados campo a campo (jq @sh + eval).
#   6. Estimativas reltuples NÃO são registradas como "CONFERIDO": a extração é
#      rotulada como informação coletada (não é verificação) e a comparação como
#      INCONCLUSIVA — aprovação exige contagem exata validada.
#   7. Consulta de referências órfãs distingue NULL permitido de referência
#      inválida: conta apenas client_id preenchido (IS NOT NULL) sem
#      correspondência — NULL legítimo não é mais contado como órfão.
#   8. Sem "|| true" no chmod do arquivo SQL temporário: sucesso do chmod E
#      permissão efetiva (stat) são verificados (idem nos arquivos de consulta
#      de identidade e pg_get_functiondef).
#
# CORREÇÕES v2.1.0 (auditoria externa independente — 3 pontos, correção cirúrgica):
#   1. Guarda Docker: o endpoint comprovado pela guarda é FIXADO para TODAS as
#      invocações docker subsequentes (export DOCKER_HOST com o unix:// validado
#      e unset DOCKER_CONTEXT, imediatamente após a guarda), eliminando a janela
#      TOCTOU da re-resolução implícita entre a guarda e as operações. Precedência
#      confirmada na documentação oficial da CLI (DOCKER_HOST sobrepõe o contexto
#      ativo; com DOCKER_HOST definido e nenhum contexto expressamente selecionado,
#      o currentContext de ~/.docker/config.json não é consultado). Bloqueio
#      preventivo com exit 11 preservado; nada é presumido.
#   2. Conferência bidirecional (sentido 2: banco restaurado -> inventário) usa os
#      MESMOS catálogos, schemas, filtros e critérios de identidade do gerador
#      21-gerar-inventario.sh: constraints via pg_constraint/pg_class/pg_namespace
#      (comparadas por schema, tabela, nome e contype) e funções via pg_proc/
#      pg_namespace, ambos com n.nspname NOT LIKE 'pg\_%' AND n.nspname <>
#      'information_schema' (TODOS os schemas de usuário). Objeto extra em
#      qualquer schema abrangido pelo inventário gera DIVERGÊNCIA BIDIRECIONAL;
#      sem listas de exceções automáticas; falha de comparação impossível impede
#      INVENTORY_COMPARISON_VALID=SIM.
#   3. Os quatro eval de decodificação JSON (@sh + eval) foram eliminados: helper
#      único jq_field_decode decodifica cada campo via jq @base64 + base64 -d,
#      SEM interpretação de comandos pelo shell, com o código de saída de AMBAS
#      as etapas (jq E base64) verificado; qualquer falha de decodificação ou
#      dado não representável produz DIVERGÊNCIA impeditiva (nunca silêncio ou
#      valor vazio). Disponibilidade de base64 verificada na inicialização;
#      ausência é falha de ambiente impeditiva.
#
# CORREÇÕES v2.1.1 (auditoria externa independente — 4 pontos, correção cirúrgica):
#   1. Guarda Docker: DOCKER_HOST e DOCKER_CONTEXT definidos e não vazios
#      SIMULTANEAMENTE abortam com exit 11 (política conservadora do auditor:
#      NENHUMA precedência é presumida entre as duas variáveis). Documentado
#      que um socket Unix, ISOLADAMENTE, não comprova que o daemon é local nem
#      que pertence ao laboratório — o que se comprova é o ENDPOINT (origem +
#      formato unix:// + socket existente), e a fixação da v2.1.0 garante que
#      toda invocação docker subsequente usa EXATAMENTE esse endpoint.
#   2. jq_field_decode endurecido: cada campo obrigatório deve EXISTIR no objeto
#      JSON e ser EFETIVAMENTE do tipo string; campo ausente, nulo ou de outro
#      tipo gera falha explícita impeditiva (nunca conversão silenciosa no texto
#      "null"). A extração JSON-lines deixa de usar tostring nos campos de
#      identidade, preservando o tipo original para que a checagem de tipo seja
#      real; strings vazias legítimas permanecem preservadas; sem eval.
#   3. record_query_failure: toda falha de escrita no registro de falhas SQL é
#      detectada imediatamente, produz diagnóstico claro em stderr e ativa um
#      SINAL FATAL em arquivo próprio (QUERY_FAILURES_FATAL_FLAG) — mecanismo
#      INDEPENDENTE do próprio arquivo cuja escrita falhou; a existência do
#      sinal é checada na consolidação e impede QUALQUER veredito APROVADO,
#      inclusive quando a contagem via arquivo não for confiável.
#   4. Contagens informativas de constraints e funções do laboratório usam o
#      MESMO critério de escopo de schemas da comparação bidirecional
#      (pg_constraint/pg_proc com n.nspname NOT LIKE 'pg\_%' AND n.nspname <>
#      'information_schema' — TODOS os schemas de usuário); sem misturar
#      contagens restritas a public com comparações de escopo completo.
#
# CORREÇÕES v2.1.2 (auditoria externa independente — 1 ponto, correção cirúrgica):
#   1. record_query_failure com fail-closed COMPLETO: se a escrita no registro
#      (QUERY_FAILURES_FILE) E no sinal fatal em arquivo (QUERY_FAILURES_FATAL_FLAG)
#      falharem SIMULTANEAMENTE, o script ainda dispõe de canais adicionais que,
#      por construção, quase não falham em conjunto:
#        (B) flag em ARQUIVO (QUERY_FAILURES_FATAL_FLAG, v2.1.1 preservada);
#        (C) DIRETÓRIO dedicado criado no pre-voo (mkdir sem -p, chmod 700 e
#            permissão efetiva stat-validated); o sinal é a criação ATÔMICA do
#            subdiretório "registro-sql-fatal" (mkdir), que só falha quando o
#            próprio sistema de arquivos falha;
#        (D) marcadores alternativos em DIRETÓRIOS FORA do diretório de
#            diagnóstico (no diretório base de auditoria e no TMPDIR);
#        (E) flag em MEMÓRIA do processo principal (QUERY_FAILURES_UNSIGNABLE)
#            — último recurso, NÃO é o mecanismo principal (não sobrevive a
#            subshell), e por isso os canais A/B/C/D em disco são os primários.
#        (Obs.: nesta nomenclatura A = arquivo de registro, B = flag, C =
#        diretório dedicado, D = marcadores alternativos, E = memória.)
#      A CONSULTA do mecanismo na consolidação também é verificada (fail-closed
#      completo): função check_query_failure_signal valida o canal com uma
#      SONDA mkdir+rmdir; canal inacessível, diretório ausente/ilegível ou
#      sonda que falhe são tratados como sinal NÃO CONFIÁVEL ⇒ contagem
#      forçada a 999 e veredito NUNCA é APROVADO. Fundamento: se o sistema de
#      arquivos está quebrado a ponto de os canais A/B/C/D falharem na
#      gravação, a mesma quebra é detectada pela sonda na consolidação — a
#      condição "impossível sinalizar" vira sistematicamente REPROVADO,
#      inclusive quando a função é chamada dentro de $(...).
#      TODAS as chamadas de record_query_failure verificam o retorno da função
#      e propagam a falha (DIVERGÊNCIA impeditiva registrada ou return não
#      zero ao chamador imediato).
#
# POLÍTICA DE AUDITORIA E VEREDITO (v1.5.0):
#   - O veredito APROVADO é emitido UNICAMENTE se TODOS os critérios técnicos
#     passarem sem exceção:
#       1. Restauração original física estrita (gunzip exit 0 E psql exit 0 E zero erros SQL)
#          executada com psql -X -v ON_ERROR_STOP=1.
#       2. Extensão pg_graphql operacional (recuperação assistida posterior NÃO
#          mascara falhas da restauração original).
#       3. Validação estrutural exaustiva (sem amostragem/sampling de 30 elementos)
#          comparando definições completas de constraints e identidades/definições de funções.
#       4. Comparação bidirecional integral das tabelas dos schemas public e auth
#          (inventário->backup e backup->inventário, schema+nome+método).
#       5. Integridade parcial do PostgreSQL restaurado comprovada (4 verificações
#          de saúde de banco, sem declarar recuperação funcional completa do CRM).
#       6. Nenhuma divergência pendente (DIVERGENCES_COUNT == 0) e
#          INVENTORY_COMPARISON_VALID=SIM estritamente após conclusão de todos os passos.
#   - Qualquer diferença de contagem entre backup e inventário posterior é
#     classificada como INCONCLUSIVA (SEM presunção de crescimento natural).
#   - Validação de permissões efetivas (stat) trata resultado vazio ou diferente de 600 como fatal.
#
# PARÂMETROS:
#   --arquivo <backup.sql.gz>       Arquivo de backup compactado a auditar (obrigatório).
#   --inventario <inventario.json>  Arquivo de inventário gerado por 21-gerar-inventario.sh.
#   --pular-graphql-fix             Pula a tentativa de recuperação assistida de pg_graphql.
#   --manter-lab                    Não destrói o contêiner ao final (para inspeção manual).
#   -h, --help                      Exibe esta ajuda.
# ==============================================================================

set -u -o pipefail
umask 077

SCRIPT_VERSION="v2.1.2"

# ------------------------------------------------------------------------------
# PONTO 9 E PONTO 10 DA AUDITORIA: GUARDA DE SEGURANÇA MÁXIMA (ANTI-VPS)
# E BLOQUEIO DE CONTEXTOS / ENDPOINTS DOCKER REMOTOS
# NENHUMA limpeza, escrita em disco ou chamada Docker é acionada antes disto!
# ------------------------------------------------------------------------------

# 1. GUARDA DOCKER COM PRECEDÊNCIA REAL DA CLI (Ponto 4 da auditoria original;
#    Ponto 2 da correção v2.0.0):
#    O endpoint efetivo é resolvido na MESMA ordem de precedência da CLI Docker:
#      (a) DOCKER_HOST, quando definido, SOBREPÕE o endpoint de qualquer contexto
#          selecionado (flag --context, DOCKER_CONTEXT ou currentContext);
#      (b) sem DOCKER_HOST, vale o CONTEXTO ATIVO, que a CLI resolve na ordem:
#          flag --context (não usada por este script) -> variável DOCKER_CONTEXT
#          -> currentContext do config.json (docker context show).
#    O endpoint só é aceito se for comprovadamente LOCAL: unix:// com socket
#    existente. tcp://, ssh://, http(s)://, npipe://, formato desconhecido ou
#    endpoint não comprovável abortam com exit 11 ANTES de qualquer operação que
#    modifique recursos Docker (nenhuma criação/remoção existe antes deste ponto).
#
#    CORREÇÃO 1 (v2.1.1) — EXCLUSÃO MÚTUA CONSERVADORA: DOCKER_HOST e
#    DOCKER_CONTEXT definidos e não vazios SIMULTANEAMENTE abortam com exit 11
#    IMEDIATAMENTE, antes de qualquer operação Docker, criação de diretório ou
#    escrita em disco. Fundamento: embora a CLI documente que DOCKER_HOST
#    sobrepõe o contexto ativo, o auditor determinou que NENHUMA precedência é
#    presumida neste script diante da configuração simultânea das duas
#    variáveis (configuração ambígua e inusualmente defensável); abortar é a
#    única resposta aceitável. Com a exclusão mútua, a resolução do endpoint
#    abaixo opera sempre com UMA ÚNICA origem definida, e a fixação (Correção 1
#    da v2.1.0, logo após a guarda) assegura que nenhum endpoint é validado
#    enquanto as chamadas docker subsequentes utilizam outro.
if [ -n "${DOCKER_HOST:-}" ] && [ -n "${DOCKER_CONTEXT:-}" ]; then
    printf '❌ ERRO CRÍTICO DE SEGURANÇA: DOCKER_HOST e DOCKER_CONTEXT definidos e não vazios simultaneamente (%s / %s).\n' "${DOCKER_HOST}" "${DOCKER_CONTEXT}" >&2
    printf '   Política conservadora: nenhuma precedência é presumida entre as duas variáveis — abortando imediatamente (exit 11), antes de qualquer operação Docker.\n' >&2
    exit 11
fi

if command -v docker >/dev/null 2>&1; then
    DOCKER_EFFECTIVE_ENDPOINT=""
    DOCKER_ENDPOINT_ORIGIN=""

    if [ -n "${DOCKER_HOST:-}" ]; then
        case "${DOCKER_HOST}" in
            tcp://*|ssh://*|http://*|https://*|npipe://*)
                printf '❌ ERRO CRÍTICO DE SEGURANÇA: DOCKER_HOST aponta para endpoint remoto (%s).\n' "${DOCKER_HOST}" >&2
                printf '   DOCKER_HOST sobrepõe o endpoint de qualquer contexto ativo; a auditoria só é permitida contra socket local verificado.\n' >&2
                exit 11
                ;;
            unix://*)
                DOCKER_EFFECTIVE_ENDPOINT="${DOCKER_HOST}"
                # DOCKER_CONTEXT é impossível aqui: a exclusão mútua (Correção 1
                # da v2.1.1) já abortou com exit 11 se ele estivesse definido.
                DOCKER_ENDPOINT_ORIGIN="DOCKER_HOST (sobrepõe o contexto ativo; DOCKER_CONTEXT vazio garantido pela exclusão mútua)"
                ;;
            *)
                printf '❌ ERRO CRÍTICO DE SEGURANÇA: DOCKER_HOST possui formato não verificado (%s).\n' "${DOCKER_HOST}" >&2
                exit 11
                ;;
        esac
    else
        # Sem DOCKER_HOST: o endpoint vem do CONTEXTO ATIVO da CLI.
        if [ -n "${DOCKER_CONTEXT:-}" ]; then
            # DOCKER_CONTEXT tem precedência sobre o currentContext do config.
            # Falha em inspecionar = endpoint não comprovado = bloqueio
            # preventivo (NUNCA presumir o contexto "default").
            DOCKER_CURRENT_CONTEXT="${DOCKER_CONTEXT}"
            DOCKER_CONTEXT_ORIGIN_KIND="selecionado expressamente pela variável DOCKER_CONTEXT"
        else
            DOCKER_CURRENT_CONTEXT="$(docker context show 2>/dev/null)" || DOCKER_CURRENT_CONTEXT=""
            if [ -z "${DOCKER_CURRENT_CONTEXT}" ]; then
                printf '❌ ERRO CRÍTICO DE SEGURANÇA: Não foi possível determinar o contexto Docker ativo (docker context show falhou ou retornou vazio).\n' >&2
                printf '   O endpoint efetivo da CLI não pôde ser comprovado — bloqueio preventivo (exit 11).\n' >&2
                exit 11
            fi
            DOCKER_CONTEXT_ORIGIN_KIND="contexto ativo da CLI (docker context show)"
        fi

        # Inspecionar o CONTEXTO ATIVO como a CLI o resolve, SEM presumir socket
        # local padrão: falha ou host vazio de docker context inspect = endpoint
        # não comprovado = bloqueio preventivo (exit 11). Endpoint unix:// só é
        # aceito quando o contexto ativo o declara expressamente (e o socket
        # existe, validado abaixo).
        DOCKER_CONTEXT_HOST_RC=0
        DOCKER_CONTEXT_HOST="$(docker context inspect "${DOCKER_CURRENT_CONTEXT}" --format '{{.Endpoints.docker.Host}}' 2>/dev/null)" || DOCKER_CONTEXT_HOST_RC=$?
        if [ "${DOCKER_CONTEXT_HOST_RC}" -ne 0 ] || [ -z "${DOCKER_CONTEXT_HOST}" ]; then
            printf '❌ ERRO CRÍTICO DE SEGURANÇA: Endpoint Docker efetivo NÃO COMPROVADO (falha ou host vazio do docker context inspect para o contexto %s, %s; exit %s).\n' "${DOCKER_CURRENT_CONTEXT}" "${DOCKER_CONTEXT_ORIGIN_KIND}" "${DOCKER_CONTEXT_HOST_RC}" >&2
            printf '   A natureza local do endpoint não pôde ser provada — bloqueio preventivo (exit 11).\n' >&2
            exit 11
        fi
        DOCKER_EFFECTIVE_ENDPOINT="${DOCKER_CONTEXT_HOST}"
        DOCKER_ENDPOINT_ORIGIN="contexto '${DOCKER_CURRENT_CONTEXT}' (${DOCKER_CONTEXT_ORIGIN_KIND})"
    fi

    case "${DOCKER_EFFECTIVE_ENDPOINT}" in
        unix://*)
            # Socket local UNIX: verificação efetiva de existência do socket.
            # CORREÇÃO 1 (v2.1.1) — ADVERTÊNCIA DOCUMENTADA: um socket Unix,
            # ISOLADAMENTE, NÃO comprova que o daemon é local nem que pertence
            # ao laboratório (um socket pode encaminhar a outro host via proxy
            # ou apontar para daemon remoto montado localmente). O que a guarda
            # comprova é o ENDPOINT EFETIVO (origem declarada + formato unix:// +
            # socket existente); a fixação da v2.1.0 abaixo garante que toda
            # invocação docker posterior do script usa EXATAMENTE este endpoint
            # (sem re-resolução implícita, sem janela TOCTOU).
            DOCKER_SOCKET_PATH="${DOCKER_EFFECTIVE_ENDPOINT#unix://}"
            if [ -z "${DOCKER_SOCKET_PATH}" ]; then
                DOCKER_SOCKET_PATH="/var/run/docker.sock"
            fi
            if ! [ -S "${DOCKER_SOCKET_PATH}" ]; then
                printf '❌ ERRO CRÍTICO DE SEGURANÇA: Socket do endpoint Docker efetivo não existe (%s; origem: %s).\n' "${DOCKER_SOCKET_PATH}" "${DOCKER_ENDPOINT_ORIGIN}" >&2
                exit 11
            fi
            ;;
        *)
            printf '❌ ERRO CRÍTICO DE SEGURANÇA: Endpoint Docker efetivo não comprovado como local (%s; origem: %s).\n' "${DOCKER_EFFECTIVE_ENDPOINT}" "${DOCKER_ENDPOINT_ORIGIN}" >&2
            exit 11
            ;;
    esac
fi

# CORREÇÃO 1 (v2.1.0): FIXAÇÃO DO ENDPOINT COMPROVADO PELA GUARDA.
# Sem isto, cada chamada `docker ...` posterior do script re-resolveria o
# endpoint implicitamente (DOCKER_HOST > DOCKER_CONTEXT > currentContext do
# config.json), reabrindo uma janela TOCTOU: uma mudança do ambiente ou de
# ~/.docker/config.json entre a guarda e as operações poderia direcionar o
# laboratório a OUTRO daemon. Exportando DOCKER_HOST com o valor unix://
# validado e removendo DOCKER_CONTEXT do ambiente, TODA invocação docker daqui
# em diante conecta EXATAMENTE ao endpoint auditado: pela precedência efetiva
# da CLI (confirmada na documentação oficial), com DOCKER_HOST definido e
# nenhum contexto expressamente selecionado, o endpoint do config.json não é
# consultado. O bloqueio preventivo com exit 11 acima permanece intacto; a
# fixação NÃO presume que socket Unix comprova isolamento — a comprovação do
# endpoint pelo contexto/ambiente continua exigida pela guarda.
if command -v docker >/dev/null 2>&1 && [ -n "${DOCKER_EFFECTIVE_ENDPOINT:-}" ]; then
    export DOCKER_HOST="${DOCKER_EFFECTIVE_ENDPOINT}"
    unset DOCKER_CONTEXT
fi

# 3. Verificação de Hostname e FQDN de produção
CURRENT_HOSTNAME="$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo "")"
CURRENT_FQDN="$(hostname -f 2>/dev/null || echo "")"

if [ -z "${CURRENT_HOSTNAME}" ]; then
    printf '❌ ERRO DE GUARDA: Não foi possível determinar o hostname da máquina.\n' >&2
    printf '   Por segurança preventiva, a execução foi abortada.\n' >&2
    exit 11
fi

case "${CURRENT_HOSTNAME}" in
    *srv1737667*|*hstgr*|*hostinger*|*dpsjur*|*sbjur*)
        printf '❌ ERRO DE GUARDA: Este script NÃO PODE ser executado na VPS de produção (%s)!\n' "${CURRENT_HOSTNAME}" >&2
        printf '   Execute-o exclusivamente em sua máquina de laboratório / WSL2 isolado.\n' >&2
        exit 11
        ;;
esac

case "${CURRENT_FQDN}" in
    *srv1737667*|*hstgr*|*hostinger*|*dpsjur*|*sbjur*)
        printf '❌ ERRO DE GUARDA: FQDN indica ambiente de produção (%s)!\n' "${CURRENT_FQDN}" >&2
        exit 11
        ;;
esac

# 4. Verificação de IPs locais
if command -v ip >/dev/null 2>&1; then
    ALL_IPS="$(ip addr show 2>/dev/null | grep -oE 'inet [0-9.]+' | awk '{print $2}' || true)"
elif command -v ifconfig >/dev/null 2>&1; then
    ALL_IPS="$(ifconfig 2>/dev/null | grep -oE 'inet (addr:)?[0-9.]+' | awk '{print $NF}' || true)"
else
    ALL_IPS=""
fi

if printf '%s\n' "${ALL_IPS}" | grep -qx "2.25.181.69"; then
    printf '❌ ERRO DE GUARDA: IP de produção 2.25.181.69 detectado localmente! Abortando.\n' >&2
    exit 11
fi

# 5. Verificação de Contêineres de Produção em execução
PROD_PATTERNS="^(sbljur-local_supabase-db-1|sbjur-local_supabase-db-1)$"

if command -v docker >/dev/null 2>&1; then
    ALL_CONTAINERS="$(docker ps -a --format '{{.Names}}' 2>/dev/null || echo "DOCKER_QUERY_FAILED")"
    if [ "${ALL_CONTAINERS}" = "DOCKER_QUERY_FAILED" ]; then
        printf '❌ ERRO DE GUARDA: Falha ao consultar Docker daemon.\n' >&2
        printf '   Por segurança preventiva, a execução foi abortada.\n' >&2
        exit 11
    fi
    MATCHING_CONTAINERS="$(printf '%s\n' "${ALL_CONTAINERS}" | grep -E "${PROD_PATTERNS}" || true)"
    if [ -n "${MATCHING_CONTAINERS}" ]; then
        printf '❌ ERRO DE GUARDA: Contêineres com nomes da produção em execução detectados:\n' >&2
        printf '%s\n' "${MATCHING_CONTAINERS}" >&2
        printf '   Este script não pode rodar no mesmo host em que a produção reside!\n' >&2
        exit 11
    fi
fi

# ------------------------------------------------------------------------------
# ESTADO GLOBAL E CONFIGURAÇÃO DA SESSÃO
# ------------------------------------------------------------------------------

TS_STAMP="$(date +%Y%m%d-%H%M%S)"
PID_ATUAL="$$"
SESSION_ID="${TS_STAMP}-${PID_ATUAL}"
SESSION_LABEL="sbjur.audit.session=${SESSION_ID}"

BACKUP_FILE=""
INVENTORY_FILE=""
SKIP_GRAPHQL_FIX=0
KEEP_LAB=0

AUDIT_WORK_DIR="${HOME}/.sbjur-audit"
DIAG_DIR="${AUDIT_WORK_DIR}/auditorias/${TS_STAMP}-${PID_ATUAL}"
TRACKED_RESOURCES_FILE="${DIAG_DIR}/session-tracked-resources.txt"

LOG_FILE="${DIAG_DIR}/auditoria-${TS_STAMP}-${PID_ATUAL}.log"
RESTORE_ERRORS_FILE="${DIAG_DIR}/erros-restore-${TS_STAMP}-${PID_ATUAL}.log"
DIVERGENCES_FILE="${DIAG_DIR}/divergencias-${TS_STAMP}-${PID_ATUAL}.txt"
CONFERIDOS_FILE="${DIAG_DIR}/conferidos-${TS_STAMP}-${PID_ATUAL}.txt"
# Ponto 1 da correção v2.0.0: registro privativo das falhas de consulta SQL
# (a contagem via variável não sobrevive a $(...); o arquivo sim).
QUERY_FAILURES_FILE="${DIAG_DIR}/falhas-sql-${TS_STAMP}-${PID_ATUAL}.txt"
# CORREÇÃO 3 (v2.1.1): sinal FATAL de registro INDEPENDENTE do arquivo de
# registro. A EXISTÊNCIA deste arquivo indica falha de escrita no registro de
# falhas SQL (ou impossibilidade de registrar a própria falha fatal). NÃO é
# criado na inicialização (e por isso NÃO entra no loop de touch/chmod 600
# abaixo): o sinal é a própria existência do arquivo.
QUERY_FAILURES_FATAL_FLAG="${DIAG_DIR}/falha-fatal-registro-sql-${TS_STAMP}-${PID_ATUAL}.flag"
# CORREÇÃO (v2.1.2): canal de sinalização ADICIONAL em DIRETÓRIO dedicado —
# criado no pre-voo com mkdir sem -p (atômico: prova ausência preexistente),
# chmod 700 e permissão efetiva validada por stat. O sinal fatal é a criação
# ATÔMICA do subdiretório "registro-sql-fatal" (mkdir), que independe da
# escrita em arquivos e por isso quase nunca falha junto com os canais A
# (registro) e B (flag). Marcadores alternativos FORA de DIAG_DIR completam a
# cascata (canal D) e a flag em memória (QUERY_FAILURES_UNSIGNABLE) é o
# último recurso (canal E).
QUERY_FAILURES_SIGNAL_DIR="${DIAG_DIR}/sinal-registro-sql-${TS_STAMP}-${PID_ATUAL}.dir"
QUERY_FAILURES_FATAL_ALT_WORK_DIR="${AUDIT_WORK_DIR}/sinal-fatal-registro-sql-${SESSION_ID}.dir"
QUERY_FAILURES_FATAL_ALT_TMP_DIR="${TMPDIR:-/tmp}/sbjur-audit-sinal-fatal-${SESSION_ID}.dir"
TEMPORAL_DIFFS_FILE="${DIAG_DIR}/diferencas-temporais-${TS_STAMP}-${PID_ATUAL}.txt"
REPORT_FILE="${DIAG_DIR}/relatorio-${TS_STAMP}-${PID_ATUAL}.txt"

LAB_NAME="sbjur-audit-lab-${TS_STAMP}-${PID_ATUAL}"
LAB_VOLUME="sbjur-audit-vol-${TS_STAMP}-${PID_ATUAL}"
PG_IMAGE="supabase/postgres:15.1.1.130"
PG_IMAGE_FALLBACK="postgres:15-alpine"

# Variáveis globais de rastreamento de resultado e integridade
RESTORE_ORIGINAL_STATUS="PENDENTE"
QUERY_FAILURES_COUNT=0
# CORREÇÃO (v2.1.2): último recurso em memória — ativado APENAS quando TODOS
# os canais persistentes (registro, flag, diretório dedicado e alternativos)
# falharem. Consultado na consolidação do veredito (processo principal).
QUERY_FAILURES_UNSIGNABLE=0
TOTAL_TABELAS_LAB=0
TOTAL_TABELAS_AUTH_LAB=0
INVENTORY_COMPARISON_VALID="NAO"
INVENTORY_BIDIRECTIONAL_CHECK_PASSED=0
STRUCTURAL_CHECK_PASSED=0
OPERATIONAL_CRM_CHECK_PASSED=0

EXIT_OK=0
EXIT_USAGE=10
EXIT_HOST_GUARD=11
EXIT_DEP_MISSING=12
EXIT_RESTORE_FAIL=20
EXIT_GRAPHQL_FAIL=21
EXIT_STRUCTURE_FAIL=22
EXIT_INVENTORY_FAIL=23
EXIT_OP_FAIL=24
EXIT_FS_FAIL=25

# ------------------------------------------------------------------------------
# HELPERS DE LOG E CONSOLE
# ------------------------------------------------------------------------------

say() {
    printf '%s\n' "$*"
}

say_err() {
    printf '❌ %s\n' "$*" >&2
}

die() {
    local msg="$1" code="$2"
    say_err "${msg}"
    if [ -n "${LOG_FILE:-}" ] && [ -f "${LOG_FILE}" ]; then
        say "   Consulte o log técnico: ${LOG_FILE}" >&2
        printf '%s ABORTADO (exit %s): %s\n' "$(date '+%F %T')" "${code}" "${msg}" >> "${LOG_FILE}"
    fi
    exit "${code}"
}

log() {
    if [ -n "${LOG_FILE:-}" ] && [ -f "${LOG_FILE}" ]; then
        printf '%s %s\n' "$(date '+%F %T')" "$*" >> "${LOG_FILE}"
    fi
}

show_help() {
    cat <<EOF
Uso: bash $0 --arquivo <caminho/backup.sql.gz> [OPÇÕES]

Opções:
  --arquivo <caminho>       Caminho do dump de backup (.sql.gz) a ser auditado (obrigatório).
  --inventario <caminho>    Caminho do arquivo JSON de inventário gerado por 21-gerar-inventario.sh.
  --pular-graphql-fix       Pula a recuperação assistida de pg_graphql se a extensão falhar.
  --manter-lab              Não destrói o contêiner de teste ao final (para depuração interativa).
  -h, --help                Exibe esta ajuda.

Exemplo:
  bash docs/vps/20-auditar-backup.sh \\
      --arquivo /tmp/backup-2026-11-10.sql.gz \\
      --inventario /tmp/inventario-20261110-180000.json
EOF
}

# ------------------------------------------------------------------------------
# PONTO 9 DA AUDITORIA: LIMPEZA E RASTREAMENTO ESTRITO DE RECURSOS DA SESSÃO
# Apenas recursos comprovadamente criados por esta sessão (nome + label + arquivo
# rastreador) podem ser removidos. Nenhuma limpeza executa antes da guarda!
# ------------------------------------------------------------------------------

track_resource() {
    local type="$1" name="$2"
    if [ -f "${TRACKED_RESOURCES_FILE}" ]; then
        printf '%s:%s\n' "${type}" "${name}" >> "${TRACKED_RESOURCES_FILE}"
    fi
}

cleanup_lab() {
    local exit_code=$?
    log "Rotina de limpeza acionada (código de saída: ${exit_code})"

    if [ "${KEEP_LAB}" -eq 1 ]; then
        say ""
        say "⚠️  Flag --manter-lab ativa: contêiner '${LAB_NAME}' e volume mantidos para depuração."
        return "${exit_code}"
    fi

    # Validação do arquivo rastreador de recursos criados nesta execução (Ponto 9)
    if [ ! -f "${TRACKED_RESOURCES_FILE}" ]; then
        log "Nenhum arquivo de recursos rastreados encontrado. Nenhuma remoção de Docker será feita."
        return "${exit_code}"
    fi

    if command -v docker >/dev/null 2>&1; then
        # 1. Remover contêiner SOMENTE se bater com LAB_NAME, SESSION_LABEL e estiver rastreado
        if grep -qx "container:${LAB_NAME}" "${TRACKED_RESOURCES_FILE}" 2>/dev/null; then
            local c_inspect_label
            c_inspect_label="$(docker inspect --format '{{index .Config.Labels "sbjur.audit.session"}}' "${LAB_NAME}" 2>/dev/null || echo "")"
            if [ "${c_inspect_label}" = "${SESSION_ID}" ]; then
                say "🧹 Removendo contêiner de laboratório isolado comprovado desta sessão: ${LAB_NAME}..."
                docker rm -f "${LAB_NAME}" >>"${LOG_FILE}" 2>&1 || true
            else
                log "Contêiner ${LAB_NAME} não possui label da sessão atual. Remoção recusada por segurança."
            fi
        fi

        # 2. Remover volume SOMENTE se bater com LAB_VOLUME, SESSION_LABEL e estiver rastreado
        if grep -qx "volume:${LAB_VOLUME}" "${TRACKED_RESOURCES_FILE}" 2>/dev/null; then
            local v_inspect_label
            v_inspect_label="$(docker volume inspect --format '{{index .Labels "sbjur.audit.session"}}' "${LAB_VOLUME}" 2>/dev/null || echo "")"
            if [ "${v_inspect_label}" = "${SESSION_ID}" ]; then
                say "🧹 Removendo volume do laboratório comprovado desta sessão: ${LAB_VOLUME}..."
                docker volume rm "${LAB_VOLUME}" >>"${LOG_FILE}" 2>&1 || true
            else
                log "Volume ${LAB_VOLUME} não possui label da sessão atual. Remoção recusada por segurança."
            fi
        fi
    fi

    return "${exit_code}"
}

# Ponto 7 da correção v1.8.0: INT/TERM possuem handler PRÓPRIO (não compartilham
# o trap de EXIT): executa a mesma limpeza RESTRITA aos recursos desta sessão
# (laboratório rastreado por label + arquivo de sessão) e TERMINA imediatamente
# com 128+n, sem permitir que a execução seja retomada após o sinal.
cleanup_lab_on_signal() {
    local signal_name="$1" signal_num="$2"
    trap '' INT TERM
    log "Sinal ${signal_name} recebido; executando limpeza restrita aos recursos da sessão e encerrando."
    say ""
    say "⚠️  Sinal ${signal_name} recebido: removendo apenas os recursos desta sessão e encerrando..."
    KEEP_LAB_SAVED="${KEEP_LAB}"
    KEEP_LAB=0
    cleanup_lab 0
    trap - EXIT
    # O estado de KEEP_LAB da sessão é preservado: a limpeza no sinal é um evento
    # de encerramento; nenhum retorno à execução principal ocorre a partir daqui.
    exit $((128 + signal_num))
}
trap 'cleanup_lab_on_signal INT 2' INT
trap 'cleanup_lab_on_signal TERM 15' TERM
trap cleanup_lab EXIT

# ------------------------------------------------------------------------------
# PONTO 2 E PONTO 3 DA AUDITORIA: CRIAÇÃO SEGURA DE DIRETÓRIOS E PERMISSÕES EFETIVAS
# Nunca aplicar chmod indiscriminadamente a diretórios preexistentes.
# Validar permissões efetivas (600/700) e não ignorar falhas com || true.
# ------------------------------------------------------------------------------

# Se AUDIT_WORK_DIR não existia, cria e ajusta 700. Se já existia, não toca no pai.
if [ ! -d "${AUDIT_WORK_DIR}" ]; then
    if ! mkdir -p "${AUDIT_WORK_DIR}"; then
        printf '❌ Falha ao criar diretório base de auditoria: %s\n' "${AUDIT_WORK_DIR}" >&2
        exit "${EXIT_FS_FAIL}"
    fi
    if ! chmod 700 "${AUDIT_WORK_DIR}"; then
        printf '❌ Falha ao definir permissões (700) no diretório base de auditoria.\n' >&2
        exit "${EXIT_FS_FAIL}"
    fi
fi

if ! mkdir -p "${DIAG_DIR}"; then
    printf '❌ Falha ao criar diretório privado da sessão: %s\n' "${DIAG_DIR}" >&2
    exit "${EXIT_FS_FAIL}"
fi
if ! chmod 700 "${DIAG_DIR}"; then
    printf '❌ Falha ao definir permissões (700) no diretório privado da sessão: %s\n' "${DIAG_DIR}" >&2
    exit "${EXIT_FS_FAIL}"
fi

# Inicializar arquivos privados de trabalho sob umask 077 estrito
for f in "${TRACKED_RESOURCES_FILE}" "${LOG_FILE}" "${RESTORE_ERRORS_FILE}" "${DIVERGENCES_FILE}" "${CONFERIDOS_FILE}" "${QUERY_FAILURES_FILE}" "${TEMPORAL_DIFFS_FILE}" "${REPORT_FILE}"; do
    if ! touch "${f}"; then
        printf '❌ Falha ao criar arquivo de trabalho da auditoria: %s\n' "${f}" >&2
        exit "${EXIT_FS_FAIL}"
    fi
    if ! chmod 600 "${f}"; then
        printf '❌ Falha ao aplicar chmod 600 no arquivo: %s\n' "${f}" >&2
        exit "${EXIT_FS_FAIL}"
    fi
    # Ponto 7 da Auditoria: tratar falha OU resultado vazio de stat como erro impeditivo (die/abort)
    eff_perm="$(stat -c '%a' "${f}" 2>/dev/null || stat -f '%Lp' "${f}" 2>/dev/null || echo "")"
    if [ -z "${eff_perm}" ]; then
        printf '❌ Falha ao obter permissão efetiva de %s via stat (resultado vazio ou comando falhou).\n' "${f}" >&2
        exit "${EXIT_FS_FAIL}"
    fi
    if [ "${eff_perm}" != "600" ]; then
        printf '❌ Permissão efetiva do arquivo %s (%s) não confere com 600.\n' "${f}" "${eff_perm}" >&2
        exit "${EXIT_FS_FAIL}"
    fi
done

# ------------------------------------------------------------------------------
# CORREÇÃO (v2.1.2): CRIAÇÃO DO CANAL DE SINALIZAÇÃO FATAL EM DIRETÓRIO DEDICADO
# mkdir SEM -p é atômico e prova que o diretório não preexistia; chmod 700 e
# permissão efetiva (stat) são validados como nos demais recursos da sessão.
# ------------------------------------------------------------------------------
if ! mkdir "${QUERY_FAILURES_SIGNAL_DIR}"; then
    printf '❌ Falha ao criar diretório do canal de sinalização de falhas SQL: %s\n' "${QUERY_FAILURES_SIGNAL_DIR}" >&2
    exit "${EXIT_FS_FAIL}"
fi
if ! chmod 700 "${QUERY_FAILURES_SIGNAL_DIR}"; then
    printf '❌ Falha ao definir permissões (700) no diretório do canal de sinalização: %s\n' "${QUERY_FAILURES_SIGNAL_DIR}" >&2
    exit "${EXIT_FS_FAIL}"
fi
SIGNAL_DIR_PERM="$(stat -c '%a' "${QUERY_FAILURES_SIGNAL_DIR}" 2>/dev/null || stat -f '%Lp' "${QUERY_FAILURES_SIGNAL_DIR}" 2>/dev/null || echo "")"
if [ -z "${SIGNAL_DIR_PERM}" ] || [ "${SIGNAL_DIR_PERM}" != "700" ]; then
    printf '❌ Permissão efetiva do diretório do canal de sinalização inválida (%s).\n' "${SIGNAL_DIR_PERM}" >&2
    exit "${EXIT_FS_FAIL}"
fi
log "Canal de sinalização de falhas SQL pronto: ${QUERY_FAILURES_SIGNAL_DIR}"

log "Iniciando script de auditoria ${SCRIPT_VERSION} (PID $$)"
log "Diretório de diagnóstico privado: ${DIAG_DIR}"

# ------------------------------------------------------------------------------
# PARSE DE ARGUMENTOS
# ------------------------------------------------------------------------------

while [ $# -gt 0 ]; do
    case "$1" in
        --arquivo)
            [ $# -ge 2 ] || die "Parâmetro --arquivo requer um caminho." "${EXIT_USAGE}"
            BACKUP_FILE="$2"
            shift 2
            ;;
        --inventario)
            [ $# -ge 2 ] || die "Parâmetro --inventario requer um caminho." "${EXIT_USAGE}"
            INVENTORY_FILE="$2"
            shift 2
            ;;
        --pular-graphql-fix)
            SKIP_GRAPHQL_FIX=1
            shift
            ;;
        --manter-lab)
            KEEP_LAB=1
            shift
            ;;
        -h|--help)
            show_help
            exit "${EXIT_OK}"
            ;;
        *)
            die "Opção desconhecida: $1 (consulte $0 --help)" "${EXIT_USAGE}"
            ;;
    esac
done

if [ -z "${BACKUP_FILE}" ]; then
    show_help
    die "O parâmetro --arquivo <backup.sql.gz> é obrigatório." "${EXIT_USAGE}"
fi

if [ ! -f "${BACKUP_FILE}" ]; then
    die "Arquivo de backup não encontrado: ${BACKUP_FILE}" "${EXIT_USAGE}"
fi

if [ -n "${INVENTORY_FILE}" ] && [ ! -f "${INVENTORY_FILE}" ]; then
    die "Arquivo de inventário especificado não foi encontrado: ${INVENTORY_FILE}" "${EXIT_USAGE}"
fi

# ------------------------------------------------------------------------------
# DEPENDÊNCIAS LOCAIS
# ------------------------------------------------------------------------------

for dep in docker gunzip psql; do
    if ! command -v "${dep}" >/dev/null 2>&1; then
        die "Dependência obrigatória não encontrada no PATH: ${dep}" "${EXIT_DEP_MISSING}"
    fi
done

if ! command -v jq >/dev/null 2>&1; then
    if [ -n "${INVENTORY_FILE}" ]; then
        die "A ferramenta 'jq' é obrigatória para validar e comparar o inventário JSON." "${EXIT_DEP_MISSING}"
    else
        say "⚠️  Aviso: 'jq' não encontrado; comparação com inventário não será possível se fornecido."
    fi
fi

# CORREÇÃO 3 (v2.1.0): 'base64' é obrigatória para a decodificação segura dos
# campos JSON do inventário e do laboratório (jq @base64 + base64 -d, sem eval).
# A disponibilidade é verificada ANTES do primeiro uso; ausência é falha de
# ambiente IMPEDITIVA (divergência registrada + aborto), jamais degradação.
if ! command -v base64 >/dev/null 2>&1; then
    printf 'DIVERGÊNCIA: Dependência obrigatória "base64" ausente no PATH — decodificação segura de JSON impossível (falha de ambiente impeditiva).\n' >> "${DIVERGENCES_FILE}"
    die "Dependência obrigatória não encontrada no PATH: base64 (exigida pela Correção 3 da v2.1.0)." "${EXIT_DEP_MISSING}"
fi

if ! docker info >>"${LOG_FILE}" 2>&1; then
    die "Docker daemon inacessível ou sem permissão de execução." "${EXIT_DEP_MISSING}"
fi

# ------------------------------------------------------------------------------
# HELPERS DE EXECUÇÃO SQL NO LABORATÓRIO (Ponto 3: não ignorar falhas)
# ------------------------------------------------------------------------------

exec_lab_sql() {
    local sql="$1"
    local out rc
    if command -v timeout >/dev/null 2>&1; then
        out="$(timeout 60 docker exec "${LAB_NAME}" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres -t -A -c "${sql}" 2>>"${LOG_FILE}")"
        rc=$?
    else
        out="$(docker exec "${LAB_NAME}" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres -t -A -c "${sql}" 2>>"${LOG_FILE}")"
        rc=$?
    fi
    if [ "${rc}" -ne 0 ]; then
        # Correção (v2.1.2): o retorno de record_query_failure é verificado —
        # falha de registro é anunciada (não silenciada) e o mecanismo fail-
        # closed interno (canais A/B/C/D + sonda na consolidação) é acionado;
        # o exit code da consulta SQL continua propagando ao chamador.
        if ! record_query_failure "exec_lab_sql (exit ${rc}): ${sql}"; then
            say_err "Falha de consulta SQL (exit ${rc}) NÃO pôde ser registrada no arquivo de falhas; mecanismo fail-closed de sinalização acionado."
        fi
        log "FALHA SQL (exit ${rc}): ${sql}"
        return "${rc}"
    fi
    printf '%s\n' "${out}"
}

exec_lab_sql_file() {
    local file="$1"
    local rc
    if command -v timeout >/dev/null 2>&1; then
        timeout 120 docker exec -i "${LAB_NAME}" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres < "${file}" >>"${LOG_FILE}" 2>&1
        rc=$?
    else
        docker exec -i "${LAB_NAME}" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres < "${file}" >>"${LOG_FILE}" 2>&1
        rc=$?
    fi
    if [ "${rc}" -ne 0 ]; then
        # Correção (v2.1.2): retorno de record_query_failure verificado (idem
        # exec_lab_sql); exit code da consulta continua propagando ao chamador.
        if ! record_query_failure "exec_lab_sql_file (exit ${rc}): ${file}"; then
            say_err "Falha de consulta SQL em arquivo (exit ${rc}) NÃO pôde ser registrada no arquivo de falhas; mecanismo fail-closed de sinalização acionado."
        fi
        log "FALHA SQL FILE (exit ${rc}): ${file}"
        return "${rc}"
    fi
    return 0
}

# ------------------------------------------------------------------------------
# PONTO 1 DA CORREÇÃO v2.0.0: CONTABILIZAÇÃO DE FALHAS SQL FORA DE SUBSHELLS
# Atribuições feitas dentro de $(...) NÃO persistem no processo Bash principal,
# de modo que um incremento de contador dentro de captura de comando se perde.
# Cada falha SQL é portanto REGISTRADA EM ARQUIVO privativo da sessão (criado
# com chmod 600 na inicialização) e a contagem efetiva usada pelo veredito é
# lida DESTE arquivo na consolidação final — nenhuma falha SQL escapa do
# veredito. Falhas SQL fora de exec_lab_sql (identidade de funções e
# pg_get_functiondef) também chamam record_query_failure.
#
# CORREÇÃO 3 (v2.1.1): toda falha de escrita no registro é detectada
# IMEDIATAMENTE (o "2>/dev/null" que mascarava a falha foi removido e o código
# de saída do append é verificado), produz diagnóstico claro em stderr e é
# refletida em mecanismo que NÃO depende do próprio arquivo cuja escrita
# falhou: o sinal fatal QUERY_FAILURES_FATAL_FLAG (arquivo criado na hora, com
# umask 077). Por ser baseada em ARQUIVO, a flag sobrevive ao retorno de
# subshells $(...) ao processo principal (idem ao arquivo de registro) e é
# checada na consolidação do veredito; presença = aprovação impossível.
#
# CORREÇÃO (v2.1.2): a checagem da consolidação NÃO se limita mais à presença
# da flag — a própria CONSULTA é verificada (sonda mkdir+rmdir no diretório
# dedicado) e cascata de canais B/C/D completa o fail-closed (ver cabeçalho).
# ------------------------------------------------------------------------------

# Correção (v2.1.2): ativa o sinal fatal de registro em CASCATA por canais
# independentes. Retorna 0 se QUALQUER canal conseguir sinalizar.
signal_query_failure_fatal() {
    local desc="$1"
    local stamp
    stamp="$(date '+%F %T')"

    # Canal B (v2.1.1, preservado): arquivo flag próprio (existência = sinal).
    if [ -n "${QUERY_FAILURES_FATAL_FLAG:-}" ]; then
        if printf '%s Falha fatal de registro SQL: %s\n' "${stamp}" "${desc}" >> "${QUERY_FAILURES_FATAL_FLAG}" 2>/dev/null; then
            return 0
        fi
        printf '❌ FALHA FATAL (registro SQL): escrita no sinal fatal %s falhou (%s) — tentando canais adicionais (diretório dedicado e alternativos).\n' "${QUERY_FAILURES_FATAL_FLAG}" "${desc}" >&2
    fi

    # Canal C (v2.1.2): DIRETÓRIO dedicado criado no pre-voo — sinal atômico
    # por mkdir (independe de escrita em arquivo). Diretório já existente =
    # sinal já ativo (também sucesso). É o canal PRIMÁRIO da v2.1.2: resiste
    # quando a escrita em arquivos falha.
    if [ -n "${QUERY_FAILURES_SIGNAL_DIR:-}" ]; then
        if mkdir "${QUERY_FAILURES_SIGNAL_DIR}/registro-sql-fatal" 2>/dev/null; then
            printf '%s Falha fatal de registro SQL: %s\n' "${stamp}" "${desc}" >> "${QUERY_FAILURES_SIGNAL_DIR}/registro-sql-fatal/motivo.txt" 2>/dev/null || true
            return 0
        elif [ -d "${QUERY_FAILURES_SIGNAL_DIR}/registro-sql-fatal" ]; then
            return 0
        fi
    fi

    # Canal D (v2.1.2): marcadores alternativos FORA de DIAG_DIR (diretório
    # base de auditoria e TMPDIR). Marcadores deixados no TMPDIR são evidência
    # deliberada da sessão (não são removidos pelo cleanup). Canal E: flag em
    # memória (QUERY_FAILURES_UNSIGNABLE, definida em record_query_failure).
    local alt
    for alt in "${QUERY_FAILURES_FATAL_ALT_WORK_DIR:-}" "${QUERY_FAILURES_FATAL_ALT_TMP_DIR:-}"; do
        [ -n "${alt}" ] || continue
        if mkdir "${alt}" 2>/dev/null; then
            printf '%s Falha fatal de registro SQL: %s\n' "${stamp}" "${desc}" >> "${alt}/motivo.txt" 2>/dev/null || true
            return 0
        elif [ -d "${alt}" ]; then
            return 0
        fi
    done

    printf '❌ FALHA FATAL GRAVE (registro SQL): TODOS os canais persistentes de sinalização falharam (%s).\n' "${desc}" >&2
    return 1
}

# Correção (v2.1.2): consulta do mecanismo de sinalização com VERIFICAÇÃO DA
# PRÓPRIA CONSULTA (fail-closed completo). Códigos de retorno:
#   0 = canal íntegro e SEM sinal fatal;
#   1 = sinal fatal presente (qualquer canal);
#   2 = canal INACESSÍVEL ou consulta NÃO CONFIÁVEL (diretório ausente,
#       ilegível/inexecutável, ou sonda mkdir+rmdir que falhe) — a etapa
#       chamadora trata 2 como sinal NÃO CONFIÁVEL: veredito NUNCA é APROVADO.
check_query_failure_signal() {
    if [ -z "${QUERY_FAILURES_SIGNAL_DIR:-}" ] || [ ! -d "${QUERY_FAILURES_SIGNAL_DIR}" ]; then
        return 2
    fi
    if [ ! -r "${QUERY_FAILURES_SIGNAL_DIR}" ] || [ ! -x "${QUERY_FAILURES_SIGNAL_DIR}" ]; then
        return 2
    fi
    # Sonda: a consulta só é confiável se o canal conseguir criar E remover um
    # diretório de sonda agora. Falha aqui indica exatamente a condição em que
    # os canais de gravação também falhariam (fail-closed por construção).
    local probe="${QUERY_FAILURES_SIGNAL_DIR}/probe-consulta-$$"
    if ! mkdir "${probe}" 2>/dev/null; then
        return 2
    fi
    if ! rmdir "${probe}" 2>/dev/null; then
        return 2
    fi
    if [ -d "${QUERY_FAILURES_SIGNAL_DIR}/registro-sql-fatal" ]; then
        return 1
    fi
    if [ -f "${QUERY_FAILURES_FATAL_FLAG}" ]; then
        return 1
    fi
    if [ -d "${QUERY_FAILURES_FATAL_ALT_WORK_DIR:-}" ]; then
        return 1
    fi
    if [ -d "${QUERY_FAILURES_FATAL_ALT_TMP_DIR:-}" ]; then
        return 1
    fi
    return 0
}

record_query_failure() {
    local desc="$1"
    local registered=0

    if [ -z "${QUERY_FAILURES_FILE:-}" ]; then
        printf '❌ FALHA FATAL (registro SQL): QUERY_FAILURES_FILE não configurado — impossível registrar a falha de consulta (%s).\n' "${desc}" >&2
    elif printf '%s %s\n' "$(date '+%F %T')" "${desc}" >> "${QUERY_FAILURES_FILE}" 2>/dev/null; then
        registered=1
    else
        printf '❌ FALHA FATAL (registro SQL): escrita no arquivo de registro de falhas SQL falhou (%s) ao registrar: %s\n' "${QUERY_FAILURES_FILE}" "${desc}" >&2
    fi

    if [ "${registered}" -eq 0 ]; then
        # Correção (v2.1.2): cascata de canais de sinalização (flag, diretório
        # dedicado por mkdir atômico, marcadores alternativos). Retorno 1 é
        # verificado por TODOS os call sites.
        if signal_query_failure_fatal "${desc}"; then
            return 1
        fi
        # NENHUM canal persistente conseguiu sinalizar: último recurso em
        # MEMÓRIA do processo principal (canal E). NÃO sobrevive a subshell —
        # e por isso NÃO é o mecanismo principal: se o sistema de arquivos está
        # quebrado a ponto de os canais A/B/C/D falharem, a SONDA da consolidação
        # (check_query_failure_signal) também falha e o veredito é negado de
        # forma independente desta flag.
        QUERY_FAILURES_UNSIGNABLE=1
        printf '❌ FALHA FATAL GRAVE (registro SQL): impossível registrar a falha E impossível sinalizar em disco (%s) — condição registrada em memória (QUERY_FAILURES_UNSIGNABLE) e detectável na consolidação pela sonda do canal; a auditoria NUNCA será APROVADA nesta condição.\n' "${desc}" >&2
        return 1
    fi
    return 0
}

count_query_failures() {
    local n
    n="$(wc -l < "${QUERY_FAILURES_FILE}" 2>/dev/null | tr -d '[:space:]')"
    case "${n}" in
        ''|*[!0-9]*)
            # Contagem não confiável é conservadora: valor impossível de zerar,
            # impedindo qualquer aprovação até que a causa seja explicada.
            n=999
            ;;
    esac
    printf '%s' "${n}"
}

# ------------------------------------------------------------------------------
# PONTO 8 DA CORREÇÃO v1.8.0: VALIDAÇÃO DE IDENTIFICADORES DO INVENTÁRIO
# Identificadores (schema, tabela, constraint, função) provenientes do
# inventário são interpolados em SQL; aceitar apenas ^[a-zA-Z_][a-zA-Z0-9_]*$.
# A etapa chamadora registra DIVERGÊNCIA e recusa a interpolação quando falha.
# ------------------------------------------------------------------------------

is_safe_identifier() {
    local ident="$1"
    case "${ident}" in
        ''|*[!a-zA-Z0-9_]*)
            return 1
            ;;
    esac
    case "${ident}" in
        [a-zA-Z_]*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# ------------------------------------------------------------------------------
# CORREÇÃO 3 (v2.1.0): DECODIFICAÇÃO SEGURA DE CAMPOS JSON SEM EVAL
# Substitui o padrão "jq @sh + eval" (que entregava o conteúdo ao shell para
# interpretação de comandos). Cada campo é extraído como UMA única linha base64
# (jq @base64) e decodificado com base64 -d: aspas, apóstrofos, barras, quebras
# de linha e demais caracteres especiais trafegam integralmente, SEM NENHUMA
# interpretação pelo shell. O código de saída de AMBAS as etapas (jq E base64)
# é verificado; qualquer falha (JSON inválido, campo ausente/não string, erro
# de base64) retorna 1 e a etapa chamadora DEVE registrar DIVERGÊNCIA
# IMPEDITIVA — nunca silêncio ou valor vazio implícito. Nota: a captura de
# comando remove apenas quebras de linha FINAIS do valor decodificado; ambas as
# pontas de toda comparação são normalizadas de forma idêntica (tr -d '\r';
# tr '\n' ' '; colapso de espaços) antes de comparadas, mantendo a comparação
# simétrica. Valores vazios legítimos (ex.: identidade vazia de função sem
# argumentos) são decodificados corretamente (base64 de "" é "", exit 0).
#
# CORREÇÃO 2 (v2.1.1): campo obrigatório deve EXISTIR no objeto JSON e ser
# EFETIVAMENTE do tipo string. O filtro exige type == "string" ANTES do
# @base64: campo ausente (produz null), nulo, booleano, número ou objeto gera
# error() do jq (exit != 0) e portanto return 1 — NUNCA a codificação
# silenciosa do texto "null" que @base64 produziria sobre um valor nulo. O
# tipo real só é verificável porque a extração JSON-lines deixa de usar
# tostring (ver os pontos de extração de constraints e funções). String vazia
# legítima continua decodificável ("" -> "" , exit 0 em ambas as etapas).
# Segue SEM eval: decodificação por jq @base64 + base64 -d somente.
# ------------------------------------------------------------------------------

jq_field_decode() {
    local filter="$1" json="$2" b64 rc
    b64="$(jq -r "${filter} | if type == \"string\" then @base64 else error(\"campo ausente, nulo ou não string\") end" <<<"${json}" 2>>"${LOG_FILE}")"
    rc=$?
    if [ "${rc}" -ne 0 ]; then
        return 1
    fi
    if ! base64 -d <<<"${b64}" 2>>"${LOG_FILE}"; then
        return 1
    fi
}

# ------------------------------------------------------------------------------
# APRESENTAÇÃO
# ------------------------------------------------------------------------------

say "================================================================================"
say " DPSjur / SBJur — AUDITORIA INDEPENDENTE DE RESTAURAÇÃO DE BACKUP (${SCRIPT_VERSION})"
say "================================================================================"
say " Arquivo a auditar ....: ${BACKUP_FILE}"
say " Inventário oficial ...: ${INVENTORY_FILE:-Nenhum informado}"
say " Sessão de auditoria ..: ${SESSION_ID}"
say " Contêiner de teste ...: ${LAB_NAME} (label: ${SESSION_LABEL})"
say " Volume isolado .......: ${LAB_VOLUME}"
say " Imagem PostgreSQL ....: ${PG_IMAGE}"
say " Diretório privado ....: ${DIAG_DIR} (chmod 700)"
say "================================================================================"

# ------------------------------------------------------------------------------
# CRIAÇÃO DO LABORATÓRIO ISOLADO COM LABELS E RASTREAMENTO (Ponto 9)
# ------------------------------------------------------------------------------

say "🚀 Criando volume e contêiner de teste isolados com label de sessão..."

if ! docker volume create --label "${SESSION_LABEL}" "${LAB_VOLUME}" >>"${LOG_FILE}" 2>&1; then
    die "Falha ao criar volume Docker isolado: ${LAB_VOLUME}" "${EXIT_RESTORE_FAIL}"
fi
track_resource "volume" "${LAB_VOLUME}"

CHOSEN_IMAGE="${PG_IMAGE}"
if ! docker pull "${CHOSEN_IMAGE}" >>"${LOG_FILE}" 2>&1; then
    say "⚠️  Imagem oficial (${PG_IMAGE}) não disponível no registry; utilizando fallback (${PG_IMAGE_FALLBACK})..."
    CHOSEN_IMAGE="${PG_IMAGE_FALLBACK}"
    if ! docker pull "${CHOSEN_IMAGE}" >>"${LOG_FILE}" 2>&1; then
        die "Falha ao baixar imagem Docker do PostgreSQL (${CHOSEN_IMAGE})." "${EXIT_RESTORE_FAIL}"
    fi
fi

if ! docker run -d \
    --name "${LAB_NAME}" \
    --label "${SESSION_LABEL}" \
    --network none \
    -v "${LAB_VOLUME}:/var/lib/postgresql/data" \
    -e POSTGRES_PASSWORD=postgres_audit_password_secret \
    -e POSTGRES_DB=postgres \
    -e POSTGRES_USER=postgres \
    "${CHOSEN_IMAGE}" >>"${LOG_FILE}" 2>&1; then
    die "Falha ao iniciar contêiner de teste isolado: ${LAB_NAME}" "${EXIT_RESTORE_FAIL}"
fi
track_resource "container" "${LAB_NAME}"

say "⏳ Aguardando PostgreSQL do laboratório ficar pronto para aceitar conexões..."
READY=0
for i in $(seq 1 40); do
    if docker exec "${LAB_NAME}" pg_isready -U postgres -d postgres >>"${LOG_FILE}" 2>&1; then
        READY=1
        break
    fi
    sleep 1
done

if [ "${READY}" -ne 1 ]; then
    die "PostgreSQL do laboratório não respondeu após 40 segundos." "${EXIT_RESTORE_FAIL}"
fi
say "✅ PostgreSQL do laboratório está pronto e operacional."

# ------------------------------------------------------------------------------
# ETAPA 1: RESTAURAÇÃO DO BACKUP COM LOG CHMOD 600 E EXIGÊNCIA ESTRITA
# Ponto 1 da Auditoria:
#   Restauração COM psql -X -v ON_ERROR_STOP=1.
#   Exige SIMULTANEAMENTE:
#     - gunzip com exit 0
#     - psql com exit 0
#     - ausência de erros SQL (RESTORE_RAW_ERRORS_COUNT == 0)
#   Se qualquer um falhar, RESTORE_ORIGINAL_STATUS="FALHA".
# ------------------------------------------------------------------------------

say "📥 Descompactando e restaurando backup no laboratório..."
log "Iniciando restauração do dump: ${BACKUP_FILE}"

GZIP_EXIT=0
PSQL_EXIT=0

set +o pipefail
gunzip -c "${BACKUP_FILE}" 2>>"${LOG_FILE}" | \
    docker exec -i "${LAB_NAME}" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres 2>>"${RESTORE_ERRORS_FILE}" >/dev/null
PIPELINE_STATUS=("${PIPESTATUS[@]}")
set -o pipefail

GZIP_EXIT="${PIPELINE_STATUS[0]:-1}"
PSQL_EXIT="${PIPELINE_STATUS[1]:-1}"

if ! chmod 600 "${RESTORE_ERRORS_FILE}"; then
    die "Falha ao ajustar permissões do arquivo de erros do restore." "${EXIT_FS_FAIL}"
fi
RESTORE_ERR_PERM="$(stat -c '%a' "${RESTORE_ERRORS_FILE}" 2>/dev/null || stat -f '%Lp' "${RESTORE_ERRORS_FILE}" 2>/dev/null || echo "")"
if [ -z "${RESTORE_ERR_PERM}" ] || [ "${RESTORE_ERR_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de erros do restore inválida (${RESTORE_ERR_PERM})." "${EXIT_FS_FAIL}"
fi

# Ponto 3 da correção v1.8.0: contagem de erros SQL SEMPRE como UM único inteiro
# válido, inclusive quando grep não encontra correspondências (exit 1 não é
# fatal). A contagem é feita com wc -l sobre arquivo temporário e validada como
# inteiro; falha real de grep (exit >= 2) é fatal.
SQL_ERR_COUNT_TMP="${DIAG_DIR}/erros-sql-count-${TS_STAMP}-$$.txt"
SQL_ERR_GREP_RC=0
grep -E 'ERROR:|ERRO:|FATAL:' "${RESTORE_ERRORS_FILE}" >"${SQL_ERR_COUNT_TMP}" 2>/dev/null
SQL_ERR_GREP_RC=$?
if [ "${SQL_ERR_GREP_RC}" -ge 2 ]; then
    die "Falha ao varrer o log de erros SQL do restore (grep exit ${SQL_ERR_GREP_RC})." "${EXIT_FS_FAIL}"
fi
RESTORE_RAW_ERRORS_COUNT="$(wc -l < "${SQL_ERR_COUNT_TMP}" 2>/dev/null | tr -d '[:space:]')"
case "${RESTORE_RAW_ERRORS_COUNT}" in
    ''|*[!0-9]*)
        printf 'DIVERGÊNCIA: Contagem de erros SQL produziu valor não inteiro ("%s"); tratada como falha fatal\n' "${RESTORE_RAW_ERRORS_COUNT}" >> "${DIVERGENCES_FILE}"
        RESTORE_RAW_ERRORS_COUNT=999
        ;;
esac
rm -f "${SQL_ERR_COUNT_TMP}" 2>/dev/null || true
log "Restauração finalizada. GZIP_EXIT=${GZIP_EXIT}, PSQL_EXIT=${PSQL_EXIT}, ERROS_SQL=${RESTORE_RAW_ERRORS_COUNT}"

# Ponto 1: Exigência simultânea de gunzip 0, psql 0 e zero erros SQL
if [ "${GZIP_EXIT}" -eq 0 ] && [ "${PSQL_EXIT}" -eq 0 ] && [ "${RESTORE_RAW_ERRORS_COUNT}" -eq 0 ]; then
    RESTORE_ORIGINAL_STATUS="OK"
else
    RESTORE_ORIGINAL_STATUS="FALHA"
    if [ "${GZIP_EXIT}" -ne 0 ]; then
        printf 'FALHA DE RESTAURAÇÃO ORIGINAL: gunzip falhou com código %s\n' "${GZIP_EXIT}" >> "${DIVERGENCES_FILE}"
    fi
    if [ "${PSQL_EXIT}" -ne 0 ]; then
        printf 'FALHA DE RESTAURAÇÃO ORIGINAL: psql falhou com código %s (ON_ERROR_STOP=1)\n' "${PSQL_EXIT}" >> "${DIVERGENCES_FILE}"
    fi
    if [ "${RESTORE_RAW_ERRORS_COUNT}" -gt 0 ]; then
        printf 'FALHA DE RESTAURAÇÃO ORIGINAL: %s erro(s) SQL capturados durante restauração\n' "${RESTORE_RAW_ERRORS_COUNT}" >> "${DIVERGENCES_FILE}"
    fi
fi

say "   Status da Restauração Original: ${RESTORE_ORIGINAL_STATUS} (gunzip: ${GZIP_EXIT}, psql: ${PSQL_EXIT}, erros SQL: ${RESTORE_RAW_ERRORS_COUNT})"

# ------------------------------------------------------------------------------
# ETAPA 2: RECUPERAÇÃO ASSISTIDA E VERIFICAÇÃO DE PG_GRAPHQL
# NUNCA DROP EXTENSION CASCADE! Apenas CREATE EXTENSION IF NOT EXISTS.
# ------------------------------------------------------------------------------

say "🔬 Verificando extensão pg_graphql (catálogo pg_extension/pg_available_extensions)..."
GRAPHQL_REC_STATUS="NAO_NECESSARIO"
GRAPHQL_FINAL_STATUS="FALHA"
# Correção 5 (v1.9.0): evidência separada da dependência pós-restauração.
# Recuperação assistida posterior NUNCA é tratada como prova de que a
# restauração original restituiu integralmente a extensão pg_graphql.
GRAPHQL_DEP_NOTE="não requerida"

# Ponto 6 da correção v1.8.0: verificação INEQUÍVOCA da extensão — consulta
# pg_extension (instalada, com extversion) e pg_available_extensions (disponível).
# A existência de função homônima (pg_proc.proname = 'graphql') NÃO é aceita
# como prova de extensão operacional.
if ! GRAPHQL_EXT_INFO="$(exec_lab_sql "SELECT CASE WHEN e.extname IS NOT NULL THEN 'INSTALADA:' || e.extversion WHEN a.name IS NOT NULL THEN 'DISPONIVEL:' || a.default_version ELSE 'AUSENTE' END FROM (SELECT 1) d LEFT JOIN pg_extension e ON e.extname = 'pg_graphql' LEFT JOIN pg_available_extensions a ON a.name = 'pg_graphql'")"; then
    GRAPHQL_EXT_INFO="ERRO_CONSULTA"
fi
GRAPHQL_EXT_INFO="$(printf '%s\n' "${GRAPHQL_EXT_INFO}" | tr -d '[:space:]')"

case "${GRAPHQL_EXT_INFO}" in
    INSTALADA:*)
        GRAPHQL_FINAL_STATUS="OK"
        say "✅ Extensão pg_graphql instalada no backup restaurado (versão: ${GRAPHQL_EXT_INFO#INSTALADA:})."
        ;;
    DISPONIVEL:*)
        say "⚠️  Extensão pg_graphql NÃO instalada no backup restaurado (disponível no catálogo: ${GRAPHQL_EXT_INFO#DISPONIVEL:})."
        if [ "${SKIP_GRAPHQL_FIX}" -eq 1 ]; then
            say "   Opção --pular-graphql-fix ativada. Nenhuma recuperação assistida será tentada."
            GRAPHQL_REC_STATUS="PULADO"
        else
            say "🛠️  Tentando recuperação assistida SEGURA (CREATE EXTENSION IF NOT EXISTS pg_graphql)..."
            # Execução estritamente aditiva: NUNCA DROP EXTENSION CASCADE!
            CREATE_EXT_RC=0
            if ! exec_lab_sql "CREATE EXTENSION IF NOT EXISTS pg_graphql WITH SCHEMA extensions;" >>"${LOG_FILE}" 2>&1; then
                CREATE_EXT_RC=1
            fi

            # Revalidação pelo catálogo de extensões (nunca por função homônima)
            if ! GRAPHQL_EXT_AFTER="$(exec_lab_sql "SELECT CASE WHEN e.extname IS NOT NULL THEN 'INSTALADA:' || e.extversion ELSE 'AUSENTE' END FROM (SELECT 1) d LEFT JOIN pg_extension e ON e.extname = 'pg_graphql'")"; then
                GRAPHQL_EXT_AFTER="ERRO_CONSULTA"
            fi
            GRAPHQL_EXT_AFTER="$(printf '%s\n' "${GRAPHQL_EXT_AFTER}" | tr -d '[:space:]')"

            GRAPHQL_REVALID_OK=0
            case "${GRAPHQL_EXT_AFTER}" in
                INSTALADA:*) GRAPHQL_REVALID_OK=1 ;;
            esac

            if [ "${CREATE_EXT_RC}" -eq 0 ] && [ "${GRAPHQL_REVALID_OK}" -eq 1 ]; then
                GRAPHQL_REC_STATUS="RECUPERADO_COM_SUCESSO"
                # Correção 5 (v1.9.0): estado "OK_RECUPERADO" PRESERVADO como evidência
                # separada (seção 2 do relatório mostra a recuperação assistida).
                GRAPHQL_FINAL_STATUS="OK_RECUPERADO"
                # Correção 5 (v1.9.0): dependência pós-restauração registrada e
                # IMPEDITIVA ao veredito APROVADO (recuperação NÃO é prova de
                # restauração original integral).
                GRAPHQL_DEP_NOTE="SIM: pg_graphql instalado por recuperação assistida (intervenção pós-restauração); auditoria NÃO emite APROVADO nesta condição"
                say "⚠️  Extensão pg_graphql só ficou operacional por recuperação assistida (intervenção PÓS-restauração); veredito NÃO será APROVADO por esta condição."
                printf 'Aviso Operacional: Extensão pg_graphql necessitou de CREATE EXTENSION aditivo pós-restauração (DEPENDÊNCIA PÓS-RESTAURAÇÃO).\n' >> "${CONFERIDOS_FILE}"
            else
                GRAPHQL_REC_STATUS="FALHA_NA_RECUPERACAO"
                GRAPHQL_FINAL_STATUS="FALHA"
                say_err "Falha na recuperação assistida de pg_graphql."
                printf 'DIVERGÊNCIA: Falha na recuperação assistida de pg_graphql (CREATE_EXT_RC=%s, estado_catalogo=%s)\n' "${CREATE_EXT_RC}" "${GRAPHQL_EXT_AFTER}" >> "${DIVERGENCES_FILE}"
            fi
        fi
        ;;
    *)
        GRAPHQL_REC_STATUS="FALHA_NA_RECUPERACAO"
        GRAPHQL_FINAL_STATUS="FALHA"
        say_err "Não foi possível determinar o estado da extensão pg_graphql (${GRAPHQL_EXT_INFO})."
        printf 'DIVERGÊNCIA: Estado da extensão pg_graphql indeterminável (%s)\n' "${GRAPHQL_EXT_INFO}" >> "${DIVERGENCES_FILE}"
        ;;
esac

# ------------------------------------------------------------------------------
# ETAPA 3: VALIDAÇÃO ESTRUTURAL DO BANCO RESTAURADO (public e auth)
# ------------------------------------------------------------------------------

say "📊 Executando inventário estrutural do banco restaurado..."

if ! TOTAL_TABELAS_LAB_RAW="$(exec_lab_sql "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE'")"; then
    printf 'DIVERGÊNCIA: Falha de consulta SQL ao contar tabelas public no laboratório\n' >> "${DIVERGENCES_FILE}"
fi
TOTAL_TABELAS_LAB="$(printf '%s\n' "${TOTAL_TABELAS_LAB_RAW:-0}" | tr -d '[:space:]')"

case "${TOTAL_TABELAS_LAB}" in
    ''|*[!0-9]*)
        printf 'DIVERGÊNCIA: Retorno não numérico ao contar tabelas public (%s)\n' "${TOTAL_TABELAS_LAB}" >> "${DIVERGENCES_FILE}"
        TOTAL_TABELAS_LAB=0
        ;;
esac

if ! TOTAL_TABELAS_AUTH_RAW="$(exec_lab_sql "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'auth' AND table_type = 'BASE TABLE'")"; then
    printf 'DIVERGÊNCIA: Falha de consulta SQL ao contar tabelas auth no laboratório\n' >> "${DIVERGENCES_FILE}"
fi
TOTAL_TABELAS_AUTH_LAB="$(printf '%s\n' "${TOTAL_TABELAS_AUTH_RAW:-0}" | tr -d '[:space:]')"

case "${TOTAL_TABELAS_AUTH_LAB}" in
    ''|*[!0-9]*)
        printf 'DIVERGÊNCIA: Retorno não numérico ao contar tabelas auth (%s)\n' "${TOTAL_TABELAS_AUTH_LAB}" >> "${DIVERGENCES_FILE}"
        TOTAL_TABELAS_AUTH_LAB=0
        ;;
esac

# CORREÇÃO 4 (v2.1.1): contagens informativas com o MESMO critério de escopo da
# comparação bidirecional (Correção 2 da v2.1.0): catálogos pg_constraint e
# pg_proc com n.nspname NOT LIKE 'pg\_%' AND n.nspname <> 'information_schema'
# — TODOS os schemas de usuário. Schemas internos do PostgreSQL (pg_%) e o
# information_schema permanecem EXCLUÍDOS em ambos os usos. Antes: contagens
# restritas a 'public' via information_schema.table_constraints/routines, que
# não contemplavam constraints EXCLUDE (contype 'x') nem objetos fora de
# public — escopo inconsistente com a comparação bidirecional de escopo
# completo (nunca misturar contagens de escopo público com comparações
# abrangendo todos os schemas de usuário).
TOTAL_CONSTRAINTS_LAB_RAW="$(exec_lab_sql "SELECT count(*) FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace WHERE n.nspname NOT LIKE 'pg\_%' AND n.nspname <> 'information_schema'")" || {
    printf 'DIVERGÊNCIA: Falha de consulta SQL ao contar constraints\n' >> "${DIVERGENCES_FILE}"
    TOTAL_CONSTRAINTS_LAB_RAW=0
}
TOTAL_CONSTRAINTS_LAB="$(printf '%s\n' "${TOTAL_CONSTRAINTS_LAB_RAW}" | tr -d '[:space:]')"

TOTAL_FUNCOES_LAB_RAW="$(exec_lab_sql "SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname NOT LIKE 'pg\_%' AND n.nspname <> 'information_schema'")" || {
    printf 'DIVERGÊNCIA: Falha de consulta SQL ao contar funções public\n' >> "${DIVERGENCES_FILE}"
    TOTAL_FUNCOES_LAB_RAW=0
}
TOTAL_FUNCOES_LAB="$(printf '%s\n' "${TOTAL_FUNCOES_LAB_RAW}" | tr -d '[:space:]')"

TOTAL_TRIGGERS_LAB_RAW="$(exec_lab_sql "SELECT count(*) FROM information_schema.triggers WHERE trigger_schema = 'public'")" || {
    printf 'DIVERGÊNCIA: Falha de consulta SQL ao contar triggers public\n' >> "${DIVERGENCES_FILE}"
    TOTAL_TRIGGERS_LAB_RAW=0
}
TOTAL_TRIGGERS_LAB="$(printf '%s\n' "${TOTAL_TRIGGERS_LAB_RAW}" | tr -d '[:space:]')"

TOTAL_EXTENSOES_LAB_RAW="$(exec_lab_sql "SELECT count(*) FROM pg_extension")" || {
    printf 'DIVERGÊNCIA: Falha de consulta SQL ao contar extensões\n' >> "${DIVERGENCES_FILE}"
    TOTAL_EXTENSOES_LAB_RAW=0
}
TOTAL_EXTENSOES_LAB="$(printf '%s\n' "${TOTAL_EXTENSOES_LAB_RAW}" | tr -d '[:space:]')"

say "   Tabelas no schema public ...: ${TOTAL_TABELAS_LAB}"
say "   Tabelas no schema auth .....: ${TOTAL_TABELAS_AUTH_LAB}"
say "   Constraints (schemas de usuário): ${TOTAL_CONSTRAINTS_LAB}"
say "   Funções (schemas de usuário) ....: ${TOTAL_FUNCOES_LAB}"
say "   Triggers no public .........: ${TOTAL_TRIGGERS_LAB}"
say "   Extensões instaladas .......: ${TOTAL_EXTENSOES_LAB}"

# Contagem de registros no laboratório (schemas public e auth)
LAB_PUBLIC_TABLES_LIST=""
if ! LAB_PUBLIC_TABLES_LIST="$(exec_lab_sql "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE' ORDER BY table_name")"; then
    printf 'DIVERGÊNCIA: Falha de consulta SQL ao listar tabelas public\n' >> "${DIVERGENCES_FILE}"
fi

LAB_AUTH_TABLES_LIST=""
if ! LAB_AUTH_TABLES_LIST="$(exec_lab_sql "SELECT table_name FROM information_schema.tables WHERE table_schema = 'auth' AND table_type = 'BASE TABLE' ORDER BY table_name")"; then
    printf 'DIVERGÊNCIA: Falha de consulta SQL ao listar tabelas auth\n' >> "${DIVERGENCES_FILE}"
fi

TOTAL_REGISTROS_STATUS="OK"
if [ -n "${LAB_PUBLIC_TABLES_LIST}" ]; then
    while IFS= read -r t; do
        [ -n "${t}" ] || continue
        cnt_raw="$(exec_lab_sql "SELECT count(*) FROM public.\"${t}\"")" || {
            printf 'DIVERGÊNCIA: Falha de consulta SQL ao contar registros de public."%s"\n' "${t}" >> "${DIVERGENCES_FILE}"
            TOTAL_REGISTROS_STATUS="FALHA"
            continue
        }
        cnt="$(printf '%s\n' "${cnt_raw}" | tr -d '[:space:]')"
        case "${cnt}" in
            ''|*[!0-9]*)
                printf 'DIVERGÊNCIA: Retorno não numérico na contagem de public."%s" (%s)\n' "${t}" "${cnt}" >> "${DIVERGENCES_FILE}"
                TOTAL_REGISTROS_STATUS="FALHA"
                ;;
            *)
                printf 'Tabela public."%s": %s registros\n' "${t}" "${cnt}" >> "${CONFERIDOS_FILE}"
                ;;
        esac
    done <<< "${LAB_PUBLIC_TABLES_LIST}"
fi

if [ -n "${LAB_AUTH_TABLES_LIST}" ]; then
    while IFS= read -r t; do
        [ -n "${t}" ] || continue
        cnt_raw="$(exec_lab_sql "SELECT count(*) FROM auth.\"${t}\"")" || {
            printf 'DIVERGÊNCIA: Falha de consulta SQL ao contar registros de auth."%s"\n' "${t}" >> "${DIVERGENCES_FILE}"
            TOTAL_REGISTROS_STATUS="FALHA"
            continue
        }
        cnt="$(printf '%s\n' "${cnt_raw}" | tr -d '[:space:]')"
        case "${cnt}" in
            ''|*[!0-9]*)
                printf 'DIVERGÊNCIA: Retorno não numérico na contagem de auth."%s" (%s)\n' "${t}" "${cnt}" >> "${DIVERGENCES_FILE}"
                TOTAL_REGISTROS_STATUS="FALHA"
                ;;
            *)
                printf 'Tabela auth."%s": %s registros\n' "${t}" "${cnt}" >> "${CONFERIDOS_FILE}"
                ;;
        esac
    done <<< "${LAB_AUTH_TABLES_LIST}"
fi

if [ "${TOTAL_TABELAS_LAB}" -gt 0 ] && [ "${TOTAL_REGISTROS_STATUS}" = "OK" ]; then
    STRUCTURAL_CHECK_PASSED=1
fi

# ------------------------------------------------------------------------------
# ETAPA 4: COMPARAÇÃO BIDIRECIONAL COM INVENTÁRIO OFICIAL (Pontos 1, 6, 7 e 8)
# - Ponto 1: jq estrito com validação de tipos, zero grep
# - Ponto 6: Comparação estrutural ampliada de constraints e funções por identidade e DDL
# - Ponto 7: Bidirecionalidade estrita (backup -> inv E inv -> backup), schemas e métodos
# - Ponto 8: Diferenças de contagem são estritamente INCONCLUSIVAS (sem presunção de crescimento)
# ------------------------------------------------------------------------------

say "🔍 Realizando auditoria semântica com o inventário oficial..."

if [ -z "${INVENTORY_FILE}" ]; then
    say "⚠️  Nenhum arquivo de inventário informado (--inventario). Comparação semântica pulada."
    printf 'Aviso: Comparação com inventário oficial não executada (nenhum arquivo informado via --inventario).\n' >> "${DIVERGENCES_FILE}"
else
    if [ ! -f "${INVENTORY_FILE}" ]; then
        printf 'DIVERGÊNCIA: Arquivo de inventário informado não existe: %s\n' "${INVENTORY_FILE}" >> "${DIVERGENCES_FILE}"
    elif ! command -v jq >/dev/null 2>&1; then
        printf 'DIVERGÊNCIA: Ferramenta jq indisponível para comparar inventário\n' >> "${DIVERGENCES_FILE}"
    elif ! jq empty "${INVENTORY_FILE}" >/dev/null 2>&1; then
        printf 'DIVERGÊNCIA: Arquivo de inventário possui JSON inválido ou corrompido: %s\n' "${INVENTORY_FILE}" >> "${DIVERGENCES_FILE}"
    else
        say "📋 Validando integridade e campos obrigatórios do inventário com jq..."

        INVENTORY_EXTRACTION_INCOMPLETE=0

        # Ponto 3 e Ponto 6: Validação rigorosa da estrutura e tipos do inventário JSON
        # Ponto 1 da correção v1.8.0: o filtro termina em `true` (nunca `else empty`),
        # tornando o exit code de jq -e determinístico: 0 somente quando TODOS os
        # campos obrigatórios existem e estão tipados corretamente; 1 caso contrário.
        INV_SCHEMA_VALID=1
        if ! jq -e '
            if type != "object" then error("raiz não é objeto")
            elif ((.sumario | type) != "object") then error("sumario ausente ou inválido")
            elif ((.sumario.total_tabelas_public | type) != "number") then error("total_tabelas_public deve ser número")
            elif ((.sumario.total_tabelas_auth | type) != "number") then error("total_tabelas_auth deve ser número")
            elif ((.tabelas | type) != "array") then error("tabelas deve ser array")
            elif ((.constraints | type) != "array") then error("constraints deve ser array")
            elif ((.funcoes | type) != "array") then error("funcoes deve ser array")
            else true end
        ' "${INVENTORY_FILE}" >/dev/null 2>&1; then
            printf 'DIVERGÊNCIA: Inventário JSON reprovado na validação de campos obrigatórios e tipos\n' >> "${DIVERGENCES_FILE}"
            INV_SCHEMA_VALID=0
        fi

        # Ponto 1 da correção v1.8.0: totais devem existir E ser inteiros não
        # negativos (rejeita ausente, nulo, texto ou negativo).
        # Correção 3 (v1.9.0): exit code do jq verificado de fato — sem "|| echo"
        # mascarando falha. Saída legítima do filtro pode ser vazia (null); a
        # distinção é feita pelo exit code (0 = filtro executado, >=2 = erro jq).
        INV_TOTAL_PUBLIC=""
        INV_TOTAL_PUBLIC_RC=0
        INV_TOTAL_PUBLIC="$(jq -er '.sumario.total_tabelas_public // empty' "${INVENTORY_FILE}" 2>/dev/null)" || INV_TOTAL_PUBLIC_RC=$?
        if [ "${INV_TOTAL_PUBLIC_RC}" -ge 2 ]; then
            printf 'DIVERGÊNCIA: Falha de jq ao extrair total_tabelas_public do inventário (exit %s)\n' "${INV_TOTAL_PUBLIC_RC}" >> "${DIVERGENCES_FILE}"
            INVENTORY_EXTRACTION_INCOMPLETE=1
            INV_SCHEMA_VALID=0
        fi
        case "${INV_TOTAL_PUBLIC}" in
            ''|*[!0-9]*)
                printf 'DIVERGÊNCIA: Campo total_tabelas_public ausente, nulo ou não inteiro no inventário (valor: "%s")\n' "${INV_TOTAL_PUBLIC}" >> "${DIVERGENCES_FILE}"
                INV_TOTAL_PUBLIC=""
                INV_SCHEMA_VALID=0
                ;;
        esac

        INV_TOTAL_AUTH=""
        INV_TOTAL_AUTH_RC=0
        INV_TOTAL_AUTH="$(jq -er '.sumario.total_tabelas_auth // empty' "${INVENTORY_FILE}" 2>/dev/null)" || INV_TOTAL_AUTH_RC=$?
        if [ "${INV_TOTAL_AUTH_RC}" -ge 2 ]; then
            printf 'DIVERGÊNCIA: Falha de jq ao extrair total_tabelas_auth do inventário (exit %s)\n' "${INV_TOTAL_AUTH_RC}" >> "${DIVERGENCES_FILE}"
            INVENTORY_EXTRACTION_INCOMPLETE=1
            INV_SCHEMA_VALID=0
        fi
        case "${INV_TOTAL_AUTH}" in
            ''|*[!0-9]*)
                printf 'DIVERGÊNCIA: Campo total_tabelas_auth ausente, nulo ou não inteiro no inventário (valor: "%s")\n' "${INV_TOTAL_AUTH}" >> "${DIVERGENCES_FILE}"
                INV_TOTAL_AUTH=""
                INV_SCHEMA_VALID=0
                ;;
        esac

        # Correção 3 (v1.9.0): exit code do jq verificado de fato — sem "|| echo"
        # mascarando falha. "desconhecido" é o fallback APENAS quando o campo
        # não existe no JSON (exit 1 de -e); erro real de jq (>=2) é divergência.
        INV_METODO_CONTAGEM=""
        INV_METODO_CONTAGEM_RC=0
        INV_METODO_CONTAGEM_TMP="$(jq -er '.politica_seguranca.metodo_contagem // empty' "${INVENTORY_FILE}" 2>/dev/null)" || INV_METODO_CONTAGEM_RC=$?
        if [ "${INV_METODO_CONTAGEM_RC}" -ge 2 ]; then
            printf 'DIVERGÊNCIA: Falha de jq ao extrair politica_seguranca.metodo_contagem do inventário (exit %s)\n' "${INV_METODO_CONTAGEM_RC}" >> "${DIVERGENCES_FILE}"
            INVENTORY_EXTRACTION_INCOMPLETE=1
        elif [ -n "${INV_METODO_CONTAGEM_TMP}" ]; then
            INV_METODO_CONTAGEM="${INV_METODO_CONTAGEM_TMP}"
        fi
        unset INV_METODO_CONTAGEM_TMP

        # Comparação do total de tabelas públicas
        if [ -n "${INV_TOTAL_PUBLIC}" ]; then
            if [ "${INV_TOTAL_PUBLIC}" != "${TOTAL_TABELAS_LAB}" ]; then
                printf 'DIVERGÊNCIA ESTRUTURAL: Quantidade de tabelas no schema public difere (Inventário: %s, Restaurado: %s)\n' "${INV_TOTAL_PUBLIC}" "${TOTAL_TABELAS_LAB}" >> "${DIVERGENCES_FILE}"
            else
                printf 'CONFERIDO: Quantidade de tabelas no schema public coincide (%s)\n' "${TOTAL_TABELAS_LAB}" >> "${CONFERIDOS_FILE}"
            fi
        fi

        # Comparação do total de tabelas auth
        if [ -n "${INV_TOTAL_AUTH}" ]; then
            if [ "${INV_TOTAL_AUTH}" != "${TOTAL_TABELAS_AUTH_LAB}" ]; then
                printf 'DIVERGÊNCIA ESTRUTURAL: Quantidade de tabelas no schema auth difere (Inventário: %s, Restaurado: %s)\n' "${INV_TOTAL_AUTH}" "${TOTAL_TABELAS_AUTH_LAB}" >> "${DIVERGENCES_FILE}"
            else
                printf 'CONFERIDO: Quantidade de tabelas no schema auth coincide (%s)\n' "${TOTAL_TABELAS_AUTH_LAB}" >> "${CONFERIDOS_FILE}"
            fi
        fi

        # Extração de tabelas do inventário via jq estrito
        # Correção 3 (v1.9.0): exit codes do jq verificados de fato — sem "|| echo"
        # mascarando falha. Exit 1 legítimo de -e (array vazio / falsidade) NÃO é
        # falha; erro real de jq (>=2) bloqueia INVENTORY_COMPARISON_VALID=SIM.
        INV_TABLES_RAW=""
        INV_TABLES_LEN=0
        INV_TABLES_RAW_RC=0
        INV_TABLES_LEN_RC=0
        INV_TABLES_RAW="$(jq -er '.tabelas[] | "\(.schema // "public")|\(.tabela)|\(.contagem)|\(.tipo_contagem // "desconhecido")"' "${INVENTORY_FILE}" 2>/dev/null)" || INV_TABLES_RAW_RC=$?
        INV_TABLES_LEN="$(jq -e '.tabelas | length' "${INVENTORY_FILE}" 2>/dev/null)" || INV_TABLES_LEN_RC=$?
        case "${INV_TABLES_LEN}" in
            ''|*[!0-9]*)
                # length produzido com erro jq: tratar como 0 e como extração incompleta
                if [ "${INV_TABLES_LEN_RC}" -ge 2 ]; then
                    printf 'DIVERGÊNCIA: Falha de jq ao contar tabelas do inventário (exit %s)\n' "${INV_TABLES_LEN_RC}" >> "${DIVERGENCES_FILE}"
                    INVENTORY_EXTRACTION_INCOMPLETE=1
                fi
                INV_TABLES_LEN=0
                ;;
        esac
        # Ponto 5: extração jq falha com inventário não vazio = verificação incompleta
        if [ -z "${INV_TABLES_RAW}" ] && [ "${INV_TABLES_LEN}" -gt 0 ]; then
            printf 'DIVERGÊNCIA: Falha na extração da lista de tabelas do inventário com jq -er (%s tabelas declaradas, 0 extraídas)\n' "${INV_TABLES_LEN}" >> "${DIVERGENCES_FILE}"
            INVENTORY_EXTRACTION_INCOMPLETE=1
        fi
        # Correção 3 (v1.9.0): erro real de jq na extração das linhas de tabelas
        # é registrado mesmo quando o array declarado também está vazio.
        if [ "${INV_TABLES_RAW_RC}" -ge 2 ]; then
            printf 'DIVERGÊNCIA: Falha de jq ao extrair linhas de tabelas do inventário (exit %s)\n' "${INV_TABLES_RAW_RC}" >> "${DIVERGENCES_FILE}"
            INVENTORY_EXTRACTION_INCOMPLETE=1
        fi

        # SENTIDO 1 (Ponto 7): Tabelas presentes no INVENTÁRIO -> Verificar se existem no BACKUP RESTAURADO
        say "   Verificando sentido 1: Tabelas do inventário -> presentes no backup restaurado..."
        if [ -n "${INV_TABLES_RAW}" ]; then
            while IFS='|' read -r inv_schema inv_tab inv_cnt inv_tipo; do
                [ -n "${inv_tab}" ] || continue

                # Ponto 8 da correção v1.8.0: identificadores do inventário
                # validados com regex estrita ANTES de qualquer interpolação em SQL.
                if ! is_safe_identifier "${inv_schema}" || ! is_safe_identifier "${inv_tab}"; then
                    printf 'DIVERGÊNCIA: Identificador inválido no inventário (schema="%s", tabela="%s") — interpolação SQL recusada\n' "${inv_schema}" "${inv_tab}" >> "${DIVERGENCES_FILE}"
                    continue
                fi

                # Ponto 8: contagem do inventário deve ser inteiro não negativo
                case "${inv_cnt}" in
                    ''|*[!0-9]*)
                        printf 'DIVERGÊNCIA: Contagem inválida no inventário para %s."%s" (valor: "%s")\n' "${inv_schema}" "${inv_tab}" "${inv_cnt}" >> "${DIVERGENCES_FILE}"
                        continue
                        ;;
                esac

                # Salvaguarda: auth.users não pode ser catalogado como public.users
                if [ "${inv_schema}" = "public" ] && [ "${inv_tab}" = "users" ]; then
                    printf 'DIVERGÊNCIA ESTRUTURAL: auth.users catalogado erroneamente como public.users no inventário\n' >> "${DIVERGENCES_FILE}"
                    continue
                fi

                # Verifica existência física no laboratório
                table_exists_raw="$(exec_lab_sql "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = '${inv_schema}' AND table_name = '${inv_tab}' AND table_type = 'BASE TABLE')")" || {
                    printf 'DIVERGÊNCIA: Falha de consulta SQL ao verificar existência de %s."%s"\n' "${inv_schema}" "${inv_tab}" >> "${DIVERGENCES_FILE}"
                    continue
                }
                table_exists="$(printf '%s\n' "${table_exists_raw}" | tr -d '[:space:]')"

                if [ "${table_exists}" != "t" ]; then
                    printf 'DIVERGÊNCIA: Tabela %s."%s" presente no inventário NÃO EXISTE no banco restaurado\n' "${inv_schema}" "${inv_tab}" >> "${DIVERGENCES_FILE}"
                    continue
                fi

                # Comparação de contagens conforme o método (Ponto 8)
                if [ "${inv_tipo}" = "exata" ]; then
                    lab_cnt_raw="$(exec_lab_sql "SELECT count(*) FROM \"${inv_schema}\".\"${inv_tab}\"")" || {
                        printf 'DIVERGÊNCIA: Falha de consulta SQL na contagem exata de %s."%s"\n' "${inv_schema}" "${inv_tab}" >> "${DIVERGENCES_FILE}"
                        continue
                    }
                    lab_cnt="$(printf '%s\n' "${lab_cnt_raw}" | tr -d '[:space:]')"
                    case "${lab_cnt}" in
                        ''|*[!0-9]*)
                            printf 'DIVERGÊNCIA: Retorno não numérico na contagem de %s."%s" (%s)\n' "${inv_schema}" "${inv_tab}" "${lab_cnt}" >> "${DIVERGENCES_FILE}"
                            continue
                            ;;
                    esac

                    if [ "${lab_cnt}" -eq "${inv_cnt}" ]; then
                        printf 'CONFERIDO: Contagem exata idêntica em %s."%s" (%s registros)\n' "${inv_schema}" "${inv_tab}" "${lab_cnt}" >> "${CONFERIDOS_FILE}"
                    elif [ "${lab_cnt}" -gt "${inv_cnt}" ]; then
                        printf 'DIVERGÊNCIA DE CONTAGEM EXATA: %s."%s" (Inventário: %s, Restaurado: %s — backup possui mais registros que inventário)\n' "${inv_schema}" "${inv_tab}" "${inv_cnt}" "${lab_cnt}" >> "${DIVERGENCES_FILE}"
                    else
                        # Ponto 8 da Auditoria: Classificar diferenças de contagem como INCONCLUSIVAS
                        # SEM presumir crescimento natural.
                        printf 'DIVERGÊNCIA DE CONTAGEM INCONCLUSIVA: %s."%s" (Backup: %s, Inventário posterior: %s — diferença não explicada por evidência factual, requer validação manual)\n' "${inv_schema}" "${inv_tab}" "${lab_cnt}" "${inv_cnt}" >> "${TEMPORAL_DIFFS_FILE}"
                        printf 'DIVERGÊNCIA DE CONTAGEM INCONCLUSIVA: %s."%s" (Backup: %s != Inventário: %s)\n' "${inv_schema}" "${inv_tab}" "${lab_cnt}" "${inv_cnt}" >> "${DIVERGENCES_FILE}"
                    fi
                else
                    # Ponto 6 da correção v2.0.0: estimativas reltuples NÃO são
                    # verificação. reltuples no banco recém-restaurado é estimativa
                    # estatística (frequentemente -1/0 antes do autovacuum) e o
                    # inventário também registra estimativa — não existe validação
                    # correspondente possível aqui. Três categorias DISTINTAS:
                    #   - informação coletada: linha rotulada NÃO VALIDADO em
                    #     CONFERIDOS_FILE (coleta de dados, JAMAIS aprovação);
                    #   - comparação inconclusiva: linha em TEMPORAL_DIFFS_FILE
                    #     (impede APROVADO enquanto não houver contagem exata);
                    #   - verificação aprovada: somente contagens "exata" iguais.
                    lab_est_raw="$(exec_lab_sql "SELECT round(reltuples)::bigint FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = '${inv_schema}' AND c.relname = '${inv_tab}'")" || {
                        printf 'DIVERGÊNCIA: Falha de consulta SQL ao estimar tuplas de %s."%s"\n' "${inv_schema}" "${inv_tab}" >> "${DIVERGENCES_FILE}"
                        continue
                    }
                    lab_est="$(printf '%s\n' "${lab_est_raw}" | tr -d '[:space:]')"
                    printf 'NÃO VALIDADO (informação coletada): %s."%s" — estimativas reltuples (Inventário: %s, Laboratório: %s); estimativa NÃO é verificação e NÃO comprova integridade\n' "${inv_schema}" "${inv_tab}" "${inv_cnt}" "${lab_est}" >> "${CONFERIDOS_FILE}"
                    printf 'DIFERENÇA DE CONTAGEM INCONCLUSIVA: %s."%s" comparada apenas por estimativa reltuples (Inventário: %s, Laboratório: %s) — comparação inconclusiva; aprovação exige contagem exata validada\n' "${inv_schema}" "${inv_tab}" "${inv_cnt}" "${lab_est}" >> "${TEMPORAL_DIFFS_FILE}"
                fi
            done <<< "${INV_TABLES_RAW}"
        fi

        # SENTIDO 2 (Ponto 7): Tabelas presentes no BACKUP RESTAURADO -> Verificar se constam no INVENTÁRIO (public E auth)
        say "   Verificando sentido 2: Tabelas do backup restaurado (public e auth) -> presentes no inventário oficial..."
        if [ -n "${LAB_PUBLIC_TABLES_LIST}" ]; then
            while IFS= read -r lab_t; do
                [ -n "${lab_t}" ] || continue
                # Validação via jq se lab_t existe no array de tabelas do inventário com schema public
                # jq SEM -e: "false" é saída legítima (tabela não catalogada) e não
                # deve ser interpretada como falha de jq (exit 1).
                # Correção 3 (v1.9.0): código de saída verificado — erro real de jq
                # (>=2) é divergência registrada e impede INVENTORY_COMPARISON_VALID=SIM.
                T_IN_INV_RC=0
                t_in_inv="$(jq --arg tab "${lab_t}" 'any(.tabelas[]; .schema == "public" and .tabela == $tab)' "${INVENTORY_FILE}" 2>/dev/null)" || T_IN_INV_RC=$?
                if [ "${T_IN_INV_RC}" -ge 2 ]; then
                    printf 'DIVERGÊNCIA: Falha de jq ao verificar tabela public."%s" no inventário (exit %s)\n' "${lab_t}" "${T_IN_INV_RC}" >> "${DIVERGENCES_FILE}"
                    INVENTORY_EXTRACTION_INCOMPLETE=1
                fi
                if [ "${t_in_inv}" != "true" ]; then
                    printf 'DIVERGÊNCIA BIDIRECIONAL: Tabela public."%s" existe no backup restaurado mas NÃO CONSTA no inventário oficial\n' "${lab_t}" >> "${DIVERGENCES_FILE}"
                else
                    printf 'CONFERIDO BIDIRECIONAL: Tabela public."%s" localizada em ambos os lados\n' "${lab_t}" >> "${CONFERIDOS_FILE}"
                fi
            done <<< "${LAB_PUBLIC_TABLES_LIST}"
        fi

        if [ -n "${LAB_AUTH_TABLES_LIST}" ]; then
            while IFS= read -r lab_auth_t; do
                [ -n "${lab_auth_t}" ] || continue
                # Validação via jq se lab_auth_t existe no array de tabelas do inventário com schema auth
                # Correção 3 (v1.9.0): código de saída verificado — erro real de jq
                # (>=2) é divergência registrada e impede INVENTORY_COMPARISON_VALID=SIM.
                T_IN_INV_AUTH_RC=0
                t_in_inv_auth="$(jq --arg tab "${lab_auth_t}" 'any(.tabelas[]; .schema == "auth" and .tabela == $tab)' "${INVENTORY_FILE}" 2>/dev/null)" || T_IN_INV_AUTH_RC=$?
                if [ "${T_IN_INV_AUTH_RC}" -ge 2 ]; then
                    printf 'DIVERGÊNCIA: Falha de jq ao verificar tabela auth."%s" no inventário (exit %s)\n' "${lab_auth_t}" "${T_IN_INV_AUTH_RC}" >> "${DIVERGENCES_FILE}"
                    INVENTORY_EXTRACTION_INCOMPLETE=1
                fi
                if [ "${t_in_inv_auth}" != "true" ]; then
                    printf 'DIVERGÊNCIA BIDIRECIONAL: Tabela auth."%s" existe no backup restaurado mas NÃO CONSTA no inventário oficial\n' "${lab_auth_t}" >> "${DIVERGENCES_FILE}"
                else
                    printf 'CONFERIDO BIDIRECIONAL: Tabela auth."%s" localizada em ambos os lados\n' "${lab_auth_t}" >> "${CONFERIDOS_FILE}"
                fi
            done <<< "${LAB_AUTH_TABLES_LIST}"
        fi

        # Ponto 2 e Ponto 3 da Auditoria:
        # Comparação estrutural COMPLETA de Constraints e Funções:
        # - REMOÇÃO DO LIMITE DE 30 ELEMENTOS (zero sampling). Todas as constraints e funções são comparadas.
        # - Comparar definições COMPLETAS das constraints (pg_get_constraintdef).
        # - Comparar identidade de argumentos (pg_get_function_identity_arguments) e definição (pg_get_functiondef quando disponível).
        say "   Comparando integralmente definições de constraints (pg_get_constraintdef) e funções (sem amostragem)..."
        # Ponto 5: falha de extração jq das contagens é registrada e impede SIM
        # jq SEM -e: um array vazio legítimo (length 0) é saída válida e NÃO deve
        # ser tratado como falha de extração (jq -e retornaria exit 1 e bloquearia
        # indevidamente o INVENTORY_COMPARISON_VALID=SIM).
        if ! INV_CONSTRAINTS_COUNT="$(jq '.constraints | if type == "array" then length else 0 end' "${INVENTORY_FILE}" 2>/dev/null)"; then
            printf 'DIVERGÊNCIA: Falha na extração jq da contagem de constraints do inventário\n' >> "${DIVERGENCES_FILE}"
            INV_CONSTRAINTS_COUNT=0
            INVENTORY_EXTRACTION_INCOMPLETE=1
        fi
        if ! INV_FUNCTIONS_COUNT="$(jq '.funcoes | if type == "array" then length else 0 end' "${INVENTORY_FILE}" 2>/dev/null)"; then
            printf 'DIVERGÊNCIA: Falha na extração jq da contagem de funções do inventário\n' >> "${DIVERGENCES_FILE}"
            INV_FUNCTIONS_COUNT=0
            INVENTORY_EXTRACTION_INCOMPLETE=1
        fi
        case "${INV_CONSTRAINTS_COUNT}" in
            ''|*[!0-9]*)
                printf 'DIVERGÊNCIA: Contagem de constraints do inventário não inteira (%s)\n' "${INV_CONSTRAINTS_COUNT}" >> "${DIVERGENCES_FILE}"
                INV_CONSTRAINTS_COUNT=0
                INVENTORY_EXTRACTION_INCOMPLETE=1
                ;;
        esac
        case "${INV_FUNCTIONS_COUNT}" in
            ''|*[!0-9]*)
                printf 'DIVERGÊNCIA: Contagem de funções do inventário não inteira (%s)\n' "${INV_FUNCTIONS_COUNT}" >> "${DIVERGENCES_FILE}"
                INV_FUNCTIONS_COUNT=0
                INVENTORY_EXTRACTION_INCOMPLETE=1
                ;;
        esac
        # Ponto 4: corpos só são comparáveis se o inventário não os tiver ofuscado
        # Correção 3 (v1.9.0): código de saída verificado — erro real de jq (>=2)
        # NÃO é tratado como "não ofuscado"; é divergência registrada (falha
        # conservadora: corpos deixam de ser comparados e o SIM é bloqueado).
        INV_OFUSCACAO_APLICADA_RC=0
        INV_OFUSCACAO_APLICADA="$(jq -er '.politica_sigilo.ofuscacao_segredos_aplicada // false' "${INVENTORY_FILE}" 2>/dev/null)" || INV_OFUSCACAO_APLICADA_RC=$?
        if [ "${INV_OFUSCACAO_APLICADA_RC}" -ge 2 ]; then
            printf 'DIVERGÊNCIA: Falha de jq ao ler politica_sigilo.ofuscacao_segredos_aplicada (exit %s)\n' "${INV_OFUSCACAO_APLICADA_RC}" >> "${DIVERGENCES_FILE}"
            INVENTORY_EXTRACTION_INCOMPLETE=1
            INV_OFUSCACAO_APLICADA="true"
        fi

        CONSTRAINTS_DIFF_FOUND=0
        CONSTRAINTS_EXTRACTED=0
        # Correção 3 (v1.9.0): extração jq das constraints com código de saída
        # verificado (sem process substitution às cegas); exit 1 de -e é array
        # vazio legítimo.
        # Ponto 5 da correção v2.0.0: extração em JSON-lines (UM objeto JSON por
        # linha): aspas, quebras de linha, \u001F e caracteres especiais dentro
        # dos campos ficam ESCAPADOS pelo codificador JSON — não há separador
        # textual que possa colidir com o conteúdo e nenhum campo é truncado. Os
        # campos são decodificados INDIVIDUALMENTE (CORREÇÃO 3 da v2.1.0:
        # jq @base64 + base64 -d, sem eval), preservando a definição DDL
        # integralmente (a normalização idêntica dos dois lados ocorre apenas na
        # comparação).
        INV_CONSTRAINTS_RAW_RC=0
        INV_CONSTRAINTS_RAW=""
        # CORREÇÃO 2 (v2.1.1): campos extraídos SEM tostring — o tipo original
        # é preservado para que jq_field_decode exija efetivamente string;
        # campo ausente, nulo ou não string vira falha explícita na
        # decodificação (nunca o texto "null").
        INV_CONSTRAINTS_RAW="$(jq -c '.constraints[] | {schema:.schema, tabela:.tabela, nome:.nome, definicao:.definicao}' "${INVENTORY_FILE}" 2>>"${LOG_FILE}")" || INV_CONSTRAINTS_RAW_RC=$?
        if [ "${INV_CONSTRAINTS_RAW_RC}" -ge 2 ]; then
            printf 'DIVERGÊNCIA: Falha de jq ao extrair constraints do inventário (exit %s)\n' "${INV_CONSTRAINTS_RAW_RC}" >> "${DIVERGENCES_FILE}"
            INVENTORY_EXTRACTION_INCOMPLETE=1
        fi
        if [ "${INV_CONSTRAINTS_COUNT}" -gt 0 ]; then
            while IFS= read -r c_line; do
                [ -n "${c_line}" ] || continue
                # CORREÇÃO 3 (v2.1.0): decodificação SEM eval (jq @base64 + base64 -d
                # via jq_field_decode), código de saída de ambas as etapas verificado;
                # falha de decodificação ou dado não representável = DIVERGÊNCIA
                # impeditiva (nunca silêncio ou valor vazio).
                CONSTRAINTS_PARSE_RC=0
                c_schema="$(jq_field_decode '.schema' "${c_line}")" || CONSTRAINTS_PARSE_RC=1
                c_tab="$(jq_field_decode '.tabela' "${c_line}")" || CONSTRAINTS_PARSE_RC=1
                c_name="$(jq_field_decode '.nome' "${c_line}")" || CONSTRAINTS_PARSE_RC=1
                c_def="$(jq_field_decode '.definicao' "${c_line}")" || CONSTRAINTS_PARSE_RC=1
                if [ "${CONSTRAINTS_PARSE_RC}" -ne 0 ]; then
                    printf 'DIVERGÊNCIA: Falha de decodificação (jq/base64) de campo do registro de constraint do inventário (JSON-lines) — interpolação SQL recusada\n' >> "${DIVERGENCES_FILE}"
                    CONSTRAINTS_DIFF_FOUND=$((CONSTRAINTS_DIFF_FOUND + 1))
                    continue
                fi
                [ -n "${c_name}" ] || continue
                CONSTRAINTS_EXTRACTED=$((CONSTRAINTS_EXTRACTED + 1))

                # Ponto 8: identificadores do inventário validados antes da interpolação SQL
                if ! is_safe_identifier "${c_schema}" || ! is_safe_identifier "${c_tab}" || ! is_safe_identifier "${c_name}"; then
                    printf 'DIVERGÊNCIA: Identificador inválido no inventário (constraint %s."%s"."%s") — interpolação SQL recusada\n' "${c_schema}" "${c_tab}" "${c_name}" >> "${DIVERGENCES_FILE}"
                    CONSTRAINTS_DIFF_FOUND=$((CONSTRAINTS_DIFF_FOUND + 1))
                    continue
                fi
                lab_c_def_raw="$(exec_lab_sql "SELECT pg_get_constraintdef(c.oid, true) FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace JOIN pg_class r ON r.oid = c.conrelid WHERE n.nspname = '${c_schema}' AND r.relname = '${c_tab}' AND c.conname = '${c_name}'")" || lab_c_def_raw=""
                # Correção 4 (v1.9.0): normalização NÃO destrutiva (quebras viram
                # espaço; nunca remoção pura que colaria palavras).
                lab_c_def="$(printf '%s\n' "${lab_c_def_raw}" | tr -d '\r' | tr '\n' ' ' | sed -e 's/[[:space:]]\+/ /g' -e 's/^[[:space:]]*//;s/[[:space:]]*$//')"
                if [ -z "${lab_c_def}" ]; then
                    printf 'DIVERGÊNCIA ESTRUTURAL (constraint ausente): %s."%s" constraint "%s" ausente no banco restaurado\n' "${c_schema}" "${c_tab}" "${c_name}" >> "${DIVERGENCES_FILE}"
                    CONSTRAINTS_DIFF_FOUND=$((CONSTRAINTS_DIFF_FOUND + 1))
                else
                    # Comparação semântica da definição DDL normalizada (idêntica dos dois lados)
                    norm_inv_def="$(printf '%s\n' "${c_def}" | tr -d '\r' | tr '\n' ' ' | sed -e 's/[[:space:]]\+/ /g' -e 's/^[[:space:]]*//;s/[[:space:]]*$//')"
                    norm_lab_def="$(printf '%s\n' "${lab_c_def}" | tr -d '\r' | tr '\n' ' ' | sed -e 's/[[:space:]]\+/ /g' -e 's/^[[:space:]]*//;s/[[:space:]]*$//')"
                    if [ "${norm_inv_def}" != "${norm_lab_def}" ]; then
                        printf 'DIVERGÊNCIA ESTRUTURAL (definicao constraint): %s."%s" constraint "%s" difere (Inv: "%s" != Lab: "%s")\n' "${c_schema}" "${c_tab}" "${c_name}" "${norm_inv_def}" "${norm_lab_def}" >> "${DIVERGENCES_FILE}"
                        CONSTRAINTS_DIFF_FOUND=$((CONSTRAINTS_DIFF_FOUND + 1))
                    fi
                fi
            done <<< "${INV_CONSTRAINTS_RAW}"
            if [ "${CONSTRAINTS_EXTRACTED}" -ne "${INV_CONSTRAINTS_COUNT}" ] || [ "${INV_CONSTRAINTS_RAW_RC}" -ge 2 ]; then
                printf 'DIVERGÊNCIA: Extração jq das constraints incompleta (%s de %s extraídas)\n' "${CONSTRAINTS_EXTRACTED}" "${INV_CONSTRAINTS_COUNT}" >> "${DIVERGENCES_FILE}"
                INVENTORY_EXTRACTION_INCOMPLETE=1
            fi
            if [ "${CONSTRAINTS_DIFF_FOUND}" -eq 0 ] && [ "${INVENTORY_EXTRACTION_INCOMPLETE}" -eq 0 ]; then
                printf 'CONFERIDO ESTRUTURAL: Todas as %s constraints conferidas integralmente por nome e definicao DDL\n' "${INV_CONSTRAINTS_COUNT}" >> "${CONFERIDOS_FILE}"
            fi
        fi

        # Ponto 4 da correção v1.8.0: comparação de funções por identidade completa
        # E, quando o inventário traz a definição efetiva (inclui_corpo=true),
        # também pelo corpo via pg_get_functiondef (normalizado como as constraints).
        # Correção 2 (v1.9.0): funções são localizadas por schema + nome + identidade
        # de argumentos (pg_get_function_identity_arguments) E tipo de retorno
        # (pg_get_function_result) — sobrecargas homônimas são comparadas
        # INDIVIDUALMENTE (uma linha por sobrecarga, sem concatenação), e a
        # pg_get_functiondef recupera a função EXATA (sem capturar homônima).
        # Correção 3 (v1.9.0): a extração jq das funções NÃO roda às cegas em
        # process substitution: exit code verificado; erro real de jq (>=2) impede
        # INVENTORY_COMPARISON_VALID=SIM; exit 1 de -e é legítimo (array vazio).
        FUNCTIONS_DIFF_FOUND=0
        FUNCTIONS_EXTRACTED=0
        INV_FUNCTIONS_RAW_RC=0
        INV_FUNCTIONS_RAW=""
        # Ponto 5 da correção v2.0.0: extração em JSON-lines (UM objeto JSON por
        # linha): aspas, quebras de linha, \u001F e caracteres especiais dentro
        # dos campos ficam ESCAPADOS pelo codificador JSON — não há separador
        # textual que possa colidir com o conteúdo (a identidade e o corpo podem
        # conter qualquer caractere) e NENHUM campo é truncado ou reescrito (o
        # gsub de v1.9.0 sobre a definição foi eliminado; a definição permanece
        # integral e a normalização idêntica dos dois lados ocorre apenas na
        # comparação). Decodificação campo a campo SEM eval (CORREÇÃO 3 da
        # v2.1.0: jq @base64 + base64 -d, helper jq_field_decode).
        # CORREÇÃO 2 (v2.1.1): campos de identidade extraídos SEM tostring (tipo
        # original preservado; ausente/nulo/não-string = falha explícita na
        # decodificação). Exceções SEMÂNTICAS preservadas: corpo é a conversão
        # intencional do booleano inclui_corpo (padrão false) em "true"/"false";
        # definicao usa padrão "" (definição ausente é legítima quando
        # inclui_corpo=false; com corpo exigido, ausência é DIVERGÊNCIA
        # explícita mais adiante).
        INV_FUNCTIONS_RAW="$(jq -c '.funcoes[] | {schema:.schema, nome:.nome, identidade:.identidade, retorno:.tipo_retorno, corpo:((.inclui_corpo // false)|tostring), definicao:(.definicao // "")}' "${INVENTORY_FILE}" 2>>"${LOG_FILE}")" || INV_FUNCTIONS_RAW_RC=$?
        if [ "${INV_FUNCTIONS_RAW_RC}" -ge 2 ]; then
            printf 'DIVERGÊNCIA: Falha de jq ao extrair funções do inventário (exit %s)\n' "${INV_FUNCTIONS_RAW_RC}" >> "${DIVERGENCES_FILE}"
            INVENTORY_EXTRACTION_INCOMPLETE=1
        fi
        if [ "${INV_FUNCTIONS_COUNT}" -gt 0 ]; then
            while IFS= read -r f_line; do
                [ -n "${f_line}" ] || continue
                # CORREÇÃO 3 (v2.1.0): decodificação SEM eval (jq @base64 + base64 -d
                # via jq_field_decode), código de saída de ambas as etapas verificado;
                # falha de decodificação ou dado não representável = DIVERGÊNCIA
                # impeditiva (nunca silêncio ou valor vazio).
                FUNCTIONS_PARSE_RC=0
                f_schema="$(jq_field_decode '.schema' "${f_line}")" || FUNCTIONS_PARSE_RC=1
                f_name="$(jq_field_decode '.nome' "${f_line}")" || FUNCTIONS_PARSE_RC=1
                f_ident="$(jq_field_decode '.identidade' "${f_line}")" || FUNCTIONS_PARSE_RC=1
                f_ret="$(jq_field_decode '.retorno' "${f_line}")" || FUNCTIONS_PARSE_RC=1
                f_corpo="$(jq_field_decode '.corpo' "${f_line}")" || FUNCTIONS_PARSE_RC=1
                f_definicao="$(jq_field_decode '.definicao' "${f_line}")" || FUNCTIONS_PARSE_RC=1
                if [ "${FUNCTIONS_PARSE_RC}" -ne 0 ]; then
                    printf 'DIVERGÊNCIA: Falha de decodificação (jq/base64) de campo do registro de função do inventário (JSON-lines) — interpolação SQL recusada\n' >> "${DIVERGENCES_FILE}"
                    FUNCTIONS_DIFF_FOUND=$((FUNCTIONS_DIFF_FOUND + 1))
                    continue
                fi
                [ -n "${f_name}" ] || continue
                FUNCTIONS_EXTRACTED=$((FUNCTIONS_EXTRACTED + 1))

                # Ponto 8: identificadores do inventário validados antes da interpolação SQL
                if ! is_safe_identifier "${f_schema}" || ! is_safe_identifier "${f_name}"; then
                    printf 'DIVERGÊNCIA: Identificador inválido no inventário (função %s."%s") — interpolação SQL recusada\n' "${f_schema}" "${f_name}" >> "${DIVERGENCES_FILE}"
                    FUNCTIONS_DIFF_FOUND=$((FUNCTIONS_DIFF_FOUND + 1))
                    continue
                fi

                # Ponto 4 da correção v2.0.0: SEM delimitador textual colidível
                # ('|RET:'/'|OID:' eliminados). A identidade do inventário (texto
                # livre) é embutida por dollar-quoting com etiqueta única gerada
                # de PID+aleatório, e o conteúdo é RECUSADO se ele próprio contiver
                # a etiqueta — nenhuma interferência do inventário na consulta. A
                # resposta vem como UM ÚNICO documento JSON (codificação
                # estrutural, não concatenação de texto) decodificado por jq —
                # sem ambiguidade de separadores/quebras.
                FUNCOES_IDENT_TAG="dq${PID_ATUAL}x${RANDOM}x${RANDOM}ident"
                case "${f_ident}" in
                    *"${FUNCOES_IDENT_TAG}"*)
                        printf 'DIVERGÊNCIA: Identidade de função do inventário contém a etiqueta de dollar-quoting (%s."%s") — interpolação SQL recusada\n' "${f_schema}" "${f_name}" >> "${DIVERGENCES_FILE}"
                        FUNCTIONS_DIFF_FOUND=$((FUNCTIONS_DIFF_FOUND + 1))
                        continue
                        ;;
                esac
                FUNCOES_IDENT_QUERY_TMP="${DIAG_DIR}/ident-funcoes-${TS_STAMP}-$$.txt"
                cat > "${FUNCOES_IDENT_QUERY_TMP}" <<SQL
SELECT coalesce(json_agg(json_build_object('oid', p.oid::text, 'retorno', pg_get_function_result(p.oid)))::text, '[]')
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = '${f_schema}' AND p.proname = '${f_name}'
  AND pg_get_function_identity_arguments(p.oid) = \$${FUNCOES_IDENT_TAG}\$${f_ident}\$${FUNCOES_IDENT_TAG}\$;
SQL
                if ! chmod 600 "${FUNCOES_IDENT_QUERY_TMP}" 2>/dev/null; then
                    printf 'DIVERGÊNCIA: Falha ao restringir permissões do arquivo de consulta de identidade de funções\n' >> "${DIVERGENCES_FILE}"
                    FUNCTIONS_DIFF_FOUND=$((FUNCTIONS_DIFF_FOUND + 1))
                    rm -f "${FUNCOES_IDENT_QUERY_TMP}" 2>/dev/null || true
                    continue
                fi
                # Ponto 8 da correção v2.0.0: permissão efetiva verificada (chmod
                # bem-sucedido não é prova de permissão final).
                FUNCOES_IDENT_PERM="$(stat -c '%a' "${FUNCOES_IDENT_QUERY_TMP}" 2>/dev/null || stat -f '%Lp' "${FUNCOES_IDENT_QUERY_TMP}" 2>/dev/null || echo "")"
                if [ -z "${FUNCOES_IDENT_PERM}" ] || [ "${FUNCOES_IDENT_PERM}" != "600" ]; then
                    printf 'DIVERGÊNCIA: Permissão efetiva inválida (%s) no arquivo de consulta de identidade de funções\n' "${FUNCOES_IDENT_PERM}" >> "${DIVERGENCES_FILE}"
                    FUNCTIONS_DIFF_FOUND=$((FUNCTIONS_DIFF_FOUND + 1))
                    rm -f "${FUNCOES_IDENT_QUERY_TMP}" 2>/dev/null || true
                    continue
                fi
                # Correção 3 (v1.9.0): UMA execução, exit code explícito (sem
                # mascarar falha com "|| var=''"); -i obrigatório para psql -f -
                FUNCOES_IDENT_RC=0
                if command -v timeout >/dev/null 2>&1; then
                    FUNCOES_IDENT_OUT="$(timeout 60 docker exec -i "${LAB_NAME}" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres -t -A -f - < "${FUNCOES_IDENT_QUERY_TMP}" 2>>"${LOG_FILE}")" || FUNCOES_IDENT_RC=$?
                else
                    FUNCOES_IDENT_OUT="$(docker exec -i "${LAB_NAME}" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres -t -A -f - < "${FUNCOES_IDENT_QUERY_TMP}" 2>>"${LOG_FILE}")" || FUNCOES_IDENT_RC=$?
                fi
                rm -f "${FUNCOES_IDENT_QUERY_TMP}" 2>/dev/null || true
                if [ "${FUNCOES_IDENT_RC}" -ne 0 ]; then
                    # Correção (v2.1.2): retorno de record_query_failure verificado;
                    # falha de registro gera DIVERGÊNCIA impeditiva adicional.
                    if ! record_query_failure "consulta de identidade de funções ${f_schema}.${f_name} (exit ${FUNCOES_IDENT_RC})"; then
                        printf 'DIVERGÊNCIA: Falha AO REGISTRAR a falha de consulta SQL (identidade de funções %s."%s", exit %s) — mecanismo fail-closed de sinalização acionado\n' "${f_schema}" "${f_name}" "${FUNCOES_IDENT_RC}" >> "${DIVERGENCES_FILE}"
                    fi
                    printf 'DIVERGÊNCIA: Falha de consulta SQL ao recuperar identidades de %s."%s" (exit %s)\n' "${f_schema}" "${f_name}" "${FUNCOES_IDENT_RC}" >> "${DIVERGENCES_FILE}"
                    FUNCTIONS_DIFF_FOUND=$((FUNCTIONS_DIFF_FOUND + 1))
                    continue
                fi

                # Interpretação da resposta em JSON (nunca por separadores de texto)
                FUNCOES_IDENT_JQ_RC=0
                FUNCOES_IDENT_JSON="$(printf '%s' "${FUNCOES_IDENT_OUT}" | jq -ce '.' 2>>"${LOG_FILE}")" || FUNCOES_IDENT_JQ_RC=$?
                if [ "${FUNCOES_IDENT_JQ_RC}" -ne 0 ] || [ -z "${FUNCOES_IDENT_JSON}" ]; then
                    # Correção (v2.1.2): retorno de record_query_failure verificado;
                    # falha de registro gera DIVERGÊNCIA impeditiva adicional.
                    if ! record_query_failure "interpretação jq da identidade de funções ${f_schema}.${f_name} (exit ${FUNCOES_IDENT_JQ_RC})"; then
                        printf 'DIVERGÊNCIA: Falha AO REGISTRAR a falha de interpretação jq (identidade de funções %s."%s") — mecanismo fail-closed de sinalização acionado\n' "${f_schema}" "${f_name}" >> "${DIVERGENCES_FILE}"
                    fi
                    printf 'DIVERGÊNCIA: Resposta da consulta de identidade de %s."%s" não é JSON interpretável (jq exit %s)\n' "${f_schema}" "${f_name}" "${FUNCOES_IDENT_JQ_RC}" >> "${DIVERGENCES_FILE}"
                    FUNCTIONS_DIFF_FOUND=$((FUNCTIONS_DIFF_FOUND + 1))
                    continue
                fi
                FUNCOES_IDENT_MATCHES="$(jq -e 'length' <<<"${FUNCOES_IDENT_JSON}" 2>>"${LOG_FILE}")" || FUNCOES_IDENT_MATCHES=0
                case "${FUNCOES_IDENT_MATCHES}" in
                    ''|*[!0-9]*) FUNCOES_IDENT_MATCHES=0 ;;
                esac
                FUNCOES_IDENT_CASADA=0
                FUNCOES_IDENT_CASADA_RET=""
                FUNCOES_IDENT_MATCHING_OID=""
                if [ "${FUNCOES_IDENT_MATCHES}" -ge 1 ]; then
                    FUNCOES_IDENT_MATCHING_OID="$(jq -er '.[0].oid // empty' <<<"${FUNCOES_IDENT_JSON}" 2>>"${LOG_FILE}")" || FUNCOES_IDENT_MATCHING_OID=""
                    FUNCOES_IDENT_CASADA_RET="$(jq -er '.[0].retorno // empty' <<<"${FUNCOES_IDENT_JSON}" 2>>"${LOG_FILE}")" || FUNCOES_IDENT_CASADA_RET=""
                    if [ -n "${FUNCOES_IDENT_MATCHING_OID}" ]; then
                        FUNCOES_IDENT_CASADA=1
                    fi
                fi
                if [ "${FUNCOES_IDENT_MATCHES}" -ge 2 ]; then
                    # Defensivo: a igualdade de identidade de argumentos deveria
                    # casar no máximo uma sobrecarga; ambiguidade é RECUSADA
                    # (nunca presumida).
                    printf 'DIVERGÊNCIA: %s sobrecargas de %s."%s" casaram com a identidade esperada — resultado ambíguo recusado\n' "${FUNCOES_IDENT_MATCHES}" "${f_schema}" "${f_name}" >> "${DIVERGENCES_FILE}"
                    FUNCTIONS_DIFF_FOUND=$((FUNCTIONS_DIFF_FOUND + 1))
                    continue
                fi
                if [ "${FUNCOES_IDENT_MATCHES}" -eq 0 ]; then
                    printf 'DIVERGÊNCIA ESTRUTURAL (funcao ausente): %s."%s" ausente no banco restaurado (nenhuma sobrecarga com a identidade esperada)\n' "${f_schema}" "${f_name}" >> "${DIVERGENCES_FILE}"
                    FUNCTIONS_DIFF_FOUND=$((FUNCTIONS_DIFF_FOUND + 1))
                    continue
                fi
                if [ "${FUNCOES_IDENT_CASADA}" -ne 1 ]; then
                    printf 'DIVERGÊNCIA ESTRUTURAL (sobrecarga funcao): %s."%s" — sobrecarga com a identidade esperada não retornou OID utilizável (Inv: "%s")\n' "${f_schema}" "${f_name}" "${f_ident}" >> "${DIVERGENCES_FILE}"
                    FUNCTIONS_DIFF_FOUND=$((FUNCTIONS_DIFF_FOUND + 1))
                    continue
                fi
                # Correção 2 (v1.9.0): tipo de retorno verificado APENAS na sobrecarga
                # que casou com a identidade de argumentos esperada.
                if [ "${FUNCOES_IDENT_CASADA_RET}" != "${f_ret}" ]; then
                    printf 'DIVERGÊNCIA ESTRUTURAL (assinatura funcao): %s."%s" difere (Inv: "%s->%s" != Lab: "%s->%s")\n' "${f_schema}" "${f_name}" "${f_ident}" "${f_ret}" "${f_ident}" "${FUNCOES_IDENT_CASADA_RET}" >> "${DIVERGENCES_FILE}"
                    FUNCTIONS_DIFF_FOUND=$((FUNCTIONS_DIFF_FOUND + 1))
                    continue
                fi

                # Corpo: comparado somente quando o inventário traz a definição
                # efetiva NÃO ofuscada (corpos redigidos não são comparáveis).
                if [ "${f_corpo}" = "true" ]; then
                    if [ -z "${f_definicao}" ]; then
                        printf 'DIVERGÊNCIA: Inventário inconsistente: inclui_corpo=true sem definicao para %s."%s"\n' "${f_schema}" "${f_name}" >> "${DIVERGENCES_FILE}"
                        FUNCTIONS_DIFF_FOUND=$((FUNCTIONS_DIFF_FOUND + 1))
                    elif [ "${INV_OFUSCACAO_APLICADA}" = "true" ]; then
                        printf 'NÃO VALIDADO (corpo funcao): %s."%s" corpo não comparável — inventário declara ofuscacao_segredos_aplicada=true (definição redigida, não é a definição efetiva)\n' "${f_schema}" "${f_name}" >> "${CONFERIDOS_FILE}"
                    elif [ -z "${FUNCOES_IDENT_MATCHING_OID}" ]; then
                        # Correção 2 (v1.9.0): sem OID não há prova de função exata;
                        # recusar a comparação (falha conservadora, nunca falso OK).
                        printf 'DIVERGÊNCIA: Impossível determinar OID da sobrecarga exata de %s."%s" — comparação de corpo NÃO VALIDADA (falha conservadora)\n' "${f_schema}" "${f_name}" >> "${DIVERGENCES_FILE}"
                        FUNCTIONS_DIFF_FOUND=$((FUNCTIONS_DIFF_FOUND + 1))
                    else
                        # Correção 2 (v1.9.0): pg_get_functiondef pelo OID EXATO da
                        # sobrecarga que casou com schema+nome+identidade — nunca
                        # recupera homônima.
                        FUNCOES_FDEF_QUERY_TMP="${DIAG_DIR}/fdef-funcao-${TS_STAMP}-$$.sql"
                        cat > "${FUNCOES_FDEF_QUERY_TMP}" <<SQL
SELECT pg_get_functiondef(${FUNCOES_IDENT_MATCHING_OID});
SQL
                        if ! chmod 600 "${FUNCOES_FDEF_QUERY_TMP}" 2>/dev/null; then
                            printf 'DIVERGÊNCIA: Falha ao restringir permissões do arquivo de consulta pg_get_functiondef\n' >> "${DIVERGENCES_FILE}"
                            FUNCTIONS_DIFF_FOUND=$((FUNCTIONS_DIFF_FOUND + 1))
                            rm -f "${FUNCOES_FDEF_QUERY_TMP}" 2>/dev/null || true
                            continue
                        fi
                        # Ponto 8 da correção v2.0.0: permissão efetiva verificada
                        FUNCOES_FDEF_PERM="$(stat -c '%a' "${FUNCOES_FDEF_QUERY_TMP}" 2>/dev/null || stat -f '%Lp' "${FUNCOES_FDEF_QUERY_TMP}" 2>/dev/null || echo "")"
                        if [ -z "${FUNCOES_FDEF_PERM}" ] || [ "${FUNCOES_FDEF_PERM}" != "600" ]; then
                            printf 'DIVERGÊNCIA: Permissão efetiva inválida (%s) no arquivo de consulta pg_get_functiondef\n' "${FUNCOES_FDEF_PERM}" >> "${DIVERGENCES_FILE}"
                            FUNCTIONS_DIFF_FOUND=$((FUNCTIONS_DIFF_FOUND + 1))
                            rm -f "${FUNCOES_FDEF_QUERY_TMP}" 2>/dev/null || true
                            continue
                        fi
                        # Correção 3 (v1.9.0): UMA execução, exit code explícito
                        FUNCOES_FDEF_RC=0
                        if command -v timeout >/dev/null 2>&1; then
                            lab_fdef_raw="$(timeout 60 docker exec -i "${LAB_NAME}" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres -t -A -f - < "${FUNCOES_FDEF_QUERY_TMP}" 2>>"${LOG_FILE}")" || FUNCOES_FDEF_RC=$?
                        else
                            lab_fdef_raw="$(docker exec -i "${LAB_NAME}" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres -t -A -f - < "${FUNCOES_FDEF_QUERY_TMP}" 2>>"${LOG_FILE}")" || FUNCOES_FDEF_RC=$?
                        fi
                        rm -f "${FUNCOES_FDEF_QUERY_TMP}" 2>/dev/null || true
                        if [ "${FUNCOES_FDEF_RC}" -ne 0 ]; then
                            # Correção (v2.1.2): retorno de record_query_failure verificado;
                            # falha de registro gera DIVERGÊNCIA impeditiva adicional.
                            if ! record_query_failure "pg_get_functiondef de ${f_schema}.${f_name} (exit ${FUNCOES_FDEF_RC})"; then
                                printf 'DIVERGÊNCIA: Falha AO REGISTRAR a falha de pg_get_functiondef (%s."%s") — mecanismo fail-closed de sinalização acionado\n' "${f_schema}" "${f_name}" >> "${DIVERGENCES_FILE}"
                            fi
                        fi
                        if [ "${FUNCOES_FDEF_RC}" -ne 0 ] || [ -z "${lab_fdef_raw}" ]; then
                            printf 'DIVERGÊNCIA ESTRUTURAL (corpo funcao): %s."%s" sem definição recuperável via pg_get_functiondef no laboratório\n' "${f_schema}" "${f_name}" >> "${DIVERGENCES_FILE}"
                            FUNCTIONS_DIFF_FOUND=$((FUNCTIONS_DIFF_FOUND + 1))
                        else
                            # Correção 4 (v1.9.0): MESMA normalização NÃO destrutiva dos
                            # dois lados (inventário e laboratório): "\r" removido,
                            # "\n" viram um espaço, espaços/tabs colapsados em um
                            # espaço, trim; NUNCA remoção pura de quebras (que
                            # colaria palavras).
                            norm_lab_fdef="$(printf '%s' "${lab_fdef_raw}" | tr -d '\r' | tr '\n' ' ' | sed -e 's/[[:space:]]\+/ /g' -e 's/^[[:space:]]*//;s/[[:space:]]*$//')"
                            norm_inv_fdef="$(printf '%s' "${f_definicao}" | tr -d '\r' | tr '\n' ' ' | sed -e 's/[[:space:]]\+/ /g' -e 's/^[[:space:]]*//;s/[[:space:]]*$//')"
                            if [ -z "${norm_lab_fdef}" ]; then
                                printf 'DIVERGÊNCIA ESTRUTURAL (corpo funcao): %s."%s" sem definição recuperável via pg_get_functiondef no laboratório\n' "${f_schema}" "${f_name}" >> "${DIVERGENCES_FILE}"
                                FUNCTIONS_DIFF_FOUND=$((FUNCTIONS_DIFF_FOUND + 1))
                            elif [ "${norm_inv_fdef}" != "${norm_lab_fdef}" ]; then
                                printf 'DIVERGÊNCIA ESTRUTURAL (corpo funcao): %s."%s" corpo difere (Inv: "%s" != Lab: "%s")\n' "${f_schema}" "${f_name}" "${norm_inv_fdef}" "${norm_lab_fdef}" >> "${DIVERGENCES_FILE}"
                                FUNCTIONS_DIFF_FOUND=$((FUNCTIONS_DIFF_FOUND + 1))
                            fi
                        fi
                    fi
                fi
            done <<< "${INV_FUNCTIONS_RAW}"
            # Correção 3 (v1.9.0): erro real de jq (>=2) na extração das funções
            # impede INVENTORY_COMPARISON_VALID=SIM; exit 1 de -e é legítimo.
            if [ "${INV_FUNCTIONS_RAW_RC}" -ge 2 ]; then
                INVENTORY_EXTRACTION_INCOMPLETE=1
            fi
            # Ponto 5: extração jq incompleta impede SIM
            if [ "${FUNCTIONS_EXTRACTED}" -ne "${INV_FUNCTIONS_COUNT}" ]; then
                printf 'DIVERGÊNCIA: Extração jq das funções incompleta (%s de %s extraídas)\n' "${FUNCTIONS_EXTRACTED}" "${INV_FUNCTIONS_COUNT}" >> "${DIVERGENCES_FILE}"
                INVENTORY_EXTRACTION_INCOMPLETE=1
            fi
            if [ "${FUNCTIONS_DIFF_FOUND}" -eq 0 ] && [ "${INVENTORY_EXTRACTION_INCOMPLETE}" -eq 0 ]; then
                printf 'CONFERIDO ESTRUTURAL: Todas as %s funcoes conferidas integralmente por identidade, assinatura e corpo (quando disponível no inventário)\n' "${INV_FUNCTIONS_COUNT}" >> "${CONFERIDOS_FILE}"
            fi
        fi

        # PONTO 3 DA CORREÇÃO v2.0.0: CONFERÊNCIA ESTRUTURAL BIDIRECIONAL
        # (sentido 2: banco restaurado -> inventário). Detecta objetos ADICIONAIS
        # presentes no banco restaurado e ausentes do inventário.
        # CORREÇÃO 2 (v2.1.0): usa os MESMOS catálogos, schemas, filtros e
        # critérios de identidade do gerador 21-gerar-inventario.sh — constraints
        # via pg_constraint/pg_class/pg_namespace (identidade: schema, tabela,
        # nome, contype) e funções via pg_proc/pg_namespace (identidade: schema,
        # nome, identidade de argumentos), AMBOS com filtro n.nspname NOT LIKE
        # 'pg\_%' AND n.nspname <> 'information_schema' (TODOS os schemas de
        # usuário; antes: information_schema.table_constraints/pg_proc restritos a
        # 'public', que não exibiam constraints EXCLUDE nem objetos fora de
        # public). SEM listas de exceções automáticas: objeto extra em qualquer
        # schema abrangido pelo inventário é DIVERGÊNCIA BIDIRECIONAL; se algum
        # objeto não puder ser comparado com segurança (falha de listagem,
        # decodificação ou verificação), BIDIRECTIONAL_INCOMPLETE=1 impede a
        # aprovação — INVENTORY_COMPARISON_VALID nunca fica SIM com verificação
        # incompleta. A listagem do lado do laboratório vem como UM ÚNICO
        # documento JSON (sem separador textual colidível) e cada campo é
        # decodificado individualmente SEM eval (Correção 3 da v2.1.0).
        say "   Verificando sentido 2: Constraints e funções do backup restaurado -> presentes no inventário oficial..."
        BIDIRECTIONAL_INCOMPLETE=0

        # --- Constraints do banco restaurado — CORREÇÃO 2 (v2.1.0): MESMOS
        # catálogos, schemas e filtros do gerador 21-gerar-inventario.sh
        # (pg_constraint JOIN pg_namespace JOIN pg_class, com n.nspname NOT LIKE
        # 'pg\_%' AND n.nspname <> 'information_schema' — TODOS os schemas de
        # usuário), exibindo também constraints EXCLUDE (contype 'x') que
        # information_schema.table_constraints não mostra. Critério de identidade
        # IGUAL ao do gerador: (schema, tabela, nome, tipo/contype).
        LAB_CONSTRAINTS_JSON_RC=0
        LAB_CONSTRAINTS_JSON="$(exec_lab_sql "SELECT coalesce(json_agg(json_build_object('schema', n.nspname, 'tabela', r.relname, 'nome', c.conname, 'tipo', c.contype))::text, '[]') FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace JOIN pg_class r ON r.oid = c.conrelid WHERE n.nspname NOT LIKE 'pg\_%' AND n.nspname <> 'information_schema'")" || LAB_CONSTRAINTS_JSON_RC=$?
        LAB_CONSTRAINTS_ITEMS=""
        if [ "${LAB_CONSTRAINTS_JSON_RC}" -ne 0 ] || [ -z "${LAB_CONSTRAINTS_JSON}" ]; then
            printf 'DIVERGÊNCIA: Falha ao listar constraints do banco restaurado para conferência bidirecional (exit %s)\n' "${LAB_CONSTRAINTS_JSON_RC}" >> "${DIVERGENCES_FILE}"
            BIDIRECTIONAL_INCOMPLETE=1
        else
            LAB_CONSTRAINTS_ITEMS_RC=0
            LAB_CONSTRAINTS_ITEMS="$(jq -c '.[]' <<<"${LAB_CONSTRAINTS_JSON}" 2>>"${LOG_FILE}")" || LAB_CONSTRAINTS_ITEMS_RC=$?
            if [ "${LAB_CONSTRAINTS_ITEMS_RC}" -ne 0 ]; then
                printf 'DIVERGÊNCIA: Listagem de constraints do laboratório não é JSON interpretável (jq exit %s)\n' "${LAB_CONSTRAINTS_ITEMS_RC}" >> "${DIVERGENCES_FILE}"
                BIDIRECTIONAL_INCOMPLETE=1
            fi
            while IFS= read -r lc_obj; do
                [ -n "${lc_obj}" ] || continue
                # CORREÇÃO 3 (v2.1.0): decodificação SEM eval (jq @base64 + base64 -d
                # via jq_field_decode); falha = verificação incompleta = sem aprovação.
                LAB_CONSTRAINTS_PARSE_RC=0
                lc_schema="$(jq_field_decode '.schema' "${lc_obj}")" || LAB_CONSTRAINTS_PARSE_RC=1
                lc_tab="$(jq_field_decode '.tabela' "${lc_obj}")" || LAB_CONSTRAINTS_PARSE_RC=1
                lc_name="$(jq_field_decode '.nome' "${lc_obj}")" || LAB_CONSTRAINTS_PARSE_RC=1
                lc_tipo="$(jq_field_decode '.tipo' "${lc_obj}")" || LAB_CONSTRAINTS_PARSE_RC=1
                if [ "${LAB_CONSTRAINTS_PARSE_RC}" -ne 0 ]; then
                    printf 'DIVERGÊNCIA: Falha de decodificação (jq/base64) de constraint do laboratório na conferência bidirecional — verificação incompleta\n' >> "${DIVERGENCES_FILE}"
                    BIDIRECTIONAL_INCOMPLETE=1
                    continue
                fi
                LC_IN_INV_RC=0
                lc_in_inv="$(jq --arg s "${lc_schema}" --arg t "${lc_tab}" --arg n "${lc_name}" --arg k "${lc_tipo}" 'any(.constraints[]; .schema == $s and .tabela == $t and .nome == $n and .tipo == $k)' "${INVENTORY_FILE}" 2>>"${LOG_FILE}")" || LC_IN_INV_RC=$?
                if [ "${LC_IN_INV_RC}" -ge 2 ]; then
                    printf 'DIVERGÊNCIA: Falha de jq ao verificar constraint %s."%s"."%s" (tipo %s) no inventário (exit %s)\n' "${lc_schema}" "${lc_tab}" "${lc_name}" "${lc_tipo}" "${LC_IN_INV_RC}" >> "${DIVERGENCES_FILE}"
                    BIDIRECTIONAL_INCOMPLETE=1
                    continue
                fi
                if [ "${lc_in_inv}" != "true" ]; then
                    printf 'DIVERGÊNCIA BIDIRECIONAL (constraint extra): constraint %s."%s"."%s" (tipo %s) existe no banco restaurado mas NÃO CONSTA no inventário oficial\n' "${lc_schema}" "${lc_tab}" "${lc_name}" "${lc_tipo}" >> "${DIVERGENCES_FILE}"
                else
                    printf 'CONFERIDO BIDIRECIONAL: Constraint %s."%s"."%s" (tipo %s) localizada em ambos os lados\n' "${lc_schema}" "${lc_tab}" "${lc_name}" "${lc_tipo}" >> "${CONFERIDOS_FILE}"
                fi
            done <<<"${LAB_CONSTRAINTS_ITEMS}"
        fi

        # --- Funções do banco restaurado — CORREÇÃO 2 (v2.1.0): MESMO filtro de
        # schemas do gerador 21-gerar-inventario.sh (pg_proc JOIN pg_namespace,
        # com n.nspname NOT LIKE 'pg\_%' AND n.nspname <> 'information_schema' —
        # TODOS os schemas de usuário; antes: restrito a 'public'). Comparação
        # por sobrecarga com a MESMA identidade do sentido 1 e do gerador:
        # (schema, nome, identidade de argumentos).
        LAB_FUNCOES_JSON_RC=0
        LAB_FUNCOES_JSON="$(exec_lab_sql "SELECT coalesce(json_agg(json_build_object('schema', n.nspname, 'nome', p.proname, 'identidade', pg_get_function_identity_arguments(p.oid)))::text, '[]') FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname NOT LIKE 'pg\_%' AND n.nspname <> 'information_schema'")" || LAB_FUNCOES_JSON_RC=$?
        LAB_FUNCOES_ITEMS=""
        if [ "${LAB_FUNCOES_JSON_RC}" -ne 0 ] || [ -z "${LAB_FUNCOES_JSON}" ]; then
            printf 'DIVERGÊNCIA: Falha ao listar funções do banco restaurado para conferência bidirecional (exit %s)\n' "${LAB_FUNCOES_JSON_RC}" >> "${DIVERGENCES_FILE}"
            BIDIRECTIONAL_INCOMPLETE=1
        else
            LAB_FUNCOES_ITEMS_RC=0
            LAB_FUNCOES_ITEMS="$(jq -c '.[]' <<<"${LAB_FUNCOES_JSON}" 2>>"${LOG_FILE}")" || LAB_FUNCOES_ITEMS_RC=$?
            if [ "${LAB_FUNCOES_ITEMS_RC}" -ne 0 ]; then
                printf 'DIVERGÊNCIA: Listagem de funções do laboratório não é JSON interpretável (jq exit %s)\n' "${LAB_FUNCOES_ITEMS_RC}" >> "${DIVERGENCES_FILE}"
                BIDIRECTIONAL_INCOMPLETE=1
            fi
            while IFS= read -r lf_obj; do
                [ -n "${lf_obj}" ] || continue
                # CORREÇÃO 3 (v2.1.0): decodificação SEM eval (jq @base64 + base64 -d
                # via jq_field_decode); falha = verificação incompleta = sem aprovação.
                LAB_FUNCOES_PARSE_RC=0
                lf_schema="$(jq_field_decode '.schema' "${lf_obj}")" || LAB_FUNCOES_PARSE_RC=1
                lf_name="$(jq_field_decode '.nome' "${lf_obj}")" || LAB_FUNCOES_PARSE_RC=1
                lf_ident="$(jq_field_decode '.identidade' "${lf_obj}")" || LAB_FUNCOES_PARSE_RC=1
                if [ "${LAB_FUNCOES_PARSE_RC}" -ne 0 ]; then
                    printf 'DIVERGÊNCIA: Falha de decodificação (jq/base64) de função do laboratório na conferência bidirecional — verificação incompleta\n' >> "${DIVERGENCES_FILE}"
                    BIDIRECTIONAL_INCOMPLETE=1
                    continue
                fi
                LF_IN_INV_RC=0
                lf_in_inv="$(jq --arg s "${lf_schema}" --arg n "${lf_name}" --arg i "${lf_ident}" 'any(.funcoes[]; .schema == $s and .nome == $n and .identidade == $i)' "${INVENTORY_FILE}" 2>>"${LOG_FILE}")" || LF_IN_INV_RC=$?
                if [ "${LF_IN_INV_RC}" -ge 2 ]; then
                    printf 'DIVERGÊNCIA: Falha de jq ao verificar função %s."%s" no inventário (exit %s)\n' "${lf_schema}" "${lf_name}" "${LF_IN_INV_RC}" >> "${DIVERGENCES_FILE}"
                    BIDIRECTIONAL_INCOMPLETE=1
                    continue
                fi
                if [ "${lf_in_inv}" != "true" ]; then
                    printf 'DIVERGÊNCIA BIDIRECIONAL (funcao extra): função %s."%s" (identidade: "%s") existe no banco restaurado mas NÃO CONSTA no inventário oficial\n' "${lf_schema}" "${lf_name}" "${lf_ident}" >> "${DIVERGENCES_FILE}"
                else
                    printf 'CONFERIDO BIDIRECIONAL: Função %s."%s" (identidade casada) localizada em ambos os lados\n' "${lf_schema}" "${lf_name}" >> "${CONFERIDOS_FILE}"
                fi
            done <<<"${LAB_FUNCOES_ITEMS}"
        fi

        # Ponto 5 da correção v1.8.0: SIM somente se NADA ficou pendente —
        # schema válido, zero divergências de constraints e funções, extrações
        # jq completas e NENHUMA divergência acumulada no arquivo (contagem
        # absoluta igual a zero, não apenas divergências novas desta etapa);
        # contagem não inteira é tratada de forma conservadora (divergido).
        DIVERG_FINAL_COUNT="$(wc -l < "${DIVERGENCES_FILE}" 2>/dev/null | tr -d '[:space:]')"
        case "${DIVERG_FINAL_COUNT}" in
            ''|*[!0-9]*) DIVERG_FINAL_COUNT=1 ;;
        esac
        INVENTORY_STAGE_DIVERGED=0
        if [ "${DIVERG_FINAL_COUNT}" -gt 0 ]; then
            INVENTORY_STAGE_DIVERGED=1
        fi

        if [ "${INV_SCHEMA_VALID}" -eq 1 ] \
            && [ "${CONSTRAINTS_DIFF_FOUND}" -eq 0 ] \
            && [ "${FUNCTIONS_DIFF_FOUND}" -eq 0 ] \
            && [ "${BIDIRECTIONAL_INCOMPLETE}" -eq 0 ] \
            && [ "${INVENTORY_EXTRACTION_INCOMPLETE}" -eq 0 ] \
            && [ "${INVENTORY_STAGE_DIVERGED}" -eq 0 ] \
            && [ ! -s "${DIVERGENCES_FILE}" ]; then
            INVENTORY_BIDIRECTIONAL_CHECK_PASSED=1
            INVENTORY_COMPARISON_VALID="SIM"
        else
            INVENTORY_BIDIRECTIONAL_CHECK_PASSED=0
            INVENTORY_COMPARISON_VALID="NAO"
        fi
    fi
fi

# ------------------------------------------------------------------------------
# ETAPA 5: INTEGRIDADE PARCIAL DO POSTGRESQL RESTAURADO (4 testes não destrutivos)
# Ponto 8 da Auditoria:
#   Distinguir expressamente "integridade parcial do PostgreSQL restaurado" de
#   "recuperação funcional completa do CRM". Estes testes provam unicamente a
#   saúde do banco de dados (FKs, auth.users, explain, rollback); não provam o
#   funcionamento da aplicação (GoTrue/Kong/PostgREST/CRM fora do escopo deste teste).
# ------------------------------------------------------------------------------

say "🛡️  Executando as 4 verificações de integridade do banco PostgreSQL restaurado..."

OP_CRITERION_STATUS="PENDENTE"

# Teste 1: Integridade referencial básica (FKs órfãs)
# Ponto 7 da correção v2.0.0: NULL permitido NÃO é referência órfã. Somente
# referências EFETIVAMENTE inválidas (client_id preenchido sem correspondência)
# são contadas — NULL legítimo de coluna nullable não é mais falso positivo.
FK_ORPHANS_CNT_RAW="$(exec_lab_sql "
SELECT (
    (SELECT count(*) FROM public.cases c LEFT JOIN public.clients cl ON cl.id = c.client_id WHERE c.client_id IS NOT NULL AND cl.id IS NULL) +
    (SELECT count(*) FROM public.tasks t LEFT JOIN public.clients cl ON cl.id = t.client_id WHERE t.client_id IS NOT NULL AND cl.id IS NULL) +
    (SELECT count(*) FROM public.appointments a LEFT JOIN public.clients cl ON cl.id = a.client_id WHERE a.client_id IS NOT NULL AND cl.id IS NULL)
) as total_orfãos;
")" || {
    printf 'DIVERGÊNCIA (saude-pg): Falha de consulta SQL ao verificar FKs órfãs\n' >> "${DIVERGENCES_FILE}"
    FK_ORPHANS_CNT_RAW=999
}
FK_ORPHANS_CNT="$(printf '%s\n' "${FK_ORPHANS_CNT_RAW}" | tr -d '[:space:]')"

case "${FK_ORPHANS_CNT}" in
    ''|*[!0-9]*)
        FK_ORPHANS_CNT=999
        ;;
esac

if [ "${FK_ORPHANS_CNT}" -eq 0 ]; then
    printf 'CONFERIDO (saude-pg): Nenhuma referência inválida detectada nas entidades centrais (cases, tasks, appointments) — valores NULL permitidos pelas colunas não são contados como órfãos\n' >> "${CONFERIDOS_FILE}"
else
    printf 'DIVERGÊNCIA (saude-pg): Encontradas %s referências inválidas (client_id preenchido sem cliente correspondente) violando a integridade referencial básica\n' "${FK_ORPHANS_CNT}" >> "${DIVERGENCES_FILE}"
fi

# Teste 2: Consistência de auth.users (sem e-mails duplicados)
USERS_DUP_COUNT_RAW="$(exec_lab_sql "SELECT count(*) FROM (SELECT lower(email), count(*) FROM auth.users GROUP BY lower(email) HAVING count(*) > 1) d;")" || {
    printf 'DIVERGÊNCIA (saude-pg): Falha de consulta SQL ao checar duplicidades em auth.users\n' >> "${DIVERGENCES_FILE}"
    USERS_DUP_COUNT_RAW=999
}
USERS_DUP_COUNT="$(printf '%s\n' "${USERS_DUP_COUNT_RAW}" | tr -d '[:space:]')"

case "${USERS_DUP_COUNT}" in
    ''|*[!0-9]*)
        USERS_DUP_COUNT=999
        ;;
esac

USERS_TOTAL_RAW="$(exec_lab_sql "SELECT count(*) FROM auth.users")" || {
    printf 'DIVERGÊNCIA (saude-pg): Falha de consulta SQL ao contar auth.users\n' >> "${DIVERGENCES_FILE}"
    USERS_TOTAL_RAW=0
}
USERS_TOTAL="$(printf '%s\n' "${USERS_TOTAL_RAW}" | tr -d '[:space:]')"

case "${USERS_TOTAL}" in
    ''|*[!0-9]*)
        USERS_TOTAL=0
        ;;
esac

if [ "${USERS_TOTAL}" -gt 0 ] && [ "${USERS_DUP_COUNT}" -eq 0 ]; then
    printf 'CONFERIDO (saude-pg): auth.users íntegro (%s usuários, 0 e-mails duplicados)\n' "${USERS_TOTAL}" >> "${CONFERIDOS_FILE}"
else
    printf 'DIVERGÊNCIA (saude-pg): Inconsistência ou falha em auth.users (total: %s, e-mails duplicados: %s)\n' "${USERS_TOTAL}" "${USERS_DUP_COUNT}" >> "${DIVERGENCES_FILE}"
fi

# Teste 3: EXPLAIN de consultas representativas de leitura das tabelas centrais
EXPLAIN_STATUS="OK"
for q in \
    "SELECT id, name, cpf_cnpj FROM public.clients ORDER BY created_at DESC LIMIT 50" \
    "SELECT id, title, case_number, status FROM public.cases ORDER BY created_at DESC LIMIT 50" \
    "SELECT id, title, due_date, status FROM public.tasks ORDER BY due_date ASC LIMIT 50" \
    "SELECT id, title, start_time FROM public.appointments ORDER BY start_time ASC LIMIT 50"; do
    if ! exec_lab_sql "EXPLAIN ${q}" >>"${LOG_FILE}" 2>&1; then
        EXPLAIN_STATUS="FALHA"
        break
    fi
done

if [ "${EXPLAIN_STATUS}" = "OK" ]; then
    printf 'CONFERIDO (saude-pg): Planos de execução (EXPLAIN) válidos para consultas representativas das tabelas centrais\n' >> "${CONFERIDOS_FILE}"
else
    printf 'DIVERGÊNCIA (saude-pg): Falha de execução nas consultas representativas das tabelas centrais\n' >> "${DIVERGENCES_FILE}"
fi

# Teste 4: Bloco transacional não destrutivo com ROLLBACK garantido
TX_STATUS="OK"
TX_TMP_FILE="${DIAG_DIR}/tx-simulation-${TS_STAMP}-$$.sql"
cat <<'EOF' > "${TX_TMP_FILE}"
BEGIN;
SELECT count(*) FROM public.clients;
SELECT count(*) FROM public.cases;
SELECT count(*) FROM public.tasks;
SELECT count(*) FROM public.appointments;
ROLLBACK;
EOF
# Ponto 8 da correção v2.0.0: sem "|| true" — sucesso do chmod E permissão
# efetiva (stat) são verificados; falha em qualquer um aborta a execução.
if ! chmod 600 "${TX_TMP_FILE}"; then
    die "Falha ao ajustar permissões (600) do arquivo SQL temporário de simulação transacional." "${EXIT_FS_FAIL}"
fi
TX_TMP_PERM="$(stat -c '%a' "${TX_TMP_FILE}" 2>/dev/null || stat -f '%Lp' "${TX_TMP_FILE}" 2>/dev/null || echo "")"
if [ -z "${TX_TMP_PERM}" ] || [ "${TX_TMP_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo SQL temporário inválida (${TX_TMP_PERM})." "${EXIT_FS_FAIL}"
fi

if ! exec_lab_sql_file "${TX_TMP_FILE}"; then
    TX_STATUS="FALHA"
    printf 'DIVERGÊNCIA (saude-pg): Bloco transacional de simulação falhou\n' >> "${DIVERGENCES_FILE}"
else
    printf 'CONFERIDO (saude-pg): Simulação transacional com ROLLBACK concluída com sucesso\n' >> "${CONFERIDOS_FILE}"
fi
rm -f "${TX_TMP_FILE}" 2>/dev/null || true

if [ "${FK_ORPHANS_CNT}" -eq 0 ] && [ "${USERS_TOTAL}" -gt 0 ] && [ "${USERS_DUP_COUNT}" -eq 0 ] && [ "${EXPLAIN_STATUS}" = "OK" ] && [ "${TX_STATUS}" = "OK" ]; then
    OP_CRITERION_STATUS="CONFORME"
    OPERATIONAL_CRM_CHECK_PASSED=1
else
    OP_CRITERION_STATUS="NAO_CONFORME"
fi

# ------------------------------------------------------------------------------
# CONSOLIDAÇÃO DO VEREDITO (v1.5.0)
# Ponto 1 da Auditoria:
#   O critério A exige SIMULTANEAMENTE gunzip exit 0, psql exit 0 e zero erros SQL.
#   A condição permissiva com '||' foi eliminada.
#   Recuperação assistida (Critério B) NÃO mascara falha na restauração original.
# ------------------------------------------------------------------------------

DIVERGENCES_COUNT="$(wc -l < "${DIVERGENCES_FILE}" 2>/dev/null || echo 0)"
CONFERIDOS_COUNT="$(wc -l < "${CONFERIDOS_FILE}" 2>/dev/null || echo 0)"
TEMPORAL_DIFFS_COUNT="$(wc -l < "${TEMPORAL_DIFFS_FILE}" 2>/dev/null || echo 0)"

# Ponto 1 da correção v2.0.0: a contagem efetiva de falhas SQL vem do ARQUIVO
# de registro da sessão (incrementos dentro de $(...) não persistem no processo
# principal). 999 = contagem não confiável (conservador: impede aprovação).
QUERY_FAILURES_COUNT="$(count_query_failures)"
log "Falhas de consulta SQL registradas nesta sessão: ${QUERY_FAILURES_COUNT}"

# CORREÇÃO 3 (v2.1.1): a existência do sinal fatal é checada na consolidação —
# mecanismo INDEPENDENTE do arquivo cuja escrita pode ter falhado. Presença do
# sinal = falha de escrita no registro (ou impossibilidade de registrar a
# falha): contagem forçada ao valor conservador 999 e aprovação impossível,
# MESMO que o arquivo de registro esteja vazio ou ilegível (count_query_failures
# não é a única fonte de bloqueio).
#
# CORREÇÃO (v2.1.2): a CONSULTA do mecanismo de sinalização é ELA MESMA
# verificada (fail-closed completo): a função check_query_failure_signal executa
# uma SONDA mkdir+rmdir no diretório dedicado e valida TODOS os canais (B: flag
# em arquivo; C: subdiretório de sinal; D: marcadores alternativos). Resultados:
#   0 = canal íntegro e sem sinal  → segue o fluxo normal;
#   1 = sinal fatal presente       → contagem 999, aprovação impossível;
#   2 (ou qualquer outro) = canal INACESSÍVEL / consulta NÃO CONFIÁVEL →
#       MESMO tratamento conservador (contagem 999, aprovação impossível).
# Assim, a condição apontada na auditoria (falha simultânea da escrita no
# registro E no flag) fica sistematicamente bloqueada: se o sistema de arquivos
# está quebrado a ponto de os canais de gravação falharem, a sonda da
# consolidação falha da mesma forma e o veredito é negado de forma INDEPENDENTE
# de variáveis de subshell ou da leitura dos dois arquivos originais.
QUERY_FAILURES_FATAL=0
QUERY_FAILURES_SIGNAL_STATE=0
check_query_failure_signal
QUERY_FAILURES_SIGNAL_STATE=$?
case "${QUERY_FAILURES_SIGNAL_STATE}" in
    0)
        : # Canal íntegro e sem sinal fatal: fluxo normal.
        ;;
    1)
        QUERY_FAILURES_FATAL=1
        QUERY_FAILURES_COUNT=999
        printf 'DIVERGÊNCIA: Sinal fatal de registro SQL presente (canais verificados: %s, %s e marcadores alternativos) — veredito NUNCA é APROVADO nesta condição\n' "${QUERY_FAILURES_SIGNAL_DIR}" "${QUERY_FAILURES_FATAL_FLAG}" >> "${DIVERGENCES_FILE}"
        say_err "Sinal fatal presente: falha de escrita no registro de falhas SQL; a auditoria NÃO pode ser aprovada."
        log "FALHA FATAL (registro SQL): sinal fatal presente (canal dedicado: ${QUERY_FAILURES_SIGNAL_DIR}; flag: ${QUERY_FAILURES_FATAL_FLAG})"
        ;;
    *)
        QUERY_FAILURES_FATAL=1
        QUERY_FAILURES_COUNT=999
        printf 'DIVERGÊNCIA: Canal de sinalização de falhas SQL INACESSÍVEL ou consulta NÃO CONFIÁVEL (estado %s da sonda) — fail-closed: veredito NUNCA é APROVADO nesta condição\n' "${QUERY_FAILURES_SIGNAL_STATE}" >> "${DIVERGENCES_FILE}"
        say_err "Canal de sinalização de falhas SQL inacessível ou consulta não confiável (fail-closed); a auditoria NÃO pode ser aprovada."
        log "FALHA FATAL (registro SQL): consulta do canal de sinalização não confiável (estado ${QUERY_FAILURES_SIGNAL_STATE})"
        ;;
esac

# Correção (v2.1.2): último recurso em memória (canal E). Só é ativo quando o
# record_query_failure rodou no PROCESSO PRINCIPAL e até os canais em disco
# falharam; cobre o caso em que o sistema de arquivos se recupera antes da
# consolidação (a sonda passaria, mas a impossibilidade ficou registrada aqui).
if [ "${QUERY_FAILURES_UNSIGNABLE:-0}" -ne 0 ]; then
    QUERY_FAILURES_FATAL=1
    QUERY_FAILURES_COUNT=999
    printf 'DIVERGÊNCIA: Registro de falhas SQL ficou IMPOSSÍVEL de sinalizar em disco durante a sessão (flag em memória) — veredito NUNCA é APROVADO nesta condição\n' >> "${DIVERGENCES_FILE}"
    say_err "Impossibilidade de sinalizar falhas SQL em disco detectada; a auditoria NÃO pode ser aprovada."
    log "FALHA FATAL (registro SQL): QUERY_FAILURES_UNSIGNABLE ativo na consolidação"
fi

CRIT_A="FALHA"
if [ "${RESTORE_ORIGINAL_STATUS}" = "OK" ] && [ "${GZIP_EXIT}" -eq 0 ] && [ "${PSQL_EXIT}" -eq 0 ] && [ "${RESTORE_RAW_ERRORS_COUNT}" -eq 0 ]; then
    CRIT_A="OK"
fi

# Correção 5 (v1.9.0): recuperação assistida NÃO satisfaz o critério B.
# Somente extensão presente NA restauração original (estado "OK") aprova.
if [ "${GRAPHQL_FINAL_STATUS}" = "OK" ]; then
    CRIT_B="OK"
else
    CRIT_B="FALHA"
fi

CRIT_C="FALHA"
if [ "${TOTAL_TABELAS_LAB}" -gt 0 ] && [ "${TOTAL_REGISTROS_STATUS}" = "OK" ]; then
    CRIT_C="OK"
fi

# Critério D: Comparação bidirecional integral com inventário (jq estrito)
# É impeditivo também qualquer falha de consulta SQL ou diferença inconclusiva.
CRIT_D_OK=0
if [ "${INVENTORY_COMPARISON_VALID}" = "SIM" ] \
    && [ "${INVENTORY_BIDIRECTIONAL_CHECK_PASSED}" -eq 1 ] \
    && [ "${QUERY_FAILURES_COUNT}" -eq 0 ] \
    && [ "${QUERY_FAILURES_FATAL}" -eq 0 ] \
    && [ "${TEMPORAL_DIFFS_COUNT}" -eq 0 ]; then
    CRIT_D_OK=1
fi

# ------------------------------------------------------------------------------
# VEREDITO FINAL (derivado EXCLUSIVAMENTE das variáveis reais acima)
# Nenhuma aprovação artificial: qualquer falha, divergência ou inconclusivo
# resulta REPROVADO.
# ------------------------------------------------------------------------------

if [ "${CRIT_A}" = "OK" ] && [ "${CRIT_B}" = "OK" ] && [ "${CRIT_C}" = "OK" ] \
    && [ "${CRIT_D_OK}" -eq 1 ] && [ "${OP_CRITERION_STATUS}" = "CONFORME" ] \
    && [ "${DIVERGENCES_COUNT}" -eq 0 ] && [ "${TEMPORAL_DIFFS_COUNT}" -eq 0 ] \
    && [ "${QUERY_FAILURES_COUNT}" -eq 0 ] && [ "${QUERY_FAILURES_FATAL}" -eq 0 ] \
    && [ "${INVENTORY_COMPARISON_VALID}" = "SIM" ]; then
    VEREDITO="APROVADO"
    MOTIVO_VEREDITO="Todos os critérios técnicos passaram sem exceção (restauração física original, pg_graphql, estrutural exaustivo, comparação bidirecional integral jq, integridade parcial do PostgreSQL e zero divergências/falhas de consulta)."
else
    VEREDITO="REPROVADO"
    MOTIVO_VEREDITO="O backup apresentou divergências ou falhas técnicas não resolvidas (CRIT_A_ORIGINAL: ${CRIT_A}, CRIT_B: ${CRIT_B}, GRAPQHL_FINAL: ${GRAPHQL_FINAL_STATUS}, RECUPERACAO: ${GRAPHQL_REC_STATUS}, DEPENDENCIA_POS_RESTORE: ${GRAPHQL_DEP_NOTE}, CRIT_D_OK: ${CRIT_D_OK}, DIVERGÊNCIAS: ${DIVERGENCES_COUNT}, INCONCLUSIVAS: ${TEMPORAL_DIFFS_COUNT}, QUERIES_FALHAS: ${QUERY_FAILURES_COUNT}, FALHA_REGISTRO_SQL: ${QUERY_FAILURES_FATAL}, COMPARAÇÃO_VÁLIDA: ${INVENTORY_COMPARISON_VALID})."
fi

# ------------------------------------------------------------------------------
# GRAVAÇÃO DO RELATÓRIO TÉCNICO (HEREDOC ÚNICO E CONSOLIDADO) COM CHMOD 600
# ------------------------------------------------------------------------------

cat <<EOF > "${REPORT_FILE}"
================================================================================
 DPSjur / SBJur — RELATÓRIO DE AUDITORIA DE BACKUP (${SCRIPT_VERSION})
 Data de emissão: $(date '+%F %T %Z')
 Sessão de auditoria: ${SESSION_ID}
================================================================================

1. ARQUIVOS E AMBIENTE
   Arquivo de backup: ${BACKUP_FILE}
   Inventário oficial: ${INVENTORY_FILE:-Nenhum informado}
   Contêiner de teste: ${LAB_NAME}
   Label da sessão: ${SESSION_LABEL}
   Volume isolado: ${LAB_VOLUME}
   Imagem PostgreSQL: ${CHOSEN_IMAGE}

2. SEÇÃO TÉCNICA SEPARADA: RESTAURAÇÃO ORIGINAL vs RECUPERAÇÃO ASSISTIDA
   (a) Restauração Original (psql -X -v ON_ERROR_STOP=1): ${RESTORE_ORIGINAL_STATUS}
       - Código gunzip .................: ${GZIP_EXIT} (exigido 0)
       - Código psql ...................: ${PSQL_EXIT} (exigido 0)
       - Erros SQL brutos ..............: ${RESTORE_RAW_ERRORS_COUNT} (exigido 0)
       - Avaliação Restauração Original : ${CRIT_A}
   (b) Recuperação Assistida (Post-Restore):
       - Extensão pg_graphql ...........: ${GRAPHQL_FINAL_STATUS}
       - Tentativa de recuperação ......: ${GRAPHQL_REC_STATUS}
       - Dependência pós-restauração ...: ${GRAPHQL_DEP_NOTE}
       - Observação de isolamento ......: A recuperação assistida NÃO mascara falha na restauração original
           (Correção 5 v1.9.0: recuperação assistida NUNCA satisfaz o Critério B;
           veredito APROVADO exige extensão presente na RESTAURAÇÃO ORIGINAL).

3. RESULTADOS DOS DEMAIS CRITÉRIOS TÉCNICOS
   Critério 3 - Inventário estrutural do laboratório: ${CRIT_C}
       - Tabelas public: ${TOTAL_TABELAS_LAB}
       - Tabelas auth: ${TOTAL_TABELAS_AUTH_LAB}
       - Constraints: ${TOTAL_CONSTRAINTS_LAB}
       - Funções: ${TOTAL_FUNCOES_LAB}
       - Triggers: ${TOTAL_TRIGGERS_LAB}
       - Extensões: ${TOTAL_EXTENSOES_LAB}
   Critério 4 - Comparação estrutural e bidirecional com inventário oficial (jq): $([ "${CRIT_D_OK}" -eq 1 ] && echo "CONFORME" || echo "NAO_CONFORME")
       - Validação JSON semântica com jq: ${INVENTORY_COMPARISON_VALID}
       - Bidirecionalidade avaliada: $([ "${INVENTORY_BIDIRECTIONAL_CHECK_PASSED}" -eq 1 ] && echo "SIM" || echo "NAO")
       - Amostragem aplicada: NENHUMA (conferência integral de constraints e funções)
   Critério 5 - Integridade parcial do PostgreSQL restaurado: ${OP_CRITERION_STATUS}
       - Integridade referencial (FKs órfãs): ${FK_ORPHANS_CNT}
       - Consistência auth.users: ${USERS_TOTAL} usuários, ${USERS_DUP_COUNT} duplicidades
       - Planos de execução EXPLAIN: ${EXPLAIN_STATUS}
       - Bloco transacional com ROLLBACK: ${TX_STATUS}
       - Escopo delimitado: Prova unicamente a saúde do PostgreSQL restaurado;
         não atesta recuperação funcional completa da aplicação CRM (Kong/GoTrue/PostgREST fora do escopo do teste).

4. DIVERGÊNCIAS E DIFERENÇAS DE CONTAGEM INCONCLUSIVAS
   Total de divergências impeditivas: ${DIVERGENCES_COUNT}
   Total de diferenças de contagem inconclusivas: ${TEMPORAL_DIFFS_COUNT}
   Total de falhas de consulta SQL: ${QUERY_FAILURES_COUNT}
   Falha fatal de registro SQL (sinal independente, consulta verificada/fail-closed): ${QUERY_FAILURES_FATAL} (0 = canal íntegro e sem sinal; >0 = escrita no registro comprometida OU canal de sinalização inacessível — aprovação impossível)
EOF

if [ -s "${DIVERGENCES_FILE}" ]; then
    printf '\n--- ITENS DE DIVERGÊNCIA REGISTRADOS ---\n' >> "${REPORT_FILE}"
    sed 's/^/   [DIVERGÊNCIA] /' "${DIVERGENCES_FILE}" >> "${REPORT_FILE}"
fi

if [ -s "${TEMPORAL_DIFFS_FILE}" ]; then
    printf '\n--- DIFERENÇAS DE CONTAGEM INCONCLUSIVAS (SEM PRESUNÇÃO DE CRESCIMENTO) ---\n' >> "${REPORT_FILE}"
    sed 's/^/   [INCONCLUSIVO] /' "${TEMPORAL_DIFFS_FILE}" >> "${REPORT_FILE}"
fi

cat <<EOF >> "${REPORT_FILE}"

5. VEREDITO FINAL DA AUDITORIA
   Veredito: ${VEREDITO}
   Motivo: ${MOTIVO_VEREDITO}

6. RASTREABILIDADE E SEGURANÇA
   Rede do contêiner de laboratório: --network none (isolamento de rede estrito)
   Arquivo do relatório: ${REPORT_FILE} (chmod 600)
   Log técnico restrito: ${LOG_FILE} (chmod 600)
   Log de erros do restore: ${RESTORE_ERRORS_FILE} (chmod 600)
   Recursos rastreados da sessão: ${TRACKED_RESOURCES_FILE} (chmod 600)
================================================================================
EOF

if ! chmod 600 "${REPORT_FILE}"; then
    die "Falha ao definir permissões no arquivo de relatório." "${EXIT_FS_FAIL}"
fi
REPORT_PERM="$(stat -c '%a' "${REPORT_FILE}" 2>/dev/null || stat -f '%Lp' "${REPORT_FILE}" 2>/dev/null || echo "")"
if [ -z "${REPORT_PERM}" ] || [ "${REPORT_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo de relatório inválida (${REPORT_PERM})." "${EXIT_FS_FAIL}"
fi

# Exibição no terminal
say ""
say "================================================================================"
say " VEREDITO FINAL DA AUDITORIA DE BACKUP: ${VEREDITO}"
say "================================================================================"
say " Motivo: ${MOTIVO_VEREDITO}"
say ""
say " Resumo dos 5 Critérios Técnicos:"
say "   1. Restauração original estrita ........: ${CRIT_A}"
say "   2. Extensão pg_graphql operacional .....: ${CRIT_B}"
say "   3. Validação estrutural do schema public : ${CRIT_C}"
say "   4. Comparação bidirecional com inventário: $([ "${CRIT_D_OK}" -eq 1 ] && echo "CONFORME" || echo "NAO_CONFORME")"
say "   5. Integridade parcial do PostgreSQL ...: ${OP_CRITERION_STATUS} (CRM fora de escopo)"
say ""
say " Divergências impeditivas : ${DIVERGENCES_COUNT}"
say " Diferenças inconclusivas : ${TEMPORAL_DIFFS_COUNT}"
say ""
say " Arquivos gerados:"
say "   Relatório técnico ......: ${REPORT_FILE} (chmod 600)"
say "   Log de execução ........: ${LOG_FILE} (chmod 600)"
say "   Log de erros do restore .: ${RESTORE_ERRORS_FILE} (chmod 600)"
say "================================================================================"

if [ "${VEREDITO}" = "APROVADO" ]; then
    exit "${EXIT_OK}"
else
    exit "${EXIT_STRUCTURE_FAIL}"
fi
