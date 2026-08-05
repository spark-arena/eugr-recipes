#!/usr/bin/env bash
#
# sync-mirror.sh — pull the mirrored content in from upstream.
#
# Mirrored paths (everything else in this repo is ours):
#   recipes/         <- eugr/spark-vllm-docker  recipes/
#   mods/            <- eugr/spark-vllm-docker  mods/
#   licenses/eugr-spark-vllm-docker-MIT.txt
#                    <- eugr/spark-vllm-docker  LICENSE
#   run-recipe.sh    <- spark-arena/sparkrun     run-recipe.sh
#   licenses/sparkrun-Apache-2.0.txt
#                    <- spark-arena/sparkrun     LICENSE
#
# Idempotent: safe to run repeatedly. It is a *mirror*, not a merge — local
# edits under the mirrored paths are overwritten and upstream deletions are
# propagated (rsync --delete).
#
# `upstream-state.json` is rewritten only when the mirrored content actually
# changed, so an upstream commit that touches nothing we mirror (a Dockerfile
# tweak, say) produces no commit here.
#
# Outputs `changed=true|false` to $GITHUB_OUTPUT when running under Actions,
# and to stdout either way.
#
# Env overrides (for testing against a fork/branch):
#   EUGR_REPO, EUGR_REF, SPARKRUN_REPO, SPARKRUN_REF
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

EUGR_REPO="${EUGR_REPO:-https://github.com/eugr/spark-vllm-docker.git}"
EUGR_REF="${EUGR_REF:-main}"
SPARKRUN_REPO="${SPARKRUN_REPO:-spark-arena/sparkrun}"
SPARKRUN_REF="${SPARKRUN_REF:-main}"

# Paths this script owns. The change check is scoped to exactly these, so
# unrelated dirty state in a local checkout can't masquerade as an upstream
# change. `recipes/README.md` is excluded to match the rsync exclude below —
# it is ours, so editing it is not an upstream sync and must not restamp
# upstream-state.json.
TRACKED=(recipes mods run-recipe.sh licenses ':(exclude)recipes/README.md')

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# curl against the GitHub API/raw host; authenticates when a token is present
# (Actions) and works unauthenticated otherwise (both source repos are public).
fetch() {
    local url="$1" out="$2"
    if [ -n "${GH_TOKEN:-}" ]; then
        curl -fsSL -H "Authorization: Bearer ${GH_TOKEN}" "$url" -o "$out"
    else
        curl -fsSL "$url" -o "$out"
    fi
}

# ---------------------------------------------------------------------------
# 1. eugr/spark-vllm-docker — recipes/ + mods/ (+ LICENSE)
# ---------------------------------------------------------------------------
# Blobless sparse clone: only the recipes/mods trees are materialized. Cone
# mode always checks out root-level files, which is how LICENSE arrives.
git clone --quiet --depth=1 --branch "$EUGR_REF" --filter=blob:none --sparse \
    -- "$EUGR_REPO" "$tmp/eugr"
git -C "$tmp/eugr" sparse-checkout set recipes mods
EUGR_SHA="$(git -C "$tmp/eugr" rev-parse HEAD)"
echo "eugr ${EUGR_REF} @ ${EUGR_SHA}"

for d in recipes mods; do
    if [ ! -d "$tmp/eugr/$d" ]; then
        echo "error: upstream ${EUGR_REPO} has no ${d}/ — refusing to wipe the mirror" >&2
        exit 1
    fi
    mkdir -p "$d"

    # `recipes/README.md` is OURS, not mirrored: upstream's documents --discover /
    # --setup / --apply-mod and the build-and-copy.sh + launch-cluster.sh pipeline,
    # none of which exist under sparkrun. The exclude is anchored (`/README.md`) so
    # a nested one — recipes/3x-spark-cluster/README.md, say — still mirrors, and
    # rsync leaves excluded files on the receiving side alone despite --delete.
    # `mods/` has no such override, so an upstream mods/README.md would mirror.
    excludes=()
    [ "$d" = "recipes" ] && excludes=(--exclude=/README.md)

    rsync -a --delete "${excludes[@]+"${excludes[@]}"}" "$tmp/eugr/$d/" "$d/"
done

mkdir -p licenses
cp "$tmp/eugr/LICENSE" licenses/eugr-spark-vllm-docker-MIT.txt

# ---------------------------------------------------------------------------
# 2. spark-arena/sparkrun — run-recipe.sh (+ LICENSE)
# ---------------------------------------------------------------------------
# Resolve the ref to a commit first, then fetch the blobs pinned to that
# commit: `raw.githubusercontent.com/<repo>/<branch>/...` is CDN-cached and
# could otherwise hand back content from a different commit than the sha we
# record.
fetch "https://api.github.com/repos/${SPARKRUN_REPO}/commits/${SPARKRUN_REF}" "$tmp/sparkrun-commit.json"
SPARKRUN_SHA="$(jq -r '.sha' "$tmp/sparkrun-commit.json")"
if [ -z "$SPARKRUN_SHA" ] || [ "$SPARKRUN_SHA" = "null" ]; then
    echo "error: could not resolve ${SPARKRUN_REPO}@${SPARKRUN_REF} to a commit" >&2
    exit 1
fi
echo "sparkrun ${SPARKRUN_REF} @ ${SPARKRUN_SHA}"

RAW="https://raw.githubusercontent.com/${SPARKRUN_REPO}/${SPARKRUN_SHA}"
fetch "${RAW}/run-recipe.sh" "$tmp/run-recipe.sh"
fetch "${RAW}/LICENSE" "$tmp/sparkrun-LICENSE"

# Sanity-check before overwriting: a proxy error page or an empty body must not
# be published as the shim.
if ! head -1 "$tmp/run-recipe.sh" | grep -q '^#!/usr/bin/env bash'; then
    echo "error: fetched run-recipe.sh does not look like a bash script — aborting" >&2
    exit 1
fi
install -m 0755 "$tmp/run-recipe.sh" run-recipe.sh
cp "$tmp/sparkrun-LICENSE" licenses/sparkrun-Apache-2.0.txt

# ---------------------------------------------------------------------------
# 3. Did anything we mirror actually change?
# ---------------------------------------------------------------------------
CHANGED=false
if [ -n "$(git status --porcelain -- "${TRACKED[@]}")" ]; then
    CHANGED=true
fi

if [ "$CHANGED" = "true" ]; then
    jq -n \
        --arg eugr_repo "$EUGR_REPO" \
        --arg eugr_ref "$EUGR_REF" \
        --arg eugr_commit "$EUGR_SHA" \
        --arg sparkrun_repo "$SPARKRUN_REPO" \
        --arg sparkrun_ref "$SPARKRUN_REF" \
        --arg sparkrun_commit "$SPARKRUN_SHA" \
        --arg synced_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{eugr_repo: $eugr_repo, eugr_ref: $eugr_ref, eugr_commit: $eugr_commit,
          sparkrun_repo: $sparkrun_repo, sparkrun_ref: $sparkrun_ref,
          sparkrun_commit: $sparkrun_commit, synced_at: $synced_at}' \
        > upstream-state.json
    echo "Mirrored content changed:"
    git status --short -- "${TRACKED[@]}" upstream-state.json
else
    echo "Mirrored content unchanged — upstream-state.json left alone."
fi

echo "changed=${CHANGED}"
{
    echo "changed=${CHANGED}"
    echo "eugr_commit=${EUGR_SHA}"
    echo "sparkrun_commit=${SPARKRUN_SHA}"
} >> "${GITHUB_OUTPUT:-/dev/null}"
