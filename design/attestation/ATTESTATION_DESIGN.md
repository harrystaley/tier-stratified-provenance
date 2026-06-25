# Attestation Tier Substrate — Design & Integration Record

**Status (2026-06-25):** Integrated and verified on branch
`feature/attestation-tier-substrate` (flowcept). Code checks 1-7 green, Ruff clean,
committed. The connective tissue (retrieval carrying tier inline) and the
container-backed end-to-end smoke test are the next steps.

**Context.** Extension to ORNL Flowcept for the IEEE OJCS paper
"A Tier-Stratified Provenance Substrate for Trustworthy LLM-Agent Workflows."
Thesis: source attestation is collected at ingest, carried with content, and
consulted at a gate before retrieved content is acted upon. AgentPoison
(arXiv:2407.12784) is the attack baseline the gate defends against.

---

## 1. Tier semantics (LOCKED)

Three tiers. The trust boundary is **T_S vs. {T_W, T_N}** — only T_S is acted on
without mitigation.

- **T_S (strong)** — a cryptographic provenance claim (C2PA manifest, PKI signature,
  Sigstore bundle, TPM-sealed signing key) is present **AND validates against a
  configured trust root**. Forgery-resistant: an attacker cannot reach this tier
  without a key that chains to a trusted root.
- **T_W (weak)** — a provenance claim is present but is **not trust-anchored**: an
  unsigned-but-resolvable source handle, or a signature that does not validate
  against any configured trust root (self-signed, unknown CA, or a TPM quote whose
  EK/AIK chain is not held). Identity-asserting but forgeable.
- **T_N (none)** — no provenance claim, or a claim that fails to parse/resolve.

**Key decision — validation, not presence.** T_S requires the claim to *validate
against a trust root*, not merely to be present. Presence-only would let an attacker
self-sign poison and claim T_S, breaking the load-bearing threat-model assumption
("the attacker can poison memory but cannot forge the provenance attestation"). This
matches how C2PA, PKI, Sigstore, and TPM actually define trust.

**Present-but-untrusted -> T_W (not T_N).** A self-signed manifest is a provenance
assertion, just not a trust-anchored one. An attacker's best case (attaching an
unverifiable claim) reaches T_W at most, never T_S — and T_W is still gated. The
defense holds against an attacker who *tries* to attest.

### TPM 2.0 tiering

TPM is not a fixed tier; the same rule applies. A TPM-sealed signing key whose
certificate chains to a trusted CA, binding the content -> **T_S**. A bare platform/
boot quote (attests the *machine*, not a content binding), or a TPM whose EK/AIK
chain is not in the trust set -> **T_W**. This matches the R2a (TPM-dominant)
deployment regime, where TPM attestations modally cluster at T_W.

| Backend | T_S (validates + binds content) | T_W (present, not trust-anchored) |
|---|---|---|
| C2PA | manifest signature chains to your C2PA trust list | self-signed / unknown-cert manifest |
| PKI | content signature chains to a CA in your bundle | signature from an untrusted CA |
| Sigstore | bundle verifies against a trusted identity | identity not in your trust set |
| TPM 2.0 | TPM-sealed key whose cert chains to your CA | bare platform quote, or unheld EK/AIK chain |
| handle | (n/a — not cryptographic) | resolvable source handle, no signature |

---

## 2. Architecture: fact-on-data, policy-in-Flowcept (LOCKED)

The central separation that makes the evaluation possible:

- **The TIER is a fact**, computed at ingest and stored on the task document:
  `attestation_tier = {"value": "S"|"W"|"N", "basis": ..., "validated_against": ...}`.
  Objective: it records what was attested, not what to do about it.
- **The GATE POLICY is a Flowcept config**, not on the data: which tiers to disallow
  (hard) and how much to down-weight each tier (soft). The same annotated corpus is
  therefore re-gateable under any policy without re-annotation — which is exactly
  what the evaluation sweep requires (sweeping `hard_blocked_tiers` and
  `soft_weight_factors` across deployment regimes R1/R2).

If either knob lived on the data, the sweep would require rewriting every document.
Policy-in-Flowcept keeps tier-facts fixed and policy tunable.

---

## 3. Components

### Tier Annotator (ingest)

`compute_tier(evidence, trust_roots, validator)` -> structured tier dict. Logic:
claim present + validates -> T_S; claim present but unverified / no validator
configured -> T_W (safe default, never T_S); resolvable handle -> T_W; else -> T_N.

`annotate_tier(message, trust_roots)` writes `message["attestation_tier"]`. Called as
a **sibling** of `TaskObject.enrich_task_dict` in the document inserter — inside
`if ENRICH_MESSAGES:` but **outside the telemetry branch**, so every provenance-
bearing message is tiered, not only telemetry-bearing ones (criticality tagging is
nested in telemetry; tier annotation must not be).

Validator is a **pluggable interface** (`validate(claim, trust_roots) -> bool`),
backend selected by attestation type (`c2pa | pki | sigstore | tpm | bundled`).
Validation is **offline** against bundled roots for the static evaluation; online
revocation/OCSP is the future-work re-validation hook.

### Gate (retrieval)

Two knobs, both Flowcept policy, in two places (forced by architecture: MongoDB does
not compute embedding similarity — `_pipeline` sorts by stored field values, no
`$vectorSearch` — so the soft re-rank cannot live in the DAO `$sort`):

- **Hard / disallow** — `gate_filter(query_filter, hard_blocked_tiers)` augments a
  DAO query `$match` to exclude blocked tiers (default `{N}`). Blocked content is
  never retrieved. Fail-closed: tier-absent documents are treated as T_N.
- **Soft / adjust-weight** — `gate_rerank(result, soft_weight_factors)` multiplies
  each retrieved item's similarity by its tier weight (`adjusted = similarity *
  weight`), re-sorts, drops zero-weight. Runs in the agent-task wrapper on `result`,
  where similarity lives. Default factors `{S:1.0, W:0.5, N:0.0}`. No-op on
  non-collection returns (shape guard). Fail-closed: missing tier -> T_N.

---

## 4. Integration (what landed on the feature branch)

New package: `src/flowcept/commons/attestation/` — `__init__.py`, `tier.py`,
`annotate.py`, `gate.py`.

Edits to existing files:
- `commons/flowcept_dataclasses/task_object.py` — `attestation_tier` field.
- `flowceptor/consumers/document_inserter.py` — `annotate_tier` import + call site
  (sibling to enrich, outside telemetry).
- `instrumentation/flowcept_agent_task.py` — `gate_rerank` soft-gate hook before
  `return result`.
- `configs.py` — `ATTESTATION_*` constants (enabled, trust_roots, gate mode,
  `hard_blocked_tiers`, `soft_weight_factors`).
- `resources/sample_settings.yaml` — `attestation:` block (trust_roots + gate policy).

### Config shape

```yaml
attestation:
  enabled: true
  # type selects the pluggable validator backend:
  # c2pa | pki | sigstore | tpm (EK/AIK chain) | bundled
  trust_roots:
    - id: "eval-root-0"
      type: "bundled"
  gate:
    enabled: true
    mode: "soft"                 # "soft" | "hard" | "off"
    hard_blocked_tiers: ["N"]    # HARD policy (Flowcept, not data)
    soft_weight_factors:         # SOFT policy (Flowcept, not data)
      S: 1.0
      W: 0.5
      N: 0.0
```

### Verification (all green)

- Imports resolve; config constants read real yaml values; `TaskObject` has
  `attestation_tier`; both consumers load.
- Logic: `compute_tier(None) -> N`; resolvable handle -> W; claim-without-validator
  -> W (safe default); `gate_rerank` drops T_N and re-ranks; non-list passes through.
- Ruff clean.

---

## 5. The connective tissue (NEXT — not yet built)

The annotator writes the tier onto the **task document**; the soft gate reads the
tier off the **retrieved items**. For the soft gate to fire, retrieval must carry
each item's tier (and similarity `score`) inline on the returned items — either
looked up by id from the store, or carried with content from ingest. The hard gate
(`gate_filter`) does NOT need this; it filters on the stored `attestation_tier.value`
directly in the DAO query.

Until this is wired:
- All content tiers **T_N** (no `attestation_evidence` reaches messages yet), and
- the **soft gate is a correct no-op** (no inline tiers on `result`).

This is expected, not a defect. The two halves are correct and ready; this is where
they begin to interact — and where the StrategyQA provenance (`title`/`para_index`,
present on 9,251/9,251 legitimate paragraphs, absent on the 2 injected poison) enters
the pipeline: the retriever resolves it to a tier, attaches it to each item, and
`gate_rerank` re-weights by it.

Two wiring points are intentionally swappable (documented in the code):
- `_extract_evidence` — where provenance is read off the message at ingest.
- `gate_rerank`'s `score_getter` / `tier_getter` — the retriever-specific item shape.

---

## 6. Open items

- **Connective tissue** (above) — the immediate next build.
- **End-to-end smoke test** — needs Mongo + MQ (Podman) up; confirms `attestation_tier`
  lands on the task document and the gate acts. Checks 1-7 (code) done; check 8 (runtime)
  pending.
- **Wikipedia title-resolution validation** — confirms StrategyQA `title` handles
  resolve to live pages with trust signals, turning derived-attestation from proposed
  to demonstrated. Small; no GPU.
- **Concrete validator backends** — a real C2PA/PKI/TPM `AttestationValidator` for the
  T_S arm (eval currently exercises T_W/T_N from real data; T_S via signed/modeled
  content).
- **Upstream question** — whether/when to propose this to ORNL Flowcept (Madisetti
  decision; code is written in upstream style — config-in-settings, NumPy docstrings,
  Ruff-clean — so it is PR-ready when scoped).
