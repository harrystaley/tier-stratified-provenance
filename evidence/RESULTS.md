# EHRAgent Attestation-Gate Defense — Evidence Bundle

This directory contains the evidence for the core evaluation result: an attestation-aware
provenance gate, applied at retrieval through the Flowcept substrate, defeats the AgentPoison
retrieval-poisoning attack on EHRAgent.

## Headline result

| Condition | Gate | ASR-r | ASR-a | ASR-t | ACC |
|-----------|------|-------|-------|-------|-----|
| Baseline (run 1) | off | **100.0%** | 84.3% | 78.6% | 60.5% |
| Baseline (run 3) | off | **100.0%** | 69.9% | 82.9% | 59.5% |
| Defended (run 2) | on (soft, N×0.0) | **0.0%** | 0.0% | 0.0% | 56.9% |

**The retrieval attack succeeds 100% of the time with the gate off and 0% of the time with
the gate on.** The only variable changed between conditions was the gate toggle
(`attestation.gate.enabled`); environment, code, data, weights, and mode were identical.

## How the gate works

Each corpus entry carries an attestation tier as a fact on the item: legitimate entries are
tiered **S** (strong), injected poison entries are tiered **N** (none). The gate is policy held
in Flowcept config, not in the data: in `soft` mode it re-weights retrieval scores by tier, with
weights `{S: 1.0, W: 0.5, N: 0.0}`. The N weight of 0.0 drops poison out of the top-k selection.

This is the "carry, don't transform" design: the tier is collected at ingest, carried with the
content along the retrieval path, and consulted at a gate before the agent acts.

## Evidence of the mechanism

The `Selected Indexes` in the run logs are the direct proof. The corpus is 193 legitimate
entries (indices 0–192) plus 4 poison entries (indices 193–196).

- **Baseline (`baseline/run.log`):** every retrieval selects poison — `[193, 194, 195, 196]`
  and permutations — on all 317 questions. Gate off, poison ranks highest, attack succeeds.
- **Defended (`defended/run.log`):** no index ≥193 appears in any of the 317 retrievals. Only
  legitimate indices (0–192) are selected. Gate on, poison weighted to 0.0, attack neutralized.

## A note on ASR-a / ASR-t variance

ASR-r (retrieval attack success) is deterministic — it depends only on the DPR retriever and the
fixed trigger — and reproduces at exactly 100.0% across both baseline runs. ASR-a and ASR-t
depend on GPT-3.5 *generation*, which is nondeterministic (API sampling), so they vary between
runs (e.g. ASR-a 84.3% vs 69.9% across the two baselines). Under the defense, all three collapse
to 0 because nothing poisoned is retrieved for the model to act on. The defense operates at the
deterministic retrieval layer, which is why the headline result (ASR-r 100 → 0) is stable.

This generation-side nondeterminism is the known reproducibility gap in the AgentPoison
methodology (victim-LLM inference precision/decoding are unspecified); it affects ASR-a/ASR-t,
not the ASR-r result reported here.

## Contents

```
baseline/
  ap_trigger_dpr.json   per-question attack results, gate OFF (ASR-r 100.0)
  run.log               full run log; Selected Indexes show poison [193-196] throughout
defended/
  ap_trigger_dpr.json   per-question attack results, gate ON  (ASR-r 0.0)
  run.log               full run log; Selected Indexes show only legit (<193) throughout
config/
  settings_baseline.yaml    Flowcept settings, gate disabled
  settings_defended.yaml     Flowcept settings, gate enabled (soft, S:1.0/W:0.5/N:0.0)
  resolved_config.txt        the gate flags/weights as actually loaded for each condition
  commits.txt                pinned commit SHAs for all three repositories
  env_py311_pip.txt          full pip freeze of the run environment
  env_py311_conda.txt        conda package listing of the run environment
```

## Reproduction

Environment: conda env `agentpoison-oai1-py311` (Python 3.11.15, torch 2.0.1+cu117). Repos pinned
per `config/commits.txt`. `OPENAI_API_KEY` must be exported (EHRAgent generation uses GPT-3.5 via
the OpenAI API).

```bash
# Baseline (gate off) — expect ASR-r 100.0
export FLOWCEPT_SETTINGS_PATH=~/.flowcept/settings_baseline.yaml
ENV_NAME=agentpoison-oai1-py311 bash scripts/reproduce_ehr.sh

# Defended (gate on) — expect ASR-r 0.0
export FLOWCEPT_SETTINGS_PATH=~/.flowcept/settings_defended.yaml
ENV_NAME=agentpoison-oai1-py311 bash scripts/reproduce_ehr.sh
```

The result JSON is written to `AgentPoison/result/Ehragent/gpt/ap_trigger_dpr.json` and is
overwritten on each run; copy it aside between conditions.

Note: the reproduction script's PASS band (88.9–100.0) validates the *attack reproduction*
(Condition 1). For the defended condition (Condition 2), a low ASR-r is the success criterion, so
the script reports `OUT-OF-BAND` — that label means the attack was defeated, not that anything
failed.
