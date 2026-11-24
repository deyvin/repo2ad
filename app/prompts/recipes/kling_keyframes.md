### 6.4 `kling_keyframes`: motion graphics SaaS (quadro inicial → quadro final)

- Steps:
  1. `start_frame`: `compose` (screenshots reais em moldura de navegador ou celular, sobre a cor de fundo da marca).
  2. `end_frame`: `nano_banana`, o cartão final (dispositivo com o produto à esquerda; wordmark, tagline e botão de CTA
     com cursor à direita), no mesmo aspecto.
  3. `main`: `kling`, `mode: image-to-video`, `start_image: step:start_frame`, `end_image: step:end_frame`, 10 s.
- **`Frames::Composer` (ruby-vips)** implementa o `compose_plan`:
  - Canvas 2752×1536 (16:9), 1536×2752 (9:16), 2048×2560 (4:5) ou 2048×2048 (1:1), preenchido com `background_hex`.
  - `frame: browser`: barra de 64 px com os três círculos (#ff5f57, #febc2e, #28c840), campo de URL arredondado,
    cantos de 22 px e sombra (blur 40, deslocamento y 30, opacidade ~27%).
  - `frame: print`: borda branca de 26 px, sombra mais curta, rotação `rotation_deg`.
  - `frame: phone`: moldura preta arredondada com notch (versão simples; o CTO decide se vale um PNG de mockup).
  - `crop_top_pct`: corta o screenshot para mostrar só o topo, sem cortar uma linha de texto ao meio. O composer
    ajusta o corte para a linha em branco mais próxima.
  - Cursor opcional desenhado como polígono preto com contorno branco, posicionado pelo P4 (adicione
    `cursor_x_pct`/`cursor_y_pct` ao schema se o CTO aprovar).
- Exemplo aprovado: §12.3 (H1).
