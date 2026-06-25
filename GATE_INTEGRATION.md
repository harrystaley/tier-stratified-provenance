# Attestation Gate — Integration

The gate consults the tier-FACT on the data and applies POLICY from Flowcept config.
Both knobs (`hard_blocked_tiers` for disallow, `soft_weight_factors` for down-weight) live in Flowcept config,
NOT on the data. This makes the same annotated corpus re-gateable under any policy --
which is what the evaluation sweep requires.

## New file

`src/flowcept/commons/attestation/gate.py`  (from outputs/attestation/gate.py)

## Architectural split (why two functions, two places)

MongoDB's pipeline does NOT compute embedding similarity (verified: `_pipeline`
sorts by stored field values, no `$vectorSearch`/`$meta` score). RAG similarity is
computed in the retriever (external), like AgentPoison's DPR cosine. Therefore:

- **Hard disallow** -> `gate_filter` augments the DAO `$match` (in-query exclusion).
  Available in Mongo because it is a pure field condition on `attestation_tier.value`.
- **Soft weight-adjust** -> `gate_rerank` runs in the wrapper on `result`, where the
  similarity scores live. It CANNOT live in the DAO `$sort` (no score there to multiply).

This matches the "two implementation points" by construction.

## Edit 1 — config: sample_settings.yaml

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
    mode: "soft"            # "soft" | "hard" | "off"
    hard_blocked_tiers: ["N"]    # HARD policy (Flowcept, not data). Default blocks T_N.
    soft_weight_factors:         # SOFT policy (Flowcept, not data).
      S: 1.0
      W: 0.5
      N: 0.0
```

## Edit 2 — config: configs.py constants

```python
_GATE = ATTESTATION_SETTINGS.get("gate", {}) or {}
ATTESTATION_GATE_ENABLED = _GATE.get("enabled", False)
ATTESTATION_GATE_MODE = _GATE.get("mode", "soft")
ATTESTATION_HARD_BLOCKED_TIERS = list(_GATE.get("hard_blocked_tiers", ["N"]))
ATTESTATION_SOFT_WEIGHT_FACTORS = dict(_GATE.get("soft_weight_factors", {"S": 1.0, "W": 0.5, "N": 0.0}))
```

## Edit 3 — SOFT gate at the agent-task wrapper (flowcept_agent_task.py, ~L101)

Insert just before `return result`:

```python
            interceptor.intercept(task_obj.to_dict())
            if ATTESTATION_GATE_ENABLED and ATTESTATION_GATE_MODE == "soft" and result is not None:
                result = gate_rerank(result, ATTESTATION_SOFT_WEIGHT_FACTORS)
            return result
```

Imports:
```python
from flowcept.commons.attestation.gate import gate_rerank
from flowcept.configs import (
    ATTESTATION_GATE_ENABLED, ATTESTATION_GATE_MODE, ATTESTATION_SOFT_WEIGHT_FACTORS,
)
```

Note: `gate_rerank` is a no-op unless `result` is a list of tier-bearing retrieval
items. It will not fire until retrieval carries `attestation_tier` (and a `score`)
inline on each item -- the connective-tissue wiring step (see below).

## Edit 4 — HARD gate at the DAO query (where the agent's RAG retrieval calls the DAO)

Wherever retrieval issues a DAO `query(...)`, wrap its filter:

```python
from flowcept.commons.attestation.gate import gate_filter
from flowcept.configs import ATTESTATION_GATE_ENABLED, ATTESTATION_GATE_MODE, ATTESTATION_HARD_BLOCKED_TIERS

if ATTESTATION_GATE_ENABLED and ATTESTATION_GATE_MODE == "hard":
    query_filter = gate_filter(query_filter, ATTESTATION_HARD_BLOCKED_TIERS)
# ... pass query_filter into dao.query(filter=query_filter, ...)
```

## The connective tissue (the real next step)

Both halves are correct and ready, but they do not yet interact, because:

- the annotator writes `attestation_tier` onto the *task document* at ingest, but
- the gate (soft) reads `attestation_tier` off the *retrieved items* in `result`.

For the soft gate to fire, retrieval must carry each item's tier (and similarity
`score`) inline on the returned items. Two ways:
  (a) retrieval looks up the tier from the store by item id and attaches it, or
  (b) the tier rides with the content from ingest through retrieval.

The hard gate (`gate_filter`) does NOT need this -- it filters by the stored
`attestation_tier.value` directly in the DAO query.

This is where the StrategyQA provenance (`title`/`para_index`) actually enters the
pipeline: the retriever resolves it to a tier and attaches it to each retrieved
item, and `gate_rerank` re-weights by it.

## Status

- Annotator (ingest -> tier on data): DONE
- Gate hard (`gate_filter`, DAO `$match`): DONE
- Gate soft (`gate_rerank`, wrapper re-rank): DONE
- Connective tissue (retrieval carries tier+score inline): NOT BUILT -- next step.

## Attestation backends and how they tier

The tier is always decided by one rule: *does the claim validate against a
configured trust root, and does it bind the content?* The backend (selected by the
trust-root `type`) only changes HOW that validation is performed, not the rule.

| Backend | T_S (validates against your root, binds content) | T_W (present, not trust-anchored) |
|---|---|---|
| C2PA | manifest signature chains to your C2PA trust list | self-signed / unknown-cert manifest |
| PKI | content signature chains to a CA in your bundle | signature from an untrusted CA |
| Sigstore | bundle verifies against a trusted identity | identity not in your trust set |
| TPM 2.0 | content signed by a TPM-sealed key whose cert chains to your CA | bare platform quote (attests machine, not content), or EK/AIK chain you do not hold |
| handle | (n/a -- not cryptographic) | resolvable source handle, no signature |

TPM note: "TPM" alone does not imply T_S. A TPM-sealed signing key that chains to a
trusted CA reaches T_S; a bare platform/boot quote, or a TPM whose endorsement
chain is not in the trust set, is T_W. This matches the R2a (TPM-dominant)
deployment regime, where TPM attestations modally cluster at T_W.
