# compile_docs.sh

Documentation site generator using MkDocs Material.

## Overview

Builds the static documentation website from the Markdown files in the `doc/` directory using mkdocs-material. Replaces the previous pasdoc-based HTML generation.

## Dependencies

- Python 3
- `mkdocs-material` (installed automatically if missing)

## Behavior

1. Checks whether `mkdocs` is available on the `PATH`.
2. If not found, installs `mkdocs-material` via pip.
3. Runs `mkdocs build --strict` to generate the static site.
4. Output is written to the `site/` directory at the project root.

## Docker Usage

The documentation site can also be built and served via Docker Compose:

```bash
# Live development server with hot-reload
docker compose up docs

# Static build only
docker compose run docs build --strict
```

The development server listens on `http://localhost:8000`.

## Configuration

The site is configured by `mkdocs.yml` in the project root. The navigation structure mirrors the `doc/` directory hierarchy.
