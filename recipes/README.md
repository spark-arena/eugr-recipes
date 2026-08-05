# Recipes

## Quick start

```bash
sparkrun list @eugr                              # every recipe in this registry
sparkrun show @eugr/glm-4.7-flash-awq             # resolved plan + VRAM estimate
sparkrun run  @eugr/glm-4.7-flash-awq             # launch
sparkrun run  @eugr/qwen3.6-35b-a3b-fp8 --tp 2    # 2-way TP = 2 hosts on DGX Spark

sparkrun logs @eugr/qwen3.6-35b-a3b-fp8           # re-attach (Ctrl+C detaches, doesn't stop)
sparkrun stop @eugr/qwen3.6-35b-a3b-fp8
sparkrun status
```

Nothing needs to be cloned or built first — sparkrun syncs the model and the image to your
hosts as part of `run`. The `@eugr/` scope is only needed to disambiguate; a bare
`glm-4.7-flash-awq` resolves here too.

## Legacy CLI: `run-recipe.sh`

[`../run-recipe.sh`](../run-recipe.sh) is sparkrun's `spark-vllm-docker` compatibility shim
— upstream's command line, sparkrun underneath:

```bash
./run-recipe.sh glm-4.7-flash-awq --solo
./run-recipe.sh qwen3.6-35b-a3b-fp8 -n 192.168.1.10,192.168.1.11
./run-recipe.sh --list
```

It resolves `sparkrun` from `.venv/bin/sparkrun`, then `PATH`, then `uv tool run sparkrun`,
so it works without installing anything first. Foreground is the default; `-d`/`--daemon`
detaches.

| Upstream flag | Under the shim |
|---|---|
| `--port`, `--host`, `--tp`, `--gpu-mem`, `--max-model-len` | mapped to the native equivalent |
| `-n/--nodes`, `-t/--container`, `--name`, `--master-port`/`--head-port` | mapped |
| `-e/--env`, `--nccl-debug`, `-v/--volume`, `-p/--publish` (solo only) | mapped via `--executor-args` |
| `--non-privileged`, `--mem-limit-gb`, `--mem-swap-limit-gb`, `--shm-size-gb`, `--pids-limit` | mapped |
| `--solo`, `--ray`, `--no-ray`, `-d/--daemon`, `--dry-run`, `-l/--list` | mapped |
| `--config <.env>` | imported as a sparkrun cluster, and the run is retargeted at it |
| `--setup` | **no-op** — images and models sync automatically during `run` |
| `--discover`, `--show-env` | **error** → `sparkrun setup wizard` / `sparkrun cluster show` |
| `--build-only`, `--download-only`, `--force-build`, `--force-download`, `-j` | **error** — no isolated build/download phase |
| `--apply-mod`, `--eth-if`, `--ib-if`, `--keep-entrypoint`, `--no-cache-dirs`, `--earlyoom` | **error** — see the shim's header for why |

Two behavioral differences worth knowing: `--list` lists sparkrun *registry* recipes rather
than a local directory, and engine passthrough after `--` becomes `-o key=value` rather than
being appended verbatim, so it only takes effect for recipe-templated or known engine keys.
`sparkrun run --help` is the full native surface.

## How sparkrun reads these recipes

They are **v1** (`recipe_version: "1"`) recipes; sparkrun runs them natively rather than
converting them.

| In the recipe | What sparkrun does |
|---|---|
| `recipe_version: "1"` | routes to the **`eugr` builder** (unless the recipe names a builder) |
| `command:` containing `--distributed-executor-backend ray` | runtime `vllm-ray`; otherwise `vllm-distributed` |
| `container: vllm-node` | **pull-first**: reused if already present, else substituted with `ghcr.io/spark-arena/dgx-vllm-eugr-nightly:latest` and pulled. Nothing is built unless `build_args` requests it |
| `mods:` | each mod is `docker cp`'d in and its `run.sh` executed as a `pre_exec` hook (2 hook entries per mod) |
| `build_args:` | forwarded verbatim to upstream's `build-and-copy.sh` **only on the build path** — triggered by `--use-wheels` or a custom build flag (`--vllm-ref`, `--exp-mxfp4`, …). `--exp-b12x` selects the b12x nightly *without* forcing a build |
| `cluster_only: true` | `min_nodes: 2` |
| `solo_only: true` | `max_nodes: 1` |
| `defaults:` | the config chain — **CLI → recipe defaults → runtime defaults**. Override anything with `-o key=value` |
| `{placeholder}` in `command:` | substituted from that chain; `{{`/`}}` escape literal braces for JSON-valued flags |

So `--setup`, `--build-only` and `--force-build` have no counterpart by design: there is no
separate build/download phase to run, and the image is normally pulled rather than built.
`sparkrun run --rebuild` is the closest equivalent — it forces a fresh pull (or a
from-scratch rebuild on the build path).

### Mods run without prompting here

Mods are `pre_exec` hooks, i.e. code execution, so sparkrun gates them on **per-registry
trust** — a local decision in your `~/.config/sparkrun/registries.yaml`; a registry manifest
cannot grant itself trust. `eugr` ships as a trusted sparkrun default, so mods just run. If
you added this registry by hand, opt in with `sparkrun registry trust eugr` (or
`sparkrun registry add --trust <url>`), or pass `sparkrun run --trust` per launch.

### Cluster-size variants

`3x-spark-cluster/` and `4x-spark-cluster/` hold node-count variants. The registry scan is
recursive and a flat `recipes/<name>.yaml` wins over a nested one *within* this registry, so
reach a nested variant explicitly when a stem exists in both:

```bash
sparkrun run @eugr/3x-spark-cluster/qwen3.5-397b-int4-autoround
```

Any name matching more than one recipe raises an error listing the path-qualified names
rather than guessing (or offers a numbered prompt on a TTY).

## Writing your own

You can save your recipes to local yaml files, create a git repo and share them,
or you can submit a PR to the [community registry](https://github.com/spark-arena/community-recipe-registry) and share them
that way. You can also publish benchmarks to [Spark Arena](https://spark-arena.com).

The recipes in this repo are in the v1 (original) recipe format. New recipes should use v2 format if possible.

References:

- [Recipe format reference](https://sparkrun.dev/recipes/format/) ([`RECIPES.md`](https://github.com/spark-arena/sparkrun/blob/main/RECIPES.md))
- [Writing recipes](https://sparkrun.dev/recipes/writing-recipes/)
- [Registries](https://sparkrun.dev/recipes/registries/) 
- [Builders](https://sparkrun.dev/developer-reference/builders/) 
- [`sparkrun run`](https://sparkrun.dev/cli/run/)
