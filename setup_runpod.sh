#!/usr/bin/env bash
#
# setup_runpod.sh — per-pod session bootstrap for the tier-stratified-provenance project.
#
# Run this ONCE at the start of every fresh RunPod session (CPU pod or A100 pod).
# It re-links the ephemeral parts of the pod (/root) to the persistent parts on
# the network volume (/workspace), so plain `git`, `python`, and `docker` commands
# just work for the rest of the session.
#
# What persists (lives on the volume, survives terminate):
#   /workspace/tier-stratified-provenance   <- the repo
#   /workspace/.ssh/deploy_key               <- git deploy key (master copy)
#   /workspace/.venv                         <- python environment
#   /workspace/hf_cache                      <- model/dataset downloads
#   /workspace/mongo-data                    <- Flowcept provenance store
#
# What's ephemeral (rebuilt each session by this script):
#   /root/.ssh/deploy_key (chmod 600 copy; the volume can't hold 600 perms)
#   git core.sshCommand pointing at that copy
#   activated venv + exported HF_HOME in the current shell
#
# Usage:
#   source /workspace/tier-stratified-provenance/setup_runpod.sh
#   (use `source`, not `bash`, so the venv activation and exports affect your shell)

set -uo pipefail   # not -e: we want to report and continue, not die on first hiccup

VOL=/workspace
REPO="$VOL/tier-stratified-provenance"
KEY_MASTER="$VOL/.ssh/deploy_key"
KEY_LOCAL=/root/.ssh/deploy_key
VENV="$VOL/.venv"
export HF_HOME="$VOL/hf_cache"

say()  { printf '\n\033[1;34m[setup]\033[0m %s\n' "$*"; }
warn() { printf '\n\033[1;33m[warn]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ✓\033[0m %s\n' "$*"; }

# ---------------------------------------------------------------------------
# 0. Sanity: is the volume actually mounted?
# ---------------------------------------------------------------------------
if [ ! -d "$VOL" ]; then
  warn "$VOL does not exist — network volume not attached? Aborting."
  return 1 2>/dev/null || exit 1
fi
ok "volume present at $VOL"

# ---------------------------------------------------------------------------
# 1. Stage the deploy key to local disk with correct (600) permissions.
#    The volume mounts 0777 and won't honor chmod, so SSH rejects the key
#    there. We copy it to /root/.ssh each session where 600 sticks.
# ---------------------------------------------------------------------------
if [ -f "$KEY_MASTER" ]; then
  mkdir -p /root/.ssh
  cp "$KEY_MASTER" "$KEY_LOCAL"
  chmod 600 "$KEY_LOCAL"
  ok "deploy key staged to $KEY_LOCAL (chmod 600)"
else
  warn "no deploy key at $KEY_MASTER — git over SSH will fail until you create one:"
  warn "  ssh-keygen -t ed25519 -C runpod-deploy -f $KEY_MASTER -N ''"
  warn "  then add $KEY_MASTER.pub to GitHub repo Settings -> Deploy keys"
fi

# ---------------------------------------------------------------------------
# 2. Point this repo's git at the staged key (persists in .git/config, but the
#    key path is ephemeral, so we (re)assert it each session to be safe).
# ---------------------------------------------------------------------------
if [ -d "$REPO/.git" ]; then
  git -C "$REPO" config core.sshCommand "ssh -i $KEY_LOCAL"
  ok "git core.sshCommand set for $REPO"
else
  warn "repo not found at $REPO — clone it first:"
  warn "  cd $VOL && GIT_SSH_COMMAND=\"ssh -i $KEY_LOCAL\" git clone git@github.com:harrystaley/tier-stratified-provenance.git"
fi

# ---------------------------------------------------------------------------
# 3. Python virtual environment on the volume.
# ---------------------------------------------------------------------------
if [ -d "$VENV" ]; then
  # shellcheck disable=SC1091
  source "$VENV/bin/activate"
  ok "activated venv at $VENV ($(python --version 2>&1))"
else
  warn "no venv at $VENV — create it once with:"
  warn "  python3 -m venv $VENV && source $VENV/bin/activate && pip install --upgrade pip"
  warn "  (then install deps: pip install -r $REPO/requirements.txt  — once that file exists)"
fi

ok "HF_HOME set to $HF_HOME"
mkdir -p "$HF_HOME"

# ---------------------------------------------------------------------------
# 4. Bring up Flowcept backing services (Mongo/Redis/etc.) via docker compose.
#    Service names come from YOUR docker-compose.yml — we don't hardcode them.
#    Mongo data is bind-mounted to the volume in the compose file so provenance
#    survives pod teardown.
# ---------------------------------------------------------------------------
if command -v docker >/dev/null 2>&1; then
  if [ -f "$REPO/docker-compose.yml" ]; then
    if docker info >/dev/null 2>&1; then
      # Ensure bind-mount dirs exist on the volume so Mongo/Neo4j data persist.
      mkdir -p "$VOL/mongo-data" "$VOL/neo4j-data"
      ok "provenance data dirs ready on volume ($VOL/mongo-data)"
      # Bring up only the core services by default; neo4j is opt-in (future work).
      ( cd "$REPO" && docker compose up -d redis mongo ) && ok "docker compose: redis + mongo up"
      ( cd "$REPO" && docker compose ps )
    else
      warn "docker daemon not reachable on this pod — skipping compose."
      warn "  (some RunPod templates don't run dockerd; pick a Docker-capable template"
      warn "   if you need Mongo/Redis here.)"
    fi
  else
    warn "no docker-compose.yml in $REPO — skipping services."
  fi
else
  warn "docker not installed on this pod — skipping Flowcept backing services."
fi

# ---------------------------------------------------------------------------
# 5. Quick environment summary.
# ---------------------------------------------------------------------------
say "session ready"
printf '  repo     : %s\n' "$REPO"
printf '  venv     : %s\n' "${VIRTUAL_ENV:-<none>}"
printf '  HF_HOME  : %s\n' "$HF_HOME"
if command -v nvidia-smi >/dev/null 2>&1; then
  GPU=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
  printf '  GPU      : %s\n' "${GPU:-<none detected>}"
else
  printf '  GPU      : <none — CPU pod>\n'
fi
say "next: cd $REPO  &&  git pull  (then run your harness)"
