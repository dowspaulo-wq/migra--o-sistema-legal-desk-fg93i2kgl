# Rotinas Automáticas de E-mail — VPS (véspera de compromissos + aniversariantes)

**Kit:** `docs/vps/11-rotinas-email-vps.sh` (instalador) + `docs/vps/11-rotinas-email.sh` (runner)
**Versão:** v1.0.0 · **Destinatário padrão:** dowspaulo@gmail.com
**Banco:** Postgres do Supabase self-hosted no próprio VPS (EasyPanel, contêiner `sbjur-local_supabase-db-1`) — **não** usa a base da nuvem Skip.

## O que as rotinas fazem

| Rotina                  | Horário (BSB) | Dias                        | Conteúdo                                                                                                                                                                                                                                                                                                                                                                               |
| ----------------------- | ------------- | --------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **1 — Véspera**         | 07:00         | seg. a sexta (pula sáb/dom) | Audiências e compromissos do **dia seguinte**: horário, tipo, cliente, processo (número), vara/juízo, comarca e link para abrir no sistema (`https://sistema.advdouglaspsantos.com.br/agenda`). Sem compromissos → e-mail curto "sem audiências/compromissos amanhã" (decisão: enviar mesmo vazio, para o silêncio significar problema).                                               |
| **2 — Aniversariantes** | 08:00         | todos os dias               | Clientes que fazem aniversário **naquele dia** (dia/mês da coluna `birthday`, independente do ano): nome, telefone e **link wa.me** com mensagem de parabéns pronta (primeiro nome + assinatura do escritório). **Envio manual**: o Douglas clica e envia — sem disparo automático (decisão registrada; automação exigiria gateway pago). Sem aniversariantes → e-mail curto avisando. |

### Regras definidas (documentadas por pedido do Douglas)

- **Fim de semana (véspera):** sábado e domingo não rodam. **Na sexta-feira o e-mail cobre sábado + domingo + segunda-feira** — ou seja, compromisso de segunda é avisado na sexta.
- **29/02 (aniversariantes):** em ano **não bissexto**, quem nasceu em 29/02 é lembrado em **01/03** (28/02 fica só de quem nasceu em 28/02). Em ano bissexto, 29/02 roda normalmente.
- Cadastros com `birthday` inválido (`0001-01-01`, placeholder) são ignorados.
- Telefones com valor sem sentido (ex.: `0`) são mostrados como "número inválido no cadastro" em vez de gerar link quebrado.
- Compromissos com status **Concluído** ou **Cancelado** não entram no e-mail de véspera.

## Instalação no VPS

**Não usar `curl | bash`** (o pipe engole a entrada — lição já registrada neste projeto). Baixe os **dois** arquivos para o mesmo diretório e rode:

```bash
cd /root
# substitua <URL_RAW> pelo endereço raw dos arquivos no repositório
curl -fsSL -o 11-rotinas-email-vps.sh <URL_RAW>/docs/vps/11-rotinas-email-vps.sh
curl -fsSL -o 11-rotinas-email.sh      <URL_RAW>/docs/vps/11-rotinas-email.sh
bash /root/11-rotinas-email-vps.sh
```

O instalador é **idempotente** (pode rodar quantas vezes quiser) e:

1. grava o runner em `/root/sbjur-emails/rotinas-email.sh`;
2. grava o destinatário em `/root/sbjur-emails/config.env` (permissão 600);
3. instala `/etc/cron.d/sbjur-rotinas-email` com as duas rotinas;
4. faz um **dry-run** de validação (não envia e-mail).

**Pré-requisito:** o envio reutiliza o mecanismo do backup (msmtp `/root/.msmtprc` + `/root/sbjur-backups/config/email.conf`, instalados por `docs/backup-fase6/04-configurar-email.sh`). Se o backup já envia e-mail (confirmado funcionando), nada a configurar. Sem esses arquivos, o envio falha e o erro fica no log.

Trocar o destinatário:

```bash
SBJUR_EMAIL_TO=outro@email.com bash /root/11-rotinas-email-vps.sh
# ou edite /root/sbjur-emails/config.env e rode o runner manualmente para testar
```

## Horários e fuso

- O cron usa `CRON_TZ=America/Sao_Paulo` e o runner fixa `TZ=America/Sao_Paulo` internamente (datas e consultas sempre em BSB).
- **Ajuste fino de horário:** versões antigas de cron ignoram `CRON_TZ`. Se o host estiver em UTC (padrão Hostinger) e os e-mails chegarem às 04/05 BSB, troque no `/etc/cron.d/sbjur-rotinas-email`:
  - `0 7 * * 1-5` → `0 10 * * 1-5` (07:00 BSB = 10:00 UTC)
  - `0 8 * * *` → `0 11 * * *` (08:00 BSB = 11:00 UTC)
- Confira o fuso com `date` no VPS antes de ajustar.

## Como testar

```bash
# 1. Dry-run: imprime o e-mail completo no terminal, NÃO envia nada
bash /root/sbjur-emails/rotinas-email.sh --vespera --dry-run
bash /root/sbjur-emails/rotinas-email.sh --aniversarios --dry-run

# 2. Teste real (envia para o destinatário configurado)
bash /root/sbjur-emails/rotinas-email.sh --vespera
bash /root/sbjur-emails/rotinas-email.sh --aniversarios

# 3. Testar para outro destinatário, sem mudar a config
bash /root/sbjur-emails/rotinas-email.sh --aniversarios --dry-run --to=dowspaulo@gmail.com
```

Logs: `/root/sbjur-emails/logs/rotinas-email.log` (rotação automática acima de 5 MB).

## Formato dos e-mails

**Véspera (com compromissos):**

```
Assunto: [SBJur] Amanha: 3 compromisso(s) - 15/10/2026 (quinta-feira)
Ola, Douglas!
Audiencias e compromissos de 15/10/2026 (quinta-feira):
---------------------------------------------
1. 2026-10-15 as 14:00 — AIJ
   Cliente:  JOAO DA SILVA
   Processo: 0001234-56.2026.8.13.0001
   Vara:     2ª Vara Cível
   Comarca:  Belo Horizonte
   Abrir no sistema: https://sistema.advdouglaspsantos.com.br/agenda
---------------------------------------------
Total: 3 compromisso(s).
Mensagem automatica do SBJur (VPS) - rotina de vespera (07:00 BSB).
```

**Véspera (sexta-feira):** mesmo formato, listando os compromissos de sábado, domingo e segunda, com o cabeçalho "compromissos de sabado, domingo e segunda".

**Aniversariantes:**

```
Assunto: [SBJur] 2 aniversariante(s) hoje (14/10/2026)
Ola, Douglas!
Aniversariantes de hoje (14/10/2026):
---------------------------------------------
1. MARIA DE SOUZA
   Telefone: 31999998888
   WhatsApp: https://wa.me/5531999998888?text=Parabens%2C%20MARIA!%20O%20escritorio%20...
   Abrir no sistema: https://sistema.advdouglaspsantos.com.br/clientes/<id>
---------------------------------------------
Total: 2 aniversariante(s). Clique no link do WhatsApp para enviar o parabens (envio manual, sem automacao).
```

## Detalhes técnicos

- **Consulta véspera:** `appointments` (date/time/type/status) LEFT JOIN `cases` (number/court/comarca) e `clients` (name), filtrando `date IN (<dias-alvo>)` — datas são gravadas como texto `YYYY-MM-DD`. Registros "de sistema" (cliente _Sincronização Google_ / _Registros internos_, número de processo `00`) aparecem como qualquer outro compromisso, com "Cliente não informado"/"—" quando não há vínculo; se quiser filtrá-los no futuro, o lugar é o `WHERE` da query.
- **Consulta aniversariantes:** `clients.birthday` (texto; ~6 cadastros com formato `DD/MM/AAAA` ou vazio no banco atual são **ignorados** pelo filtro regex `^\d{4}-\d{2}-\d{2}$`), comparado por `substring(birthday from 6 for 5)`.
- **Acesso ao banco:** `docker exec` no contêiner `supabase-db` com a senha lida da variável `POSTGRES_PASSWORD` do próprio contêiner (mesmo padrão dos demais scripts VPS deste projeto). Não há credencial nova para configurar.
- **Envio:** msmtp (conta `default` do `/root/.msmtprc`); fallback curl SMTP com as credenciais de `email.conf`.
- Nenhuma alteração no app React, no banco (sem migration/trigger) ou nas integrações existentes — apenas estes dois scripts e este documento.
