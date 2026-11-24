# Repo2Ad

Transforma um repositório público do GitHub em criativos de anúncio. Especificação completa em [SPEC.md](SPEC.md).

## Rodar em desenvolvimento (Docker é o ambiente oficial)

```bash
docker compose up --build   # web em http://localhost:3000 (Solid Queue roda dentro do Puma) + watcher do Tailwind
docker compose run --rm web bin/rails test
```

O container traz libvips + libheif, ffmpeg e a CLI `higgsfield`. O login da Higgsfield é feito uma vez no host
(`higgsfield auth login`) e montado no container a partir de `~/.config/higgsfield`.
