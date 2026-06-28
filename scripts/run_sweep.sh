#!/usr/bin/env bash
# =============================================================================
# run_sweep.sh — EHRAgent attestation-gate evaluation sweep
#
# Loops the focused-design cells (poison threat profile x gate policy, at a
# fixed deployment regime), running reproduce_ehr.sh for each. Per cell it sets:
#   ATTEST_POISON_DISTRIBUTION   (threat profile; poison tier distribution)
#   ATTEST_LEGIT_DISTRIBUTION    (deployment regime; legit tier distribution)
#   FLOWCEPT_SETTINGS_PATH       (gate policy; config/settings_*.yaml)
# and copies the result JSON + full log to evidence/sweep/<label>/, then prints
# a summary table of ASR-r per cell.
#
# Usage:
#   export OPENAI_API_KEY=sk-...
#   bash scripts/run_sweep.sh
#
# Overridable:
#   REGIME_LABEL / LEGIT_DIST   (default R1 / "N:0.80,W:0.15,S:0.05")
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

# ---- deployment regime (legit tier distribution), fixed across the sweep ----
REGIME_LABEL="${REGIME_LABEL:-R1}"
LEGIT_DIST="${LEGIT_DIST:-N:0.80,W:0.15,S:0.05}"   # R1 commodity (Table 2)

: "${OPENAI_API_KEY:?Set OPENAI_API_KEY (export OPENAI_API_KEY=sk-...)}"
mkdir -p "$SWEEP_OUT"

# ---- the sweep cells --------------------------------------------------------
# Each cell: "label | poison_dist | settings_file"
# Baseline is gate-off (poison_dist irrelevant to the gate, but set for the record).
# Threat profiles are single-tier per the paper's threat model (P_N/P_W/P_S).
# Two gate policies: strict (W:0,N:0) and downweight (W:0.5,N:0).
CELLS=(
  "baseline                | N:1.0 | settings_baseline.yaml"
  "strict_P_N_${REGIME_LABEL}     | N:1.0 | settings_strict.yaml"
  "strict_P_W_${REGIME_LABEL}     | W:1.0 | settings_strict.yaml"
  "strict_P_S_${REGIME_LABEL}     | S:1.0 | settings_strict.yaml"
  "downweight_P_N_${REGIME_LABEL} | N:1.0 | settings_downweight.yaml"
  "downweight_P_W_${REGIME_LABEL} | W:1.0 | settings_downweight.yaml"
  "downweight_P_S_${REGIME_LABEL} | S:1.0 | settings_downweight.yaml"
)

SUMMARY="$SWEEP_OUT/SUMMARY_${REGIME_LABEL}.tsv"
echo -e "label\tpoison\tlegit_regime\tpolicy\tASR-r(%)\tresult" > "$SUMMARY"

echo "=============================================================="
echo " SWEEP: regime=$REGIME_LABEL  legit=$LEGIT_DIST  env=$ENV_NAME"
echo " cells: ${#CELLS[@]}   out: $SWEEP_OUT"
echo "=============================================================="

for cell in "${CELLS[@]}"; do
  label="$(echo "$cell"   | cut -d'|' -f1 | xargs)"
  poison="$(echo "$cell"  | cut -d'|' -f2 | xargs)"
  sfile="$(echo "$cell"   | cut -d'|' -f3 | xargs)"
  outdir="$SWEEP_OUT/$label"
  mkdir -p "$outdir"
  log="$outdir/run.log"

  echo ""
  echo "---- CELL: $label  (poison=$poison, policy=$sfile) ----"

  # gate off for baseline => no legit/poison tiering effect, but set vars anyway for provenance
  export ATTEST_POISON_DISTRIBUTION="$poison"
  export ATTEST_LEGIT_DISTRIBUTION="$LEGIT_DIST"
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

  echo -e "${label}\t${poison}\t${LEGIT_DIST}\t${pol}\t${asrr}\t${result}" >> "$SUMMARY"
  echo "   ASR-r=${asrr}%  ($result)   -> $outdir"
done

echo ""
echo "=============================================================="
echo " SWEEP COMPLETE — summary: $SUMMARY"
echo "=============================================================="
column -t -s $'\t' "$SUMMARY"