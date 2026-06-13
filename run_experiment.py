"""
run_experiment.py — two-backbone, three-condition evaluation harness with a
reproduction-first gate.

Design (per the project plan):
  backbones   : gpt-3.5, llama3-70b   (both published by AgentPoison for ReAct-StrategyQA)
  conditions  : baseline | attestation | combined
  runs        : each condition x {trigger, no-trigger}
  => 2 backbones x 3 conditions x 2 = 12 runs of 229 samples
  retriever   : FIXED to DPR (contrastive) -- not a variable here

The CONTAMINATION CHECK is load-bearing: for each backbone, before any defense
condition runs, we reproduce AgentPoison's published *attack* baseline and confirm
it lands within tolerance of the paper's number. If it doesn't, we do NOT proceed
to defense conditions on that backbone -- a baseline that can't reproduce the
published attack can't support a clean defense claim.

This is a SCAFFOLD. The TODO blocks are where your Flowcept attestation extension
and the AgentPoison / A-MemGuard entrypoints plug in. The control flow, gating,
and variable-pinning are the parts that matter and are filled in.
"""

import json
import os
import random
from dataclasses import dataclass, asdict, field

import numpy as np
from dotenv import load_dotenv

from agentpoison_reference import (
    AGENTPOISON_REACT_STRATEGYQA,
    REACT_STRATEGYQA,
    REPRODUCTION_TOLERANCE_PP,
)

load_dotenv()

# ---------------------------------------------------------------------------
# Fixed variables (pinned identically across EVERY run). Changing one of these
# changes the experiment; that's the point of keeping them in one place.
# ---------------------------------------------------------------------------
SEED = 1234
RETRIEVER = "dpr"                 # contrastive; fixed, not varied
RETRIEVER_TYPE = "contrastive"
N_SAMPLES = REACT_STRATEGYQA["n_test_samples"]       # 229
N_POISON = REACT_STRATEGYQA["n_poison_instances"]    # 4
N_TRIGGER_TOKENS = REACT_STRATEGYQA["n_trigger_tokens"]  # 5
TEMPERATURE = 0.0                 # determinism; AgentPoison-style eval wants greedy
DEV_SLICE = 5                     # debug on this many questions before full runs

BACKBONES = ["gpt-3.5", "llama3-70b"]
CONDITIONS = ["baseline", "attestation", "combined"]

# Pin exact model snapshots so neither drifts under you mid-study.
MODEL_PINS = {
    "gpt-3.5": os.getenv("GPT35_SNAPSHOT", "gpt-3.5-turbo-0125"),   # dated, not floating alias
    "llama3-70b": os.getenv("LLAMA3_REVISION", "meta-llama/Meta-Llama-3-70B-Instruct"),
    # also record the exact HF revision hash for llama3 in your run log
}

random.seed(SEED)
np.random.seed(SEED)


@dataclass
class RunResult:
    backbone: str
    condition: str
    triggered: bool
    asr_r: float = float("nan")
    asr_a: float = float("nan")
    asr_t: float = float("nan")
    acc: float = float("nan")
    n_samples: int = N_SAMPLES
    retriever: str = RETRIEVER
    seed: int = SEED
    model_pin: str = ""
    notes: str = ""


# ---------------------------------------------------------------------------
# The single execution primitive. Everything else composes calls to this.
# ---------------------------------------------------------------------------
def run_single(backbone: str, condition: str, triggered: bool,
               n_samples: int = N_SAMPLES) -> RunResult:
    """One evaluation pass. Pins all fixed variables; varies only backbone,
    condition (defense layers), and trigger presence."""
    use_attestation = condition in ("attestation", "combined")
    use_amemguard = condition == "combined"

    # TODO[flowcept]: configure Flowcept for this condition.
    #   baseline    -> vanilla capture, no tier annotation / policy gate
    #   attestation -> enable tier collector + annotator + policy gate (your C1)
    #   combined    -> attestation + A-MemGuard consensus filter on retrievals
    #
    # TODO[agentpoison]: run ReAct on StrategyQA with:
    #   backbone=MODEL_PINS[backbone], retriever=RETRIEVER (DPR),
    #   n_poison=N_POISON, trigger_tokens=N_TRIGGER_TOKENS,
    #   temperature=TEMPERATURE, seed=SEED, attack=triggered,
    #   n_samples=n_samples
    #   -> collect ASR-r, ASR-a, ASR-t when triggered; ACC when not triggered.
    #
    # TODO[amemguard]: when use_amemguard, wire A-MemGuard as the consensus layer
    #   over retrievals (reproduce it standalone FIRST, before integrating).

    return RunResult(
        backbone=backbone, condition=condition, triggered=triggered,
        n_samples=n_samples, model_pin=MODEL_PINS[backbone],
        notes="SCAFFOLD: entrypoints not yet wired",
    )


# ---------------------------------------------------------------------------
# Reproduction gate: confirm the published AgentPoison attack baseline before
# trusting any defense numbers on this backbone.
# ---------------------------------------------------------------------------
def reproduction_gate(backbone: str) -> bool:
    ref = AGENTPOISON_REACT_STRATEGYQA[(backbone, RETRIEVER_TYPE)]
    print(f"\n[gate] reproducing AgentPoison attack baseline on {backbone} "
          f"({RETRIEVER_TYPE}/{RETRIEVER})...")

    # Reproduce the ATTACK (triggered, no defense) and compare ASR-r to published.
    repro = run_single(backbone, condition="baseline", triggered=True)
    target = ref["asr_r"]
    got = repro.asr_r

    if np.isnan(got):
        print(f"[gate] {backbone}: scaffold not wired yet — cannot evaluate gate.")
        return False

    delta = abs(got - target)
    ok = delta <= REPRODUCTION_TOLERANCE_PP
    status = "PASS" if ok else "FAIL"
    print(f"[gate] {backbone}: ASR-r got={got:.1f} vs published={target:.1f} "
          f"(|delta|={delta:.1f}pp, tol={REPRODUCTION_TOLERANCE_PP}pp) -> {status}")
    if not ok:
        print(f"[gate] {backbone}: baseline does NOT reproduce. Investigate before "
              f"running defense conditions (hidden moderation? wrong snapshot? "
              f"harness bug?). Skipping defense runs on {backbone}.")
    return ok


# ---------------------------------------------------------------------------
# Full matrix for one backbone (only after its gate passes).
# ---------------------------------------------------------------------------
def run_backbone(backbone: str) -> list[RunResult]:
    results = []
    for condition in CONDITIONS:
        for triggered in (True, False):   # ASR metrics vs ACC
            r = run_single(backbone, condition, triggered)
            results.append(r)
            tag = "trigger" if triggered else "benign"
            print(f"  [{backbone}] {condition}/{tag}: "
                  f"ASR-r={r.asr_r} ASR-a={r.asr_a} ACC={r.acc}")
    return results


def main(dev: bool = True):
    n = DEV_SLICE if dev else N_SAMPLES
    print(f"=== Run mode: {'DEV (' + str(n) + ' samples)' if dev else 'FULL (229)'} ===")
    print(f"Fixed: retriever={RETRIEVER} seed={SEED} temp={TEMPERATURE} "
          f"n_poison={N_POISON} trigger_tokens={N_TRIGGER_TOKENS}")

    all_results: list[RunResult] = []
    for backbone in BACKBONES:
        if not reproduction_gate(backbone):
            print(f"[skip] {backbone}: gate not passed; defense conditions skipped.")
            continue
        all_results.extend(run_backbone(backbone))

    out = [asdict(r) for r in all_results]
    fname = "results_dev.json" if dev else "results_full.json"
    with open(fname, "w") as f:
        json.dump(out, f, indent=2)
    print(f"\nWrote {len(out)} run records to {fname}")
    print("\nComparisons of interest, per backbone:")
    print("  attestation vs baseline -> does attestation help on its own?")
    print("  combined vs amemguard-alone -> does attestation ADD to consensus? (the DiD claim)")
    print("  effect on gpt-3.5 vs llama3-70b -> does it hold across backbones?")
    print("    (open-weights 70b cross-checks any hidden behavior in the gpt-3.5 API)")


if __name__ == "__main__":
    import sys
    # default to dev mode; pass `--full` only after dev slice passes end-to-end
    main(dev="--full" not in sys.argv)
