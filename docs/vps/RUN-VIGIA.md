# Vigia Automático (Watchdog) do Supabase Self-Hosted no VPS

Este documento explica como instalar, testar, monitorar e desinstalar o **vigia automático** criado para monitorar e manter no ar os contêineres do Supabase self-hosted no VPS Hostinger KVM 1 (EasyPanel: projeto `sbjur-local`, serviço `supabase`).

---

## 1. Contexto e Motivação

No incidente recente, o contêiner `sbjur-local_supabase-kong-1` sofreu uma queda abrupta (`Exited (128)`), deixando todo o tráfego do backend (PostgREST, Auth/GoTrue e Edge Functions) inacessível por horas até a intervenção manual.

O VPS opera com recursos enxutos (3,8 GB de RAM) compartilhados entre o frontend (`dpsjur`) e o stack do Supabase (`sbjur-local`). O vigia atua a cada **1 minuto** via Cron do sistema para detectar qualquer contêiner do Supabase que não esteja no estado `running` e religá-lo de forma imediata (`docker start`).

---

## 2. O que o Vigia Faz e Como Funciona

- **Monitoramento contínuo:** A cada 60 segundos via agendamento em `/etc/cron.d/vigia-supabase`.
- **Detecção dinâmica:** Lista os contêineres do prefixo `sbjur-local_supabase` (incluindo `kong`, `functions`, `auth`, `rest`, `db`, `storage`, `studio`, `realtime`, `supavisor`, `meta`, `vector`, `imgproxy`).
- **Recuperação automática:** Se um contêiner existir mas estiver parado (`Exited (128)`, `Exited (137)`, `Exited (0)`, etc.), executa `docker start <nome>`.
- **Registro histórico:** Registra no log `/var/log/vigia-supabase.log` a data, hora, nome do contêiner e o status anterior da queda.
- **Proteção contra sobreposição:** Usa lock de execução (`flock`) para evitar corridas se uma checagem demorar.
- **Controle de log:** Rotação e truncagem automática quando o arquivo de log ultrapassa ~5 MB, mantendo sempre o histórico recente sem encher o disco.
- **Idempotente:** Pode ser executado múltiplas vezes sem duplicar entradas no cron.

> ⚠️ **Limitação Importante e Honesta:**  
> O vigia reinicia contêineres **existentes** via `docker start`. Se um contêiner for completamente **removido ou apagado** (`docker rm`), a recriação das portas e redes virtuais continua sendo atribuição do EasyPanel (botão **Implantar** no painel web ou recriação do serviço). O vigia registrará no log um aviso de que o contêiner está ausente, mas nunca tentará inventar comandos de `docker run`, preservando a consistência do EasyPanel.

---

## 3. Como Instalar no VPS

Acesse o terminal do VPS via SSH como `root`:

```bash
ssh root@2.25.181.69
```

Baixe e execute o script instalador:

```bash
curl -fsSL https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/vps/01-instalar-vigia.sh -o /root/01-instalar-vigia.sh && bash /root/01-instalar-vigia.sh
```

O instalador irá:

1. Criar o script mestre em `/root/vigia-supabase.sh` com permissões `755`.
2. Criar a entrada no cron em `/etc/cron.d/vigia-supabase`.
3. Criar `/var/log/vigia-supabase.log`.
4. Executar uma rodada inicial de verificação para validar o funcionamento.

---

## 4. Como Testar o Vigia

Para confirmar com 100% de segurança que o vigia realmente ressuscita contêineres caídos:

Baixe e execute o script de teste:

```bash
curl -fsSL https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/vps/02-testar-vigia.sh -o /root/02-testar-vigia.sh && bash /root/02-testar-vigia.sh
```

**O que este teste faz:**

1. Identifica o contêiner do Kong (`sbjur-local_supabase-kong-1`);
2. Para o contêiner propositalmente com `docker stop`;
3. Aguarda até 75 segundos pelo ciclo do vigia;
4. Mostra na tela a recuperação do contêiner voltando a `running`;
5. Imprime o trecho do log `/var/log/vigia-supabase.log` que comprova a intervenção automática.

---

## 5. Como Monitorar e Acompanhar o Log

Para acompanhar o vigia em tempo real pelo terminal:

```bash
tail -f /var/log/vigia-supabase.log
```

Para ver as últimas 50 linhas:

```bash
tail -n 50 /var/log/vigia-supabase.log
```

### Exemplos de saídas do log:

- **Operação normal (tudo OK):**

  ```text
  [2026-10-17 10:00:01] [VIGIA-OK] Todos os servicos Supabase estao saudaveis e operantes.
  ```

- **Queda detectada e resolvida com sucesso:**

  ```text
  [2026-10-17 10:01:02] [VIGIA-ALERTA] Conteiner 'sbjur-local_supabase-kong-1' NAO esta Up! Status anterior: 'Exited (128) 2 minutes ago' (State: exited). Tentando 'docker start'...
  [2026-10-17 10:01:03] [VIGIA-SUCESSO] Conteiner 'sbjur-local_supabase-kong-1' reiniciado com sucesso via 'docker start'.
  ```

- **Contêiner ausente / removido do Docker:**
  ```text
  [2026-10-17 10:02:01] [VIGIA-AVISO] Componente 'kong' ausente no Docker (nenhum conteiner 'sbjur-local_supabase*kong*' encontrado). Recriacao depende do EasyPanel.
  ```

---

## 6. Como Desinstalar o Vigia (se necessário)

Se em algum momento quiser remover o vigia do VPS, execute:

```bash
rm -f /etc/cron.d/vigia-supabase
rm -f /root/vigia-supabase.sh
rm -f /root/01-instalar-vigia.sh
rm -f /root/02-testar-vigia.sh
```

O log `/var/log/vigia-supabase.log` pode ser mantido para histórico ou removido com `rm -f /var/log/vigia-supabase.log`.
