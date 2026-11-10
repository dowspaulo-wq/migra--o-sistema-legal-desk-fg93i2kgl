# Manual de Execução: Auditoria Independente de Backup (v1.4.0)

> **Status da Solução**: **NÃO PRONTA PARA USO OPERACIONAL IMEDIATO** — aguarda nova auditoria e aprovação independente (4ª rodada de correções técnicas aplicada, v1.4.0).  
> **Objetivo**: Testar restauração de backup com validação semântica estrita, integridade referencial do CRM, proteção contra execução indevida em produção (Guarda Anti-VPS estrita no topo absoluto), bloqueio de endpoints Docker remotos, serialização segura JSON via `jq`, inventário estrutural ampliado (DDL de constraints e identidades de funções) e classificação estrita de diferenças de contagem como **INCONCLUSIVAS** (sem presunção de crescimento natural).

---

## 1. Visão Geral dos Scripts

| Script                            | Versão     | Local de Execução                            | Propósito                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| :-------------------------------- | :--------- | :------------------------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `docs/vps/21-gerar-inventario.sh` | **v1.4.0** | **VPS Hostinger de Produção**                | Extrai metadados estruturais DDL e contagens de catálogo em formato JSON sob `umask 077 + chmod 600`, sem nunca extrair dados de clientes. Por padrão faz contagem leve (`reltuples`); a contagem exata (`SELECT count(*)`) exige `--contagem-exata` e é bloqueada no horário de expediente (08h–18h BSB) a menos que se passe `--forcar-horario-expediente`. Serialização estrita via `jq -n --arg/--argjson`.                                             |
| `docs/vps/20-auditar-backup.sh`   | **v1.4.0** | **Máquina de Teste / WSL2 / Docker Desktop** | Restaura o dump `.sql.gz` em contêiner descartável isolado, verifica `pg_graphql` (sem `DROP EXTENSION CASCADE`), valida schemas `public` e `auth`, realiza comparação bidirecional estrita com o inventário JSON via `jq`, avalia integridade operacional do CRM (4 testes técnicos) e emite veredito fundamentado. Bloqueia endpoints remotos de Docker (`DOCKER_HOST`), protege permissões e remove apenas recursos rastreados e rotulados com a sessão. |

---

## 2. As 10 Correções Técnicas Aplicadas na Versão v1.4.0

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
# Modo 1: Recomendado / Leve (zero impacto, estimativas pg_class.reltuples)
bash docs/vps/21-gerar-inventario.sh

# Modo 2: Contagem exata fora do horário comercial (SELECT count(*))
bash docs/vps/21-gerar-inventario.sh --contagem-exata

# Modo 3: Contagem exata forçada durante o expediente (08h-18h BSB)
bash docs/vps/21-gerar-inventario.sh --contagem-exata --forcar-horario-expediente --saida /root/sbjur-backups/inventarios/inventario-manual.json
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
- `11`: Docker indisponível.
- `12`: Contêiner de produção não encontrado.
- `15`: Bloqueio de horário comercial (tentativa de `--contagem-exata` entre 08h e 18h BSB sem `--forcar-horario-expediente`).
- `20`: Falha em consulta SQL de catálogo.
- `25`: Falha em permissão ou sistema de arquivos (`mkdir`, `touch`, `chmod`).
- `30`: Falha na serialização ou validação do JSON (`jq`).

### `20-auditar-backup.sh`

- `0`: Auditoria APROVADA (todos os critérios técnicos passaram sem divergências).
- `10`: Erro de sintaxe de parâmetros (`--help`).
- `11`: Abortado pela Guarda Anti-VPS ou bloqueio de DOCKER_HOST remoto.
- `12`: Dependência ausente (`docker`, `gunzip`, `psql`, `jq`).
- `20`: Falha de restauração física do dump.
- `21`: Falha de recuperação de `pg_graphql`.
- `22`: Divergência estrutural ou auditoria REPROVADA.
- `23`: Falha na leitura ou validação semântica do inventário.
- `24`: Falha nas verificações de recuperação operacional do CRM.
- `25`: Falha de sistema de arquivos ou permissões.

---

## 5. Próximos Passos Obrigatórios

- **Aprovação Independente**: Os arquivos e scripts permanecem em status de revisão técnica, aguardando validação do auditor independente antes de qualquer uso operacional em produção.
