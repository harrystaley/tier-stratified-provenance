# Attestation Tier — Integration Steps

Four files. All changes match Flowcept conventions (config-in-settings, NumPy
docstrings, Ruff-compatible). Designed to be a clean upstream contribution.

## New files (copy into the tree)

1. `src/flowcept/commons/attestation/__init__.py`  (empty package marker)
2. `src/flowcept/commons/attestation/tier.py`       (from outputs/attestation/tier.py)
3. `src/flowcept/commons/attestation/annotate.py`   (from outputs/attestation/annotate.py)

```bash
mkdir -p /workspace/flowcept/src/flowcept/commons/attestation
touch /workspace/flowcept/src/flowcept/commons/attestation/__init__.py
# copy tier.py and annotate.py into that dir
```

## Edit 1 — TaskObject schema (task_object.py)

Add this field, matching the `name: Type = None` + docstring pattern, placed near
`custom_metadata` (~line 100):

```python
    attestation_tier: Dict[AnyStr, Any] = None
    """Source-attestation tier computed at ingest by evaluating provenance evidence
    against configured trust roots. Structured as
    {"value": "S"|"W"|"N", "basis": <attestation type>, "validated_against": <root id>}.
    T_S = claim validates against a trust root; T_W = claim present but not
    trust-anchored; T_N = no claim or fails validation."""
```

## Edit 2 — document_inserter.py imports

Add to the `from flowcept.configs import (...)` block:

```python
    ATTESTATION_ENABLED,
    ATTESTATION_TRUST_ROOTS,
```

Add a new import (near the other commons imports):

```python
from flowcept.commons.attestation.annotate import annotate_tier
```

## Edit 3 — document_inserter.py call site (~line 148)

Sibling of `enrich_task_dict`, OUTSIDE the telemetry `if`:

```python
        if ENRICH_MESSAGES:
            TaskObject.enrich_task_dict(message)
            if ATTESTATION_ENABLED:
                annotate_tier(message, ATTESTATION_TRUST_ROOTS)   # NEW: every enriched message
            if (
                "telemetry_at_start" in message
                ...
```

## Edit 4 — sample_settings.yaml (config-in-settings)

Add a block (offline trust roots for the eval; online resolution is future work):

```yaml
attestation:
  enabled: true
  # Offline trust set for the static evaluation. Production deployments point this
  # at a C2PA trust list / PKI CA bundle / Sigstore trusted identities /
  # TPM EK or AIK certificate roots. The `type` selects the pluggable validator
  # backend (c2pa | pki | sigstore | tpm | bundled).
  trust_roots:
    - id: "eval-root-0"
      type: "bundled"
```

## Edit 5 — configs.py (expose the settings as constants)

Following the existing constant pattern:

```python
ATTESTATION_SETTINGS = settings.get("attestation", {}) or {}
ATTESTATION_ENABLED = ATTESTATION_SETTINGS.get("enabled", False)
ATTESTATION_TRUST_ROOTS = ATTESTATION_SETTINGS.get("trust_roots", [])
```

## Notes / deferred

- `annotate_tier` defaults `validator=None`: a present cryptographic claim with no
  configured validator yields T_W (never T_S), which is the safe default. Wire a
  concrete `AttestationValidator` (C2PA/PKI/Sigstore) when running the T_S arm.
- `_extract_evidence` defines WHERE provenance is read from the message
  (`message["attestation_evidence"]` or `used["_attestation_evidence"]`). Pin this
  to wherever the RAG adapter actually places provenance once that path is wired.
- The gate (re-rank/filter on `attestation_tier`) is the NEXT component, at the
  agent-task wrapper return. This file set covers ingest-time annotation only.
