#!/usr/bin/env bash
# Pre-flight check for the attestation-gate sweep. Verifies code, config, grid,
# and runtime prerequisites. Run from the tier repo root on the pod.
# Does NOT run any cells -- read-only checks, takes seconds.

REPO="/workspace/tier-stratified-provenance"
AGENTPOISON="/workspace/AgentPoison"
FLOWCEPT="/workspace/flowcept"
CONFIG="$REPO/config"
pass=0; fail=0
ok(){ echo "  [ OK ] $1"; pass=$((pass+1)); }
no(){ echo "  [FAIL] $1"; fail=$((fail+1)); }

echo "=============================================================="
echo " SWEEP PRE-FLIGHT CHECK"
echo "=============================================================="

echo ""
echo "--- 1. CODE: medagent parameterized ---"
n=$(grep -c "ATTEST_POISON_DISTRIBUTION\|_stratified_tiers" "$AGENTPOISON/EhrAgent/ehragent/medagent.py" 2>/dev/null)
[ "${n:-0}" -ge 4 ] && ok "medagent parameterized (grep=$n, want >=4)" || no "medagent NOT parameterized (grep=$n) -- apply the patch"
grep -q "_attestation_tier_for" "$AGENTPOISON/EhrAgent/ehragent/medagent.py" 2>/dev/null \
  && no "medagent still has OLD _attestation_tier_for helper -- stale file" \
  || ok "old hardcoded helper absent (good)"

echo ""
echo "--- 2. CODE: flowcept weights-only gate ---"
( cd "$FLOWCEPT" && python -c "from flowcept.configs import ATTESTATION_WEIGHT_FACTORS" 2>/dev/null ) \
  && ok "flowcept exports ATTESTATION_WEIGHT_FACTORS (renamed)" \
  || no "flowcept missing ATTESTATION_WEIGHT_FACTORS -- old code, pull mode-removal commit"
( cd "$FLOWCEPT" && python -c "from flowcept.configs import ATTESTATION_GATE_MODE" 2>/dev/null ) \
  && no "flowcept STILL has ATTESTATION_GATE_MODE -- old code" \
  || ok "ATTESTATION_GATE_MODE removed (good)"

echo ""
echo "--- 3. CONFIG: settings files exist and resolve ---"
for p in baseline strict downweight; do
  f="$CONFIG/settings_$p.yaml"
  if [ -f "$f" ]; then
    out=$( cd "$FLOWCEPT" && FLOWCEPT_SETTINGS_PATH="$f" python -c "from flowcept.configs import ATTESTATION_GATE_ENABLED, ATTESTATION_WEIGHT_FACTORS as W; print(ATTESTATION_GATE_ENABLED, W)" 2>/dev/null )
    [ -n "$out" ] && ok "settings_$p.yaml resolves: $out" || no "settings_$p.yaml exists but FAILS to load"
  else
    no "settings_$p.yaml MISSING at $f"
  fi
done

echo ""
echo "--- 4. CONFIG: expected weight vectors ---"
chk(){ # file, expected-substring
  out=$( cd "$FLOWCEPT" && FLOWCEPT_SETTINGS_PATH="$CONFIG/$1" python -c "from flowcept.configs import ATTESTATION_WEIGHT_FACTORS as W; print(W)" 2>/dev/null )
  echo "$out" | grep -q "$2" && ok "$1 weights = $out" || no "$1 weights unexpected: $out (want $2)"
}
chk settings_strict.yaml     "'W': 0.0"
chk settings_downweight.yaml "'W': 0.5"

echo ""
echo "--- 5. GRID: run_sweep.sh present and complete ---"
SW="$REPO/scripts/run_sweep.sh"
[ -f "$SW" ] && ok "run_sweep.sh present" || no "run_sweep.sh MISSING"
bash -n "$SW" 2>/dev/null && ok "run_sweep.sh syntax OK" || no "run_sweep.sh SYNTAX ERROR"
ncells=$(sed -n '/^CELLS=(/,/^)/p' "$SW" | grep -c '"')
[ "$ncells" -eq 13 ] && ok "grid has 13 cells" || no "grid has $ncells cells (want 13)"
# confirm each profile present under both policies
for prof in P_N P_W P_S A1_capable A2_sophisticated A3_state; do
  s=$(grep -c "strict_${prof}_" "$SW"); d=$(grep -c "downweight_${prof}_" "$SW")
  [ "$s" -ge 1 ] && [ "$d" -ge 1 ] && ok "$prof: strict+downweight present" || no "$prof: missing a policy (strict=$s downweight=$d)"
done

echo ""
echo "--- 6. RUNTIME prerequisites ---"
[ -n "${OPENAI_API_KEY:-}" ] && ok "OPENAI_API_KEY is set" || no "OPENAI_API_KEY NOT set (export it before running)"
command -v tmux >/dev/null 2>&1 && ok "tmux available" || no "tmux not found (run with nohup instead)"
[ -f "$REPO/scripts/reproduce_ehr.sh" ] && ok "reproduce_ehr.sh present" || no "reproduce_ehr.sh MISSING"
[ -d "$AGENTPOISON" ] && ok "AgentPoison dir present" || no "AgentPoison dir MISSING at $AGENTPOISON"
# data file the attack reads
[ -f "$AGENTPOISON/EhrAgent/database/ehr_logs/eicu_ac.json" ] && ok "eICU data present" || no "eICU data file MISSING"

echo ""
echo "--- 7. OUTPUT location writable ---"
mkdir -p "$REPO/evidence/sweep" 2>/dev/null && [ -w "$REPO/evidence/sweep" ] \
  && ok "evidence/sweep writable" || no "evidence/sweep NOT writable"

echo ""
echo "=============================================================="
echo " RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] && echo " ALL CHECKS PASSED -- safe to launch the sweep." \
                  || echo " $fail CHECK(S) FAILED -- fix before launching."
echo "=============================================================="