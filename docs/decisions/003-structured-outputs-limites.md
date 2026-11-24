# 003: Limites de structured outputs (spike S3)

Data: 2026-11-24. Testado: os 5 schemas da §5 enviados ao `anthropic/claude-opus-5.5` pelo OpenRouter
(`/api/v1/messages`, `output_config.format`, esforço `low`).

## Resultado
| Schema | Resultado |
| --- | --- |
| p1_brief | aceito |
| p2_angles | aceito |
| p3_menu | **400**: `Enum value 5 does not match declared type ['integer', 'null']` |
| p4_spec | **400**: `Enum value 'nano_banana_2_1' does not match declared type ['string', 'null']` |
| p5_review | aceito |

- **`type: [X, "null"]` junto com `enum` é rejeitado.** Com `anyOf: [{ type: X, enum: [...sem null] }, { type: "null" }]`,
  p3 e p4 passam (testado).
- **`minItems`, `maxItems` e similares são aceitos, mas NÃO são obedecidos.** Na chamada de teste o P1 voltou com
  0 `features` (mínimo 3) e 0 `audiences` (exatamente 3); o P2 voltou com 1 ângulo (mínimo 4).
  `pattern` e `maxLength` também devem ser tratados como não garantidos.

## Decisão (aprovada pelo CTO, mudança de schema autorizada)
1. Em `app/prompts/schemas/p3_menu.json` e `p4_spec.json`, todo campo com `type` em lista contendo `"null"` e `enum`
   vira `anyOf` como acima, mantendo `description`. Campos afetados: p3 `duration_seconds`; p4 `model`, `params.duration`,
   `params.mode`, `params.thinking_level`. Os demais schemas não mudam.
2. A validação no Ruby com `json_schemer` contra o schema completo é **obrigatória em toda etapa (P1–P5)**, não só no P4.
   Se falhar, a etapa pede de novo ao modelo com a lista de erros, no máximo 2 vezes (mesma regra do P4), e depois
   falha com mensagem em português.
