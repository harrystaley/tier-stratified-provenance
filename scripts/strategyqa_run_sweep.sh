#!/usr/bin/env bash
# =============================================================================
# strategyqa_run_sweep.sh — StrategyQA attestation-gate sweep (STRUCTURAL model)
#
# Sibling to ehra_run_sweep.sh. Where the EHRAgent sweep derives tiers by
# validating an ed25519 SIGNATURE (PKI), this sweep derives tiers by validating
# STRUCTURAL PROVENANCE: whether a passage's provenance handle ("<title>-<para>")
# is a member of the genuine corpus manifest (9251 real Wikipedia handles =
# structural trust root). Membership is the attestation; it is DERIVED per entry
# by the gate, NOT assigned.
#
# Per cell it sets:
#   ATTEST_GATE_ENABLED         "1" enables the structural gate (read in
#                                 local_wikienv.py); unset/0 = gate off (baseline)
#   ATTEST_POISON_STRUCT_CAP    attacker capability (none|forge|member), read in
#                                 attestation_structural.py:
#                                   none   -> integer id, no handle      -> T_N
#                                   forge  -> fabricated handle, NOT in   -> T_N
#                                             manifest (unforgeability)
#                                   member -> handle GENUINELY in manifest-> T_W
#                                             (models a COMPROMISED corpus)
# and copies the result jsonl + log to evidence/sweep_strategyqa/<label>/, then
# prints a summary table of ASR-r per cell.
#
# KEY ASYMMETRY vs the EHRAgent (PKI) sweep:
#   In PKI, "capable -> self-signed -> T_W": a self-signature is a real (if
#   untrusted) signature, so it reaches the weak tier. In STRUCTURAL provenance
#   there is no self-signing analogue: a forged handle that is not in the manifest
#   fails membership outright and stays T_N. Both `none` AND `forge` therefore land
#   at T_N -- structural attestation is UNFORGEABLE in a way PKI self-signing is not.
#   Only `member` (an attacker who has COMPROMISED the corpus so the poison handle
#   is genuinely present) reaches T_W. This is the structural analogue of the PKI
#   "state -> root -> compromised anchor" condition: poison passes the gate only
#   under trust-root compromise, not under sophistication.
#
# ASR-r is computed HERE by AgentPoison's eval.py (single source of truth), parsed
# from its "ASR-r:" line (the StrategyQA run does not print an ASR-r line itself).
#
# Usage:
#   export OPENAI_API_KEY=sk-...
#   bash scripts/strategyqa_run_sweep.sh
#
# Overridable:
#   REGIME_LABEL (default R1)
#   ENV_NAME (default agentpoison-oai1-py311)
#   AGENTPOISON_DIR (default <repo>/../AgentPoison)
#   SWEEP_OUT (default evidence/sweep_strategyqa)
# =============================================================================
set -uo pipefail   # no -e: a defended cell or a transient error must not abort the sweep
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
ENV_NAME="${ENV_NAME:-agentpoison-oai1-py311}"
AGENTPOISON_DIR="${AGENTPOISON_DIR:-$REPO_ROOT/../AgentPoison}"
SWEEP_OUT="${SWEEP_OUT:-$REPO_ROOT/evidence/sweep_strategyqa}"
REGIME_LABEL="${REGIME_LABEL:-R1}"
: "${OPENAI_API_KEY:?Set OPENAI_API_KEY (export OPENAI_API_KEY=sk-...)}"
mkdir -p "$SWEEP_OUT"

# The StrategyQA run writes {save_dir}/{embedder}-{algo}-{task_type}.jsonl.
# With -m dpr -a ap -t adv that is dpr-ap-adv.jsonl.
RUN_JSONL_NAME="dpr-ap-adv.jsonl"
# ---- the sweep cells --------------------------------------------------------
# Each cell: "label | gate_enabled | struct_cap"
#
#   baseline            gate off               -> no gating, full attack surface
#   downweight_none     gate on, cap=none      -> poison no handle    -> T_N -> dropped
#   downweight_forge    gate on, cap=forge     -> forged handle, not  -> T_N -> dropped
#                                                  in manifest (UNFORGEABILITY)
#   downweight_member   gate on, cap=member    -> handle in compromised-> T_W -> survives
#                                                  manifest (RESIDUAL RISK)
#
# Gate policy is down-weight (the gate zero-weights T_N, the structural floor for
# this corpus; T_W legit content is retained). There is no strict/downweight YAML
# split here as in EHRAgent: the structural gate's policy is the weight vector it
# applies at load, controlled by ATTEST_GATE_ENABLED.
CELLS=(
  "baseline                          | 0 | none"
  "downweight_none_${REGIME_LABEL}        | 1 | none"
  "downweight_forge_${REGIME_LABEL}       | 1 | forge"
  "downweight_member_${REGIME_LABEL}      | 1 | member"
)
SUMMARY="$SWEEP_OUT/SUMMARY_${REGIME_LABEL}.tsv"
echo -e "label\tgate\tstruct_cap\ttier_outcome\tASR-r(%)\tn" > "$SUMMARY"
echo "=============================================================="
echo " STRATEGYQA SWEEP (structural model): regime=$REGIME_LABEL"
echo " env=$ENV_NAME   agentpoison=$AGENTPOISON_DIR"
echo " cells: ${#CELLS[@]}   out: $SWEEP_OUT"
echo "=============================================================="
for cell in "${CELLS[@]}"; do
  label="$(echo "$cell" | cut -d'|' -f1 | xargs)"
  gate="$(echo "$cell"  | cut -d'|' -f2 | xargs)"
  scap="$(echo "$cell"  | cut -d'|' -f3 | xargs)"
  outdir="$SWEEP_OUT/$label"
  mkdir -p "$outdir"
  log="$outdir/run.log"
  echo ""
  echo "---- CELL: $label  (gate=$gate, struct_cap=$scap) ----"
  # tier outcome for the summary table (documents the structural ladder)
  if [ "$gate" = "0" ]; then
    tier="(gate off)"
  else
    case "$scap" in
      none)   tier="T_N(dropped)";;
      forge)  tier="T_N(unforgeable)";;
      member) tier="T_W(residual)";;
      *)      tier="$scap";;
    esac
  fi
  # The run resumes from any rows already present in outdir/$RUN_JSONL_NAME, so a
  # transient 429 that kills a run is recovered by re-invocation (done questions
  # are skipped). Retry up to 3 times per cell.
  export ATTEST_GATE_ENABLED="$gate"
  export ATTEST_POISON_STRUCT_CAP="$scap"
  ok=0
  for attempt in 1 2 3; do
    echo "   attempt $attempt ..." | tee -a "$log"
    ( cd "$AGENTPOISON_DIR" && \
      python ReAct/run_strategyqa_gpt3.5.py -m dpr -a ap -t adv -s "$outdir" ) \
      >>"$log" 2>&1
    rc=$?
    if [ $rc -eq 0 ]; then ok=1; break; fi
    echo "   attempt $attempt failed (rc=$rc); sleeping 60s, will resume" | tee -a "$log"
    sleep 60
  done
  [ $ok -eq 0 ] && echo "   WARNING: cell $label did not complete after 3 attempts" | tee -a "$log"

  # --- ASR-r via AgentPoison eval.py (single source of truth) -----------------
  # Replaces the former inline retrieval_success>=1 formula. eval.py reads only
  # --path (verified: single jsonlines.open(args.path)) and prints "ASR-r:  <fraction>".
  # We parse that line and convert to a one-decimal percent to match the SUMMARY
  # "ASR-r(%)" column. NOTE: eval.py's ASR-r is the AgentPoison-repo scorer
  # (asrr_count/overall_retrieval), which is not identical to the paper's written
  # definition, "fraction of instances where all retrieved demonstrations are
  # poisoned" [K. Chen et al., "AgentPoison: Red-teaming LLM Agents via Poisoning
  # Memory or Knowledge Bases," arXiv:2407.12784v1, Sec. 4.1]. Switching scorers
  # changes reported ASR-r relative to the prior inline formula; regenerate
  # SUMMARY_R1.tsv and tab_results_strategyqa.tex after adopting this.
  rjson="$outdir/$RUN_JSONL_NAME"
  if [ ! -f "$rjson" ]; then
    asrr="ERR"; n=0
  else
    n="$(grep -c . "$rjson")"
    eval_out="$(python "$AGENTPOISON_DIR/ReAct/eval.py" --path "$rjson" 2>/dev/null)"
    asrr="$(printf '%s\n' "$eval_out" \
      | awk -F'ASR-r:' '/ASR-r:/{gsub(/ /,"",$2); printf "%.1f", $2*100; found=1} END{if(!found) print "ERR"}')"
    [ -z "$asrr" ] && asrr="ERR"
  fi
  # ---------------------------------------------------------------------------

  echo -e "${label}\t${gate}\t${scap}\t${tier}\t${asrr}\t${n}" >> "$SUMMARY"
  echo "   ASR-r=${asrr}%  (n=${n}, tier=${tier})   -> $outdir"
done
echo ""
echo "=============================================================="
echo " STRATEGYQA SWEEP COMPLETE — summary: $SUMMARY"
echo "=============================================================="
column -t -s $'\t' "$SUMMARY" 2>/dev/null || cat "$SUMMARY"