# {{FEATURE_NAME}} — dex plan

## Overview

{{GOAL_SENTENCE}}

Source plan: {{PLAN_FILE_PATH}}

<!--
  One source Task = one "### Task N:" heading = one dex iteration.
  dex hands the whole group (heading + checkboxes + prose) to codex at once,
  then exits and re-reads. Repeat the block below per source task.
  Quality-gate checkbox is appended to EVERY task. [manual] criteria get a
  "[manual] " prefix so a human knows codex will tick them without real proof.
-->

### Task {{N}}: {{COMPONENT_NAME}}

**Files:** {{FILE_LIST}}

- [ ] {{STEP_WRITE_FAILING_TEST}}
- [ ] {{STEP_IMPLEMENT}}
- [ ] {{STEP_VERIFY_TESTS_PASS}}
- [ ] Quality gates: {{QUALITY_GATE_COMMANDS}} pass
- [ ] Commit
