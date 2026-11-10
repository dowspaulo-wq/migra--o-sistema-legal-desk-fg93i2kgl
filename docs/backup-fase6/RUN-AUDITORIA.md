# Manual de Execução: Auditoria Independente de Backup (v1.5.0)

> **Status da Solução**: **NÃO PRONTA PARA USO OPERACIONAL IMEDIATO** — aguarda nova auditoria e aprovação independente (5ª rodada de correções técnicas aplicada, v1.5.0).  
> **Objetivo**: Testar restauração de backup com validação semântica estrita, proteção contra execução indevida em produção (Guarda Anti-VPS estrita no topo absoluto), isolamento total de rede com `--network none`, verificação de endpoints de todos os contextos Docker, restauração física com `psql -X -v ON_ERROR_STOP=1` (exigência simultânea de gunzip 0, psql 0 e zero erros SQL), comparação estrutural completa sem amostragem (definições completas de constraints e funções), delimitação expressa da saúde do PostgreSQL (sem atestar funcionamento da aplicação CRM) e política de sigilo no inventário (sem expor corpos DDL por padrão).

---

## 1. Visão Geral dos Scripts

| Script                            | Versão     | Local de Execução                            | Propósito                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| :-------------------------------- | :--------- | :------------------------------------------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `docs/vps/21-gerar-inventario.sh` | **v1.5.0** | **VPS Hostinger de Produção**                | Extrai metadados estruturais e contagens de catálogo em formato JSON sob `umask 077 + chmod 600`, sem expor dados de clientes ou corpos de funções por padrão. Por padrão faz contagem leve (`reltuples`); a contagem exata (`SELECT count(*)`) exige `--contagem-exata` e é bloqueada no horário de expediente (08h–18h BSB) a menos que se passe `--forcar-horario-expediente`. Serialização estrita via `jq -n --arg/--argjson` com validação de tipos `jq -e`. A inclusão do corpo DDL das funções exige flag explícita `--incluir-corpo-funcoes`. |
| `docs/vps/20-auditar-backup.sh`   | **v1.5.0** | **Máquina de Teste / WSL2 / Docker Desktop** | Restaura o dump `.sql.gz` em contêiner descartável isolado com `--network none`, verificação rigorosa de endpoints Docker em todos os contextos, restauração original estrita (`psql -X -v ON_ERROR_STOP=1`), seções separadas de restauração original e recuperação assistida, conferência de constraints e funções sem amostragem (zero sampling), comparação bidirecional integral `public`/`auth`, 4 testes de integridade do PostgreSQL e veredito técnico.                                                                                       |

---

## 2. As 9 Correções Técnicas Aplicadas na Versão v1.5.0

Em cumprimento à 5ª rodada de auditoria independente, foram incorporadas as seguintes melhorias:

1. **Critério Estrito de Restauração Original**: Eliminada qualquer condição com `||` que permitisse aprovação de restauração com erros residuais. O script agora exige **simultaneamente**: `gunzip` com exit 0, `psql` com exit 0 e zero erros SQL (`RESTORE_RAW_ERRORS_COUNT == 0`), rodando com `psql -X -v ON_ERROR_STOP=1`. O relatório separa estritamente a Restauração Original da Recuperação Assistida posterior (`pg_graphql`), e esta última nunca mascara falhas da restauração original.
2. **Comparação Estrutural Completa Sem Amostragem**: Removido o limite arbitrário de 30 elementos (`head -n 30`). Todas as constraints são conferidas integralmente por definição DDL completa (`pg_get_constraintdef`), e todas as funções são conferidas integralmente por identidade e assinatura (`pg_get_function_identity_arguments` e tipos de retorno).
3. **Comparação Bidirecional Integral com Validação Semântica**: As tabelas dos schemas `public` e `auth` são comparadas integralmente nos dois sentidos (`inventário -> backup` e `backup -> inventário`, por schema, nome e método de contagem). O sinalizador `INVENTORY_COMPARISON_VALID="SIM"` só é atribuído após aprovação cumulativa de todas as checagens e integridade semântica do JSON.
4. **Isolamento de Rede Docker e Inspeção de Contextos**: O contêiner de laboratório utiliza obrigatoriamente a flag `--network none` (o tráfego local do auditor é via `docker exec`). Todos os contextos Docker (inclusive `default`, `desktop-linux` e `colima`) têm seus endpoints inspecionados, abortando imediatamente com exit 11 diante de qualquer endpoint remoto ou não verificável (`tcp://`, `ssh://`, `http://`, `https://`, `npipe://`).
5. **Política de Sigilo do Inventário DDL**: Avaliado o risco de funções conterem credenciais, chaves ou tokens confidenciais. O script `21-gerar-inventario.sh` armazena apenas identidade/assinatura por padrão (`pg_get_function_identity_arguments`). O corpo completo (`pg_get_functiondef`) só é coletado mediante flag explícita `--incluir-corpo-funcoes`, passando por ofuscação automática de padrões sensíveis (`password`, `secret`, `token`, `api_key`).
6. **Validação JSON Estrita**: Validação tipada rigorosa com `jq -e` rejeitando elementos malformados. Campos obrigatórios e tipos de `sumario`, `tabelas`, `constraints` e `funcoes` são verificados antes de permitir avanço do auditor.
7. **Tratamento Impeditivo em Falhas de Permissões**: Falha ou resultado vazio no comando `stat` ao inspecionar arquivos gerados é tratada como erro fatal (`die`/abort imediato), não como mero aviso. Preservada a regra de `mkdir`/`chmod` apenas sobre os artefatos criados pelo próprio script.
8. **Delimitação Expressa da Integridade Parcial do PostgreSQL**: Distinção textual expressa entre "saúde do banco PostgreSQL restaurado" e "recuperação funcional completa do CRM". Os quatro testes (FKs órfãs, `auth.users`, planos `EXPLAIN` e bloco transacional com `ROLLBACK`) atestam exclusivamente a consistência do banco de dados, sem declarar funcionamento de componentes de aplicação (Kong, GoTrue, PostgREST e CRM fora do escopo do teste).
9. **Alinhamento do Manual Operacional**: Manual sincronizado com todos os comandos, flags, códigos de saída e arquivos gerados pelos scripts.

Em cumprimento à 4ª rodada de auditoria independente, foram incorporadas as seguintes melhorias:

1. **Substituição de contadores baseados em grep por jq**: Todos os contadores estruturais no inventário e no auditor foram substituídos por consultas `jq` estritas (`type == "object"`, arrays, strings e números validados). Totais inconsistentes (`total_todas != public + auth`) abortam a execução com erro.
2. **Criação de diretórios privados e verificação de permissões efetivas**: Nenhum `chmod` indiscriminado é aplicado a diretórios preexistentes do sistema. Subdiretórios privados da sessão são criados com `chmod 700`, e cada arquivo gerado (`.json`, `.log`, `.txt`) tem sua permissão efetiva inspecionada via `stat` (`0600`).
3. **Nenhuma falha silenciosa ignorada**: Removidos supressores de erro (`|| true`) em comandos de sistema de arquivos (`mkdir`, `touch`, `chmod`), validações JSON (`jq`) e consultas SQL (`psql -X -v ON_ERROR_STOP=1`).
4. **Montagem do JSON com serialização segura**: O arquivo de inventário é construído através de `jq -n` com passagem tipada de parâmetros (`--arg` para strings seguras, `--argjson` para números e estruturas validadas), eliminando interpolações manuais de strings.
5. **Identificação expressa de instantes temporais distintos**: O cabeçalho do inventário registra explicitamente a seção `"ressalva_temporal"`, documentando que as métricas foram obtidas no instante da execução do script, o qual diverge do instante em que qualquer dump de backup foi gravado.
6. **Inventário estrutural ampliado sem dados de clientes**: Extração de definições completas de constraints (`pg_get_constraintdef`) e de identidades/definições de funções (`pg_get_function_identity_arguments`, `pg_get_functiondef`), permitindo conferência estrutural aprofundada sem extrair nenhuma linha de dados de clientes.
7. **Validação bidirecional de tabelas e critérios prévios**: O auditor confere a correspondência das tabelas nos dois sentidos (inventário $\rightarrow$ backup restaurado e backup restaurado $\rightarrow$ inventário oficial), validando schemas, nomes e métodos de contagem. O sinalizador `INVENTORY_COMPARISON_VALID="SIM"` só é atribuído após o término satisfatório de todas as checagens.
8. **Diferenças de contagem classificadas como INCONCLUSIVAS**: Eliminada a presunção automática de "crescimento natural da produção". Qualquer divergência de contagem é registrada como `INCONCLUSIVA`, impedindo aprovação inadvertida sem investigação factual.
9. **Rastreamento estrito de recursos Docker e limpeza pós-guarda**: Nenhuma limpeza Docker ocorre antes da guarda anti-VPS. O contêiner e o volume isolados recebem labels específicos da sessão (`sbjur.audit.session=<timestamp-pid>`), são registrados em `session-tracked-resources.txt` e somente esses recursos validados podem ser destruídos ao final.
10. **Bloqueio de contextos e endpoints Docker remotos**: O auditor inspeciona `$DOCKER_HOST` e o contexto ativo do Docker daemon, abortando imediatamente se detectar endpoints remotos (`tcp://`, `ssh://`, `http://`, etc.), garantindo que o teste ocorra apenas em socket local seguro.

---

## 3. Roteiro de Execução

### Passo 1: Geração do Inventário na VPS de Produção (Hostinger)

Acesse a VPS via SSH e execute o script 21 em modo somente leitura:

```bash
# Modo 1: Recomendado / Leve (zero impacto, estimativas pg_class.reltuples, sem expor corpos de funções)
bash docs/vps/21-gerar-inventario.sh

# Modo 2: Contagem exata fora do horário comercial (SELECT count(*))
bash docs/vps/21-gerar-inventario.sh --contagem-exata

# Modo 3: Contagem exata forçada durante o expediente (08h-18h BSB)
bash docs/vps/21-gerar-inventario.sh --contagem-exata --forcar-horario-expediente --saida /root/sbjur-backups/inventarios/inventario-manual.json

# Modo 4: Inclusão explícita do corpo DDL das funções com ofuscação de credenciais
bash docs/vps/21-gerar-inventario.sh --incluir-corpo-funcoes
```

O arquivo gerado (`inventario-AAAAMMDD-HHMMSS.json`) tem permissões `0600` e não contém dados confidenciais de clientes.

### Passo 2: Cópia do Backup e do Inventário para a Máquina de Teste

Copie o dump do backup e o arquivo JSON para seu ambiente local isolado (WSL2 / Linux / Docker Desktop):

```bash
scp root@2.25.181.69:/root/sbjur-backups/backups/backup-2026-11-10_03-00.sql.gz /tmp/
scp root@2.25.181.69:/root/sbjur-backups/inventarios/inventario-20261110-180000.json /tmp/
```

### Passo 3: Execução da Auditoria Independente de Restauração

Na máquina de teste (nunca na VPS de produção):

```bash
bash docs/vps/20-auditar-backup.sh \
    --arquivo /tmp/backup-2026-11-10_03-00.sql.gz \
    --inventario /tmp/inventario-20261110-180000.json
```

Caso queira manter o contêiner de teste após a execução para inspeção interativa:

```bash
bash docs/vps/20-auditar-backup.sh \
    --arquivo /tmp/backup-2026-11-10_03-00.sql.gz \
    --inventario /tmp/inventario-20261110-180000.json \
    --manter-lab
```

---

## 4. Códigos de Saída dos Scripts

### `21-gerar-inventario.sh`

- `0`: Sucesso total (JSON gerado e validado).
- `10`: Erro de sintaxe de parâmetros (`--help`).
- `11`: Docker indisponível no host de produção.
- `12`: Contêiner de produção não encontrado ou inativo.
- `15`: Bloqueio de horário comercial (tentativa de `--contagem-exata` entre 08h e 18h BSB sem `--forcar-horario-expediente`).
- `20`: Falha em consulta SQL de catálogo no contêiner.
- `25`: Falha em permissão ou sistema de arquivos (`mkdir`, `touch`, `chmod`, `stat`).
- `30`: Falha na serialização ou validação estrita do JSON (`jq`).

### `20-auditar-backup.sh`

- `0`: Auditoria APROVADA (todos os critérios técnicos passaram sem divergências).
- `10`: Erro de sintaxe de parâmetros (`--help`).
- `11`: Abortado pela Guarda Anti-VPS ou detecção de endpoint Docker remoto/não-verificável.
- `12`: Dependência ausente no host de teste (`docker`, `gunzip`, `psql`, `jq`, `stat`).
- `20`: Falha de restauração física original do dump (`psql -X -v ON_ERROR_STOP=1` ou `gunzip`).
- `21`: Falha de recuperação de `pg_graphql`.
- `22`: Divergência estrutural ou auditoria REPROVADA.
- `23`: Falha na leitura ou validação semântica do inventário oficial.
- `24`: Falha nas verificações de integridade parcial do PostgreSQL restaurado.
- `25`: Falha de sistema de arquivos ou permissões efetivas (`mkdir`, `touch`, `chmod`, `stat`).

---

## 5. Próximos Passos Obrigatórios

- **Aprovação Independente**: Os arquivos e scripts permanecem em status de revisão técnica, aguardando validação do auditor independente antes de qualquer uso operacional em produção.
