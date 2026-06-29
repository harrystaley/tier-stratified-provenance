#!/usr/bin/env bash
# =============================================================================
# run_sweep.sh — EHRAgent attestation-gate evaluation sweep (capability model)
#
# Tiers are DERIVED by validating a real ed25519 signature carried with each
# entry (PkiValidator + compute_tier), NOT assigned. Each cell therefore sets a
# signing CAPABILITY for poison and an adoption distribution for legit content;
# the attestation tier is the validation outcome.
#
# Per cell it sets:
#   ATTEST_POISON_CAPABILITY      attacker capability (none|untrusted|root)
#                                   none      -> unsigned             -> T_N
#                                   untrusted -> self-signed          -> T_W
#                                   root      -> trust-anchored key    -> T_S
#                                                (models a COMPROMISED anchor)
#   ATTEST_LEGIT_CAPABILITY_DIST  deployment regime as an adoption distribution
#                                   over signing capabilities (none/untrusted/root)
#   FLOWCEPT_SETTINGS_PATH        gate policy (config/settings_*.yaml)
# and copies the result JSON + full log to evidence/sweep/<label>/, then prints
# a summary table of ASR-r per cell.
#
# The three poison capabilities are the real attacker-capability ladder
# (commodity / capable / state). Because each profile is a SINGLE capability and
# the tier is derived per-entry by validation, there is no tier-proportion knob
# and no stratification artifact: a poison entry reaches T_S only if the attacker
# signs with a key that chains to the trust root.
#
# Usage:
#   export OPENAI_API_KEY=sk-...
#   bash scripts/run_sweep.sh
#
# Overridable:
#   REGIME_LABEL / LEGIT_CAP_DIST  (default R1 / "none:0.80,untrusted:0.15,root:0.05")
#   ENV_NAME (default agentpoison-oai1-py311), AGENTPOISON_DIR, NUM_QUESTIONS
#   SWEEP_OUT (default evidence/sweep)
# =============================================================================
set -uo pipefail   # NOTE: no -e; reproduce_ehr.sh exits 2 on OUT-OF-BAND (expected for defended cells)

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

CONFIG_DIR="$REPO_ROOT/config"
SWEEP_OUT="${SWEEP_OUT:-$REPO_ROOT/evidence/sweep}"
ENV_NAME="${ENV_NAME:-agentpoison-oai1-py311}"
REPRO="$REPO_ROOT/scripts/reproduce_ehr.sh"

# ---- deployment regime: legit adoption distribution, fixed across the sweep ----
# Regime = what fraction of legitimate publishers have adopted which signing
# capability. R1 (commodity): mostly unsigned, little strong adoption. The tier
# of each legit entry is DERIVED by validating whatever signature it carries.
REGIME_LABEL="${REGIME_LABEL:-R1}"
LEGIT_CAP_DIST="${LEGIT_CAP_DIST:-none:0.80,untrusted:0.15,root:0.05}"   # R1 commodity

: "${OPENAI_API_KEY:?Set OPENAI_API_KEY (export OPENAI_API_KEY=sk-...)}"
mkdir -p "$SWEEP_OUT"

# ---- the sweep cells --------------------------------------------------------
# Each cell: "label | poison_capability | settings_file"
#
# Poison capability is the attacker-capability ladder (single capability per
# profile -- the attacker signs all poison with what they can obtain):
#   commodity  -> none      -> poison unsigned       -> T_N  (gate drops it)
#   capable    -> untrusted -> poison self-signed    -> T_W  (strict drops; downweight penalizes)
#   state      -> root      -> poison anchor-signed  -> T_S  (passes gate; residual risk)
#
# "state -> root" models an attacker who has COMPROMISED a trust-anchored key
# (e.g. a stolen author/CA key). This is the honest condition under which poison
# reaches T_S: not "sophistication," but key compromise. See the threat-model
# grounding (docs/threat_model/attacker_profile_grounding.md) for the cost/
# capability ladder this maps onto (crypting unsigned -> certs -> stolen keys).
#
# Two gate policies: strict (W:0,N:0 -> S-only) and downweight (W:0.5,N:0).
# Plus one gate-off baseline. Baseline's capability is irrelevant (no gating).
CELLS=(
  "baseline                          | none      | settings_baseline.yaml"

  "strict_commodity_${REGIME_LABEL}        | none      | settings_strict.yaml"
  "strict_capable_${REGIME_LABEL}          | untrusted | settings_strict.yaml"
  "strict_state_${REGIME_LABEL}            | root      | settings_strict.yaml"

  "downweight_commodity_${REGIME_LABEL}    | none      | settings_downweight.yaml"
  "downweight_capable_${REGIME_LABEL}      | untrusted | settings_downweight.yaml"
  "downweight_state_${REGIME_LABEL}        | root      | settings_downweight.yaml"
)

SUMMARY="$SWEEP_OUT/SUMMARY_${REGIME_LABEL}.tsv"
echo -e "label\tpoison_cap\tlegit_regime\tpolicy\tASR-r(%)\tresult" > "$SUMMARY"

echo "=============================================================="
echo " SWEEP (capability model): regime=$REGIME_LABEL"
echo " legit adoption=$LEGIT_CAP_DIST  env=$ENV_NAME"
echo " cells: ${#CELLS[@]}   out: $SWEEP_OUT"
echo "=============================================================="

for cell in "${CELLS[@]}"; do
  label="$(echo "$cell"  | cut -d'|' -f1 | xargs)"
  pcap="$(echo "$cell"   | cut -d'|' -f2 | xargs)"
  sfile="$(echo "$cell"  | cut -d'|' -f3 | xargs)"
  outdir="$SWEEP_OUT/$label"
  mkdir -p "$outdir"
  log="$outdir/run.log"

  echo ""
  echo "---- CELL: $label  (poison_cap=$pcap, policy=$sfile) ----"

  # Capability-driven: poison signs with $pcap; legit follows the regime adoption
  # distribution. Tiers are derived by validating the resulting signatures.
  export ATTEST_POISON_CAPABILITY="$pcap"
  export ATTEST_LEGIT_CAPABILITY_DIST="$LEGIT_CAP_DIST"
  export FLOWCEPT_SETTINGS_PATH="$CONFIG_DIR/$sfile"

  # run; capture everything; do NOT let exit 2 (OUT-OF-BAND) abort the sweep
  ENV_NAME="$ENV_NAME" bash "$REPRO" >"$log" 2>&1
  rc=$?

  # parse ASR-r from the log (the script prints "ASR-r = NN.N%")
  asrr="$(sed -n 's/.*ASR-r = \([0-9.]*\)%.*/\1/p' "$log" | head -1)"
  result="$(sed -n 's/RESULT: \(.*\)/\1/p' "$log" | head -1)"
  [ -z "$asrr" ] && asrr="ERR"
  [ -z "$result" ] && result="(rc=$rc)"

  # copy the result JSON the run produced (overwritten each run, so grab it now)
  rjson="$(ls -t "$REPO_ROOT"/../AgentPoison/result/Ehragent/gpt/*.json 2>/dev/null | head -1 || true)"
  [ -n "$rjson" ] && cp "$rjson" "$outdir/result.json" 2>/dev/null || true
  # snapshot the exact settings used
  cp "$CONFIG_DIR/$sfile" "$outdir/settings_used.yaml" 2>/dev/null || true

  # policy label for the table
  case "$sfile" in
    settings_baseline.yaml)   pol="baseline(off)";;
    settings_strict.yaml)     pol="strict(W0,N0)";;
    settings_downweight.yaml) pol="downweight(W.5,N0)";;
    *) pol="$sfile";;
  esac

  echo -e "${label}\t${pcap}\t${LEGIT_CAP_DIST}\t${pol}\t${asrr}\t${result}" >> "$SUMMARY"
  echo "   ASR-r=${asrr}%  ($result)   -> $outdir"
done

echo ""
echo "=============================================================="
echo " SWEEP COMPLETE — summary: $SUMMARY"
echo "=============================================================="
column -t -s $'\t' "$SUMMARY" 2>/dev/null || cat "$SUMMARY"