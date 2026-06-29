# Tier-Stratified Provenance Substrate for Trustworthy LLM-Agent Workflows

An attestation-aware provenance gate, built on ORNL's [Flowcept](https://github.com/ORNL/flowcept),
that defends LLM-agent retrieval pipelines against memory/knowledge-base poisoning. The gate
follows a **carry, don't transform** design: an attestation tier is established at ingest by
*validating a real cryptographic signature* carried with each piece of content, carried along
the retrieval path, and consulted at a gate before the agent acts. The study reproduces the
[AgentPoison](https://arxiv.org/abs/2407.12784) retrieval-poisoning attack as a baseline and
shows the gate neutralizes it.

## Headline result

On EHRAgent, the attestation gate reduces the AgentPoison retrieval attack from **100% to 0%**
ASR-r. Under the capability-model evaluation — where each attacker profile is a real *signing
capability* and the poison tier is **derived by validating its signature** — the gate stops
poison from every modeled attacker **except one that controls a trust-anchored key** (a
compromised trust anchor). Forged or tampered claims fail validation and never reach the trusted
tier. This is the residual-risk bound: the defense's protection equals the integrity of the
trust roots.

| Attacker capability | Poison tier (derived) | Strict ⟨1,0,0⟩ | Down-weight ⟨1,0.5,0⟩ |
|---------------------|-----------------------|----------------|------------------------|
| Baseline (gate off) | —                     | 100            | 100                    |
| Commodity (unsigned)        | T_N           | **0**          | **0**                  |
| Capable (self-signed)       | T_W           | **0**          | **0**                  |
| State (anchor-signed)       | T_S           | 100            | 100                    |

Full evidence and methodology: [`evidence/RESULTS.md`](evidence/RESULTS.md).

## How it works

Each corpus entry carries **attestation evidence** (a signature) at ingest. A validator
(`PkiValidator`, real ed25519) checks whether the signature is authentic *and* chains to a
configured trust root, and `compute_tier` **derives** the tier from that outcome: anchored →
T_S, authentic-but-unanchored → T_W, none → T_N. The gate is *policy held in Flowcept config*,
not in the data: it re-weights retrieval scores by tier (e.g. strict ⟨S,W,N⟩=⟨1,0,0⟩ or
down-weight ⟨1,0.5,0⟩), dropping or penalizing low-tier content out of the top-k the agent acts
on. Because the tier is derived from a real signature, a poison entry reaches the trusted tier
only if the attacker holds a trust-anchored key — not by assertion.

## Repository map

### Design & setup
- [`docs/design/attestation/ATTESTATION_DESIGN.md`](docs/design/attestation/ATTESTATION_DESIGN.md) — the
  tier substrate design and integration record (compute_tier, validators, annotate).
- [`docs/SETUP_PLAN.md`](docs/SETUP_PLAN.md) — staged runbook for standing up the full stack
  (Flowcept, AgentPoison, the conda environment) in dependency order.
- [`docs/INTEGRATION.md`](docs/INTEGRATION.md) / [`docs/GATE_INTEGRATION.md`](docs/GATE_INTEGRATION.md)
  — how the tier annotation and the retrieval gate wire into Flowcept.
- [`config/SETTINGS.md`](config/SETTINGS.md) — the canonical gate-policy settings files
  (`settings_baseline`, `settings_strict`, `settings_downweight`).

### Reproduction — Condition 1 (the attack baseline)
- [`docs/MULTI_DOMAIN_ASSESSMENT.md`](docs/MULTI_DOMAIN_ASSESSMENT.md) — feasibility map for
  reproducing AgentPoison across EHRAgent, StrategyQA, and Agent-Driver.
- [`docs/STRATEGYQA_REPRODUCTION.md`](docs/STRATEGYQA_REPRODUCTION.md) — the ReAct-StrategyQA/DPR
  reproduction gate (GPT-3.5 + LLaMA3-70B arms), the Condition-1 baseline.
- [`docs/TRIGGER_OPTIMIZATION_RUNBOOK.md`](docs/TRIGGER_OPTIMIZATION_RUNBOOK.md) — optimizing the
  attack trigger for Agent-Driver and EHRAgent (GPU).
- [`docs/DEVIATION.md`](docs/DEVIATION.md) — documented deviations from upstream AgentPoison.

### Evaluation — the attestation-gate defense
- [`evidence/RESULTS.md`](evidence/RESULTS.md) — the core results across two benchmarks. EHRAgent
  (PKI attestation), in two layers: the clean-split mechanism demonstration (assigned tiers, 100→0)
  and the capability-model evaluation (derived tiers, commodity/capable/state × strict/down-weight).
  StrategyQA (structural attestation): the manifest-membership capability sweep (none/forge/member
  → T_N/T_N/T_W), with a cross-benchmark synthesis tying the two mechanisms together.
- [`docs/threat_model/attacker_profile_grounding.md`](docs/threat_model/attacker_profile_grounding.md)
  — empirical grounding for the commodity/capable/state capability ladder (attestation-economics
  literature, IEEE refs).
- [`evidence/sweep/`](evidence/sweep/) — the capability sweep evidence (per-cell result.json,
  run.log, settings_used.yaml; `SUMMARY_R1.tsv`).

## Quickstart — the capability sweep

```bash
# environment: conda env agentpoison-oai1-py311 (Python 3.11, torch 2.0.1+cu117)
export OPENAI_API_KEY=sk-...

# run the capability-model sweep (regime R1): commodity/capable/state x strict/down-weight
bash scripts/ehra_run_sweep.sh                  # writes evidence/sweep/SUMMARY_R1.tsv + per-cell evidence

# render the results table
python scripts/make_results_table.py evidence/sweep/SUMMARY_R1.tsv > evidence/tab_results.tex
```

For the clean-split mechanism demonstration and full reproduction details, see
[`evidence/RESULTS.md`](evidence/RESULTS.md).

## Repository layout

```
config/        canonical gate-policy settings (baseline / strict / down-weight)
scripts/       ehra_run_sweep.sh, reproduce_ehr.sh, make_results_table.py, ...
evidence/      RESULTS.md, EHRAgent sweep (sweep/) + clean-split (baseline/, defended/), StrategyQA sweep (sweep_strategyqa/)
docs/          design, setup, reproduction runbooks, deviations, threat model
patches/       AgentPoison reproduction + attestation-tiering patches
environment/   conda environment specs and lockfiles
```

## Components

The substrate spans three repositories:
- **this repo** — the evaluation: configs, scripts, evidence, reproduction runbooks.
- **Flowcept** (fork) — the substrate: `compute_tier`, the `PkiValidator` backend, the retrieval
  gate instrumentation.
- **AgentPoison** (fork) — the attack + the EHRAgent overlay that signs entries at ingest and
  derives tiers via validation.

Pinned commit SHAs for a given evidence bundle are recorded with that bundle.

## License

See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).
