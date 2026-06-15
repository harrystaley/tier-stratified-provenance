#!/usr/bin/env bash
# setup_pod.sh — re-establish pod-local state on a fresh RunPod after attaching
# the agentpoison-vol network volume at /workspace.
#
# What this does NOT do: install packages, download data, or touch the volume's
# contents. Everything real (repos, conda env, .env, data, deploy keys) already
# persists on /workspace. This only fixes the pod-local shell/git/ssh state that
# resets per pod.
#
# Usage:
#   source /workspace/setup_pod.sh     <- use 'source' so conda + .env load into
#                                          your CURRENT shell. 'bash' also works
#                                          for the git/ssh fixes but won't activate
#                                          the env in your session.

set -u

VOL=/workspace
REPOS=("$VOL/AgentPoison" "$VOL/tier-stratified-provenance")
CONDA_SH="$VOL/miniconda3/etc/profile.d/conda.sh"
ENV_NAME=agentpoison

# EDIT THESE to your details (used for git commit attribution):
GIT_USER_NAME="Harry Staley"
GIT_USER_EMAIL="staleyh@gmail.com"

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
git config --global user.name  "$GIT_USER_NAME"
git config --global user.email "$GIT_USER_EMAIL"
echo "  user.name  = $(git config --global user.name)"
echo "  user.email = $(git config --global user.email)"
if [ "$GIT_USER_EMAIL" = "REPLACE_WITH_YOUR_GITHUB_EMAIL" ]; then
  echo "  !! edit GIT_USER_EMAIL in this script (currently a placeholder)"
fi
echo

# ---- 4. ssh: GitHub deploy-key config (keys persist on volume at /workspace/.ssh) --
# Two per-repo deploy keys live on the volume; each is scoped to one repo, so we
# give them distinct host aliases and point each repo's remote at its alias.
#   deploy_key            -> tier-stratified-provenance   (alias github-tier)
#   agentpoison_deploy_key-> AgentPoison                  (alias github-agentpoison)
echo "== ssh github deploy keys =="
mkdir -p ~/.ssh && chmod 700 ~/.ssh

TIER_KEY="$VOL/.ssh/deploy_key"
AP_KEY="$VOL/.ssh/agentpoison_deploy_key"

# (re)write the two Host blocks idempotently: strip any prior copies, then append.
if [ -f ~/.ssh/config ]; then
  # remove existing github-tier / github-agentpoison blocks to avoid duplicates
  awk '
    BEGIN{skip=0}
    /^Host github-tier$/      {skip=1}
    /^Host github-agentpoison$/ {skip=1}
    /^Host /{ if($2!="github-tier" && $2!="github-agentpoison") skip=0 }
    { if(!skip) print }
  ' ~/.ssh/config > ~/.ssh/config.tmp && mv ~/.ssh/config.tmp ~/.ssh/config
fi

cat >> ~/.ssh/config << CFG

Host github-tier
    HostName github.com
    User git
    IdentityFile $TIER_KEY
    IdentitiesOnly yes

Host github-agentpoison
    HostName github.com
    User git
    IdentityFile $AP_KEY
    IdentitiesOnly yes
CFG
chmod 600 ~/.ssh/config

# pre-accept github's host key so first push isn't an interactive prompt
ssh-keyscan -t ecdsa github.com >> ~/.ssh/known_hosts 2>/dev/null
sort -u ~/.ssh/known_hosts -o ~/.ssh/known_hosts 2>/dev/null

# ensure each repo's remote uses its alias (idempotent)
if [ -d "$VOL/tier-stratified-provenance/.git" ]; then
  git -C "$VOL/tier-stratified-provenance" remote set-url origin \
    git@github-tier:harrystaley/tier-stratified-provenance.git 2>/dev/null
fi
if [ -d "$VOL/AgentPoison/.git" ]; then
  git -C "$VOL/AgentPoison" remote set-url origin \
    git@github-agentpoison:harrystaley/AgentPoison.git 2>/dev/null
fi

if [ -f "$TIER_KEY" ] && [ -f "$AP_KEY" ]; then
  echo "  configured github-tier ($TIER_KEY) and github-agentpoison ($AP_KEY)"
  echo "  test:  ssh -T git@github-tier   /   ssh -T git@github-agentpoison"
else
  echo "  !! one or both deploy keys missing on volume:"
  [ -f "$TIER_KEY" ] || echo "     missing $TIER_KEY"
  [ -f "$AP_KEY" ]   || echo "     missing $AP_KEY"
fi
echo

# ---- 5. report remotes + branch state for both repos ----------------------
echo "== repo status =="
for r in "${REPOS[@]}"; do
  echo "--- $r ---"
  git -C "$r" remote -v | grep origin | sed 's/^/  /'
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

echo "== done."
echo "   If you ran with 'bash', conda is NOT active here — re-run with:"
echo "     source /workspace/setup_pod.sh"
echo "   Push with:  cd <repo> && git push   (uses the right deploy key via alias)"
