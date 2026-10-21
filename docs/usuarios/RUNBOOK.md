# DPSjur / SBJur — Runbook: Renomear Colaborador no VPS (Filippini)

Guia prático para Douglas executar no VPS e atualizar o nome do colaborador **Guilherme Filippini** para meramente **Filippini**, eliminando duplicidade interna de identificação com o colaborador **Guilherme Almeida**.

---

## 1. O que este script faz

O script `01-renomear-filippini-vps.sh`:

1. Varre todos os contêineres Docker do VPS filtrando serviços de banco de dados (`db`, `postgres`, `postg`).
2. Identifica com precisão o banco real da aplicação (onde `public.profiles` tem os dados dos colaboradores do escritório).
3. Atualiza `public.profiles` definindo `name = 'Filippini'` para o usuário `guilherme.f.augusto@gmail.com` (id `97971288-d3cf-4d66-a48f-8691ab0b40a4`) de forma idempotente.
4. Atualiza o metadado `raw_user_meta_data->>'name'` em `auth.users` para manter a integridade com o GoTrue/Auth do Supabase self-hosted.
5. Notifica o PostgREST para recarregar o cache (`NOTIFY pgrst, 'reload schema'`).
6. Valida os dados na tela, conferindo que **Filippini** foi renomeado e que **Guilherme Almeida** permaneceu intacto.
7. Exibe um resumo final visual com `[OK]`.

---

## 2. Como executar no VPS (Terminal SSH)

Conecte no VPS como **root**:

```bash
ssh root@2.25.181.69
```

### Comando único recomendado (baixa e executa sem pipe):

```bash
curl -sSL "https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/usuarios/01-renomear-filippini-vps.sh" -o /root/01-renomear-filippini-vps.sh && bash /root/01-renomear-filippini-vps.sh
```

> **Atenção:** Como padrão do ambiente VPS, nunca use `curl ... | bash` direto: o pipe engole o stdin do terminal. O formato `curl ... -o /root/... && bash /root/...` garante execução segura e sem falhas.

---

## 3. Resultado esperado no terminal

O script imprimirá um relatório visual concluindo com:

```text
=====================================================================
                      RESUMO DA ATUALIZAÇÃO
=====================================================================
1. Banco Real: sbjur-local_supabase-db-1 (banco: postgres)
2. Perfil Alterado:
   - ID:    97971288-d3cf-4d66-a48f-8691ab0b40a4
   - Email: guilherme.f.augusto@gmail.com
   - De:    Guilherme Filippini
   - Para:  Filippini [OK]
3. Perfil Preservado:
   - Email: willhelmalmeida@gmail.com
   - Nome:  Guilherme Almeida [OK]
=====================================================================

✅ OPERAÇÃO CONCLUÍDA COM SUCESSO! [OK]
O usuário guilherme.f.augusto@gmail.com agora se chama exclusivamente 'Filippini' no VPS.
Não há mais duplicidade com o colaborador 'Guilherme Almeida'.
```

---

## 4. Conferência no Sistema

1. Abra no navegador: **https://sistema.advdouglaspsantos.com.br**
2. Se necessário, dê `Ctrl + F5` para limpar o cache da página.
3. Nas telas de **Processos**, **Tarefas** e **Agenda**, ao filtrar ou atribuir responsáveis, o usuário aparecerá meramente como **Filippini**, e o outro continuará como **Guilherme Almeida**.
