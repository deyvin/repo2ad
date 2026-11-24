# Repo2Ad

Transforma um repositório público do GitHub em criativos de anúncio. Especificação completa em [SPEC.md](SPEC.md).

## Rodar em desenvolvimento (Docker é o ambiente oficial)

```bash
docker compose up --build   # web em http://localhost:3000 (Solid Queue roda dentro do Puma) + watcher do Tailwind
docker compose run --rm web bin/rails test
```

Copie `.env.example` para `.env` e preencha (o `.env` nunca é commitado). O container traz libvips + libheif e ffmpeg.
A Higgsfield é usada via MCP: o login é feito no próprio app, pelo botão "Conectar Higgsfield" (OAuth).
Se a porta 3000 estiver ocupada, use `PORT=3001 docker compose up`.
