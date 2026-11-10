# Manual Operacional de Auditoria de Backups — SBJur / DPSjur

Este documento descreve o procedimento operacional padrão para verificação de integridade e auditoria de restauração dos backups do banco de dados PostgreSQL do CRM **SBJur / DPSjur**.

O objetivo deste procedimento é assegurar, com rigor técnico e comprovação prática periódica, que os backups gerados na VPS Hostinger são física e logicamente recuperáveis em caso de desastre.

---

## ⚠️ AVISO DE SEGURANÇA E O QUE NÃO É AUTORIZADO

Por diretriz expressa de segurança do escritório:

1. **NÃO É AUTORIZADO EXECUTAR RESTAURAÇÃO OU TESTE DE LABORATÓRIO NA VPS DE PRODUÇÃO:**
   - O teste de restauração (`--laboratorio`) cria contêineres e consome CPU, memória e I/O que podem sobrecarregar ou derrubar o sistema em uso pelos advogados.
   - O script `docs/vps/20-auditar-backup.sh` possui uma **guarda de segurança automática** que detecta o ambiente da VPS e **recusa-se terminantemente a rodar** em modo laboratório se suspeitar que está em produção.
2. **NÃO É AUTORIZADO ALTERAR A ROTINA DE BACKUP ATUAL:**
   - A rotina de backup em execução (`docs/backup-fase6/01-instalar-backup.sh` e cron da VPS) está funcionando e não deve ser modificada sem validação prévia.
3. **NÃO É AUTORIZADO EXCLUIR BACKUPS OU CONTÊINERES SEM POLÍTICA APROVADA:**
   - Backups históricos no VPS ou na nuvem não devem ser excluídos manualmente.
   - O laboratório limpa apenas os contêineres e volumes temporários gerados em sua própria sessão de teste.

---

## 1. Visão Geral dos Dois Modos do Script `20-auditar-backup.sh`

O script `20-auditar-backup.sh` opera em dois modos distintos:

| Modo                                   | Onde pode rodar                                                      | O que faz                                                                                                                                                                              | Risco para o CRM                                   |
| :------------------------------------- | :------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :------------------------------------------------- |
| **Modo Leve (`--leve`)**               | **Na VPS de Produção** ou em qualquer máquina                        | Verifica se o arquivo existe, testa a integridade com `gzip -t`, calcula SHA-256 e tamanho. **Não usa Docker.**                                                                        | **Zero** (apenas leitura rápida do arquivo).       |
| **Modo Laboratório (`--laboratorio`)** | **Exclusivamente FORA da VPS** (WSL2, Docker Desktop ou Linux local) | Cria um contêiner temporário isolado sem rede (`--network none`), restaura o banco de dados em um banco limpo e vazio, valida tabelas, funções, contagens e gera o relatório completo. | **Zero na VPS** (roda em máquina externa isolada). |

---

## 2. Pré-requisitos da Máquina de Laboratório (Fora da VPS)

Para executar a auditoria completa em modo laboratório, você precisará de uma máquina independente (computador local com Linux, ou Windows com WSL2 e Docker Desktop):

- **Docker:** Docker instalado e funcionando (`docker ps` deve rodar sem erro).
- **Memória RAM:** No mínimo 4 GB disponíveis no host de teste.
- **Espaço em Disco:** No mínimo 5 GB livres para acomodar o contêiner e a expansão dos dados descomprimidos.
- **Imagem Docker:** Ter acesso à imagem do PostgreSQL compatível com o Supabase:
  ```bash
  docker pull supabase/postgres:15.8.1.085
  ```
- **Utilitários comuns:** `bash`, `gzip`, `sha256sum` (ou `shasum`), e opcionalmente `jq` para conferência avançada de JSON.

---

## 3. Passo a Passo Operacional

### Etapa 1: Gerar o Inventário Estrutural na VPS (Somente Leitura)

O inventário serve como a "fotografia" oficial do banco em produção, contendo a lista de tabelas, funções e número de registros para conferência após a restauração.

1. Acesse a VPS via SSH:
   ```bash
   ssh root@srv1737667.hstgr.cloud
   ```
2. Execute o gerador de inventário (modo padrão leve, instantâneo e seguro):
   ```bash
   bash docs/vps/21-gerar-inventario.sh
   ```
   _Nota sobre horários:_ O modo padrão utiliza estimativas do catálogo PostgreSQL (`pg_class.reltuples`), com custo zero para o sistema. Caso deseje contagens exatas (`SELECT count(*)`), execute fora do horário comercial (após as 18:00 ou fins de semana):
   ```bash
   bash docs/vps/21-gerar-inventario.sh --contagem-exata
   ```
3. O script informará onde o arquivo JSON restrito foi gerado, por exemplo:
   `/root/sbjur-backups/inventarios/inventario-20261111-120000.json`.

---

### Etapa 2: Copiar o Backup e o Inventário para a Máquina de Teste

Na sua máquina local ou WSL2 (fora da VPS), faça o download seguro dos arquivos:

```bash
# Crie uma pasta de trabalho local
mkdir -p ~/auditoria-sbjur && cd ~/auditoria-sbjur

# Baixe o backup mais recente gerado na VPS (exemplo com scp)
scp root@srv1737667.hstgr.cloud:/root/sbjur-backups/diario/sbjur_backup_2026-11-10_030001.sql.gz ./backup-teste.sql.gz

# Baixe o inventário gerado na Etapa 1
scp root@srv1737667.hstgr.cloud:/root/sbjur-backups/inventarios/inventario-*.json ./inventario-prod.json
```

---

### Etapa 3: Executar a Auditoria Completa no Laboratório

Na sua máquina de teste (fora da VPS), execute o script de auditoria apontando para os arquivos baixados:

```bash
bash docs/vps/20-auditar-backup.sh \
  --arquivo ./backup-teste.sql.gz \
  --inventario ./inventario-prod.json
```

O que o script fará automaticamente:

1. **Guarda Anti-VPS Estrita:** Testa se por engano o script está sendo rodado na VPS de produção. Qualquer falha em consultar o hostname ou inspecionar contêineres Docker bloqueia preventivamente a execução antes de criar qualquer recurso.
2. **Checagem de Integridade Física:** Executa `gzip -t` e calcula o hash SHA-256 do arquivo.
3. **Checagem de Recursos:** Confere se a máquina tem memória (≥ 4 GB) e disco suficientes.
4. **Criação do Laboratório Isolado:** Sobe um contêiner temporário com `--network none` (sem qualquer acesso à internet ou rede local).
5. **Restauração com `psql -X -v ON_ERROR_STOP=1`:** Carrega o dump PostgreSQL interrompendo e registrando claramente qualquer erro SQL em arquivo restrito (`chmod 600`), com sanitização de dados sensíveis para privacidade.
6. **Pós-Restauração Controlada (Supabase):** Verifica dependências do Supabase (como `graphql_public.graphql` da extensão `pg_graphql`) e recria no laboratório se necessário, diferenciando erros reais de lacunas do dump.
7. **Validação Estrutural e Comparação de Inventário:** Valida tabelas `public` e `auth.users`. Compara contagens exatas com rigor numérico e contagens estimadas sem exigir igualdade numérica estrita. Exige `jq` e inventário válido para certificar a aprovação integral.
8. **Testes Operacionais Não Destrutivos do CRM:** Executa 4 baterias técnicas ativas (FKs órfãs, sanidade de usuários, planos de execução `EXPLAIN` e simulação transacional `BEGIN ... ROLLBACK`).
9. **Limpeza Segura (Cleanup):** Remove os contêineres e volumes efêmeros que ele mesmo criou, sem deixar resíduos.
10. **Emissão do Relatório:** Exibe o resumo no terminal e salva o relatório completo em texto restrito (`chmod 600`), separando restauração original de recuperação assistida.

---

### Novidades e Ajustes de Segurança da Versão v1.2.0

A versão **v1.2.0** dos scripts incorpora as recomendações da auditoria independente do commit `60c4941`:

1. **Separação Rigorosa dos Schemas `public` e `auth`:**
   - O inventário e o auditor separam a contagem de tabelas públicas da contagem de tabelas de autenticação (`auth.users`, etc.). `auth.users` não é contabilizada como tabela `public`.
2. **Eliminação de Mascaramento de Falhas (`|| true` e Conversões para Zero):**
   - Nenhuma falha de consulta do `jq` ou do `psql` é mascarada como "0 registros" ou resultado válido. Falhas de consulta SQL ou de leitura JSON são registradas explicitamente como divergências e impedem o veredito APROVADO integral.
3. **Pós-Restauração de Extensões sem `DROP CASCADE` Destrutivo:**
   - A correção de `pg_graphql` no laboratório utiliza `CREATE EXTENSION IF NOT EXISTS` e validação pontual de integridade, sem recorrer a `DROP EXTENSION ... CASCADE` automático, protegendo todas as tabelas e views dependentes.
4. **Diferenciação Clara entre Restauração Original e Recuperação Assistida:**
   - O relatório final discrimina o status da restauração original direta do dump e o status pós-recuperação assistida (caso ajustes de extensões do Supabase sejam aplicados).
5. **Critério de Reconciliação Temporal para Backups Anteriores ao Inventário:**
   - Quando o backup restaurado é anterior ao inventário da produção, o crescimento natural de registros (ex.: clientes e atendimentos cadastrados após a criação do arquivo de backup) é registrado como diferença temporal esperada em seção informativa do relatório, evitando falsas reprovações em backups íntegros.
6. **Escopo Real dos Testes Técnicos (Critério e):**
   - O critério (e) foi redefinido como **Compatibilidade e Operação Básica do CRM**, atestando que os 4 testes do banco (FKs órfãs, unicidade de `auth.users`, planos `EXPLAIN` e bloco transacional) passaram com sucesso no banco, esclarecendo que o funcionamento operacional completo da aplicação em produção envolve também o runtime ativo dos contêineres GoTrue, Kong e PostgREST.
7. **Guarda Anti-VPS no Topo Absoluto:**
   - A guarda anti-VPS do script 20 é executada imediatamente no início do script, antes de criar qualquer arquivo, pasta temporária ou redirecionamento de log em disco.
8. **Privacidade e Permissões Restritas:**
   - Aplicação de `umask 077` e permissões `600` para logs/relatórios e `700` para diretórios temporários, além de ofuscação de identificadores sensíveis (como CPFs/CNPJs e dados textuais) capturados em eventuais mensagens de erro de restore.

---

### Teste Rápido na VPS: Modo Leve (Opcional)

Se você quiser apenas checar rapidamente se os arquivos de backup na VPS estão íntegros e não corrompidos, sem restaurar nada:

```bash
# Na VPS de produção:
bash docs/vps/20-auditar-backup.sh --leve
```

---

## 4. Como Interpretar o Relatório e os 5 Critérios

O relatório gerado avalia a restauração sob **5 critérios independentes e rigorosos**:

| Critério                                         | Descrição                                                                                                                                                                                                                                       | O que significa se der FALHA                                                                                              |
| :----------------------------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------ |
| **(a) Integridade do arquivo**                   | Teste físico do compactador `gzip -t` e tamanho mínimo.                                                                                                                                                                                         | O arquivo de backup foi corrompido, interrompido durante a gravação ou truncado.                                          |
| **(b) Restauração sem erros**                    | Verificação se a carga inicial do `psql` ocorreu com zero erros SQL.                                                                                                                                                                            | O dump gerou mensagens de erro ao ser restaurado (ex.: comandos que dependiam de roles de cluster ausentes no dump).      |
| **(c) Recuperação de estruturas e dados**        | Confirmação de que as tabelas existem e os dados foram inseridos, conferindo com o inventário (schemas `public` e `auth` separados).                                                                                                            | Faltam tabelas essenciais ou a contagem de registros divergiu da produção.                                                |
| **(d) Dependências Supabase**                    | Verificação das extensões e funções internas do ecossistema Supabase (como `graphql_public.graphql`), distinguindo restauração direta de recuperação assistida.                                                                                 | Extensão não foi inicializada corretamente pelo dump original e procedimento não destrutivo não pôde ativá-la.            |
| **(e) Compatibilidade e operação básica do CRM** | Avaliação técnica ativa do banco via 4 testes não destrutivos representativos (integridade referencial de chaves estrangeiras, sanidade de `auth.users`, planos `EXPLAIN` de consultas centrais e simulação transacional `BEGIN ... ROLLBACK`). | Qualquer teste operacional falhou; o critério é classificado como NÃO COMPROVADO ou FALHA, impedindo o veredito APROVADO. |

### Veredito Final da Auditoria

- **APROVADO (Restauração Integral ou Recuperação Assistida Validada):** Concedido **única e exclusivamente** se os 5 critérios forem atendidos com sucesso (critérios A, B, C, D e E aprovados), sem divergências estruturais críticas pendentes, e com inventário oficial validado via `jq` (diferenciando contagens exatas, diferenças temporais esperadas e estimativas estatísticas não vinculantes). Se ajustes não destrutivos de extensões foram necessários no lab, o veredito registra `RECUPERAÇÃO ASSISTIDA VALIDADA`.
- **RECUPERAÇÃO PARCIAL / REPROVADO:** Emitido se houver qualquer divergência estrutural, interrupção por erro SQL (`psql -X -v ON_ERROR_STOP=1`), falha de integridade referencial ou se a comparação com o inventário oficial estiver ausente ou corrompida.
- **INCONCLUSIVO:** Emitido se o teste for interrompido antes do fim por falta de recursos (disco, memória).

---

## 5. Proposta de Política de Retenção de Relatórios

> **Atenção:** Esta é uma proposta de governança recomendada para o escritório e **NÃO é aplicada de forma destrutiva ou automática** por nenhum script.

1. **Periodicidade Recomendada de Auditoria:**
   - Auditoria completa em laboratório: **1 vez por mês** (preferencialmente na primeira semana do mês).
   - Auditoria em modo leve na VPS: **semanal** ou após grandes manutenções.
2. **Retenção dos Relatórios de Auditoria:**
   - Manter os relatórios de texto gerados (`relatorio-auditoria-*.txt`) arquivados por **12 meses**.
   - Os arquivos de relatório não contêm dados de clientes nem senhas (apenas métricas e contagens numéricas), podendo ser guardados na pasta de documentação de TI do escritório.
3. **Retenção dos Backups:**
   - Mantida integralmente a política já aprovada por Douglas: backups diários (rotatividade local), semanais (30 dias) e mensais (1 ano), com sincronização externa.

---

## 6. Resolução de Dúvidas Comuns

**P: Por que o restore bruto pode acusar erro sobre `graphql_public.graphql`?**  
R: O utilitário `pg_dump` com a flag `--clean --if-exists` tenta recriar extensões. Como a imagem Docker `supabase/postgres` já traz a extensão `pg_graphql` pré-instalada na inicialização do contêiner, o restore pula a criação e as funções da extensão podem não ser registradas no schema público. O script `20-auditar-backup.sh` detecta isso e aplica um procedimento corretivo não destrutivo (sem `DROP CASCADE`) para validar se a dependência é plenamente recuperável, diferenciando no relatório final a restauração original da recuperação assistida.

**P: Os dados de clientes e processos aparecem nos relatórios ou logs?**  
R: **Não.** Todos os scripts foram programados sob rigorosa política de privacidade: são extraídos apenas nomes de tabelas, funções, erros técnicos do PostgreSQL e números de contagem. Nenhum conteúdo de linha, nome de cliente ou processo é gravado nos relatórios. Além disso, todos os arquivos são criados com permissão estrita `chmod 600` e máscara `umask 077`.
