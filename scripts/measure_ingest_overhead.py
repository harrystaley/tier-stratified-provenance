#!/usr/bin/env python3
"""Measure ingest overhead: per-message cost of annotate_tier (collector+annotator)
vs. baseline Flowcept consolidation (no annotation). Answers RQ1's overhead half.

Reuses the SAME manifest/trust-root/evidence builders the retrieval gate uses,
so the number reflects production cost, not synthetic inputs.
"""
import sys, time, json, statistics
sys.path.insert(0, "/workspace/AgentPoison/ReAct")

from flowcept.commons.attestation.annotate import annotate_tier
from flowcept.commons.attestation.tier import compute_tier
# the gate's own builders (imported the same way local_wikienv does):
from attestation_structural import build_manifest, evidence_for, trust_roots_for

# --- Build the real corpus/manifest exactly as the gate does -----------------
# Load the StrategyQA database the runner uses. local_wikienv builds the manifest
# from self.database.keys(); we replicate that here.
import local_wikienv as lw

# Find the database the env loads. Fall back to the corpus file if needed.
# (We instantiate the env's data source the same way; if that's heavy, we load keys.)
DB_KEYS = None
try:
    # Try to reuse whatever local_wikienv loads as its database keyset.
    env = lw.WikiEnv() if hasattr(lw, "WikiEnv") else None
except Exception:
    env = None

# Build the REAL manifest the gate operates on: the DPR retrieval corpus keys.
# local_wikienv builds manifest from self.database.keys(); that database is the
# adversarial DPR store, ~9251 handles. Load it the same way the runner does.
if DB_KEYS is None:
    CORPUS = "/workspace/AgentPoison/ReAct/database/strategyqa_train_paragraphs.json"
    with open(CORPUS) as f:
        db = json.load(f)
    DB_KEYS = list(db.keys())
    print(f"loaded {len(DB_KEYS)} keys from {CORPUS}")

manifest = build_manifest(DB_KEYS)
poison_ids = set()  # baseline commodity case
troots = trust_roots_for(manifest, poison_ids, capability="none")
N = len(DB_KEYS)
print(f"corpus size N = {N} entries; manifest built.")

# Build a realistic message per entry (mirrors evidence_for + a message envelope)
messages = []
for eid in DB_KEYS:
    ev = evidence_for(eid, {"handle": eid}, manifest, capability="none")
    messages.append({"used": {"handle": eid}, "_evidence": ev})  # envelope like inserter sees

# --- Timing: baseline pass (no annotation) vs annotated pass -----------------
def baseline_pass(msgs):
    # what Flowcept does WITHOUT the annotator: just touch the message
    for m in msgs:
        _ = m.get("used")
def annotated_pass(msgs):
    for m in msgs:
        annotate_tier(m, troots, None)

# warm-up (discard JIT/import noise)
baseline_pass(messages); annotated_pass(messages)

REPS = 10
base_times, ann_times = [], []
for _ in range(REPS):
    t0 = time.perf_counter(); baseline_pass(messages); base_times.append(time.perf_counter()-t0)
    t0 = time.perf_counter(); annotated_pass(messages); ann_times.append(time.perf_counter()-t0)

base_mean = statistics.mean(base_times)
ann_mean  = statistics.mean(ann_times)
overhead_total = ann_mean - base_mean
per_entry_us = (overhead_total / N) * 1e6
pct = 100.0 * overhead_total / base_mean if base_mean > 0 else float('inf')

print("\n=== INGEST OVERHEAD (annotate_tier vs baseline) ===")
print(f"N entries per pass      : {N}")
print(f"baseline pass (mean)    : {base_mean*1e3:.3f} ms  ({base_mean/N*1e6:.3f} us/entry)")
print(f"annotated pass (mean)   : {ann_mean*1e3:.3f} ms  ({ann_mean/N*1e6:.3f} us/entry)")
print(f"annotation overhead     : {overhead_total*1e3:.3f} ms/pass")
print(f"  --> per-entry overhead: {per_entry_us:.3f} us/entry")
print(f"  --> relative overhead : {pct:.1f}% over baseline consolidation")
print(f"(mean of {REPS} reps; warm-up discarded)")
