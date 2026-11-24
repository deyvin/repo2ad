### 6.1 `nb_image`: imagem estática

- Steps: `main` (`nano_banana`). Até 8 `image_references` (fotos reais, screenshots, catálogo).
- Params: `aspect_ratio` do item, `resolution: 2k`, `thinking_level: high`.
- Pré-processamento: toda referência passa por `Media::Normalizer` (HEIC→JPEG, EXIF aplicado, máx. 2048 px).
- Exemplo aprovado: §12.1 (I1, antes/depois).
