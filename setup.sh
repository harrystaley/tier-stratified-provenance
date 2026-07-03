#!/usr/bin/env bash
#
# setup.sh — per-session bootstrap for the tier-stratified-provenance project.
#
# Environment-agnostic: derives its own location, discovers conda, ensures the
# project's two conda envs exist, loads .env, and activates. Works on a laptop,
# a server, or a RunPod pod. RunPod-specific steps (SSH-key staging for the 0777
# network volume) are auto-detected and skipped elsewhere.
#
# >>> THIS SCRIPT MUST BE SOURCED, NOT EXECUTED. <<<
#   GOOD:  source /path/to/tier-stratified-provenance/setup.sh
#   BAD:   bash   .../setup.sh      (env changes vanish when the child shell exits)
#   BAD:   ./setup.sh
# Sourcing runs the commands in YOUR shell so `conda activate`, HF_HOME, and the
# .env keys persist. The guard below detects a non-sourced run and tells you how.
# NOTE: every new terminal tab / SSH session is a fresh shell and must re-source this.
#
# ---------------------------------------------------------------------------
# CONFIGURATION (all overridable from the environment before sourcing):
#   TIER_REPO       auto = directory containing this script
#   PROJECT_ROOT    auto = parent of TIER_REPO (where sibling repos are looked for)
#   AP_REPO         default $PROJECT_ROOT/AgentPoison
#   FLOWCEPT_REPO   default $PROJECT_ROOT/flowcept
#   CONDA_BASE      auto-discovered if unset (see init_conda)
#   ACTIVATE_ENV    default 'agentpoison' (the env activated at the end)
#   DATA_DIR        default $PROJECT_ROOT      (HF cache, mongo data live under here)
#   HF_HOME         default $DATA_DIR/hf_cache
#   GIT_USER_NAME   default unset — set ONLY if git has no global user.name
#   GIT_USER_EMAIL  default unset — set ONLY if git has no global user.email
#   SETUP_RUNPOD_SSH   '1' to force RunPod SSH-key staging; auto-detected otherwise
#   START_SERVICES  '1' to bring up Flowcept Mongo/Redis via docker compose (default 0)
# ---------------------------------------------------------------------------

# ---- GUARD: must be sourced ------------------------------------------------
_srp_sourced=0
if [ -n "${ZSH_VERSION:-}" ]; then
  case "${ZSH_EVAL_CONTEXT:-}" in *:file) _srp_sourced=1;; esac
elif [ -n "${BASH_VERSION:-}" ]; then
  (return 0 2>/dev/null) && _srp_sourced=1
fi
if [ "$_srp_sourced" -eq 0 ]; then
  _srp_self="${BASH_SOURCE[0]:-$0}"
  printf '\n\033[1;33m[setup] This script configures your shell and must be SOURCED, not executed.\033[0m\n'
  printf 'Run it like this instead:\n\n    source %s\n\n' "$_srp_self"
  printf '(Running with bash or ./ starts a child process; conda activate, HF_HOME,\n'
  printf ' and the .env keys are set in that child and vanish when it exits.)\n\n'
  exit 1
fi

set -uo pipefail   # not -e: report and continue, don't die on first hiccup

say()  { printf '\n\033[1;34m[setup]\033[0m %s\n' "$*"; }
warn() { printf '\n\033[1;33m[warn]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  +\033[0m %s\n' "$*"; }

# ---------------------------------------------------------------------------
# 0. Locate THIS repo from the script's own path (the key to portability).
#    Sibling repos and the data dir derive from it but stay overridable.
# ---------------------------------------------------------------------------
# Resolve the directory of this script across bash/zsh, following one symlink.
_srp_src="${BASH_SOURCE[0]:-${(%):-%x}}"
while [ -h "$_srp_src" ]; do
  _srp_dir="$(cd -P "$(dirname "$_srp_src")" >/dev/null 2>&1 && pwd)"
  _srp_src="$(readlink "$_srp_src")"
  case "$_srp_src" in /*) ;; *) _srp_src="$_srp_dir/$_srp_src";; esac
done
TIER_REPO="${TIER_REPO:-$(cd -P "$(dirname "$_srp_src")" >/dev/null 2>&1 && pwd)}"
PROJECT_ROOT="${PROJECT_ROOT:-$(dirname "$TIER_REPO")}"
AP_REPO="${AP_REPO:-$PROJECT_ROOT/AgentPoison}"
FLOWCEPT_REPO="${FLOWCEPT_REPO:-$PROJECT_ROOT/flowcept}"
DATA_DIR="${DATA_DIR:-$PROJECT_ROOT}"
ACTIVATE_ENV="${ACTIVATE_ENV:-agentpoison}"
export HF_HOME="${HF_HOME:-$DATA_DIR/hf_cache}"

# Env names + their definition files (under TIER_REPO/environment/).
ENV_DIR="$TIER_REPO/environment"
ENV_DEFAULT=agentpoison
ENV_DEFAULT_YML=environment.lock.yml
ENV_OAI1=agentpoison-oai1
ENV_OAI1_YML=environment-oai1.lock.yml

if [ ! -d "$TIER_REPO" ]; then
  warn "could not resolve TIER_REPO; set TIER_REPO=/path/to/tier-stratified-provenance. Aborting."
  return 1 2>/dev/null || exit 1
fi
ok "tier repo: $TIER_REPO"
[ -d "$AP_REPO" ]       && ok "agentpoison repo: $AP_REPO"       || warn "AgentPoison repo not at $AP_REPO (set AP_REPO=... if elsewhere)"
[ -d "$FLOWCEPT_REPO" ] && ok "flowcept repo: $FLOWCEPT_REPO"    || warn "flowcept repo not at $FLOWCEPT_REPO (set FLOWCEPT_REPO=... if elsewhere)"

# ---------------------------------------------------------------------------
# 1. (RunPod only) Stage SSH deploy keys to local disk with 0600 perms.
#    A RunPod network volume mounts 0777 and won't honor chmod, so SSH rejects
#    keys living there. We copy them to ~/.ssh per session. Auto-detected via the
#    RUNPOD_POD_ID env var (or force with SETUP_RUNPOD_SSH=1). Skipped elsewhere.
# ---------------------------------------------------------------------------
_is_runpod=0
[ -n "${RUNPOD_POD_ID:-}" ] && _is_runpod=1
[ "${SETUP_RUNPOD_SSH:-0}" = "1" ] && _is_runpod=1
if [ "$_is_runpod" = "1" ]; then
  SSH_SRC="${SSH_SRC:-$PROJECT_ROOT/.ssh}"
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  if [ -d "$SSH_SRC" ] && ls "$SSH_SRC"/* >/dev/null 2>&1; then
    cp -f "$SSH_SRC"/* "$HOME/.ssh/"
    chmod 600 "$HOME"/.ssh/* 2>/dev/null
    chmod 644 "$HOME"/.ssh/*.pub 2>/dev/null
    ok "staged SSH material from $SSH_SRC (chmod 600)"
  else
    warn "RunPod detected but no SSH material at $SSH_SRC — git over SSH may fail."
  fi
  ssh-keyscan -t ecdsa,ed25519,rsa github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null
  sort -u "$HOME/.ssh/known_hosts" -o "$HOME/.ssh/known_hosts" 2>/dev/null

  # Ensure tmux is installed (long runs must survive SSH disconnects; a foreground
  # run in an SSH session is killed by SIGHUP on drop). Idempotent: only installs if
  # missing. Non-fatal: warns and continues if apt is unavailable or offline.
  if command -v tmux >/dev/null 2>&1; then
    ok "tmux present: $(tmux -V 2>/dev/null)"
  elif command -v apt-get >/dev/null 2>&1; then
    say "installing tmux (one-time; for disconnect-proof long runs)..."
    if DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null 2>&1 \
       && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq tmux >/dev/null 2>&1; then
      ok "installed tmux: $(tmux -V 2>/dev/null)"
    else
      warn "tmux install failed (offline or apt issue); run long jobs under nohup instead."
    fi
  else
    warn "tmux not found and apt-get unavailable; run long jobs under nohup to survive disconnects."
  fi
else
  ok "non-RunPod environment: using your existing SSH config as-is"
fi

# ---------------------------------------------------------------------------
# 2. Verify repo remotes (informational; never rewrites).
# ---------------------------------------------------------------------------
for repo in "$TIER_REPO" "$AP_REPO" "$FLOWCEPT_REPO"; do
  [ -d "$repo/.git" ] || continue
  url=$(git -C "$repo" remote get-url origin 2>/dev/null || true)
  [ -n "$url" ] && ok "$(basename "$repo") origin: $url"
done

# ---------------------------------------------------------------------------
# 3. Git: mark repos safe (multi-UID checkouts), and set identity ONLY IF the
#    user has none configured. We never overwrite an existing git identity.
# ---------------------------------------------------------------------------
for repo in "$TIER_REPO" "$AP_REPO" "$FLOWCEPT_REPO"; do
  [ -d "$repo/.git" ] && git config --global --add safe.directory "$repo" 2>/dev/null
done
if [ -z "$(git config --global user.name 2>/dev/null)" ]; then
  if [ -n "${GIT_USER_NAME:-}" ]; then
    git config --global user.name "$GIT_USER_NAME"; ok "set git user.name=$GIT_USER_NAME"
  else
    warn "git user.name not set; export GIT_USER_NAME=... (or run: git config --global user.name '...')"
  fi
else
  ok "git user.name already set: $(git config --global user.name) (left as-is)"
fi
if [ -z "$(git config --global user.email 2>/dev/null)" ]; then
  if [ -n "${GIT_USER_EMAIL:-}" ]; then
    git config --global user.email "$GIT_USER_EMAIL"; ok "set git user.email=$GIT_USER_EMAIL"
  else
    warn "git user.email not set; export GIT_USER_EMAIL=... (or run: git config --global user.email '...')"
  fi
else
  ok "git user.email already set: $(git config --global user.email) (left as-is)"
fi

# ---------------------------------------------------------------------------
# 4. Conda: discover, ensure BOTH project envs exist (create from the committed
#    lock files only if missing), then activate the default.
#      agentpoison      (environment/environment.lock.yml)      openai 0.28  -> StrategyQA
#      agentpoison-oai1 (environment/environment-oai1.lock.yml) openai 1.x   -> EHRAgent
# ---------------------------------------------------------------------------
init_conda() {
  local candidates=()
  [ -n "${CONDA_BASE:-}" ] && candidates+=("$CONDA_BASE/etc/profile.d/conda.sh")
  command -v conda >/dev/null 2>&1 && candidates+=("$(conda info --base)/etc/profile.d/conda.sh")
  candidates+=(
    "$PROJECT_ROOT/miniconda3/etc/profile.d/conda.sh"
    "$HOME/miniconda3/etc/profile.d/conda.sh"
    "$HOME/anaconda3/etc/profile.d/conda.sh"
    /opt/conda/etc/profile.d/conda.sh
    /opt/miniconda3/etc/profile.d/conda.sh
  )
  local c
  for c in "${candidates[@]}"; do
    if [ -f "$c" ]; then
      # shellcheck disable=SC1090
      source "$c"; return 0
    fi
  done
  return 1
}

if init_conda; then
  ok "conda: $(conda info --base)"
  ensure_env() {  # $1 = env name, $2 = lock-file name (under $ENV_DIR)
    local env_name="$1" yml="$ENV_DIR/$2"
    if conda env list | awk '{print $1}' | grep -qx "$env_name"; then
      ok "conda env present: $env_name"
    elif [ -f "$yml" ]; then
      say "creating conda env '$env_name' from $yml (one-time, slow)..."
      conda env create -f "$yml" && ok "created env: $env_name" \
        || warn "failed to create '$env_name' from $yml (see output above)"
    else
      warn "env '$env_name' missing and no $yml to build it from"
    fi
  }
  ensure_env "$ENV_DEFAULT" "$ENV_DEFAULT_YML"
  ensure_env "$ENV_OAI1"    "$ENV_OAI1_YML"
  if conda activate "$ACTIVATE_ENV" 2>/dev/null; then
    ok "activated conda env: $ACTIVATE_ENV ($(python --version 2>&1))"
  else
    warn "could not activate '$ACTIVATE_ENV' (does it exist? try: conda env list)"
  fi
else
  warn "conda not found. Set CONDA_BASE=/path/to/miniconda3 (dir containing etc/profile.d/conda.sh)."
fi
mkdir -p "$HF_HOME"; ok "HF_HOME=$HF_HOME"

# ---------------------------------------------------------------------------
# 5. Load .env (OPENAI_API_KEY, HF_TOKEN, ...) into this shell, EXPORTED so
#    child processes (reproduce scripts) inherit them. Searched at PROJECT_ROOT
#    then TIER_REPO; override with ENV_FILE=/path/to/.env.
# ---------------------------------------------------------------------------
ENV_FILE="${ENV_FILE:-}"
if [ -z "$ENV_FILE" ]; then
  for cand in "$PROJECT_ROOT/.env" "$TIER_REPO/.env"; do
    [ -f "$cand" ] && { ENV_FILE="$cand"; break; }
  done
fi
if [ -n "$ENV_FILE" ] && [ -f "$ENV_FILE" ]; then
  set -a; # shellcheck disable=SC1090
  source "$ENV_FILE"; set +a
  ok "sourced $ENV_FILE (keys exported in this shell)"
else
  warn "no .env found (looked at \$PROJECT_ROOT/.env, \$TIER_REPO/.env). Set ENV_FILE=... or export keys manually."
fi

# ---------------------------------------------------------------------------
# 6. (Optional) Flowcept backing services via docker compose. Off by default;
#    enable with START_SERVICES=1. Mongo data persists under $DATA_DIR.
# ---------------------------------------------------------------------------
if [ "${START_SERVICES:-0}" = "1" ]; then
  COMPOSE_FILE="${COMPOSE_FILE:-$FLOWCEPT_REPO/deployment/compose-mongo.yml}"
  if command -v docker >/dev/null 2>&1 && [ -f "$COMPOSE_FILE" ] && docker info >/dev/null 2>&1; then
    mkdir -p "$DATA_DIR/mongo-data"; ok "provenance data dir: $DATA_DIR/mongo-data"
    ( cd "$FLOWCEPT_REPO" && docker compose -f "$COMPOSE_FILE" up -d ) && ok "compose: redis + mongo up"
  else
    warn "START_SERVICES=1 but docker/daemon/compose file unavailable — skipping."
  fi
fi

# ---------------------------------------------------------------------------
# 7. Summary.
# ---------------------------------------------------------------------------
say "session ready"
printf '  tier repo : %s\n' "$TIER_REPO"
printf '  ap repo   : %s\n' "$AP_REPO"
printf '  flowcept  : %s\n' "$FLOWCEPT_REPO"
printf '  python    : %s\n' "$(command -v python 2>/dev/null) ($(python --version 2>&1))"
printf '  conda env : %s (active)   envs: %s, %s\n' "$ACTIVATE_ENV" "$ENV_DEFAULT" "$ENV_OAI1"
printf '  HF_HOME   : %s\n' "$HF_HOME"
if command -v nvidia-smi >/dev/null 2>&1; then
  printf '  GPU       : %s\n' "$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)"
else
  printf '  GPU       : <none / CPU>\n'
fi
say "next: cd $TIER_REPO && git pull"

unset _srp_sourced _srp_self _srp_src _srp_dir _is_runpod 2>/dev/null