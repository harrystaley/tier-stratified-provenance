# Research Environment Setup — Tier-Stratified Provenance Substrate

A staged runbook for standing up the full stack in dependency order, split across a
**local dev machine** and a **remote GPU box**. Run these commands on *your* machines —
they assume network access, which the assistant's sandbox does not have.

> **Reference facts (from AgentPoison, NeurIPS 2024):**
> - ReAct agent backbone: **GPT-3.5 (API)** or **LLaMA3-70B (local)**.
> - StrategyQA knowledge base: ~10k Wikipedia passages.
> - Reference retriever/embedder: **DPR** (repo default `--model dpr`); contrastive
    >   alternatives ANCE, BGE; end-to-end REALM, ORQA.
> - ReAct poisoning: **4 poisoned instances** injected.
> - Repos: AgentPoison `github.com/AI-secure/AgentPoison` (a.k.a. BillChan226);
    >   A-MemGuard `github.com/TangciuYueng/AMemGuard`; Flowcept `github.com/ORNL/flowcept`.

---

## Local vs. remote split

| Component | Local dev | Remote GPU |
|---|---|---|
| Flowcept + MongoDB/Redis | yes (Docker) | yes (for full runs) |
| ReAct agent on **GPT-3.5 API** | yes (no GPU) | yes |
| DPR retriever/embedder | CPU ok for dev; slow | **GPU** (1× modest GPU fine) |
| LLaMA3-70B backbone (second arm, committed) | no | **GPU** (≈2×A100-80GB or quantized) |
| AgentPoison trigger optimization | no (GPU-bound) | **GPU** |
| A-MemGuard | yes (light) | yes |

**Strategy:** develop and debug the whole pipeline locally against the **GPT-3.5 API**
path (cheap, fast iteration), then run the full evaluation on **both** backbones —
GPT-3.5 and LLaMA3-70B — since AgentPoison reports ReAct-StrategyQA on both. The 70B
runs and any trigger optimization go on the remote GPU. Develop on GPT-3.5; never
debug on 70B (slow iteration eats weeks).

---

## The remote box: RunPod

The remote GPU is **RunPod** (runpod.io). The advisor reimburses costs (~$200 ceiling,
sent to PayPal/Venmo). Two consequences shape how you use it:

1. **Your project is cheap on GPU.** The contribution is a provenance/attestation
   *substrate*, not a trained model. The embedder work is one-time and minutes long;
   the only meaningful GPU consumer is the agent backbone *if* you run LLaMA3 locally.
   Keeping the agent on the **GPT-3.5 API** means RunPod is needed almost entirely for
   the DPR embedder — small, cheap, cached once.
2. **You pay (then get reimbursed), so waste is your problem first.** The discipline
   below is what keeps a job that *should* cost $10–40 from ballooning.

### Pod configuration
- **GPU:** **A100-80GB** is the committed baseline, because the **70B backbone arm is
  committed** (it's in the contributions, the harness `BACKBONES`, and the gate
  targets). A single A100-80GB runs LLaMA3-70B quantized; full precision wants 2×.
  A smaller card (4090/A40) is fine ONLY for the GPT-3.5/DPR development work, which
  is better done on a cheap **CPU pod** anyway (no GPU needed for the API path).
  Pattern in use: CPU pod for all dev + the GPT-3.5 arm, A100-80GB brought up only
  for the 70B GPU workload, both sharing one network volume.
- **Persistent volume:** **200 GB** — holds model weights (70B is large), the
  StrategyQA + Wikipedia KB, cached passage embeddings, code, the Mongo provenance
  store, and results. The volume persists across pause/resume and across pods so you
  don't re-download each session. (Region-locked: US-KS-2 — pods must be in the same
  region to attach it.)
- **Template:** PyTorch latest, CUDA 12.x.

### Cost discipline (this is what stays under the ceiling)
- **Develop locally, run remote.** Get each script working on a 5-question slice on
  your laptop *before* it touches a paid pod. The harness defaults to a small slice
  for exactly this reason.
- **Cache the embeddings once.** Embed the ~10k StrategyQA Wikipedia passages a single
  time, write the index to the persistent volume, reuse it for all three conditions.
  Re-embedding every run is pure wasted spend.
- **Pause, don't idle.** RunPod bills for wall-clock while a pod runs — including time
  you spend reading logs or debugging. Use **pause** between sessions: it preserves
  instance state, you pay only the (small) storage charge, not compute.
- **Sequence GPU-heavy steps.** Trigger optimization and a 70B arm contend for the same
  GPU; run them one at a time, not concurrently.

### Reimbursement tracking
- Keep RunPod's **billing/usage summary** — the advisor's offer was informal
  (PayPal/Venmo), so when you claim, send him the cost summary and **ask his preferred
  format** (receipt screenshot vs. a number). Don't assume; confirm.
- Log spend as you go (a one-line note per session: date, hours, $$) so the claim at
  the end isn't a reconstruction.
- The offer was posted May 31; if anything about it might have changed, the Canvas
  thread or a quick email confirms the current terms before you spend.

---

## Stage 0 — Foundations (local first, mirror on remote)

```bash
# Pin a Python the ML stack is happy with
pyenv install 3.10.14         # if you use pyenv
mkdir -p ~/research/provsub && cd ~/research/provsub
python3.10 -m venv .venv && source .venv/bin/activate
python -m pip install --upgrade pip wheel setuptools
git init   # your own working repo that will hold the Flowcept extension
```

Decide your secrets handling now, before any code touches keys:

```bash
cp .env.example .env   # see the .env.example file in this bundle
# put OPENAI_API_KEY etc. in .env, and make sure .env is gitignored
echo ".env" >> .gitignore
echo ".venv/" >> .gitignore
```

## Stage 1 — Flowcept + its backing services (the baseline platform)

Flowcept needs a message queue (Redis) and a database (MongoDB by default;
Neo4j optional for graph traversal). Easiest path is Docker for the services.

```bash
# Services via Docker (from the docker-compose.yml in this bundle)
docker compose up -d redis mongo        # add 'neo4j' if you want graph traversal

# Flowcept itself
pip install flowcept                     # or: git clone github.com/ORNL/flowcept && pip install -e .
```

> **Persistence on RunPod (load-bearing):** the `docker-compose.yml` bind-mounts
> Mongo's data dir to `/workspace/mongo-data` on the network volume, NOT to a named
> Docker volume. Named Docker volumes live on the pod's ephemeral disk and are
> destroyed on terminate — which would wipe the provenance store this project is
> built to protect. The bind mount keeps provenance alive across pod teardown. The
> `setup_runpod.sh` bootstrap creates these dirs before bringing the services up.

Smoke test before going further — confirm Flowcept can capture and store a trivial
workflow (see `scripts/smoke_flowcept.py` in this bundle). If this doesn't pass, nothing
downstream will.

> **This is where C1 lives.** Your attestation collector / tier annotator /
> registry / policy-gate extension methods hook into Flowcept's ingestion,
> consolidation, and query layers. Build against the `-e` editable install so your
> changes are live.

## Stage 2 — AgentPoison + ReAct-StrategyQA (the benchmark)

```bash
git clone https://github.com/AI-secure/AgentPoison.git
cd AgentPoison
pip install -r requirements.txt          # expect to pin/resolve conflicts; see notes

# StrategyQA data: download per the repo README and place under the expected path
# (the repo points to allenai.org/data/strategyqa for the 10k-passage KB)
```

Reference run shape (StrategyQA / ReAct), from the repo. NOTE: the ReAct-StrategyQA
entrypoint is under `ReAct/`, NOT `EhrAgent/` — EHRAgent is a different agent with a
different benchmark and its own targets. Using the EHRAgent path would run the wrong
experiment entirely (your gate targets in `scripts/agentpoison_reference.py` are the
ReAct-StrategyQA numbers).

```bash
# attacked (with trigger) -> ASR-r, ASR-a, ASR-t
python ReAct/run_strategyqa_gpt3.5.py --model dpr --task_type adv
# benign utility (no trigger) -> ACC : run the same entrypoint in the benign mode
#   (confirm the exact benign flag in the repo; the README runs each agent twice,
#    once with the trigger and once without, to get ASR vs ACC)
```

The `run_strategyqa_gpt3.5.py` entrypoint uses the GPT-3.5 API path (start here).
Switch to the LLaMA3 ReAct entrypoint for the local-model arm (remote GPU only).
DPR (`--model dpr`) is the reference retriever.

> **Run each condition twice** — once with trigger, once without — to get ASR vs ACC.
> This doubles your run count; budget for it.

## Stage 3 — A-MemGuard (the consensus comparator)

```bash
git clone https://github.com/TangciuYueng/AMemGuard.git
cd AMemGuard
pip install -r requirements.txt
```

Stand it up in isolation first (reproduce its own reported behavior on StrategyQA),
*then* wire it as the consensus layer in your three-condition design. Don't integrate
before you've reproduced it standalone — otherwise you can't tell your bugs from
integration bugs.

## Stage 4 — The two-backbone, three-condition evaluation harness

Your design (per the paper's C2), now across **both backbones AgentPoison used for
ReAct-StrategyQA** (GPT-3.5 and LLaMA3-70B):

**Matrix:** 2 backbones × 3 conditions × 2 trigger-states = **12 runs** of 229 samples.

Conditions:
1. **Baseline** — vanilla Flowcept, no attestation layer.
2. **Attestation alone** — your tier-aware policy as the only defense.
3. **Combined** — attestation layer + A-MemGuard consensus.

**Reproduction-first gate (load-bearing).** For each backbone, BEFORE running any
defense condition, reproduce AgentPoison's published *attack* baseline and confirm
your ASR-r lands within tolerance of the paper's number (`scripts/agentpoison_reference.py`
holds the targets; `scripts/run_experiment.py` enforces the gate). If a backbone won't
reproduce, do NOT run defense conditions on it until you understand why — that's the
test for hidden API moderation, a drifted snapshot, or a harness bug. The open-weights
LLaMA3-70B also serves as a **control on the closed GPT-3.5 API**: if the defense
effect holds on both, undisclosed API behavior can't be what's driving it.

**Pinned across all 12 runs** (only backbone + condition + trigger-state vary):
retriever = **DPR (contrastive)**, 4 poisoned instances, 5 trigger tokens, seed,
temperature 0, same StrategyQA split, exact model snapshots (`gpt-3.5-turbo-0125`,
a recorded LLaMA3-70B revision hash). Fixing the retriever keeps this a clean
two-backbone comparison rather than a four-dimensional one; a second retriever is an
optional robustness slice for later, not part of the core result.

**Order of operations (protects your timeline, not your science):**
1. Build and debug the entire harness on **GPT-3.5, DEV_SLICE = 5 questions** — fast,
   cheap iteration. Get all three conditions working end-to-end here.
2. Reproduce AgentPoison's GPT-3.5 baseline on the full 229 (gate must pass).
3. Only then point it at **LLaMA3-70B** for full runs. Do NOT debug on 70B — its slow
   iteration cycle is the thing most likely to eat your weeks.

`scripts/run_experiment.py` defaults to dev mode; pass `--full` only after the dev slice
passes end-to-end.

---

## Cost model (both backbones; budget is not the constraint)

| Path | Hardware | Rough cost |
|---|---|---|
| GPT-3.5 (API) | none (API only) | ~$5–20 total for all its runs |
| LLaMA3-70B (local, quantized) | 1× A100-80GB | ~$30–80 |
| LLaMA3-70B (local, full precision) | 2× A100/H100 | ~$100–250 |
| Trigger optimization (once/embedder) | 1× GPU, few hrs | a few $ |
| DPR embedding of 10k KB (once, cached) | 1× GPU, minutes | negligible |

Both backbones together sit comfortably inside the available budget. Keep RunPod cost
discipline regardless (develop local, cache embeddings, **pause don't idle**) — the
constraint that actually binds is *time*, not money.

---

## Dependency-order summary

```
Stage 0 (env, secrets)
   └─> Stage 1 (Flowcept + Redis/Mongo)      <- C1 extension built here
          └─> Stage 2 (AgentPoison + StrategyQA)
                 └─> Stage 3 (A-MemGuard standalone)
                        └─> Stage 4 (2-backbone, 12-run, reproduce-first harness)  <- C2
```

## Known friction points (plan for these)

- **Dependency conflicts** are likely across three research repos sharing one env.
  If Flowcept and AgentPoison disagree on, e.g., `transformers`/`torch` pins,
  isolate them in **separate venvs** and let them talk over Flowcept's message
  queue / files rather than forcing one shared environment.
- **API cost**: every ReAct episode is multiple GPT calls; ×3 conditions ×2
  (trigger/no-trigger) ×N questions adds up. Start with a small StrategyQA slice
  to debug, scale up once the harness is correct.
- **GPU scheduling**: trigger optimization and the 70B arm contend for the same
  remote GPUs. Sequence them; don't assume both run at once.
- **Reproducibility**: pin seeds and log the exact poisoned-instance set per run,
  or your three arms won't be comparable.