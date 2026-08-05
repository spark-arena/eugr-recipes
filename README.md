# eugr-recipes

Automated **mirror** of the recipes and mods from
[eugr/spark-vllm-docker](https://github.com/eugr/spark-vllm-docker), packaged as a
[sparkrun](https://github.com/spark-arena/sparkrun) recipe registry.

This repo is the **official mirror for eugr's recipes** — it is the `eugr` registry that
sparkrun resolves `@eugr/<recipe>` against. Mirroring (rather than pointing sparkrun
directly at the upstream repo) means:

- sparkrun clones a ~2 MB registry instead of sparse-checking-out a repo whose primary
  content is a multi-megabyte container build,
- the registry layout (`.sparkrun/registry.yaml`) is ours to declare without asking
  upstream to carry sparkrun metadata,
- every sync is a commit here, so the registry has a reviewable history and a pinnable
  state independent of upstream's.

**Nothing in `recipes/` or `mods/` is authored here.** Fixes belong upstream in
[eugr/spark-vllm-docker](https://github.com/eugr/spark-vllm-docker); this mirror will
overwrite local edits on its next sync.

## Contents

| Path                     | Source                                              |
|--------------------------|-----------------------------------------------------|
| `recipes/`               | `eugr/spark-vllm-docker` → `recipes/` (verbatim)     |
| `mods/`                  | `eugr/spark-vllm-docker` → `mods/` (verbatim)        |
| `run-recipe.sh`          | `spark-arena/sparkrun` (`main`) → `run-recipe.sh`    |
| `licenses/`              | Upstream license texts, synced alongside the content |
| `.sparkrun/registry.yaml`| Ours — the registry manifest                          |
| `upstream-state.json`    | Provenance: the commits each sync mirrored from       |

`run-recipe.sh` is sparkrun's `spark-vllm-docker` compatibility shim: it accepts the
legacy `run-recipe.py`/`run-recipe.sh` CLI surface and performs the work through
`sparkrun`. It lives here so a recipe mirrored from upstream can be run with upstream's
command line, from this checkout:

```bash
git clone https://github.com/spark-arena/eugr-recipes.git
cd eugr-recipes
./run-recipe.sh qwen3.6-35b-a3b-fp8 --tp 2
```

The shim resolves `sparkrun` from `.venv/bin/sparkrun`, then `PATH`, then `uv tool run
sparkrun` — so it works in this checkout without installing anything first. Run
`sparkrun run --help` for the full native option set; the shim's header documents where
it intentionally deviates from the legacy tool.

## Using it as a registry

The `eugr` registry ships as a sparkrun default, so normally there is nothing to add:

```bash
sparkrun list @eugr             # list the mirrored recipes
sparkrun run @eugr/qwen3.6-35b-a3b-fp8 --tp 2
```

To add or re-point it manually:

```bash
sparkrun registry add https://github.com/spark-arena/eugr-recipes.git
```

Recipes under `recipes/3x-spark-cluster/` and `recipes/4x-spark-cluster/` are node-count
variants; sparkrun's registry scan recurses, so they resolve by name and are
path-qualified (`@eugr/3x-spark-cluster/<name>`) when a name is ambiguous.

## How the sync works

[`.github/workflows/mirror.yml`](.github/workflows/mirror.yml) runs
[`scripts/sync-mirror.sh`](scripts/sync-mirror.sh) **hourly** (and on
`workflow_dispatch`). The script:

1. Blobless sparse-clones `eugr/spark-vllm-docker@main` and `rsync -a --delete`s
   `recipes/` and `mods/` into place — so upstream deletions propagate.
2. Resolves `spark-arena/sparkrun@main` to a commit sha, then fetches `run-recipe.sh`
   **pinned to that sha** (the branch-named raw URL is CDN-cached and can serve content
   from a different commit than the sha being recorded), and sanity-checks the shebang
   before overwriting.
3. Commits only if the mirrored paths actually changed. `upstream-state.json` is
   rewritten in the same breath, so an upstream commit that touches nothing we mirror
   produces no commit here.

The script is the whole sync — run it locally to reproduce or backfill:

```bash
./scripts/sync-mirror.sh          # prints changed=true|false
EUGR_REF=some-branch ./scripts/sync-mirror.sh
```

## Licensing

Mirrored content keeps its upstream license; this repo adds no original code beyond the
sync tooling and the registry manifest.

- `recipes/`, `mods/` — MIT, © Eugene Rakhmatulin
  ([`licenses/eugr-spark-vllm-docker-MIT.txt`](licenses/eugr-spark-vllm-docker-MIT.txt))
- `run-recipe.sh` — Apache-2.0, from sparkrun
  ([`licenses/sparkrun-Apache-2.0.txt`](licenses/sparkrun-Apache-2.0.txt))
