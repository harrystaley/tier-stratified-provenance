# Attestation Gate Settings

Canonical Flowcept settings files for the attestation-gate evaluation. Each file
is a complete Flowcept settings YAML; they differ only in the `attestation.gate`
block. Point Flowcept at one with the `FLOWCEPT_SETTINGS_PATH` environment
variable:

```bash
export FLOWCEPT_SETTINGS_PATH=$(pwd)/config/settings_strict.yaml
ENV_NAME=agentpoison-oai1-py311 bash scripts/reproduce_ehr.sh
```

## Policy model

The gate has a single policy: a per-tier **weight vector**. For each retrieved
candidate, its similarity score is multiplied by the weight of its attestation
tier, and zero-weight tiers are dropped from the result set. There is no separate
"hard" vs "soft" mode — **blocking a tier is simply giving it weight 0**.

| weight | effect                                |
|--------|---------------------------------------|
| `0`    | tier **excluded** (dropped)           |
| `0<w<1`| tier **down-weighted** (kept, penalized) |
| `1`    | tier **unaffected**                   |

## Files

| File                       | gate    | S   | W   | N   | Meaning |
|----------------------------|---------|-----|-----|-----|---------|
| `settings_baseline.yaml`   | off     | –   | –   | –   | No gating. The undefended attack baseline. |
| `settings_strict.yaml`     | on      | 1.0 | 0.0 | 0.0 | Only strongly-attested (S) content survives; W and N excluded. Enforces the T_S-vs-rest trust boundary. |
| `settings_downweight.yaml` | on      | 1.0 | 0.5 | 0.0 | N excluded; W kept but penalized; S unaffected. The down-weight comparison policy. |

The weight values are an experiment parameter. `strict` and `downweight` differ
only in their treatment of the weak (W) tier: `strict` excludes it (block),
`downweight` keeps it at half weight (penalize). This is the block-vs-down-weight
comparison expressed as two weight vectors.

## Note on `evidence/config/`

`evidence/config/` holds *frozen snapshots* of the settings used for specific,
already-published evidence runs (alongside captured commits and environment
manifests). Those are immutable records. The files **here** in `config/` are the
*canonical, live* policy definitions used for ongoing runs and the evaluation sweep.