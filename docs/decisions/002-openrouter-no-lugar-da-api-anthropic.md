# 002: Raciocínio via OpenRouter (spike S2)

Data: 2026-11-24. Decisão afetada: **D3 (alterada a pedido do usuário)**.

## Mudança
P1–P5 usam o **OpenRouter** no lugar da API direta da Anthropic. O OpenRouter expõe o formato Anthropic Messages em
`POST https://openrouter.ai/api/v1/messages` (auth `Authorization: Bearer <OPENROUTER_API_KEY>`), com suporte a
`output_config.effort`, `output_config.format` (`json_schema`), `cache_control`, blocos de imagem e `fallbacks`.

## Como chamar (substitui o snippet da §4.2)
- Continua a gem oficial **`anthropic`** (2.13.0 verificada no código-fonte: aceita `base_url:`, `auth_token:` e
  `request_options: { extra_body: ... }`).
- Cliente: `Anthropic::Client.new(auth_token: ENV.fetch("OPENROUTER_API_KEY"), base_url: "https://openrouter.ai/api")`.
- Modelo: `"anthropic/claude-opus-5.5"` (no OpenRouter: contexto de 1M, imagem, `structured_outputs`, esforço obrigatório,
  padrão `high`; US$ 4 / US$ 20 por milhão de tokens de entrada/saída).
- Usar `client.messages.create` (não `beta`), sem `betas:`.
- `fallbacks` no OpenRouter é uma **lista** de até 3 `{ model: }`, não a string `"default"`. Usar
  `request_options: { extra_body: { fallbacks: [{ model: "anthropic/claude-opus-5" }] } }`.
- A chave fica só no `.env` (nunca commitado); o compose a injeta via `env_file`.

## Diferenças em relação ao spec
- **Não existe `count_tokens` no OpenRouter** (`/api/v1/messages/count_tokens` retorna 404). O `Repo::Selector` estima
  tokens localmente: `(bytes / 3.5).ceil`, com orçamento de 120 mil. Determinístico, sem rede, testável.
- Os provedores por trás variam (Anthropic, Vertex, Bedrock, Azure); a resposta vem no formato Anthropic.

## Verificar na T4 (Rubyson)
- Caminho final da URL montado pela gem (`base_url` + `/v1/messages`) com uma chamada real gravada.
- `stop_reason: "refusal"` e blocos de imagem base64 passando pelo OpenRouter.
