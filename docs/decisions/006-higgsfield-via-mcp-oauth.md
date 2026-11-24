# 006: Higgsfield via MCP com OAuth (igual ao Cabide)

Data: 2026-11-24. Decisões afetadas: **D1 e D2 (alteradas a pedido do usuário)**. Substitui a decisão 001.

## Mudança
O app **não usa a CLI nem as credenciais do host**. Ele fala com o servidor MCP oficial da Higgsfield
(`https://mcp.higgsfield.ai/mcp`) como cliente MCP, com o mesmo esquema de login do `~/dev/labs/cabide`:

- OAuth 2.1 + PKCE com registro dinâmico de cliente (authorization server `https://higgsfield.ai/_clerk`,
  escopo `openid email offline_access`), feito no navegador pelo botão **"Conectar Higgsfield"**.
- Rotas `GET /higgsfield/connect`, `GET /higgsfield/callback`, `DELETE /higgsfield/connection`.
- Modelo `HiggsfieldConnection` (uma linha; `client_information`, `tokens` com `encrypts`, `pending`, `connected_at`),
  que também é o storage do `MCP::Client::OAuth::Provider`, com renovação do access token e proteção contra corrida na
  rotação do refresh token.
- `Higgsfield::Mcp::Session` (gems `mcp ~> 1.10`, `faraday`, `event_stream_parser`), copiada do Cabide e adaptada.
- Chaves do Active Record Encryption no `.env` (`AR_ENCRYPTION_PRIMARY_KEY`, `AR_ENCRYPTION_DETERMINISTIC_KEY`,
  `AR_ENCRYPTION_KEY_DERIVATION_SALT`); nomes no `.env.example`.
- `HF_MCP_REDIRECT_URI` com padrão `http://localhost:${PORT}/higgsfield/callback` (o Repo2Ad roda na 3001, porque o Cabide usa a 3000).

## O que muda na arquitetura
- `Higgsfield::Gateway` continua (`upload`, `submit`, `status`, `cost`, `balance`). A implementação v1 passa a ser
  `Higgsfield::McpGateway`: `media_upload` → PUT pré-assinado → `media_confirm`; `generate_image_batch` /
  `generate_video_batch` com `medias: [{ value:, role: }]` e `use_unlim: false`; `jobs_wait` com `timeout_seconds: 0`
  para o polling; ferramenta `balance` para o saldo.
- O Docker não instala a CLI `higgsfield` nem o Node e não monta `~/.config/higgsfield`.
- Os comandos da §4.3 do SPEC servem só como referência de parâmetros dos modelos.

## Riscos abertos (spike obrigatório no início da T8)
No Cabide, o MCP só foi provado com `role: "image_references"`. As receitas precisam de quadro inicial e final.
O modelo `kling4_0` tem os parâmetros `start_image` e `end_image` (ver `higgsfield model get`), mas falta confirmar:
1. se `generate_video_batch` aceita `role: "start_image"` e `role: "end_image"` em `medias`;
2. se existe uma ferramenta de estimativa de custo no MCP (para a T13);
3. os status intermediários de `jobs_wait`.
Como confirmar: depois que o usuário conectar a Higgsfield no app, rodar `tools/list` (não gasta créditos) e registrar
os schemas aqui. Se `start_image` / `end_image` não existirem, o CTO decide o plano B antes da T9.
