#!/usr/bin/env bash
#
# setup_runpod.sh — per-pod session bootstrap for the tier-stratified-provenance project.
#
# Run ONCE at the start of every fresh RunPod session (CPU pod or A100 pod), AFTER
# attaching the agentpoison-vol network volume at /workspace. It re-links the
# ephemeral parts of the pod (/root, shell state) to the persistent parts on the
# volume, so plain `git`, `python`, and `docker` just work for the rest of the session.
#
# What persists (on the volume, survives terminate):
#   /workspace/AgentPoison                    <- attack/reproduction repo
#   /workspace/tier-stratified-provenance     <- paper/artifact repo
#   /workspace/.ssh/deploy_key(.pub)          <- tier repo deploy key (master copy)
#   /workspace/.ssh/agentpoison_deploy_key(.pub) <- AgentPoison repo deploy key
#   /workspace/miniconda3                     <- conda + the 'agentpoison' env
#   /workspace/.env                           <- OPENAI_API_KEY / HF_TOKEN
#   /workspace/hf_cache                       <- model/dataset downloads
#   /workspace/mongo-data                     <- Flowcept provenance store
#
# What's ephemeral (rebuilt each session by this script):
#   /root/.ssh/*deploy_key (chmod 600 copies; the 0777 volume can't hold 600 perms)
#   per-repo git core.sshCommand pointing at those copies
#   git global identity + safe.directory (reset per pod)
#   activated conda env + exported HF_HOME + sourced .env in the current shell
#
# Usage:
#   source /workspace/tier-stratified-provenance/setup_runpod.sh
#   (use `source`, not `bash`, so env activation and exports affect your shell)

set -uo pipefail   # not -e: report and continue, don't die on first hiccup

# ===== EDIT THESE =====
GIT_USER_NAME="Harry Staley"
GIT_USER_EMAIL="REPLACE_WITH_YOUR_GITHUB_EMAIL"
# ======================

VOL=/workspace
TIER_REPO="$VOL/tier-stratified-provenance"
AP_REPO="$VOL/AgentPoison"

# deploy keys: master copy on volume -> staged 600 copy on local disk
TIER_KEY_MASTER="$VOL/.ssh/deploy_key"
TIER_KEY_LOCAL=/root/.ssh/deploy_key
AP_KEY_MASTER="$VOL/.ssh/agentpoison_deploy_key"
AP_KEY_LOCAL=/root/.ssh/agentpoison_deploy_key

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
# 1. Stage deploy keys to local disk with correct (600) perms.
#    The volume mounts 0777 and won't honor chmod, so SSH rejects keys there.
#    We copy each to /root/.ssh per session where 600 sticks.
# ---------------------------------------------------------------------------
mkdir -p /root/.ssh && chmod 700 /root/.ssh
stage_key() {  # $1=master $2=local $3=label
  if [ -f "$1" ]; then
    cp "$1" "$2"; chmod 600 "$2"
    ok "$3 deploy key staged to $2 (chmod 600)"
  else
    warn "no $3 deploy key at $1 — git over SSH for that repo will fail."
  fi
}
stage_key "$TIER_KEY_MASTER" "$TIER_KEY_LOCAL" "tier"
stage_key "$AP_KEY_MASTER"   "$AP_KEY_LOCAL"   "AgentPoison"

# pre-accept GitHub host key so first push isn't an interactive prompt
ssh-keyscan -t ecdsa,ed25519,rsa github.com >> /root/.ssh/known_hosts 2>/dev/null
sort -u /root/.ssh/known_hosts -o /root/.ssh/known_hosts 2>/dev/null

# ---------------------------------------------------------------------------
# 2. Point each repo's git at its staged key (per-repo core.sshCommand).
#    Also normalize remotes to plain git@github.com (core.sshCommand handles the key).
# ---------------------------------------------------------------------------
if [ -d "$TIER_REPO/.git" ]; then
  git -C "$TIER_REPO" config core.sshCommand "ssh -i $TIER_KEY_LOCAL -o IdentitiesOnly=yes"
  git -C "$TIER_REPO" remote set-url origin git@github.com:harrystaley/tier-stratified-provenance.git 2>/dev/null
  ok "git sshCommand set for tier repo"
else
  warn "tier repo has no .git"
fi
if [ -d "$AP_REPO/.git" ]; then
  git -C "$AP_REPO" config core.sshCommand "ssh -i $AP_KEY_LOCAL -o IdentitiesOnly=yes"
  git -C "$AP_REPO" remote set-url origin git@github.com:harrystaley/AgentPoison.git 2>/dev/null
  ok "git sshCommand set for AgentPoison repo"
else
  warn "AgentPoison repo has no .git"
fi

# ---------------------------------------------------------------------------
# 3. Git global identity + safe.directory (reset per pod; volume files are owned
#    by a different UID than root -> 'dubious ownership' without this).
# ---------------------------------------------------------------------------
git config --global --add safe.directory "$TIER_REPO"
git config --global --add safe.directory "$AP_REPO"
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
# ---------------------------------------------------------------------------
if command -v docker >/dev/null 2>&1; then
  if [ -f "$TIER_REPO/docker-compose.yml" ] && docker info >/dev/null 2>&1; then
    mkdir -p "$VOL/mongo-data" "$VOL/neo4j-data"
    ok "provenance data dirs ready ($VOL/mongo-data)"
    ( cd "$TIER_REPO" && docker compose up -d redis mongo ) && ok "compose: redis + mongo up"
    ( cd "$TIER_REPO" && docker compose ps )
  else
    warn "docker present but daemon unreachable or no compose file — skipping services."
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
printf '  python    : %s\n' "$(command -v python) ($(python --version 2>&1))"
printf '  HF_HOME   : %s\n' "$HF_HOME"
if command -v nvidia-smi >/dev/null 2>&1; then
  printf '  GPU       : %s\n' "$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)"
else
  printf '  GPU       : <none — CPU pod>\n'
fi
echo
ok "push test:  ssh -i $TIER_KEY_LOCAL -T git@github.com   (deploy-key per-repo message = success)"
say "next: cd $TIER_REPO && git pull"
