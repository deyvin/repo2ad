# 007: Semântica das camadas do compose_plan

Data: 2026-11-24. Afeta: §5.5 (schema p4_spec) e §6.4 (`Frames::Composer`). O SPEC define os campos, mas não o que cada número significa.

## Decisão (implementada na T7, `c3f7958`)
- `x_pct`, `y_pct`: canto superior esquerdo da moldura (sem rotação e sem sombra), em % da largura e da altura do canvas.
- `width_pct`: largura da moldura em % da largura do canvas. A altura segue a proporção da mídia depois do corte.
- `rotation_deg`: graus no sentido horário, como no CSS, em volta do centro da moldura. Negativo inclina para a esquerda (o H1 usa −7).
- `crop_top_pct`: % da altura da mídia mantida a partir do topo. 0 ou 100 = sem corte. O corte vai para a linha em
  branco mais próxima (desvio padrão ≤ 3) num raio de 8% da altura, para não partir texto.
- Moldura `phone` e cursor: fora do v1 por enquanto (dão erro claro).

## Consequência para o P4
O modelo precisa saber dessas regras para gerar planos corretos. Na T9, adicionar `description` em pt-BR a esses
5 campos em `app/prompts/schemas/p4_spec.json`, com o texto acima. É uma mudança só de descrição, aprovada pelo CTO;
os tipos e os campos não mudam. Conferir de novo no OpenRouter que o schema continua aceito.
