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

## Adendo (2026-11-24): spike `tools/list` (T8)

Rodado no app principal com o login do usuário (`Higgsfield::Mcp::Session`, `bin/rails runner`). Só leitura:
`tools/list`, `models_explore get`, `estimate_*_cost` e `balance`. Nenhum `generate_*`, `media_upload` ou job.
O saldo continuou em 5.734,5 créditos. O servidor expõe 242 ferramentas. Os schemas completos das relevantes,
o retorno de `models_explore get` dos dois modelos e as estimativas estão em
[`006-mcp-tools.json`](006-mcp-tools.json).

### Respostas

1. **`start_image` e `end_image`: sim.** `generate_video_batch` não fixa os papéis
   (`medias[].role`: "Role — varies by model; inspect the selected model's medias[].roles"). Para `kling4_0`,
   `models_explore get` devolve `roles: ["start_image", "end_image", "image_references", "video_references"]`:
   "start_image — Optional first frame; included in the ten-image limit. | end_image — Optional last frame; included
   in the ten-image limit. | image_references — Ordered middle frames in image-to-video; reference images in other
   modes. (array, max 10)". `medias[].value` é o UUID de `media_upload`/`media_import_url` ou o job_id de uma geração
   anterior (útil para encadear o `end_frame` do Nano Banana direto no Kling); URLs https não são aceitas.
   Para `nano_banana_2_1`: `image_references` (máx. 14), `mask`, `video_references`.
2. **Custo: sim.** `estimate_video_cost` e `estimate_image_cost` (`readOnlyHint: true`, "Submits no job") recebem o
   mesmo `params` do `generate_*` e devolvem `cost.credits` e um `quote_ref`. Referência para a T13 (sem medias):
   Kling 4.0 image-to-video 16:9, 10 s, 1080p = **37,5 créditos**; Nano Banana 2.1 4:5, 2k, thinking high = **2 créditos**.
   Não dá para pedir custo dentro do batch (`get_cost` proibido); a estimativa é por item.
3. **Status do `jobs_wait`** (`jobs[].status`): `pending`, `waiting`, `queued`, `dna`, `script`, `visuals`, `vision`,
   `flow`, `in_progress`, `ip_detect` (em andamento); `completed`, `canceled`, `failed`, `nsfw`, `ip_detected`
   (terminais); `lookup_failed` com `retryable` (false = permanente). A resposta traz `all_terminal`,
   `poll_after_seconds`, `summary` e, por job, `result_url`, `thumbnail_url` e `error` (motivo legível em
   failed/nsfw/ip_detected). `timeout_seconds` vai de 0 (snapshot imediato) a 15; aceita até 12 jobs por chamada.
   `job_status` (um job, `sync` opcional) usa a mesma lista de status.
4. **Parâmetros do §4.3: sim, com ressalvas.** No `params` do batch, `aspect_ratio` e `duration` são explícitos; os
   demais são específicos do modelo e entram pelo `additionalProperties`, conforme `models_explore get`:
   - `kling4_0`: `mode` ∈ {text-to-video, image-to-video, reference-to-video, video-edit} (padrão **text-to-video**),
     `resolution` ∈ {720p, 1080p, 4k} (padrão 1080p), `duration` 3–30 s inteiros (padrão 10), `aspect_ratio` ∈
     {21:9, 16:9, 9:16, 1:1, auto}; extras `dynamic_range` (sdr/hdr) e `kling_element_ids`.
   - `nano_banana_2_1`: `resolution` ∈ {1k, 2k, 4k} (padrão **1k**), `thinking_level` ∈ {minimal, medium, high}
     (padrão **medium**), `aspect_ratio` com 4:5, 1:1, 9:16, 16:9 e outros; extras `seed`, `is_inpaint`,
     `enable_web_search`, `enable_image_search`.
   - Os padrões não batem com as receitas: o gateway deve sempre mandar `mode: "image-to-video"`,
     `resolution: "2k"` e `thinking_level: "high"`, como o P4 já define.

### Consequências para a T8b
- `submit` usa `generate_image_batch` / `generate_video_batch` com um item (`count: 1`) e sempre `use_unlim: false`.
  Sem esse campo, o servidor pode devolver `unlim_choice` sem criar o job.
- `status` usa `jobs_wait` com `timeout_seconds: 0` a cada 5 s (ou respeitando `poll_after_seconds`). Terminal de
  sucesso é só `completed`; `canceled`, `failed`, `nsfw`, `ip_detected` e `lookup_failed` com `retryable: false`
  falham o render_step com o `error` em português.
- `cost` usa `estimate_*_cost` (T13). `balance` já é usado no topo.
- Ferramentas a avaliar depois, não usadas agora: `reframe` e `outpaint_image`, para o quadro inicial no aspecto
  final (D6, receita `kling_reference`).
