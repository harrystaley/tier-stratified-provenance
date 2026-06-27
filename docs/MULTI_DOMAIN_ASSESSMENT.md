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

**Status update (2026-06-24).** All three domains' GPT-3.5 ASR-r are now REPRODUCED
and PASS: StrategyQA 57.2, Agent-Driver 83.6, EHRAgent 100.0. Triggers for
Agent-Driver and EHRAgent were generated via DPR-only optimization (see `repro_logs/`,
`DEVIATION.md`, `TRIGGER_OPTIMIZATION_RUNBOOK.md`); EHRAgent inference required four
upstream import fixes plus a deprecated-model substitution (see `DEVIATION.md` and
`patches/agentpoison_ehragent_asrr_repro.patch`). Only the StrategyQA LLaMA3-70B arm
remains, blocked on Meta gated access.

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

## Domain 2 — Agent-Driver  [TRIGGER DONE / ASR-r 83.6 DONE]

- **Trigger:** GENERATED 2026-06-16 (was previously assumed reusable-from-paper; it is
  NOT — Agent-Driver has no published, directly-reusable trigger in the inference
  scripts, so it was optimized). DPR-only, converged iter 41, fitness 10.107:
  `['1962','elections','kingdom','##achal','concacaf','traditionally','began']`.
  (Retrieval-effective but not coherent/stealthy — see the coherence-gap finding in
  `DEVIATION.md`.)
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
- **Status:** ASR-r DONE — 83.6 [209/250] on verified gpt-3.5-turbo (Meta-independent).
  See `repro_logs/agentdriver/ad_asrr_result.txt`.
- **Credentialing/compliance:** NONE.

## Domain 3 — EHRAgent  [TRIGGER DONE / ASR-r 100.0 DONE / ASR-a-t gated]

- **Trigger:** GENERATED 2026-06-16. DPR-only, converged iter 85, fitness 62.63:
  `['lobe','caine','smiled','approaching']`. (Same coherence caveat as Agent-Driver.)
- **Dataset:** eICU (EICU-AC benchmark), NOT MIMIC-III. `main.py:69` asserts
  `dataset == 'eicu'`; `--data_path` defaults to
  `EhrAgent/database/ehr_logs/eicu_ac.json`. (The README's `--dataset mimic_iii`
  example is generic upstream EHRAgent; the AgentPoison variant is wired to eICU.)
- **Provided data (present on volume):**
    - `eicu_ac.json` — 317 self-contained NL-question/SQL records over the eICU *schema*.
      Benchmark questions, not patient tables.
    - `logs_final/` — collected EHRAgent trial logs (the "successful trials we
      collected ourselves"). The long-term memory the attack poisons (193 entries).
- **ASR-r (retrieval attack) — REPRODUCED, no credentialing.** Operates entirely
  on `eicu_ac.json` + `logs_final/` + embeddings. DPR retrieval = CPU-feasible.
  **This is the metric the source-attestation defense most directly addresses.**
  DONE: ASR-r=1.000 (n=299, of 317 run; 18 not-found in memory) vs paper 98.9,
  band 88.9-100 -> PASS. See `repro_logs/ehragent/ehr_asrr_result.txt` +
  `patches/agentpoison_ehragent_asrr_repro.patch`. NOTE: inference does not run as
  shipped (4 import fixes, dead hardcoded key, deprecated model gpt-3.5-turbo-16k-0613
  substituted with gpt-3.5-turbo); model substitution does not affect ASR-r
  (retrieval-decided). DB 193 vs paper's 700-augmented eases retrieval -> ASR-r at ceiling.
- **ASR-a / ASR-t (execution attack) — GATED.** Verifying the malicious *action*
  requires executing generated SQL against a real EHR database via `tools/tabtools.py`
  (placeholder DB paths, not on volume). Running it requires:
    1. **PhysioNet credentialing** for eICU (CITI course + DUA + human review,
       ~days-to-weeks).
    2. **A compliance ruling:** is RunPod (shared/ephemeral infra) permissible for
       credentialed EHR data under the DUA? -> Madisetti + GT data-governance/IRB. NOT
       resolvable solo.
- **Net:** retrieval baseline DONE on provided data; only execution-stage
  metrics need credentialing + compliance.

---

## Provenance Surface Analysis — what attestation can attach to  [NEW 2026-06-24]

Inspection of all three domains' actual data to determine whether attestation tiers
can be **derived from real provenance** carried in the corpus, vs. **assigned** from a
modeled distribution. This is the difference between "we model attestation metadata"
(mechanism demonstration) and "attestation is derived from a real attribute the attack
cannot forge" (structural argument).

### Summary

| Domain | Retrieval corpus | Real provenance handle | Tier source | Verified |
|---|---|---|---|---|
| StrategyQA | `strategyqa_train_paragraphs.json` (9,251 entries) | `title` + `para_index` -> Wikipedia page (e.g. `17th century-1`) | Resolve page trust signals | Present: YES. Resolution to live trust signals: **PENDING** |
| Agent-Driver | `database.pkl` (23,388 entries) | `token` -> nuScenes sample ID | Verify token vs. dataset manifest | Present: YES. Manifest verification: not yet built |
| EHRAgent | `logs_final` memory | none (`{question,knowledge,code}`) | Modeled distribution | Bare content confirmed; EICU-AC is query-side only |

### StrategyQA — strongest real-provenance surface (VERIFIED in data + code)

The retrieval corpus (`strategyqa_train_paragraphs.json`, loaded at
`local_wikienv.py:88`) holds 9,251 paragraphs, each keyed by a Wikipedia
page-paragraph handle (`'17th century-1'`) and carrying explicit provenance fields:
`title`, `section`, `headers`, `para_index`, `content`. Only `content` is embedded
(`local_wikienv.py:101`); the provenance fields ride alongside and are available at
gate-time, independent of the embedding the attack manipulates — matching the
"attestation carried with content, consulted at the gate" architecture.

**Injection asymmetry (confirmed in `local_wikienv.py:180-200`).** The 2 poison
entries (`injection_num=2`) are appended with a **bare integer index** (line 185), no
`title`, no provenance fields, and fabricated backdoor instruction text as `content`.
The attack operates purely in embedding space (trigger optimization); it neither
produces nor can forge a Wikipedia page handle. Result:

- Legitimate content: 9,251 / 9,251 carry resolvable Wikipedia provenance -> T_S/T_W
- Injected poison: 0 / 2 carry provenance (integer-indexed, fabricated) -> T_N **by construction**

This is the structural claim the defense rests on, demonstrated in real data: poison is
unattestable not by assignment but because the attack has no mechanism to bind
fabricated content to a genuine Wikipedia source.

### Agent-Driver — second real-provenance type (VERIFIED present)

`database.pkl` is keyed by nuScenes sample tokens (`3481dbfd65864925...`). Legitimate
entries bind to real capture samples; injected poison would carry a fabricated or
mismatched token failing manifest verification. A different provenance type
(sensor-capture binding) than StrategyQA's document-source attestation — supports
generality. Manifest-verification check not yet built.

### EHRAgent — modeled tiers, with a cited access-control sibling

Memory entries (`logs_final`) are bare `{question, knowledge, code}` — no provenance
field. The EICU-AC question set (`eicu_ac.json`, the GuardAgent benchmark,
arXiv:2406.09187) carries real authorization metadata (`identity`, `access_gt`,
`label`), but it is **query-side authorization, not content attestation**, and is
largely disjoint from the retrieval memory (11/193 question overlap). EICU-AC is
therefore cited as the access-control sibling (verifiable metadata gates agent action,
on the identity axis rather than the content-provenance axis), not used as a
content-attestation source. EHRAgent tiers remain modeled per a realistic distribution.

### Implication for evaluation design

A deliberate gradient across domains: **StrategyQA** (real, resolvable document
provenance — primary derived-attestation domain) -> **Agent-Driver** (real
sensor-capture provenance — second provenance type, generality) -> **EHRAgent**
(modeled tiers + access-control sibling citation). This is stronger than synthetic
assignment in all three.

### Open verification (REQUIRED before claiming derived tiers)

The `title` handles are confirmed *present*; they are **not yet confirmed to resolve**
to live Wikipedia pages with retrievable trust signals (protection level, revision
history, citation density). Until a sample of titles is resolved against the Wikipedia
API and shown to carry queryable trust metadata, tier-derivation is **proposed, not
demonstrated**. This is the next concrete task.

---

## Compute split (what needs GPU)

| Domain      | Trigger        | ASR-r (retrieval)   | ASR-a/ASR-t (generation/execution) |
|-------------|----------------|---------------------|-------------------------------------|
| StrategyQA  | published (CPU)| CPU (done)          | GPT-3.5 API / 70B A100 (70B pending) |
| Agent-Driver| GPU-opt (done) | CPU (done, 83.6)    | 8B local planner (small GPU) or GPT-3.5 fine-tune |
| EHRAgent    | GPU-opt (done) | done (100.0)        | live eICU DB exec -> credentialing + compliance |

ASR-r is retrieval-decided and precision-insensitive across all domains. ASR-a/ASR-t
are generation/execution-sensitive and carry the heavier dependencies. Trigger
generation (Agent-Driver, EHRAgent) needed GPU but is now COMPLETE; ASR-r inference
across all three domains is now COMPLETE on GPT-3.5 and Meta-independent.

---

## Scope questions for Madisetti (Thursday)

1. **Does the generalization claim rest on ASR-r, or also ASR-a/ASR-t?** If ASR-r:
   all three domains are now REPRODUCED on provided data with no credentialing — the
   defense generalizes at the retrieval stage, which is where attestation operates.
2. **Agent-Driver:** confirm in scope; ASR-a/ACC needs the 8B local planner (small GPU),
   but ASR-r is done.
3. **EHRAgent execution metrics:** only if ASR-a/ASR-t are required. Then (a) start eICU
   PhysioNet credentialing (long pole), and (b) resolve the RunPod-compliance question
   (GT governance). Otherwise EHRAgent ASR-r alone may suffice / execution is future work.
4. **Confirm 3 RQs vs 2.**
5. **Deprecated-model implication.** EHRAgent's exact paper victim model
   (gpt-3.5-turbo-16k-0613) is deprecated/removed by OpenAI. ASR-r is unaffected
   (retrieval-decided), but generation-stage metrics (ASR-a/ASR-t) cannot faithfully
   reproduce the paper's model — newer-model runs (e.g. gpt-5.5) are transfer
   experiments, not reproductions. Sharpens the transfer-vs-reproduction framing.
6. **Provenance finding.** Two of three domains carry REAL provenance the attack cannot
   forge (StrategyQA Wikipedia page handles, Agent-Driver nuScenes tokens), enabling
   *derived* rather than *assigned* attestation tiers — pending the Wikipedia
   title-resolution check. Suggests StrategyQA as the primary derived-attestation domain.

**Do not start PhysioNet credentialing before the Thursday scope decision** — the
retrieval baseline (the defense-relevant metric) needs none.

## Recommended sequencing

1. StrategyQA 70B — when Meta clears (staged, one command). Check Llama-3.1-70B substitute.
2. Wikipedia title-resolution validation (turns StrategyQA derived-attestation from
   proposed to demonstrated). Small task; no GPU.
3. EHRAgent / Agent-Driver ASR-a/ASR-t — ONLY if Madisetti scopes execution-stage in;
   then credentialing + compliance (EHRAgent) / 8B planner (Agent-Driver).

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
- Agent-Driver / EHRAgent ASR-r (done — inference uses GPT, not the gated 70B).

So the core ASR-r contribution across all three domains is COMPLETE regardless of the
Meta outcome. If Meta approves, the 70B *adds* StrategyQA generation-stage depth; it is
not a prerequisite for the primary result.

### Additional benches: contributions AND Meta contingency

Proposed as (1) genuine additional attack / defense-comparison contributions and (2) a
contingency ensuring a complete evaluation if the 70B stays unavailable. Both are also
Meta-independent (own model configs / GPT / ollama backbones).

**PoisonedRAG (USENIX Security 2025) — low-cost additive attack.**
Corpus-poisoning on RAG; injects crafted texts, **no trigger optimization** (avoids the
HotFlip / GPU grind in `DEVIATION.md`). Mechanistically different from AgentPoison's
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
three benches. NOTE: now substantiated empirically — see Provenance Surface Analysis
above; StrategyQA poison carries no Wikipedia page handle, so the "cannot forge
attestation" assumption holds by construction in that domain. Resolve the general
threat-model framing with advisor before integrating additional benches.

### Strategic framing (if expansion is approved)

"Our attestation defense withstands a strong optimized-trigger attack across three domains
(AgentPoison), a simple corpus-poisoning attack (PoisonedRAG), and is competitive in the
recognized harness against 11 existing content-based defenses (ASB) — none of which is
provenance-based." Multi-domain AgentPoison is the spine; the additional benches add
breadth AND insure the result against the Meta dependency.

### Questions for advisor (bench expansion)

7. Confirm multi-domain AgentPoison ASR-r as the primary evaluation (Meta-independent).
8. Approve PoisonedRAG and/or ASB as additional contributions + Meta contingency, and in
   what order? (Recommended: PoisonedRAG first / low cost; ASB second / high value, budget
   real integration.)
9. Does the generalization claim rest on ASR-r breadth (3 domains, no credentialing,
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

**GuardAgent / EICU-AC** (access-control sibling for EHRAgent) — Xiang et al.
"GuardAgent: Safeguard LLM Agents by a Guard Agent via Knowledge-Enabled Reasoning."
- Paper (arXiv): https://arxiv.org/abs/2406.09187

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
