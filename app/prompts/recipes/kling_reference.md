### 6.2 `kling_reference`: vídeo UGC ou demonstração com o produto consistente

- Steps:
  1. `start_frame`: `nano_banana` se o primeiro quadro for uma cena nova, ou `compose` se for uma foto real
     reenquadrada. **Sempre** no aspecto final (9:16 ou 16:9). Se a foto real tiver outro aspecto, o prompt pede para
     estender as bordas (outpaint) mantendo o conteúdo original no centro.
  2. `main`: `kling`, `mode: image-to-video`, `start_image: step:start_frame`, até 4 `image_references` do produto
     limpo (ex.: catálogo frente e costas), `duration` 5 ou 10, `resolution: 1080p`.
- Exemplo aprovado com ressalvas: §12.2 (V3). As ressalvas viraram regras: quadro inicial no aspecto final e no máximo
  4 beats.
