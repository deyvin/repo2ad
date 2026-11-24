# Repo2Ad

Transforma um repositório público do GitHub em criativos de anúncio. Especificação completa em [SPEC.md](SPEC.md).

## Rodar em desenvolvimento (Docker é o ambiente oficial)

```bash
docker compose up --build   # web em http://localhost:3001 (Solid Queue roda dentro do Puma) + watcher do Tailwind
docker compose run --rm web bin/rails test
```

Copie `.env.example` para `.env` e preencha (o `.env` nunca é commitado). O container traz libvips + libheif e ffmpeg.
A Higgsfield é usada via MCP: o login é feito no próprio app, pelo botão "Conectar Higgsfield" (OAuth).
A porta padrão é a 3001 (o Cabide usa a 3000); para outra, use `PORT=3002 docker compose up`.
