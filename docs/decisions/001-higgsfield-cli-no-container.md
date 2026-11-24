# 001: Higgsfield CLI dentro do container (spike S1)

> **Substituída pela decisão 006** (Higgsfield via MCP com OAuth). Os custos medidos e o formato dos jobs continuam valendo como referência.

Data: 2026-11-24. Decisões afetadas: D1 e D2 (confirmadas).

## O que foi testado
- `@higgsfield/cli` 1.2.2 instalado via `npm i -g` numa imagem `node:24-slim`.
- Credenciais do host ficam em `~/.config/higgsfield/` (`credentials.json` + `config.json`, com o workspace).
  Montando a pasta em `/root/.config/higgsfield`, `higgsfield account status --json` e
  `higgsfield generate cost ... --json` funcionam dentro do container.
- Sem o pacote `ca-certificates` a CLI falha com `request failed (no response received)`.

## Decisão
- `Dockerfile.dev` instala `ca-certificates` e `@higgsfield/cli`.
- `docker-compose.yml` monta `~/.config/higgsfield` com leitura e escrita (a CLI pode renovar o token).
- O app nunca faz login; só lê `account status`.
- Formato confirmado de `generate list/get --json`: campos `id`, `job_type`, `status` (ex.: `completed`), `result_url`, `min_result_url`, `params`.

## Pendente (vai para a T8)
- Não foi feita geração real neste spike (gasta créditos). Ainda falta confirmar que
  `generate create ... --json` sem `--wait` devolve o job id e quais status intermediários o `generate get` retorna.
  O aceite da T8 já prevê 1 geração real de imagem (cerca de 2 créditos), rodada pelo CTO com aprovação do usuário.
