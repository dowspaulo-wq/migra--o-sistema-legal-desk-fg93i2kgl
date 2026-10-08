# Kit de Backup Automático do SBJur no VPS — Fase 6

**Servidor:** VPS Hostinger KVM 1 (`srv1737667` — IP `2.25.181.69`)  
**Banco de Dados:** Supabase Self-Hosted no EasyPanel (PostgreSQL 15 via Docker `sbjur-local_supabase-db-1`)  
**Cópia Externa:** Google Drive do escritório (`advdouglaspsantos@gmail.com`) via `rclone`  
**Notificação Diária:** E-mail automático via Gmail SMTP para `advdouglaspsantos@gmail.com`  
**Agendamento:** Diariamente às 03:00 da manhã (via cron do Linux)  
**Versão do Kit:** `v1.0.0`

---

## 🎯 O que este kit faz de forma 100% automática?

1. **Dump Integral Diário às 03:00:** Gera um arquivo `.sql.gz` comprimido contendo todo o banco de dados (tabelas de negócio, clientes, processos, tarefas, financeiro, configurações e usuários de autenticação).
2. **Política de Retenção Inteligente (Regra 7/30/365):**
   - **Diários:** mantidos pelos últimos 7 dias;
   - **Semanais (gerados aos domingos):** guardados por 30 dias;
   - **Mensais (gerados no dia 1º de cada mês):** guardados por 1 ano completo.
3. **Cópia em Nuvem Externa (Google Drive):** Envia o arquivo de backup para a pasta `SBJur-Backups/` na sua conta Google Drive do escritório (`advdouglaspsantos@gmail.com`). Se o VPS queimar ou a Hostinger cair, seus dados continuam a salvo no seu Drive pessoal.
4. **Notificação Diária por E-mail:** Envia um e-mail diário para `advdouglaspsantos@gmail.com` confirmando que o backup foi concluído com sucesso (e, caso haja qualquer falha, dispara um alerta vermelho urgente).
5. **Teste de Restauração em Banco Paralelo:** Script que restaura o dump mais recente num banco temporário de teste (`sbjur_restore_test`) para auditar contagens de linhas de cada tabela, sem nunca tocar no banco de produção.

---

## 📁 Estrutura de Arquivos no Repositório e no VPS

```text
docs/backup-fase6/
├── 00-README.md                 <- Este guia completo
├── 01-instalar-backup.sh        <- Instalador completo e idempotente
├── 02-testar-backup.sh          <- Roda o backup agora e valida Drive + E-mail
├── 03-testar-restauracao.sh     <- Simula restauração e confere contagens
└── 04-configurar-email.sh       <- Assistente isolado para senha de app do Gmail
```

No VPS, todos os backups e arquivos operacionais ficam organizados em:

```text
/root/sbjur-backups/
├── backup.sh                    <- Script mestre executado pelo cron às 03:00
├── diario/                      <- Backups dos últimos 7 dias (.sql.gz)
├── semanal/                     <- Backups de domingo (mantidos 30 dias)
├── mensal/                      <- Backups do dia 1º (mantidos 1 ano)
├── config/                      <- Configuração segura (email.conf, permissão 600)
└── logs/                        <- Histórico detalhado (backup.log)
```

---

## 🚀 PASSO A PASSO: Como Instalar no Terminal do VPS

Você só precisa abrir o terminal do seu VPS (via **EasyPanel** ou **SSH**) e seguir os 4 passos rápidos abaixo.

---

### Passo 1: Gerar a "Senha de App" do Google (1 minuto no navegador)

Para o VPS conseguir enviar e-mails de aviso diários sem pedir sua senha pessoal da conta Google, gere uma Senha de App segura:

1. Acesse: **[https://myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords)**
2. Faça login com o e-mail: `advdouglaspsantos@gmail.com`
   _(Nota: a verificação em 2 etapas precisa estar ativada na sua conta Google)_;
3. No campo **Nome do app**, digite: `SBJur Backup VPS` e clique em **Criar**;
4. O Google exibirá uma senha amarela de 16 letras (ex: `abcd efgh ijkl mnop`).  
   👉 **Copie essas 16 letras** (pode deixar anotado no bloco de notas).

---

### Passo 2: Executar o Instalador no VPS (Comando Único)

Abra o terminal do VPS e cole o comando abaixo:

```bash
mkdir -p /root/sbjur-backups && cd /root/sbjur-backups && \
curl -sSf -L -H "Accept: application/vnd.github.v3.raw" -H "User-Agent: DPSjur-BackupKit" \
  "https://api.github.com/repos/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/contents/docs/backup-fase6/01-instalar-backup.sh?ref=main" \
  -o 01-instalar-backup.sh && \
bash 01-instalar-backup.sh
```

_(Se o GitHub der algum bloqueio de conexão temporário, o comando alternativo é:)_

```bash
curl -sSf -L https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/backup-fase6/01-instalar-backup.sh | bash
```

---

### Passo 3: Autorizar o Google Drive (Assistente do rclone)

Durante a execução do instalador (ou ao rodar `rclone config`), o assistente perguntará:

1. `n/s/q>` ➔ Digite `n` _(New remote)_
2. `name>` ➔ Digite `gdrive` _(tudo minúsculo)_
3. `Storage>` ➔ Digite `drive` _(Google Drive)_
4. `client_id>` ➔ Apenas aperte **Enter** (deixe em branco)
5. `client_secret>` ➔ Apenas aperte **Enter** (deixe em branco)
6. `scope>` ➔ Digite `1` _(Full access to all files)_
7. `service_account_file>` ➔ Apenas aperte **Enter**
8. `Edit advanced config?` ➔ Digite `n` _(No)_
9. `Use auto config?` ➔ Digite `n` _(No, pois o servidor não tem navegador próprio)_
10. **O rclone mostrará um link longo na tela começando com `https://accounts.google.com/o/oauth2/auth...`**:
    - **Copie esse link completo**;
    - Abra no navegador do seu computador pessoal;
    - Faça login com `advdouglaspsantos@gmail.com`;
    - Clique em **Continuar / Permitir**;
    - O Google exibirá um código longo de autorização na tela;
    - Copie o código, volte para a tela do VPS e cole em `verification code>`.
11. `Configure this as a Shared Drive?` ➔ Digite `n`
12. `y/e/d>` ➔ Digite `y` _(Yes this is OK)_
13. `e/n/d/r/c/s/q>` ➔ Digite `q` _(Quit)_

Pronto! A pasta `SBJur-Backups/` será criada automaticamente no seu Google Drive.

---

### Passo 4: Configurar o E-mail (Informar a Senha de App)

O instalador perguntará se você quer configurar o e-mail. Quando pedir:

- Remetente/Destinatário: pressione **Enter** para aceitar `advdouglaspsantos@gmail.com`;
- Senha de App: cole a senha de 16 letras gerada no **Passo 1**.

O sistema enviará imediatamente um e-mail de teste para você com o assunto:  
`[SBJur] Teste de Notificacao de Backup - Sucesso!`

---

## 🧪 Como Testar Tudo Imediatamente

Após instalar, rode o comando abaixo para ver o backup sendo gerado, copiado para o Drive e o e-mail chegando na sua caixa de entrada:

```bash
bash /root/sbjur-backups/02-testar-backup.sh
```

O script fará na hora:

1. Extração do banco PostgreSQL via `pg_dump`;
2. Compactação máxima com `gzip`;
3. Cópia para o Google Drive em `SBJur-Backups/diario/`;
4. Envio de e-mail diário com resumo e estatísticas de clientes, processos e tarefas.

---

## 🔬 Teste Mensal de Restauração (Sem Tocar na Produção)

Para ter certeza absoluta de que seus backups são 100% recuperáveis (e não arquivos corrompidos), criamos o script `03-testar-restauracao.sh`.

Ele cria um banco temporário isolado chamado `sbjur_restore_test`, descompacta o backup mais recente nele, compara a contagem de clientes, processos, transações e usuários com a sua produção e apaga o banco de teste ao terminar.

Para rodar uma vez por mês (ou quando quiser):

```bash
bash /root/sbjur-backups/03-testar-restauracao.sh
```

**Resultado exibido na tela:**

```text
Tabela                           | Produção (postgres) | Teste (sbjur_restore_test) | Status
----------------------------------------------------------------------------------------
public.clients                   | 345                 | 345                 | ✅ OK
public.cases                     | 550                 | 550                 | ✅ OK
public.tasks                     | 836                 | 836                 | ✅ OK
public.appointments              | 258                 | 258                 | ✅ OK
public.transactions              | 941                 | 941                 | ✅ OK
public.transaction_cases         | 471                 | 471                 | ✅ OK
auth.users                       | 7                   | 7                   | ✅ OK
========================================================================================
🎉 SUCESSO TOTAL! O TESTE DE RESTAURAÇÃO FOI 100% VALIDADO!
```

---

## 🚨 Restauração de Emergência (Se um dia o VPS for recriado)

Caso um desastre aconteça com o servidor e você precise restaurar o sistema do zero:

1. Baixe o backup mais recente do seu Google Drive (da pasta `SBJur-Backups/diario/`);
2. Ou use o arquivo já existente em `/root/sbjur-backups/diario/`;
3. Execute o comando de restauração no contêiner do banco:

```bash
# 1. Localizar o contêiner do banco
DB_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E 'supa?base.*db' | head -n 1)

# 2. Restaurar o arquivo .sql.gz diretamente no banco de produção
gzip -dc /root/sbjur-backups/diario/sbjur_backup_NOME_DO_ARQUIVO.sql.gz | docker exec -i "$DB_CONTAINER" psql -U postgres -d postgres
```

---

## 🛠️ Comandos Rápidos de Consulta no VPS

| O que você quer fazer?                     | Comando no terminal do VPS                          |
| ------------------------------------------ | --------------------------------------------------- |
| **Ver se o cron das 3h está ativo**        | `crontab -l`                                        |
| **Ver os arquivos de backup locais**       | `ls -lh /root/sbjur-backups/diario/`                |
| **Ver os arquivos salvos no Google Drive** | `rclone lsl gdrive:SBJur-Backups/`                  |
| **Ver o histórico de logs das execuções**  | `tail -n 30 /root/sbjur-backups/logs/backup.log`    |
| **Reconfigurar a senha do e-mail**         | `bash /root/sbjur-backups/04-configurar-email.sh`   |
| **Reconfigurar o Google Drive**            | `rclone config`                                     |
| **Rodar um backup agora**                  | `bash /root/sbjur-backups/02-testar-backup.sh`      |
| **Testar a restauração sem risco**         | `bash /root/sbjur-backups/03-testar-restauracao.sh` |

---

## ✅ Conclusão

Com a conclusão da **Fase 6**, o DPSjur no seu VPS conta com a mesma segurança e redundância de grandes provedores de nuvem, mantendo o custo mensal em **zero** no seu VPS Hostinger já pago até 2027.
