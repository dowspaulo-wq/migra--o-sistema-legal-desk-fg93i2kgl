# docs/vps/tests/ — Suíte de testes negativos (v1.6.0)

Utilitários de suporte à auditoria de backup (DPSjur/SBJur), criados na rodada
v1.9.0 do `docs/vps/20-auditar-backup.sh` e mantidos fora dos commits autorizados
pelo usuário (o usuário autorizou commits contendo somente o script 20).

- `testes-negativos-json.sh` — testes negativos dos validadores jq do
  inventário (JSONs malformados/parciais DEVEM ser rejeitados). Executar em
  ambiente com Bash (WSL2 de Douglas): `bash docs/vps/tests/testes-negativos-json.sh`.
- `executar-testes-negativos.mjs` — runner em Node para o mesmo suíte,
  para ambientes sem Bash.

Futuro: decidir com Douglas se esta pasta é limpa ou commitada em rodada futura
(pendente registrado desde a rodada v1.9.0).
