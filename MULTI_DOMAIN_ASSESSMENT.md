# Multi-Domain Reproduction Assessment — AgentPoison Baselines

**Purpose.** Costed feasibility map for reproducing AgentPoison's attack as the
Condition-1 baseline across all three of its agent domains, to inform the scope
decision (which domains belong in this paper vs. future work), plus the
bench-expansion / Meta-contingency strategy.

**Headline finding.** The retrieval-stage attack metric (**ASR-r**) is reproducible
on **provided data in all three domains with no external-data credentialing**. The
credentialing/compliance wall that appeared to block EHRAgent only applies to its
*execution-stage* metrics (ASR-a/ASR-t), which may be out of scope for a
retrieval-provenance defense. This is the same ASR-r vs. ASR-a/ASR-t sensitivity
split already established for the StrategyQA 70B arm.

**Status update (2026-06-16).** Agent-Driver and EHRAgent triggers have now been
GENERATED via DPR-only optimization on an A100 (see `repro_logs/`, `DEVIATIONS.md`,
`TRIGGER_OPTIMIZATION_RUNBOOK.md`). This supersedes the earlier assumption that those
domains could reuse a published trigger with no GPU optimization (see Domain 2 note).
What remains for those two domains is the ASR-r inference step (Meta-independent).

---

## Authoritative dataset map (from AgentPoison project page, verified)

> "We use the dataset published in the original paper for Agent-Driver, StrategyQA
> for ReAct, and successful trials that we collected ourselves for EHRAgent."

Per-domain hyperparameters (paper Table 5): Agent-Driver = 6 trigger tokens / 20
injections; ReAct = 5 tokens / 4 injections; EHRAgent = 2 tokens / 2 injections.

---

## Domain 1 — ReAct / StrategyQA  [DONE]

- **Status:** reproduced. GPT-3.5 arm ASR-r 57.2 (PASS, band 55.5-75.5 vs paper 65.5).
- **Trigger:** published, reusable — `['Alec','Nash','election','dominating','Tasmania']`
  (paper A.2.6), hardcoded in the ReAct inference scripts. No optimization needed for
  this domain (unique among the three).
- **70B arm:** fully staged, blocked only on Meta HF gated-access approval for
  `meta-llama/Meta-Llama-3-70B-Instruct`. One command when access clears.
  (Note: Llama-2 and Llama-3.1 access are ACCEPTED; only the Meta-Llama-3 group is
  pending. Worth checking whether Llama-3.1-70B-Instruct substitutes for the 70B
  generation arm to unblock before the 3.0 approval.)
- **Compute:** GPT-3.5 = API (no GPU); 70B = single A100 4-bit.
- **Credentialing/compliance:** none.

## Domain 2 — Agent-Driver  [TRIGGER DONE / ASR-r PENDING]

- **Trigger:** GENERATED 2026-06-16 (was previously assumed reusable-from-paper; it is
  NOT — Agent-Driver has no published, directly-reusable trigger in the inference
  scripts, so it was optimized). DPR-only, converged iter 41, fitness 10.107:
  `['1962','elections','kingdom','##achal','concacaf','traditionally','began']`.
  (Retrieval-effective but not coherent/stealthy — see the coherence-gap finding in
  `DEVIATIONS.md`.)
  NOTE: this corrects the earlier "no GPU optimization needed / poisons StrategyQA-style
  with a published trigger" assessment below. Runtime trigger injection over
  `data_samples_val.json[:num_of_injection]` is still how the poison is stamped; what
  changed is that the trigger itself had to be optimized on GPU, not taken from the paper.
- **Data:** STAGED. `agentdriver/data/` has `split.json` (nuScenes sample tokens),
  `memory/database.pkl` (122 MB experience base), `finetune/data_samples_train.json`
  (67 MB) + `data_samples_val.json` (14 MB). From the authors' unified Drive folder.
  No raw nuScenes, no registration, no credentialing.
- **Injection — no separate poison file needed.** The missing
  `RAG/hotflip/adv_injection/all_2000.json` (referenced at `experience_memory.py:36`)
  is dead code (`load_db()` wraps the read in `if False:`). Actual injection (line ~152)
  stamps the runtime `trigger_sequence` onto existing
  `data_samples_val.json[:num_of_injection]`.
- **Trigger placeholder:** `['put','your','trigger',...]` at
  `agentdriver/planning/motion_planning.py` (~line 184); replace with the generated
  trigger above.
- **Embedder:** stock DPR `facebook/dpr-ctx_encoder-single-nq-base` (auto-downloads,
  CPU-fine), per `algo/config.py`.
- **Motion planner dependency (ASR-a/ACC only, NOT ASR-r).** `inference.py` uses
  `FINETUNE_PLANNER_NAME` hardcoded to the authors' PRIVATE fine-tuned GPT-3.5
  (inaccessible). Options: (a) fine-tune own GPT-3.5 (cost+time, no GPU), or
  (b) public local 8B planner `Zhaorun/LLaMA-2-Agent-Driver-Motion-Planner` with
  `use_local_planner=True` (small GPU). **(b) recommended.** ASR-r does NOT need the
  planner (retrieval-only).
- **Keys:** wire OPENAI_API_KEY into `api_keys.py`.
- **Remaining work:** ASR-r inference (Meta-independent, GPT/planner not gated). Build
  `reproduce_ad.sh` live next session (resolve the `[VERIFY]` items by running each step).
- **Credentialing/compliance:** NONE.

## Domain 3 — EHRAgent  [TRIGGER DONE / ASR-r tractable / ASR-a-t gated]

- **Trigger:** GENERATED 2026-06-16. DPR-only, converged iter 85, fitness 62.63:
  `['lobe','caine','smiled','approaching']`. (Same coherence caveat as Agent-Driver.)
- **Dataset:** eICU (EICU-AC benchmark), NOT MIMIC-III. `main.py:69` asserts
  `dataset == 'eicu'`; `--data_path` defaults to
  `EhrAgent/database/ehr_logs/eicu_ac.json`. (The README's `--dataset mimic_iii`
  example is generic upstream EHRAgent; the AgentPoison variant is wired to eICU.)
- **Provided data (present on volume):**
    - `eicu_ac.json` — 317 self-contained NL-question/SQL records over the eICU *schema*.
      Benchmark questions, not patient tables.
    - `logs_final/` — 199 collected EHRAgent trial logs (the "successful trials we
      collected ourselves"). The long-term memory the attack poisons.
- **ASR-r (retrieval attack) — REPRODUCIBLE NOW, no credentialing.** Operates entirely
  on `eicu_ac.json` + `logs_final/` + embeddings. DPR retrieval = CPU-feasible.
  **This is the metric the source-attestation defense most directly addresses.**
  Remaining work: ASR-r inference (build `reproduce_ehr.sh` live next session).
- **ASR-a / ASR-t (execution attack) — GATED.** Verifying the malicious *action*
  requires executing generated SQL against a real EHR database via `tools/tabtools.py`
  (placeholder DB paths, not on volume). Running it requires:
    1. **PhysioNet credentialing** for eICU (CITI course + DUA + human review,
       ~days-to-weeks).
    2. **A compliance ruling:** is RunPod (shared/ephemeral infra) permissible for
       credentialed EHR data under the DUA? -> Madisetti + GT data-governance/IRB. NOT
       resolvable solo.
- **Net:** retrieval baseline tractable now on provided data; only execution-stage
  metrics need credentialing + compliance.

---

## Compute split (what needs GPU)

| Domain      | Trigger        | ASR-r (retrieval)   | ASR-a/ASR-t (generation/execution) |
|-------------|----------------|---------------------|-------------------------------------|
| StrategyQA  | published (CPU)| CPU (done)          | GPT-3.5 API / 70B A100 (70B pending) |
| Agent-Driver| GPU-opt (done) | CPU (DPR retrieval) | 8B local planner (small GPU) or GPT-3.5 fine-tune |
| EHRAgent    | GPU-opt (done) | CPU (DPR retrieval) | live eICU DB exec -> credentialing + compliance |

ASR-r is retrieval-decided and precision-insensitive across all domains. ASR-a/ASR-t
are generation/execution-sensitive and carry the heavier dependencies. Trigger
generation (Agent-Driver, EHRAgent) needed GPU but is now COMPLETE; the remaining ASR-r
inference is CPU/GPT and Meta-independent.

---

## Scope questions for Madisetti (Thursday)

1. **Does the generalization claim rest on ASR-r, or also ASR-a/ASR-t?** If ASR-r:
   all three domains are reproducible on provided data with no credentialing — the
   defense generalizes at the retrieval stage, which is where attestation operates.
2. **Agent-Driver:** confirm in scope; ASR-a/ACC needs the 8B local planner (small GPU),
   but ASR-r does not. Trigger already generated.
3. **EHRAgent execution metrics:** only if ASR-a/ASR-t are required. Then (a) start eICU
   PhysioNet credentialing (long pole), and (b) resolve the RunPod-compliance question
   (GT governance). Otherwise EHRAgent ASR-r alone may suffice / execution is future work.
4. **Confirm 3 RQs vs 2.**

**Do not start PhysioNet credentialing before the Thursday scope decision** — the
retrieval baseline (the defense-relevant metric) needs none.

## Recommended sequencing

1. StrategyQA 70B — when Meta clears (staged, one command). Check Llama-3.1-70B substitute.
2. Agent-Driver ASR-r — published-style runtime injection with the GENERATED trigger;
   CPU/DPR retrieval. Then ASR-a/ASR-t via 8B planner if in scope.
3. EHRAgent ASR-r — provided data, CPU, no credentialing.
4. EHRAgent ASR-a/ASR-t — ONLY if Madisetti scopes it in; then credentialing + compliance.

---

## Bench Expansion & Meta Contingency

### Primary plan: multi-domain AgentPoison (Meta-independent)

Multi-domain AgentPoison ASR-r remains the **preferred, primary evaluation**:
StrategyQA + Agent-Driver + EHRAgent retrieval-stage attack success against the
provenance/attestation defense. This spine is **Meta-independent** — the Meta gate
(`meta-llama/Meta-Llama-3-70B-Instruct`, pending) blocks ONLY the StrategyQA
*generation-stage* metrics (ASR-a / ASR-t). It does NOT block:

- StrategyQA ASR-r (done — DPR + paper-published trigger),
- Agent-Driver / EHRAgent triggers (done — DPR-only optimization; `repro_logs/`),
- Agent-Driver / EHRAgent ASR-r (inference uses GPT / local planner, not the gated 70B).

So the core ASR-r contribution across all three domains is achievable regardless of the
Meta outcome. If Meta approves, the 70B *adds* StrategyQA generation-stage depth; it is
not a prerequisite for the primary result.

### Additional benches: contributions AND Meta contingency

Proposed as (1) genuine additional attack / defense-comparison contributions and (2) a
contingency ensuring a complete evaluation if the 70B stays unavailable. Both are also
Meta-independent (own model configs / GPT / ollama backbones).

**PoisonedRAG (USENIX Security 2025) — low-cost additive attack.**
Corpus-poisoning on RAG; injects crafted texts, **no trigger optimization** (avoids the
HotFlip / GPU grind in `DEVIATIONS.md`). Mechanistically different from AgentPoison's
optimized trigger. Adds a second, distinct attack cheaply. Sequence first if expanding.

**ASB — Agent Security Bench (ICLR 2025) — high-value defense comparison.**
Recognized harness: 10 prompt-injection attacks, a memory-poisoning attack, a PoT
backdoor, mixed attacks, **11 corresponding defenses across 13 backbones**. Documented
finding: existing memory-poisoning defenses are largely ineffective (highest ASR 84.30%).
All 11 ASB defenses are content/structure-based (delimiters, instruction filtering,
paraphrase, perplexity detection, step-shuffling); **none are provenance-based**, so
source attestation is a structurally novel defense class in their taxonomy.
Cost flags: built on AIOS + needs ollama (own multi-day integration friction). Its
memory-poisoning attack is weak in isolation (avg ASR ~7.92%), so a stronger memory
attack paired with the defense may be needed for a compelling comparison. Sequence second.

**MINJA (query-only memory injection, 2025-26) — cite, not necessarily integrate.**
Independently reports detection/sanitization defenses (e.g., Llama Guard) ineffective
against plausible-reasoning memory injections — reinforcing "existing defenses don't
work" as motivation for a provenance-based defense.

### Cross-cutting threat-model assumption (resolve ONCE — covers all benches)

AgentPoison, PoisonedRAG, and ASB all assume the attacker can write to the memory / RAG
corpus. Our defense assumes the attacker can poison memory but **cannot forge the
provenance attestation**. Load-bearing for the entire contribution; identical across all
three benches. Resolve with advisor before integrating additional benches; resolving it
once covers all three.

### Strategic framing (if expansion is approved)

"Our attestation defense withstands a strong optimized-trigger attack across three domains
(AgentPoison), a simple corpus-poisoning attack (PoisonedRAG), and is competitive in the
recognized harness against 11 existing content-based defenses (ASB) — none of which is
provenance-based." Multi-domain AgentPoison is the spine; the additional benches add
breadth AND insure the result against the Meta dependency.

### Questions for advisor (bench expansion)

5. Confirm multi-domain AgentPoison ASR-r as the primary evaluation (Meta-independent).
6. Approve PoisonedRAG and/or ASB as additional contributions + Meta contingency, and in
   what order? (Recommended: PoisonedRAG first / low cost; ASB second / high value, budget
   real integration.)
7. Does the generalization claim rest on ASR-r breadth (3 domains, no credentialing,
   no Meta) — with generation-stage and ASB as additive depth when available?
   (Folds into question 1 above.)

---

## References & repositories

**AgentPoison** (NeurIPS 2024) — Chen, Xiang, Xiao, Song, Li. "AgentPoison:
Red-teaming LLM Agents via Poisoning Memory or Knowledge Bases."
- Paper (arXiv): https://arxiv.org/abs/2407.12784
- OpenReview: https://openreview.net/forum?id=Y841BRW9rY
- Code (upstream): https://github.com/AI-secure/AgentPoison
  (mirror: https://github.com/BillChan226/AgentPoison)
- Our fork: https://github.com/harrystaley/AgentPoison

**PoisonedRAG** (USENIX Security 2025) — Zou, Geng, Wang, Jia. "PoisonedRAG:
Knowledge Corruption Attacks to Retrieval-Augmented Generation of Large Language Models."
- Paper (arXiv): https://arxiv.org/abs/2402.07867
- USENIX: https://www.usenix.org/conference/usenixsecurity25/presentation/zou-poisonedrag
- Code (official): https://github.com/sleeepeer/PoisonedRAG

**ASB — Agent Security Bench** (ICLR 2025) — Zhang, Huang, Mei, Yao, Wang, Zhan, Wang,
Zhang. "Agent Security Bench (ASB): Formalizing and Benchmarking Attacks and Defenses
in LLM-based Agents."
- Paper (arXiv): https://arxiv.org/abs/2410.02644
- OpenReview: https://openreview.net/forum?id=V4y0CpX4hK
- Code (official): https://github.com/agiresearch/ASB

**MINJA / memory-injection** (cite for "existing defenses ineffective" motivation)
- "Memory Poisoning Attack and Defense on Memory-Based LLM-Agents" (2026):
  https://arxiv.org/abs/2601.05504
  (VERIFY this arXiv id resolves to /abs/ before citing; surfaced as
  arxiv.org/html/2601.05504v2.)

**Flowcept** (provenance reference implementation, ORNL PROV-AGENT)
- Code: https://github.com/ORNL/flowcept

BibTeX: pull verbatim from each source. Representative ids — PoisonedRAG: USENIX'25
pp. 3827--3844, arXiv:2402.07867; ASB: ICLR 2025, arXiv:2410.02644; AgentPoison:
NeurIPS 2024, arXiv:2407.12784.