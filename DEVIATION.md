# Reproduction Deviations from Upstream AgentPoison

## Trigger optimization (algo/trigger_optimization.py, algo/utils.py, algo/config.py)

### DPR-only optimization (target gradient guidance disabled)
`--target_gradient_guidance` is non-functional as released. `target_word_prob()`
in `algo/utils.py` is a development stub: it computes no target-word probability,
has no return statement (falls through into the next function definition), and
ends in a blocking `input()` call. Verified identical across all commits, branches,
and tags of AI-secure/AgentPoison (full history checked). No working implementation
exists publicly. Emailed first author (zhaorun@uchicago.edu) 2026-06-16; awaiting
response.

Impact: triggers optimized against the DPR retriever embedding space only. This
is appropriate for the retrieval objective (ASR-r), which our attestation defense
targets. The target guidance refines generation-stage success (ASR-a/ASR-t), not
retrieval. Documented as a reproducibility gap in the artifact.

### Variable initialization fixes (non-functional to the DPR objective)
- `last_best_asr`: upstream initializes it only inside the target-guidance block
  but references it unconditionally (NameError when target guidance off).
  Initialized to 0 before the loop.
- `trigger_sequence`: upstream assigns it only in the `agent=='ad'` branch but
  references it in logging/target paths for all agents (NameError for ehr/qa).
  Initialized to "" before the loop.
Both are target-stage / logging variables; neither affects the DPR retrieval
fitness computation. Confirmed by normal convergence with the fixes applied.

### openai import guard (agentdriver/llm_core/chat_utils.py)
Agent-Driver code uses the openai 1.x API (`from openai import OpenAI`), but the
environment pins openai 0.28 for the StrategyQA legacy 0.x API. Guarded the import
(try/except → None) so the module loads under 0.28. Safe because DPR-only
optimization never calls OpenAI (no `--use_gpt`).

### Llama-2-7b config path (algo/config.py)
Upstream `model_code_to_embedder_name["meta-llama-2-chat-7b"]` points to an author
local filesystem path (`/home/czr/.cache/...`). Repointed to the HF id
`meta-llama/Llama-2-7b-chat-hf`. Unused in DPR-only mode (target guidance off);
fixed for correctness.

### wandb (run-time, not committed)
Upstream hardcodes `wandb.init(entity="billchan226")` (authors' account) and
defines `config` only inside the wandb block. Ran with `WANDB_MODE=disabled` to
no-op wandb without patching; `config` is still defined because `-w` is passed.
