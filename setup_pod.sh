#!/usr/bin/env bash
# setup_pod.sh — re-establish pod-local state on a fresh RunPod after attaching
# the agentpoison-vol network volume at /workspace.
#
# What this does NOT do: install packages, download data, or touch the volume's
# contents. Everything real (repos, conda env, .env, data) already persists on
# /workspace. This only fixes the pod-local shell/git state that resets per pod.
#
# Usage:
#   bash /workspace/setup_pod.sh
# then, to pick up conda in your CURRENT shell:
#   source /workspace/setup_pod.sh        (instead of bash, so the env activates here)

set -u

VOL=/workspace
REPOS=("$VOL/AgentPoison" "$VOL/tier-stratified-provenance")
CONDA_SH="$VOL/miniconda3/etc/profile.d/conda.sh"
ENV_NAME=agentpoison

# ---- 0. sanity: is the volume actually mounted with our work? -------------
echo "== verifying volume =="
if [ ! -d "$VOL/AgentPoison" ] || [ ! -d "$VOL/tier-stratified-provenance" ]; then
  echo "!! /workspace is missing the repos. Is agentpoison-vol attached at /workspace?"
  df -h "$VOL" 2>/dev/null
  return 1 2>/dev/null || exit 1
fi
df -h "$VOL" | tail -1
echo

# ---- 1. conda: init for this shell + activate the env ---------------------
echo "== conda =="
if [ -f "$CONDA_SH" ]; then
  # shellcheck disable=SC1090
  source "$CONDA_SH"
  conda activate "$ENV_NAME" && echo "activated env: $ENV_NAME ($(python --version 2>&1))" \
    || echo "!! could not activate $ENV_NAME (env on volume but activate failed)"
else
  echo "!! $CONDA_SH not found — conda not on volume where expected"
fi
echo

# ---- 2. git: mark volume repos safe (fresh pod = different file ownership) -
echo "== git safe.directory =="
for r in "${REPOS[@]}"; do
  git config --global --add safe.directory "$r"
  echo "  marked safe: $r"
done
echo

# ---- 3. git identity (does not persist across pods) -----------------------
echo "== git identity =="
# EDIT THESE TWO LINES to your details (kept here so the script is self-contained):
GIT_USER_NAME="Harry Staley"
GIT_USER_EMAIL="REPLACE_WITH_YOUR_GITHUB_EMAIL"
git config --global user.name  "$GIT_USER_NAME"
git config --global user.email "$GIT_USER_EMAIL"
echo "  user.name  = $(git config --global user.name)"
echo "  user.email = $(git config --global user.email)"
if [ "$GIT_USER_EMAIL" = "REPLACE_WITH_YOUR_GITHUB_EMAIL" ]; then
  echo "  !! edit GIT_USER_EMAIL in this script (currently a placeholder)"
fi
echo

# ---- 4. git auth helper (so HTTPS pushes can cache a PAT) ------------------
# Harmless if you use SSH remotes. Stores credentials under $HOME on first push.
git config --global credential.helper store
echo "== git credential helper: store (PAT cached on first HTTPS push) =="
echo

# ---- 5. report remotes + branch state for both repos ----------------------
echo "== repo status =="
for r in "${REPOS[@]}"; do
  echo "--- $r ---"
  git -C "$r" remote -v | sed 's/^/  /'
  git -C "$r" status -sb | head -1 | sed 's/^/  /'
done
echo

# ---- 6. load .env into THIS shell if present (OPENAI_API_KEY, HF_TOKEN) ----
echo "== .env =="
if [ -f "$VOL/.env" ]; then
  set -a; # shellcheck disable=SC1091
  source "$VOL/.env"; set +a
  echo "  sourced $VOL/.env (keys now in this shell's environment)"
else
  echo "  no $VOL/.env found (skip)"
fi
echo

echo "== done. If you ran with 'bash', conda is NOT active in your shell."
echo "   Re-run with:  source /workspace/setup_pod.sh   to activate it here."
