# 004: Custo de referência por criativo (spike S4)

Data: 2026-11-24. Medido com `higgsfield generate cost ... --json` (não gasta créditos). Saldo da conta no teste: 5.734,5 créditos.

| Modelo | Parâmetros | Créditos |
| --- | --- | --- |
| nano_banana_2_1 | 4:5, 2k, thinking_level high | 2 |
| nano_banana_2_1 | 16:9, 4k | 3 |
| kling4_0 | 16:9, 1080p, 5 s (text-to-video) | 18,75 |
| kling4_0 | 16:9, 1080p, 10 s (text-to-video) | 37,5 |

Estimativa por receita (para a T13):
- `nb_image`: cerca de 2.
- `kling_reference` / `kling_magic` 10 s: cerca de 39,5 (quadro inicial com Nano Banana + Kling); cerca de 37,5 se o quadro inicial for `compose`.
- `kling_keyframes` 10 s: cerca de 39,5 (compose local + quadro final com Nano Banana + Kling).

Image-to-video foi estimado como text-to-video. A T13 deve sempre chamar `generate cost` com os parâmetros reais antes de
gerar, em vez de usar esta tabela fixa.
