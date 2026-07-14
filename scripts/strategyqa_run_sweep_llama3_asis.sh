#!/usr/bin/env bash
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
AGENTPOISON_DIR="${AGENTPOISON_DIR:-/workspace/AgentPoison}"
SWEEP_OUT="${SWEEP_OUT:-$REPO_ROOT/evidence/sweep_strategyqa_llama3_asis}"
REGIME_LABEL="${REGIME_LABEL:-R1}"
: "${REPLICATE_API_TOKEN:?Set REPLICATE_API_TOKEN}"
export LANG=C.UTF-8 LC_ALL=C.UTF-8
mkdir -p "$SWEEP_OUT"
RUN_JSONL_NAME="dpr-ap-adv.jsonl"
CELLS=(
  "baseline                       | 0 | none"
  "downweight_none_${REGIME_LABEL}    | 1 | none"
  "downweight_forge_${REGIME_LABEL}   | 1 | forge"
  "downweight_member_${REGIME_LABEL}  | 1 | member"
)
SUMMARY="$SWEEP_OUT/SUMMARY_${REGIME_LABEL}.tsv"
echo -e "label\tgate\tstruct_cap\ttier_outcome\tASR-r(%)\tn" > "$SUMMARY"
for cell in "${CELLS[@]}"; do
  label="$(echo "$cell" | cut -d'|' -f1 | xargs)"
  gate="$(echo "$cell"  | cut -d'|' -f2 | xargs)"
  scap="$(echo "$cell"  | cut -d'|' -f3 | xargs)"
  outdir="$SWEEP_OUT/$label"; mkdir -p "$outdir"; log="$outdir/run.log"
  case "$scap" in
    none) [ "$gate" = 0 ] && tier="(gate off)" || tier="T_N(dropped)";;
    forge) tier="T_N(unforgeable)";; member) tier="T_W(residual)";; *) tier="$scap";;
  esac
  export ATTEST_GATE_ENABLED="$gate"
  export ATTEST_POISON_STRUCT_CAP="$scap"
  echo "---- CELL: $label (gate=$gate cap=$scap) ----"
  ok=0
  for attempt in 1 2 3; do
    echo "  attempt $attempt ..." | tee -a "$log"
    ( cd "$AGENTPOISON_DIR" && \
      python ReAct/run_strategyqa_llama3_api.py -m dpr -a ap -t adv --limit 229 -s "$outdir" ) >>"$log" 2>&1
    rc=$?; [ $rc -eq 0 ] && { ok=1; break; }
    echo "  attempt $attempt failed rc=$rc; sleeping 60s" | tee -a "$log"; sleep 60
  done
  [ $ok -eq 0 ] && echo "  WARNING: $label did not complete" | tee -a "$log"
  rjson="$outdir/$RUN_JSONL_NAME"
  if [ -f "$rjson" ]; then
    n="$(grep -c . "$rjson")"
    eval_out="$(python "$AGENTPOISON_DIR/ReAct/eval.py" --path "$rjson" 2>/dev/null)"
    asrr="$(printf '%s\n' "$eval_out" | awk -F'ASR-r:' '/ASR-r:/{gsub(/ /,"",$2); printf "%.1f",$2*100; f=1} END{if(!f)print "ERR"}')"
  else asrr="ERR"; n=0; fi
  echo -e "${label}\t${gate}\t${scap}\t${tier}\t${asrr}\t${n}" >> "$SUMMARY"
  echo "  ASR-r=${asrr}% (n=${n})"
done
echo "=== SWEEP COMPLETE: $SUMMARY ==="
column -t -s $'\t' "$SUMMARY" 2>/dev/null || cat "$SUMMARY"
