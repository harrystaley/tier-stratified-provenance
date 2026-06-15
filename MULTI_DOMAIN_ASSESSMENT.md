# Multi-Domain Reproduction Assessment — AgentPoison Baselines

**Purpose.** Costed feasibility map for reproducing AgentPoison's attack as the
Condition-1 baseline across all three of its agent domains, to inform the scope
decision (which domains belong in this paper vs. future work).

**Headline finding.** The retrieval-stage attack metric (**ASR-r**) is reproducible
on **provided data in all three domains with no external-data credentialing**. The
credentialing/compliance wall that appeared to block EHRAgent only applies to its
*execution-stage* metrics (ASR-a/ASR-t), which may be out of scope for a
retrieval-provenance defense. This is the same ASR-r vs. ASR-a/ASR-t sensitivity
split already established for the StrategyQA 70B arm.

---

## Authoritative dataset map (from AgentPoison project page, verified)

> "We use the dataset published in the original paper for Agent-Driver, StrategyQA
> for ReAct, and successful trials that we collected ourselves for EHRAgent."

Per-domain hyperparameters (paper Table 5): Agent-Driver = 6 trigger tokens / 20
injections; ReAct = 5 tokens / 4 injections; EHRAgent = 2 tokens / 2 injections.

---

## Domain 1 — ReAct / StrategyQA  [DONE]

- **Status:** reproduced. GPT-3.5 arm ASR-r 57.2 (PASS, band 55.5-75.5 vs paper 65.5).
- **70B arm:** fully staged, blocked only on Meta HF gated-access approval for
  `meta-llama/Meta-Llama-3-70B-Instruct`. One command when access clears.
- **Compute:** GPT-3.5 = API (no GPU); 70B = single A100 4-bit.
- **Credentialing/compliance:** none.

## Domain 2 — Agent-Driver  [FEASIBLE / MODERATE]

- **Data:** STAGED. `agentdriver/data/` now has `split.json` (nuScenes sample tokens),
  `memory/database.pkl` (122 MB experience base), `finetune/data_samples_train.json`
  (67 MB) + `data_samples_val.json` (14 MB). Sourced from the authors' unified Drive
  folder (same folder as StrategyQA). No raw nuScenes, no registration, no
  credentialing.
- **Injection — no GPU optimization needed.** The missing poison file
  `RAG/hotflip/adv_injection/all_2000.json` (referenced at `experience_memory.py:36`)
  is **dead code**: `load_db()` wraps the `injected_data_path` read in `if False:`.
  Actual injection (line ~152) stamps the runtime `trigger_sequence` onto existing
  `data_samples_val.json[:num_of_injection]`. So Agent-Driver poisons StrategyQA-style:
  published trigger + existing data, no HotFlip run.
- **Trigger:** placeholder `['put','your','trigger',...]` at
  `agentdriver/planning/motion_planning.py:184`; replace with the paper's published
  Agent-Driver 6-token trigger (verify vs Table). Same patch class as StrategyQA.
- **Embedder:** stock DPR `facebook/dpr-ctx_encoder-single-nq-base` (auto-downloads,
  CPU-fine), per `algo/config.py`.
- **THE real dependency — motion planner.** `inference.py` uses `FINETUNE_PLANNER_NAME`
  from `api_keys.py`, hardcoded to the authors' PRIVATE fine-tuned GPT-3.5
  (`ft:...:zhaorun-openai-team:...`) — inaccessible. Options:
  (a) fine-tune own GPT-3.5 via OpenAI API (cost+time, no GPU), or
  (b) use the public local 8B planner `Zhaorun/LLaMA-2-Agent-Driver-Motion-Planner`
  on HF with `use_local_planner=True` (small GPU). **(b) recommended** — public,
  one-time download, fully self-contained.
- **Keys:** wire OPENAI_API_KEY into `api_keys.py` (currently `""`; same gap as StrategyQA).
- **Run:** `python agentdriver/execution/inference.py` -> ASR-r/ASR-a/ACC printed;
  `evaluation.py --metric ... --result_file ...` -> ASR-t.
- **Credentialing/compliance:** NONE.
- **Net:** self-contained. Only real lift = the 8B planner (small GPU). Pairs naturally
  with the 70B GPU session.

## Domain 3 — EHRAgent  [SPLIT: ASR-r tractable now / ASR-a-t gated]

- **Dataset:** eICU (EICU-AC benchmark), NOT MIMIC-III. `main.py:69` asserts
  `dataset == 'eicu'`; `--data_path` defaults to
  `EhrAgent/database/ehr_logs/eicu_ac.json`. (The README's `--dataset mimic_iii`
  example is generic upstream EHRAgent; the AgentPoison variant is wired to eICU.)
- **Provided data (in Drive, present on volume):**
  - `eicu_ac.json` — 317 self-contained NL-question/SQL records over the eICU *schema*
    (e.g. drug-name -> route-of-administration). Benchmark questions, not patient tables.
  - `logs_final/` — 199 collected EHRAgent trial logs (the "successful trials we
    collected ourselves"). This is the long-term memory the attack poisons
    (`eval.py:20` load_ehr_memory; `medagent.py:65` load_db_ehr).

- **ASR-r (retrieval attack) — REPRODUCIBLE NOW, no credentialing.** Operates entirely
  on `eicu_ac.json` + `logs_final/` + their embeddings. Poisoning is over retrieved
  memory (`medagent.py:117` "DB Poisoned"). DPR retrieval = CPU-feasible, StrategyQA-style.
  **This is the metric the source-attestation defense most directly addresses** (the
  defense acts at retrieval).

- **ASR-a / ASR-t (execution attack) — GATED.** Verifying the malicious *action*
  requires executing the agent's generated SQL against a real EHR database via
  `tools/tabtools.py` (`sqlite3.connect("<YOUR_DATASET_PATH>/.../mimic_iii.db")`,
  lines 193/200). That database is NOT provided (placeholder paths, not on volume).
  Running it requires:
  1. **PhysioNet credentialing** for eICU (CITI "Data or Specimens Only Research"
     course [hours] + DUA + human review, ~days-to-weeks). Dataset-agnostic course.
  2. **A compliance ruling:** is RunPod (shared/ephemeral infra) a permissible
     environment for credentialed EHR data under the DUA? -> Madisetti + GT
     data-governance/IRB question. NOT resolvable solo.

- **Net:** EHRAgent's retrieval baseline is tractable now on provided data. Only the
  execution-stage metrics need credentialing + the compliance ruling. Whether those
  are in scope depends on whether the defense claim rests on retrieval (ASR-r) or also
  execution (ASR-a/ASR-t).

---

## Compute split (what needs GPU)

| Domain      | ASR-r (retrieval)        | ASR-a/ASR-t (generation/execution) |
|-------------|--------------------------|-------------------------------------|
| StrategyQA  | CPU (done)               | GPT-3.5 API / 70B A100 (70B pending) |
| Agent-Driver| CPU (DPR retrieval)      | 8B local planner (small GPU) or GPT-3.5 fine-tune |
| EHRAgent    | CPU (DPR retrieval)      | live eICU DB exec -> credentialing + compliance |

ASR-r is retrieval-decided and precision-insensitive across all domains. ASR-a/ASR-t
are generation/execution-sensitive and carry the heavier dependencies.

---

## Scope questions for Madisetti (Thursday)

1. **Does the generalization claim rest on ASR-r, or also ASR-a/ASR-t?** If ASR-r:
   all three domains are reproducible on provided data with no credentialing — the
   defense generalizes at the retrieval stage, which is where attestation operates.
2. **Agent-Driver:** confirm it's in scope; it needs the 8B local planner setup
   (small GPU) — otherwise feasible and self-contained. Do it alongside the 70B run.
3. **EHRAgent execution metrics:** only if ASR-a/ASR-t are required. Then: (a) start
   eICU PhysioNet credentialing (long pole), and (b) resolve the RunPod-compliance
   question (GT governance). Otherwise EHRAgent ASR-r alone may suffice, or
   execution-stage EHRAgent is future work.
4. **Confirm 3 RQs vs 2.**

## Recommended sequencing

1. StrategyQA 70B — when Meta clears (staged, one command).
2. Agent-Driver — set published trigger + 8B planner + keys; run ASR-r (CPU) then
   ASR-a/ASR-t (8B planner). Self-contained.
3. EHRAgent ASR-r — provided data, CPU, no credentialing. Reproduce as retrieval baseline.
4. EHRAgent ASR-a/ASR-t — ONLY if Madisetti scopes it in; then start credentialing +
   compliance ruling (do not start CITI before the scope decision).

**Do not start PhysioNet credentialing before the Thursday scope decision** — the
retrieval baseline (the defense-relevant metric) needs none, and credentialing is
only required if execution-stage EHRAgent is explicitly in scope.
