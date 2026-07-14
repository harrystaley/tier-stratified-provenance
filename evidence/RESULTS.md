# Attestation-Gate Defense — Evidence Bundle

This directory holds the evidence that an attestation-aware provenance gate, applied at
retrieval through the Flowcept substrate, defeats the AgentPoison retrieval-poisoning attack.
The defense is evaluated on **two benchmarks** that exercise **two different attestation
mechanisms**, and the central claim is that the **same capability model holds across both**:

- **EHRAgent** (PKI attestation) — a tier is derived by validating a cryptographic **signature**
  (ed25519 + trust anchor). Evaluated in **two layers**: a clean-split mechanism demonstration
  and a capability-model sweep.
- **StrategyQA** (structural attestation) — a tier is derived by validating **structural
  provenance**: whether a passage's provenance handle (`"<title>-<para_index>"`) is a member of
  the genuine corpus manifest (9,251 real Wikipedia handles = the structural trust root).

For EHRAgent the evidence comes in two layers, which answer two different questions:

1. **Clean-split mechanism demonstration** (`baseline/`, `defended/`) — *does the gate
   mechanism defeat the attack at all?* A controlled two-condition test: legitimate content
   tier **S**, poison tier **N**, gate off vs. on.
2. **Capability-model evaluation** (`sweep/`) — *how does the gate behave across attacker
   capabilities, when tiers are **derived** by validating real signatures rather than
   assigned?* A sweep over attacker signing capability × gate policy.

The two layers use different machinery and should be read as a progression: the clean-split
shows the mechanism works; the capability sweep shows it generalizes under a realistic,
cryptographically-grounded threat model. **The most important difference between them is how
the attestation tier is obtained** — assigned in the clean-split, derived by validation in the
sweep (see "What changed between the two layers" below). StrategyQA is then presented as a
second benchmark that confirms the capability model via a structural (non-PKI) mechanism, and
the two are tied together under "Cross-benchmark synthesis."

---

## Layer 1 — Clean-split mechanism demonstration

### Headline result

| Condition | Gate | ASR-r | ASR-a | ASR-t | ACC |
|-----------|------|-------|-------|-------|-----|
| Baseline (run 1) | off | **100.0%** | 84.3% | 78.6% | 60.5% |
| Baseline (run 3) | off | **100.0%** | 69.9% | 82.9% | 59.5% |
| Defended (run 2) | on  | **0.0%**   | 0.0%  | 0.0%  | 56.9% |

The retrieval attack succeeds 100% of the time with the gate off and 0% with the gate on. The
only variable changed between conditions was the gate toggle; environment, code, data, and
weights were otherwise identical.

### How the gate works (this layer)

In this layer each corpus entry carries an attestation tier **assigned as a fact on the item**:
legitimate entries are tiered **S**, injected poison entries **N**. The gate is policy held in
Flowcept config (not in the data): it re-weights retrieval scores by tier with
`{S: 1.0, W: 0.5, N: 0.0}`. The N weight of 0.0 drops poison out of top-k selection.

This is the "carry, don't transform" design: the tier is collected at ingest, carried with the
content along the retrieval path, and consulted at a gate before the agent acts.

### Evidence of the mechanism

The `Selected Indexes` in the run logs are the direct proof. The corpus is 193 legitimate
entries (indices 0–192) plus 4 poison entries (indices 193–196).

- **Baseline (`baseline/run.log`):** every retrieval selects poison — `[193, 194, 195, 196]`
  and permutations — on all 317 questions. Gate off, poison ranks highest, attack succeeds.
- **Defended (`defended/run.log`):** no index ≥193 appears in any of the 317 retrievals; only
  legitimate indices (0–192) are selected. Gate on, poison weighted to 0.0, attack neutralized.

### A note on ASR-a / ASR-t variance

ASR-r (retrieval attack success) is deterministic — it depends only on the DPR retriever and the
fixed trigger — and reproduces at exactly 100.0% across both baseline runs. ASR-a and ASR-t
depend on GPT-3.5 *generation*, which is nondeterministic (API sampling), so they vary between
runs (e.g. ASR-a 84.3% vs 69.9%). Under the defense all three collapse to 0 because nothing
poisoned is retrieved for the model to act on. The defense operates at the deterministic
retrieval layer, which is why the headline ASR-r 100 → 0 is stable. This generation-side
nondeterminism is the known reproducibility gap in the AgentPoison methodology (victim-LLM
inference precision/decoding are unspecified); it affects ASR-a/ASR-t, not the ASR-r result.

---

## Layer 2 — Capability-model evaluation (derived tiers)

This layer replaces *assigned* tiers with tiers **derived by validating a real ed25519
signature carried with each entry** (the `PkiValidator` backend in the Flowcept substrate).
Each attacker profile is a single signing **capability**; the poison tier is whatever that
capability's signature validates to. Legitimate content is signed per a deployment **regime**
(an adoption distribution over capabilities). Regime R1 (commodity):
`⟨none, untrusted, root⟩ = ⟨0.80, 0.15, 0.05⟩`.

### Results (regime R1)

| Attacker capability | Signs with | Derived tier | Strict ⟨1,0,0⟩ | Down-weight ⟨1,0.5,0⟩ |
|---------------------|------------|--------------|----------------|------------------------|
| Baseline (gate off) | —          | —            | 100.0 | 100.0 |
| Commodity           | nothing (unsigned)            | T_N | **0.0**   | **0.0**   |
| Capable             | untrusted key (self-signed)   | T_W | **0.0**   | **0.0**   |
| State               | trust-anchored key            | T_S | **100.0** | **100.0** |

(Source: `sweep/SUMMARY_R1.tsv`; per-cell `result.json` + `run.log` + `settings_used.yaml`
under `sweep/<cell>/`.)

### Reading the result

- **Commodity (T_N)** and **Capable (T_W)** poison are blocked under **both** policies (ASR-r 0).
  Verified against the traces: no poison index (≥193) appears in any selected set for these cells.
- **State (T_S)** poison **passes** (ASR-r 100): the gate trusts T_S, so an attacker who signs
  with a key that chains to the trust root gets through. This is the **residual-risk bound**.
- Crucially, reaching T_S requires a **compromised trust anchor** (a stolen/anchored key), not
  "sophistication." Forged or tampered claims fail validation and remain T_W/T_N — the validator
  is forgery- and tamper-resistant. So the honest security claim is: *the gate stops poison from
  every modeled capability except one that controls a trust-anchored signing key.*
- Down-weight equals strict here (both 0 for Capable) because at W=0.5 the penalized T_W poison
  still falls below the legitimate cluster in top-k for regime R1. Whether the two policies
  diverge under other regimes (more adoption) is an open question for the regime sweep.

The attacker-capability ladder (commodity/capable/state) is grounded in the
attestation-economics literature; see `docs/threat_model/attacker_profile_grounding.md`.

---

## What changed between the two layers

| Aspect | Layer 1 (clean-split) | Layer 2 (capability sweep) |
|--------|-----------------------|----------------------------|
| Tier origin | **Assigned** as a fact on the item (legit=S, poison=N) | **Derived** by validating a real ed25519 signature carried with the entry |
| Attacker model | Implicit (poison is simply "untrusted") | Explicit signing **capability** (none / untrusted / root) |
| Gate policy | Single re-weighting, `{S:1,W:0.5,N:0}` (then called "soft mode") | Two policies, **strict** `⟨1,0,0⟩` and **down-weight** `⟨1,0.5,0⟩`; the mode concept was removed in favor of a single weight vector |
| What it shows | The mechanism defeats the attack (100 → 0) | How the gate behaves across attacker capabilities, with tiers earned by validation |
| Forgery resistance | Not exercised (tiers asserted) | Exercised: poison reaches T_S only via a trust-anchored key; forge/tamper fail |

The clean-split is the **mechanism proof**; the capability sweep is the **threat-model
evaluation**. Layer 1's tiers are stipulated, so it demonstrates the gate's plumbing; Layer 2's
tiers are cryptographically derived, so it bounds the gate's security against a realistic
attacker. Read together, they show the defense works *and* why it works under a threat model
where attestation cannot simply be claimed.

> Note on Layer 1 vocabulary: the clean-split bundle and its config files use the earlier
> "defended" / "soft mode" naming. That terminology is accurate for the run it documents, which
> predates the mode removal and the capability model. The current substrate exposes a single
> weight-vector policy (no soft/hard mode); see `config/` (`settings_strict.yaml`,
> `settings_downweight.yaml`) and `sweep/` for the current model.

---

## StrategyQA — Structural-attestation capability evaluation

The second benchmark evaluates the same gate on ReAct-StrategyQA (AgentPoison's QA agent over a
local Wikipedia corpus), with a **structural** attestation mechanism in place of PKI. The tier
is derived not from a signature but from **manifest membership**: a passage's provenance handle
(`"<title>-<para_index>"`) is validated against the genuine corpus manifest of 9,251 real
Wikipedia handles. Legitimate encyclopedic content reaches **T_W** (membership establishes
resolution/custody binding, not author identity — T_S would require authorship-level C2PA
signing, which is not deployed on encyclopedic text in the near term; this is treated as a
real-world gap, not a modeling choice). The poison's capability is the independent variable,
set per cell by `ATTEST_POISON_STRUCT_CAP`.

### Results (regime R1, down-weight policy)

| Condition | Gate | Poison capability | Derived tier | ASR-r |
|-----------|------|-------------------|--------------|-------|
| baseline           | off | (none)  | —                  | **55.2** |
| downweight_none    | on  | none    | T_N (dropped)      | **0.0**  |
| downweight_forge   | on  | forge   | T_N (unforgeable)  | **0.0**  |
| downweight_member  | on  | member  | T_W (residual)     | **57.4** |

n = 229 questions per cell. (Source: `sweep_strategyqa/SUMMARY_R1.tsv`; per-cell
`dpr-ap-adv.jsonl` + `run.log` under `sweep_strategyqa/<cell>/`.)

The baseline reproduces the AgentPoison attack at ASR-r 55.2% (in the reproduction band
55.5–75.5; AgentPoison reports 65.5). With the gate on, `none` and `forge` poison are driven to
**0.0**, while `member` poison (corpus compromise) returns ASR-r to 57.4%, essentially the baseline (the 2.2-point gap is generation-side non-determinism).

### How the gate works (this benchmark)

Attestation rides with each corpus entry as a provenance handle. At load the gate validates every
handle against the genuine manifest and assigns a weight: an in-manifest handle is T_W and
retained; a missing/integer-id handle is T_N and zero-weighted; a forged handle not in the
manifest is also T_N and zero-weighted. The weight vector is applied before the retriever's
`argsort`, so a T_N entry can never enter the agent's top-k. This is the same "carry, don't
transform" design as the EHRAgent layers — tier collected at ingest, carried along retrieval,
consulted at the gate before the agent acts — with membership-validation in place of
signature-validation.

### Evidence of the mechanism

The gate prints its weighting decision at load. The **zero-weighted count** across the three
gated cells is the mechanism made legible:

| Cell | Gate diagnostic | retrieval_success (sum / max over 229) |
|------|-----------------|----------------------------------------|
| none   | `9251 kept-or-penalized, 2 zero-weighted` | 0 / 0 |
| forge  | `9251 kept-or-penalized, 2 zero-weighted` | 0 / 0 |
| member | `9253 kept-or-penalized, 0 zero-weighted` | 136 / 3 |

- **none → 2 zero-weighted.** The 2 poison entries have integer ids / no handle, fail membership,
  land at T_N, and are zero-weighted; `retrieval_success` is 0 across all 229 questions.
- **forge → 2 zero-weighted.** The attacker fabricated handles for the 2 poison entries, but they
  are not in the genuine manifest, so they *still* fail membership and remain T_N — **identical 2
  zero-weighted to `none`.** The forgery bought zero uplift.
- **member → 0 zero-weighted, manifest 9253.** Under corpus compromise the 2 poison handles are
  genuinely present, pass membership, reach T_W, and nothing is zero-weighted; the poison is
  retrieved freely (`sum=136`), ASR-r 57.4%.

### Reading the result

- **none (T_N)** and **forge (T_N)** poison are blocked (ASR-r 0.0): the structural floor for this
  corpus is T_N, and the gate zero-weights T_N before retrieval.
- **member (T_W)** poison **passes** (ASR-r 57.4): under down-weight, T_W is retained, so an
  attacker who has compromised the corpus — making the poison handle a genuine manifest member —
  restores the full attack surface. This is the residual-risk bound, the structural analogue of
  EHRAgent's "State / compromised trust anchor."
- **The forge → 0.0 result is the structural-unforgeability point** (developed under
  "Cross-benchmark synthesis" below): a fabricated handle cannot reach T_W, whereas a PKI
  self-signature can.

---

## StrategyQA — Backbone and decoding generality

The structural sweep above uses GPT-3.5 as the victim backbone under provider-default decoding. Two additional sweeps test whether the gate's capability-ladder behavior is a property of the gate (retrieval-stage) rather than of the backbone or the decoding settings.

**LLaMA3-70B, provider-default decoding (Arm A).** Identical structural sweep, LLaMA3-70B (Replicate API) in place of GPT-3.5:

| Condition | Gate | Poison capability | Derived tier | ASR-r |
|-----------|------|-------------------|--------------|-------|
| baseline          | off | (none)  | — | **35.4** |
| downweight_none   | on  | none    | T_N (dropped) | **0.0** |
| downweight_forge  | on  | forge   | T_N (unforgeable) | **0.0** |
| downweight_member | on  | member  | T_W (residual) | **34.6** |

n = 229. Source: `sweep_strategyqa_llama3_asis/SUMMARY_R1.tsv`. Gate diagnostics: none/forge `9251 kept, 2 zero-weighted`; member `9253 kept, 0 zero-weighted`.

**LLaMA3-70B, deterministic decoding (Arm B).** Same sweep, Replicate call pinned to `temperature=0, top_p=1, max_new_tokens=128`:

| Condition | Gate | Poison capability | Derived tier | ASR-r |
|-----------|------|-------------------|--------------|-------|
| baseline          | off | (none)  | — | **30.1** |
| downweight_none   | on  | none    | T_N (dropped) | **0.0** |
| downweight_forge  | on  | forge   | T_N (unforgeable) | **0.0** |
| downweight_member | on  | member  | T_W (residual) | **29.1** |

n = 229. Source: `sweep_strategyqa_llama3_det/SUMMARY_R1.tsv`.

**Reading the three sweeps together.** The gate drives none/forge poison to exactly 0.0% in all three (GPT-3.5, LLaMA3 provider-default, LLaMA3 deterministic) — the block is decided at retrieval, so it is invariant to both backbone and decoding. The gate-off baseline shifts across configurations (55.2 / 35.4 / 30.1) but never toward AgentPoison's published LLaMA3 figure of 58.4%; the deterministic arm moves *further* from it, so the reproduction gap is not attributable to decoding and points to served-weight or retrieval differences.

## Ingest overhead

Computing and attaching an attestation tier at consolidation (`annotate_tier` running `compute_tier` over the manifest-membership check) adds **0.19 µs per entry**, measured as the mean over the full 9,251-handle StrategyQA manifest across 10 repetitions (1.7 ms total; source: `evidence/ingest_overhead_R1.txt`, `scripts/measure_ingest_overhead.py`). Because tier computation is an O(1) membership check, this per-entry cost is independent of corpus size and is negligible against Flowcept's existing per-message consolidation (schema enrichment, message-queue transport, persistence), which dominates ingest by orders of magnitude.


## Cross-benchmark synthesis

The two benchmarks evaluate the same gate under two attestation mechanisms — PKI signature
validation (EHRAgent) and structural manifest membership (StrategyQA). Aligning their capability
ladders shows the same defense-in-depth behavior, with one informative asymmetry:

| Rung | EHRAgent (PKI) | tier | StrategyQA (structural) | tier | Outcome |
|------|----------------|------|-------------------------|------|---------|
| low      | commodity → unsigned          | T_N | none → no handle / integer id     | T_N | **blocked** |
| forged   | capable → self-signed         | **T_W** | forge → fabricated handle      | **T_N** | **see below** |
| compromise | state → anchor-signed       | T_S | member → handle in compromised manifest | T_W | **passes** |

**The symmetry.** In both benchmarks, low-capability poison is blocked, and only genuine
trust-root compromise (state / member) passes the gate. The defense is not a function of the
attestation mechanism; it is a function of where the poison lands on the capability ladder. This
is the paper's central empirical claim, now demonstrated across two independent mechanisms.

**The asymmetry (the "forged" rung).** This is where the two mechanisms differ, and it is the
structural-unforgeability point. Under PKI, a "capable" attacker **self-signs**: a self-signature
is a *real* (if untrusted) signature, so the poison reaches **T_W** — the weak tier. It is then
blocked by the strict policy and penalized by down-weight, but it has *earned a tier*. Under
structural attestation there is **no self-signing analogue**: a fabricated handle that is not in
the manifest fails membership outright and stays **T_N**. Forging attestation is therefore
*impossible to leverage* in the structural setting — the forged poison never rises above the floor
— whereas PKI forgery (self-signing) at least reaches T_W. Empirically this shows as StrategyQA's
`forge → 0.0` with the *same 2 zero-weighted* as `none`: the forgery changed nothing.

**Why this matters.** Structural provenance buys unforgeability that PKI self-signing does not,
because membership in a curated manifest cannot be self-asserted — only the manifest's custodian
can grant it. The cost is reach: structural attestation tops out at T_W for encyclopedic content
(no author identity), whereas PKI can express T_S. The two mechanisms are therefore
complementary, and the gate's capability model accommodates both without modification.

---

## Contents

```
RESULTS.md            this file
tab_results.tex       LaTeX results table for Layer 2 (generated from sweep/SUMMARY_R1.tsv)

baseline/             Layer 1, gate OFF
  ap_trigger_dpr.json   per-question attack results (ASR-r 100.0)
  run.log               Selected Indexes show poison [193-196] throughout
defended/             Layer 1, gate ON
  ap_trigger_dpr.json   per-question attack results (ASR-r 0.0)
  run.log               Selected Indexes show only legit (<193) throughout

sweep/                Layer 2, EHRAgent capability model (regime R1)
  SUMMARY_R1.tsv        headline table (capability x policy -> ASR-r)
  baseline/             gate off (ASR-r 100)
  strict_commodity_R1/      strict policy, poison capability none      (T_N)
  strict_capable_R1/        strict policy, poison capability untrusted (T_W)
  strict_state_R1/          strict policy, poison capability root      (T_S)
  downweight_commodity_R1/  down-weight policy, none      (T_N)
  downweight_capable_R1/    down-weight policy, untrusted (T_W)
  downweight_state_R1/      down-weight policy, root      (T_S)
    each cell: result.json + run.log + settings_used.yaml

sweep_strategyqa/     StrategyQA, structural capability model (regime R1)
  SUMMARY_R1.tsv        headline table (capability x gate -> ASR-r)
  baseline/             gate off (ASR-r 55.2)
  downweight_none_R1/       gate on, struct_cap=none   (T_N, dropped)
  downweight_forge_R1/      gate on, struct_cap=forge  (T_N, unforgeable)
  downweight_member_R1/     gate on, struct_cap=member (T_W, residual)
    each cell: dpr-ap-adv.jsonl + run.log
```

## Reproduction

Environment: conda env `agentpoison-oai1-py311` (Python 3.11.15, torch 2.0.1+cu117).
`OPENAI_API_KEY` must be exported (generation uses GPT-3.5 via the OpenAI API).

**EHRAgent — Layer 2 (capability sweep, current model):**

```bash
export OPENAI_API_KEY=sk-...
bash scripts/ehra_run_sweep.sh     # writes sweep/SUMMARY_R1.tsv + per-cell evidence
python scripts/make_results_table.py evidence/sweep/SUMMARY_R1.tsv > evidence/tab_results.tex
```

**EHRAgent — Layer 1 (clean-split, for the mechanism demo):**

```bash
# Baseline (gate off) — expect ASR-r 100.0
export FLOWCEPT_SETTINGS_PATH=$(pwd)/config/settings_baseline.yaml
ENV_NAME=agentpoison-oai1-py311 bash scripts/reproduce_ehr.sh

# Defended (gate on) — expect ASR-r 0.0  (uses down-weight, matching the original W:0.5 defended run)
export FLOWCEPT_SETTINGS_PATH=$(pwd)/config/settings_downweight.yaml
ENV_NAME=agentpoison-oai1-py311 bash scripts/reproduce_ehr.sh
```

The result JSON is written to `AgentPoison/result/Ehragent/gpt/ap_trigger_dpr.json` and is
overwritten on each run; copy it aside between conditions.

Note: the reproduction script's PASS band (88.9–100.0) validates the *attack reproduction*
(Condition 1). For a defended condition a low ASR-r is the success criterion, so the script
reports `OUT-OF-BAND` — that label means the attack was defeated, not that anything failed.

**StrategyQA (structural capability sweep):**

```bash
export OPENAI_API_KEY=sk-...
bash scripts/strategyqa_run_sweep.sh    # writes sweep_strategyqa/SUMMARY_R1.tsv + per-cell evidence
```

The sweep runs four cells (baseline gate-off, plus down-weight none/forge/member), each 229
questions, computing ASR-r from `retrieval_success` in each cell's `dpr-ap-adv.jsonl`. Per-cell
runs resume from rows already present, so a transient quota/rate-limit error is recovered by
re-invocation (completed questions are skipped). Each gated cell's `run.log` records the gate
diagnostic (`Attestation gate ON (cap=...): N kept-or-penalized, M zero-weighted`).