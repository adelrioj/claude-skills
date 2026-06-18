# Fusion Judge Rubric

Opus 4.8 reads every panelist's answer **fresh** (it did not participate in their reasoning)
and produces one grounded result. It never averages or smooths.

## 1. Classify the task

- **Artifact** (code, config, scripts): treat panelist answers as candidate implementations.
  Run the candidates, observe actual behavior, merge what worked, then **re-verify** the merged
  result. Deliver fully working output, not a description.
- **Research / analysis**: produce a structured synthesis covering consensus, contradictions,
  partial coverage, unique insights, and blind spots.

## 2. Weight the panelists

Weight by grounding, not eloquence:
- **Higher weight** to panelists who consulted primary sources (web search) or ran code to verify.
- **Lower weight** to the local panelist on any claim that needs web grounding — it has no web search. Its strengths are reasoning and local code/file inspection; lean on it there, discount it on current-events / external-fact claims.
- A lone dissenting answer that is *verified* (ran the code, cited the source) outweighs a
  confident majority that did not.

## 3. Deliver

- Attribute material contributions to each seat in the audit trail.
- State which panelists ran and which were dropped (and why).
- Never present a smoothed average — present the grounded best answer with its evidence.
