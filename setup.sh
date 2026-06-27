#!/usr/bin/env bash
#
# setup.sh — per-pod session bootstrap for the tier-stratified-provenance project.
#
# Run ONCE at the start of every fresh RunPod session (CPU pod or A100 pod), AFTER
# attaching the agentpoison-vol network volume at /workspace. It re-links the
# ephemeral parts of the pod (/root, shell state) to the persistent parts on the
# volume, so plain `git`, `python`, and `docker` just work for the rest of the session.
#
# >>> THIS SCRIPT MUST BE SOURCED, NOT EXECUTED. <<<
#   GOOD:  source /workspace/tier-stratified-provenance/setup.sh
#   BAD:   bash   /workspace/tier-stratified-provenance/setup.sh   (env vanishes)
#   BAD:   ./setup.sh                                              (env vanishes)
# Sourcing runs the commands in YOUR shell so conda activate / HF_HOME / .env keys
# persist. Running with bash/./ starts a child process that exits and takes all of
# that with it. The guard below detects a non-sourced run and tells you what to do.
# NOTE: every new terminal tab / SSH session is a fresh shell and must re-source this.
#
# What persists (on the volume, survives terminate):
#   /workspace/AgentPoison                    <- attack/reproduction repo
#   /workspace/tier-stratified-provenance     <- paper/artifact repo
#   /workspace/flowcept                       <- Flowcept fork (tier substrate work)
#   /workspace/.ssh/deploy_key(.pub)          <- tier repo deploy key (master copy)
#   /workspace/.ssh/agentpoison_deploy_key(.pub) <- AgentPoison repo deploy key
#   /workspace/.ssh/flowcept_deploy_key(.pub) <- Flowcept fork deploy key
#   /workspace/.ssh/config                    <- SSH host aliases (per-repo key routing)
#   /workspace/miniconda3                     <- conda + the 'agentpoison' env
#   /workspace/.env                           <- OPENAI_API_KEY / HF_TOKEN
#   /workspace/hf_cache                       <- model/dataset downloads
#   /workspace/mongo-data                     <- Flowcept provenance store
#
# What's ephemeral (rebuilt each session by this script):
#   /root/.ssh/config + *deploy_key (chmod 600 copies; the 0777 volume can't hold 600)
#   git routing via SSH host aliases in /root/.ssh/config (github-tier/-agentpoison/-flowcept)
#   git global identity + safe.directory (reset per pod)
#   activated conda env + exported HF_HOME + sourced .env in the current shell

# ---------------------------------------------------------------------------
# GUARD: refuse to run unless sourced. `return` only succeeds in a sourced
# context; in a child process (bash script.sh / ./script.sh) it fails, so we
# detect that, print the correct invocation, and exit instead of silently
# doing setup that would evaporate when the child exits.
# ---------------------------------------------------------------------------
_srp_sourced=0
if [ -n "${ZSH_VERSION:-}" ]; then
  # zsh: sourced scripts are not in $zsh_eval_context as 'toplevel' with a file
  case "${ZSH_EVAL_CONTEXT:-}" in *:file) _srp_sourced=1;; esac
elif [ -n "${BASH_VERSION:-}" ]; then
  # bash: BASH_SOURCE[0] != $0 when sourced; also `return` works only when sourced
  (return 0 2>/dev/null) && _srp_sourced=1
fi

if [ "$_srp_sourced" -eq 0 ]; then
  # Best-effort path to this script for the copy-paste hint.
  _srp_self="${BASH_SOURCE[0]:-$0}"
  printf '\n\033[1;33m[setup] This script configures your shell and must be SOURCED, not executed.\033[0m\n'
  printf 'Run it like this instead:\n\n'
  printf '    source %s\n\n' "$_srp_self"
  printf '(Running with bash or ./ starts a child process; conda activate, HF_HOME,\n'
  printf ' and the .env keys are set in that child and vanish when it exits — which\n'
  printf ' looks like "it ran fine" but leaves your shell unconfigured.)\n\n'
  exit 1
fi

# From here down we KNOW we are sourced; env changes will persist in the caller.
set -uo pipefail   # not -e: report and continue, don't die on first hiccup

# ===== EDIT THESE =====
GIT_USER_NAME="Harry Staley"
GIT_USER_EMAIL="staleyh@gmail.com"
# ======================

VOL=/workspace
TIER_REPO="$VOL/tier-stratified-provenance"
AP_REPO="$VOL/AgentPoison"
FLOWCEPT_REPO="$VOL/flowcept"

CONDA_SH="$VOL/miniconda3/etc/profile.d/conda.sh"
CONDA_ENV=agentpoison
export HF_HOME="$VOL/hf_cache"

say()  { printf '\n\033[1;34m[setup]\033[0m %s\n' "$*"; }
warn() { printf '\n\033[1;33m[warn]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  +\033[0m %s\n' "$*"; }

# ---------------------------------------------------------------------------
# 0. Sanity: is the volume actually mounted with our work?
# ---------------------------------------------------------------------------
if [ ! -d "$VOL" ] || [ ! -d "$TIER_REPO" ] || [ ! -d "$AP_REPO" ]; then
  warn "$VOL is missing the repos — is agentpoison-vol attached at $VOL? Aborting."
  df -h "$VOL" 2>/dev/null | tail -1
  return 1 2>/dev/null || exit 1
fi
ok "volume present at $VOL (both repos found)"

# ---------------------------------------------------------------------------
# 1. Stage ALL SSH material (deploy keys + config) to local disk with correct
#    perms. The volume mounts 0777 and won't honor chmod, so SSH rejects keys
#    there. We copy the whole $VOL/.ssh dir to /root/.ssh per session where 600
#    sticks. A glob copy auto-handles any key added to the volume later.
# ---------------------------------------------------------------------------
mkdir -p /root/.ssh && chmod 700 /root/.ssh
if [ -d "$VOL/.ssh" ] && ls "$VOL"/.ssh/* >/dev/null 2>&1; then
  cp -f "$VOL"/.ssh/* /root/.ssh/
  chmod 600 /root/.ssh/* 2>/dev/null          # keys + config to 600 (SSH rejects looser)
  chmod 644 /root/.ssh/*.pub 2>/dev/null       # .pub may be world-readable
  ok "staged SSH material from $VOL/.ssh (keys + config, chmod 600)"
  [ -f /root/.ssh/config ] || warn "no config in $VOL/.ssh — alias-based git over SSH will fail"
else
  warn "no SSH material at $VOL/.ssh — git over SSH will fail."
fi

# pre-accept GitHub host key so first push isn't an interactive prompt
ssh-keyscan -t ecdsa,ed25519,rsa github.com >> /root/.ssh/known_hosts 2>/dev/null
sort -u /root/.ssh/known_hosts -o /root/.ssh/known_hosts 2>/dev/null

# ---------------------------------------------------------------------------
# 2. Verify each repo's origin uses its SSH-config host alias. Routing is now
#    handled entirely by /root/.ssh/config (github-tier / github-agentpoison /
#    github-flowcept), so we VERIFY the alias remotes rather than rewriting them.
#    (The old version rewrote remotes to plain git@github.com each session, which
#    silently reverted the aliases and broke per-repo key selection.)
# ---------------------------------------------------------------------------
for repo in "$TIER_REPO" "$AP_REPO" "$FLOWCEPT_REPO"; do
  [ -d "$repo/.git" ] || { warn "$(basename "$repo") has no .git (skipping)"; continue; }
  url=$(git -C "$repo" remote get-url origin 2>/dev/null)
  case "$url" in
    git@github-*) ok "$(basename "$repo") origin alias OK: $url" ;;
    *) warn "$(basename "$repo") origin is not an alias ($url); fix with:
        git -C $repo remote set-url origin git@github-<alias>:<owner>/<repo>.git" ;;
  esac
done

# ---------------------------------------------------------------------------
# 3. Git global identity + safe.directory (reset per pod; volume files are owned
#    by a different UID than root -> 'dubious ownership' without this).
# ---------------------------------------------------------------------------
git config --global --add safe.directory "$TIER_REPO"
git config --global --add safe.directory "$AP_REPO"
git config --global --add safe.directory "$FLOWCEPT_REPO"
git config --global user.name  "$GIT_USER_NAME"
git config --global user.email "$GIT_USER_EMAIL"
ok "git identity: $(git config --global user.name) <$(git config --global user.email)>"
[ "$GIT_USER_EMAIL" = "REPLACE_WITH_YOUR_GITHUB_EMAIL" ] && \
  warn "edit GIT_USER_EMAIL at the top of this script (currently a placeholder)"

# ---------------------------------------------------------------------------
# 4. Activate the conda 'agentpoison' env on the volume.
#    (If you actually use the venv at /workspace/.venv instead, replace this
#     block with:  source "$VOL/.venv/bin/activate" )
# ---------------------------------------------------------------------------
if [ -f "$CONDA_SH" ]; then
  # shellcheck disable=SC1090
  source "$CONDA_SH"
  conda activate "$CONDA_ENV" && ok "activated conda env: $CONDA_ENV ($(python --version 2>&1))" \
    || warn "could not activate conda env '$CONDA_ENV'"
else
  warn "conda not found at $CONDA_SH — environment NOT activated"
fi
mkdir -p "$HF_HOME"; ok "HF_HOME set to $HF_HOME"

# ---------------------------------------------------------------------------
# 5. Load .env (OPENAI_API_KEY, HF_TOKEN) into this shell.
# ---------------------------------------------------------------------------
if [ -f "$VOL/.env" ]; then
  set -a; # shellcheck disable=SC1091
  source "$VOL/.env"; set +a
  ok "sourced $VOL/.env (keys in this shell)"
else
  warn "no $VOL/.env found"
fi

# ---------------------------------------------------------------------------
# 6. Flowcept backing services (Mongo/Redis) via docker compose — if available.
#    Mongo data bind-mounts to the volume so provenance survives teardown.
#    NOTE: Flowcept's compose file lives in the FLOWCEPT repo, not the tier repo.
# ---------------------------------------------------------------------------
COMPOSE_FILE="$FLOWCEPT_REPO/deployment/compose-mongo.yml"
if command -v docker >/dev/null 2>&1; then
  if [ -f "$COMPOSE_FILE" ] && docker info >/dev/null 2>&1; then
    mkdir -p "$VOL/mongo-data"
    ok "provenance data dir ready ($VOL/mongo-data)"
    ( cd "$FLOWCEPT_REPO" && docker compose -f "$COMPOSE_FILE" up -d ) && ok "compose: redis + mongo up"
    ( cd "$FLOWCEPT_REPO" && docker compose -f "$COMPOSE_FILE" ps )
  else
    warn "docker present but daemon unreachable or no compose file at $COMPOSE_FILE — skipping services."
  fi
else
  warn "docker not installed on this pod — skipping Flowcept services (fine for CPU recon)."
fi

# ---------------------------------------------------------------------------
# 7. Summary.
# ---------------------------------------------------------------------------
say "session ready"
printf '  tier repo : %s\n' "$TIER_REPO"
printf '  ap repo   : %s\n' "$AP_REPO"
printf '  flowcept  : %s\n' "$FLOWCEPT_REPO"
printf '  python    : %s\n' "$(command -v python) ($(python --version 2>&1))"
printf '  HF_HOME   : %s\n' "$HF_HOME"
if command -v nvidia-smi >/dev/null 2>&1; then
  printf '  GPU       : %s\n' "$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)"
else
  printf '  GPU       : <none — CPU pod>\n'
fi
echo
ok "push test:  ssh -T git@github-flowcept   (repo-named auth message = success)"
say "next: cd $TIER_REPO && git pull"

# tidy up guard vars (sourced => they'd otherwise linger in the shell)
unset _srp_sourced _srp_self 2>/dev/null
