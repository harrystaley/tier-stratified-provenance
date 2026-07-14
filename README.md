## Headline result

The attestation gate neutralizes AgentPoison's retrieval-poisoning attack across **two benchmarks** (two attestation mechanisms), **two victim backbones**, and **two decoding regimes** — and adds negligible ingest cost. In every configuration the gate drives low-capability poison to **0.0% ASR-r** and only genuine trust-root compromise passes, the residual-risk bound.

**EHRAgent (PKI / cryptographic attestation).** The gate reduces the attack from **100% to 0%** ASR-r for unsigned (T_N) and self-signed (T_W) poison; only anchor-signed (T_S) poison from a compromised trust anchor passes.

| Attacker capability | Poison tier (derived) | Strict ⟨1,0,0⟩ | Down-weight ⟨1,0.5,0⟩ |
|---------------------|-----------------------|----------------|------------------------|
| Baseline (gate off) | —                     | 100            | 100                    |
| Commodity (unsigned)        | T_N           | **0**          | **0**                  |
| Capable (self-signed)       | T_W           | **0**          | **0**                  |
| State (anchor-signed)       | T_S           | 100            | 100                    |

**ReAct-StrategyQA (structural attestation).** The same gate, with manifest-membership in place of signatures. Baseline reproduces the attack; none/forge poison is blocked to 0.0%; only corpus compromise (member, T_W) passes. Forging a handle buys no uplift — a fabricated handle fails membership and stays T_N (structural unforgeability).

| Backbone / decoding | baseline | none | forge | member |
|---------------------|----------|------|-------|--------|
| GPT-3.5 (provider default)    | 55.2 | **0.0** | **0.0** | 57.4 |
| LLaMA3-70B (provider default) | 35.4 | **0.0** | **0.0** | 34.6 |
| LLaMA3-70B (deterministic)    | 30.1 | **0.0** | **0.0** | 29.1 |

The block is decided at retrieval, so it holds identically across backbone and decoding — none/forge → 0.0% in all three. (The gate-off baseline shifts with backbone/decoding but never toward AgentPoison's published 58.4%, so the reproduction gap is not decoding-attributable.)

**Ingest overhead.** Computing and attaching a tier at consolidation adds **0.19 µs per entry** (mean over the 9,251-handle manifest) — an O(1) membership check, negligible against Flowcept's existing per-message consolidation.

Full evidence and methodology: [`evidence/RESULTS.md`](evidence/RESULTS.md).
