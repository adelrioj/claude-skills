---
name: spec-to-symphony
description: 'Use when a groomed Linear ticket already carries its design spec and the build must be handed to a Symphony autonomous pipeline — puts the spec on the remote under the filename that deployment actually reads, then arms the existing ticket so the poller dispatches it. The ticket must already exist; this skill never creates one. Triggers on: hand off to symphony, hand the build to symphony, arm the pipeline, arm the ticket, spec to symphony, spec-to-symphony.'
user-invocable: true
---

# Spec-to-Symphony Handoff

Hand a finished design spec to a [Symphony](https://github.com/openai/symphony) pipeline: put the spec on the remote where the pipeline will look for it, then arm the existing ticket so the poller picks it up.

**This skill does not create tickets. It continues one.** By the time it runs, `/to-linear` filed the ticket, `/linear-groom-ticket` made it coherent, `/linear-spec-ticket` attached the spec, and `/spec-review-codex` hardened the file on disk. What is still missing is that the ticket is still parked and the spec is still only on the ticket — and that is this skill's job. An earlier revision created the ticket itself, from a premise ("no ticket exists yet") the ticket line no longer has: creating one here yields a second ticket for work that already has one, with the groomed ticket and the branch pointing at each other's absence. **No ticket at all ⇒ run `/to-linear` first**, then groom it, then come back.

**What is load-bearing here is the arming, not the push.** That is a change of emphasis worth stating plainly, because the skill was written when the push was the *only* way a spec could reach a pipeline:

- On a deployment that **cannot** read attachments, the push is still the sole delivery channel and everything downstream depends on it.
- On a deployment that **can**, the pipeline self-serves from the attachment — so the push is redundancy, not delivery. Keep doing it anyway: it costs one commit, it makes the spec reviewable in the PR, and it means the first stage finds the file already present and skips authoring entirely rather than re-fetching and re-writing it.
- What no deployment does for itself is **arm**: set the ticket's project if it has none, move it into the intake state, and prove both landed. That sequence exists nowhere else on the line.

**Arming is this skill's to do, and only after Step 7's proof.** `/linear-spec-ticket` deliberately leaves the ticket where it found it: it pushes nothing and it checks no project, so it cannot arm anything safely. This skill can, because by the time it moves the state `git ls-tree` has shown the spec on the remote branch and the project has been read back.

**What a stage agent reads from Linear depends on the deployment, and only two things are constant.** Constant: `issue.description` always reaches the agent, and Linear **comments** never do. Variable: **file attachments**. Attachment reading is a property of the Symphony *build* behind the deployment, not of the config file: a build whose `Tracker.Issue` carries an `attachments` field can have the stage prompt render the list and fetch one with an attachment-fetch tool, and a first stage so equipped writes the attached `<IDENT>-design.md` into the repo and treats it as **outranking the description**. A build without that field has none of it, and the attachment is not a delivery channel at all. **Read the answer out of the config you resolve in Step 1 — never assume either one**, and where you cannot tell, record it as `unknown` and treat it as *not readable*. Step 1's checklist names the two things to look for (an `issue.attachments` loop in the prompt body, an attachment-fetch tool in `allowed_tools`).

**Symphony contains no git code.** Cloning is the config's `after_create` hook, and it runs **once**, on first workspace creation. Anything not on the remote before the ticket is first dispatched never arrives by the filesystem path — which is why the branch push is the channel that works on *every* deployment, including one that cannot read attachments.

**The transport is the Linear MCP — the same server `/to-linear` uses, not `orca`.** Every Linear read and write here is an MCP tool call (`list_projects`, `list_issue_statuses`, `get_issue`, `list_issues`, `save_issue`, …); load them with ToolSearch if they are deferred. **`save_issue` is one tool for create and update, and `id` is the switch** — omitting it *creates a ticket*, which is FORBIDDEN here, so every `save_issue` call in this skill carries an `id`.
 There is **no workspace parameter**: the caller's token binds the session to exactly one workspace, so resolve the project by reading it back, never by selecting a workspace. If the only Linear tools visible are `authenticate`/`complete_authentication`, the connector is not authenticated — ask the user to run `/mcp`, select the Linear connector, and retry. Never fall back to `orca` or hand-rolled GraphQL; there is no shared API key.

---

## The Iron Rule: Read the Workflow Config. Never Infer It.

There is more than one Symphony deployment, and deployments disagree on **every** value this handoff depends on. Nothing in the list below has a safe default, and none of it is inferable from the repo:

| Value | Why it differs per deployment | If you get it wrong |
|---|---|---|
| `active_states`, and which entry is the **intake (arming) state** | each deployment names its own Linear states; some rendered configs *also* name the intake state explicitly (e.g. an Ansible var like `symphony_intake_state`), and the explicit name wins | the ticket is armed into a state the poller does not watch — Linear accepts the write, Symphony never dispatches |
| **spec path convention** | identifier-keyed (`docs/superpowers/specs/<IDENT>-design.md`) vs date-slug (`<YYYY-MM-DD>-<slug>-design.md`) | the stage authors a competing spec and yours sits orphaned on the branch |
| **branch** | usually Linear's own `branchName`, lowercased — but it is stated in the config, not assumed | the pipeline builds a branch your spec is not on |
| **whether the stage agent can read attachments** | a property of the Symphony *build*, not the config file (see above) | you count the attachment as delivery when nothing can read it |
| **whether the first stage guards against clobbering an existing spec** | some stage bodies say *"write it only if it does not exist"*, some do not | your pushed spec is overwritten by one authored from the description |
| poll interval | per deployment (seconds to tens of seconds) | only affects how long you wait before checking |

Two shapes of config exist and both are readable, so there is no excuse for inferring: a **file-based** config (a single markdown file with YAML front matter) and an **Ansible-rendered** one (a `WORKFLOW.md.j2` template plus the role vars that fill it — read *both*, since values like the intake state and a dry-run flag live in the vars, not the template).

A handoff built for one config is silently wrong against another. **Silently** is the word that matters: every known config says *"seed the spec if it does not exist."* Push a spec under the wrong filename and nothing errors — the stage writes its own spec from the ticket description (or, where attachments are readable, from the attachment), and the brainstorming work sits orphaned on the same branch, unread, while the pipeline runs to completion on a spec nobody wrote.

**If you cannot read the governing config, STOP.** Do not proceed on an inferred convention, do not hedge by satisfying two conventions at once, and do not let the ticket description "instruct" a stage out of a hardcoded path. Baseline runs did all three.

---

## The Job

1. Resolve the governing workflow config — STOP if unreadable
2. Resolve the target repo and the spec
3. Resolve Linear coordinates (the MCP token binds the workspace)
4. Resolve the **existing** ticket — never create one
5. Verify it: identifier, `branchName`, current state, spec attachment
6. Reconcile the spec filename to the config's convention
7. Push the ticket branch — never the default branch
8. Make sure the description names the spec path — append, never rewrite
9. Confirm, then arm
10. Report

## FORBIDDEN

- **Never push to the default branch.** A docs-only commit on `main` is still an unrequested write to a shared branch, and it is not needed: the ticket branch is what the pipeline checks out. A baseline run proposed `git push origin main` as a hedge against not knowing the checkout strategy — the fix for not knowing is Step 1, not a write to `main`.
- **Never land the spec under a name the caller has not seen and agreed to** (Step 6). The local file is never renamed — only the branch copy takes the pipeline's name — but a different filename on the branch is still a surprise if nobody was shown it.
- **Never create a ticket — that means never call `save_issue` without an `id`.** There is no separate create tool to avoid: the tool this skill uses for every update is the same tool that creates when `id` is absent, so the prohibition is on the missing parameter, not on a tool name. A ticket created here duplicates work that `/to-linear` already filed and `/linear-groom-ticket` already groomed, and splits one piece of work across two tickets — one with the grooming, one with the branch. No ticket ⇒ STOP and name `/to-linear`.
- **Never arm a ticket that has no project.** Symphony's tracker filters `project` **before** `state`: a ticket with no project matches the poller's query in *no* state, so arming it is a silent no-op — no dispatch, no log line, an orchestrator that just looks idle. Step 9 sets the project first, and proves it, before it touches the state.
- **Never arm before Step 7's proof.** The poller can dispatch within one interval; a stage that finds no spec on the branch seeds its own. Arming is the last write, after `git ls-tree` shows the file on the remote.
- **Never rewrite the ticket description.** It is a groomed, templated artifact: `/to-linear` filed it against a shared template and `/linear-groom-ticket` redrafted it against the same one. Step 8 appends one spec-path line if it is missing; it does not author a body.
- **Never deliver the spec path via a Linear comment.** Comments reach no stage agent, on any deployment. An attachment is different — where the config renders attachments it *is* a channel, and `/linear-spec-ticket` already put the spec there — but it is never this skill's channel: the branch is, and it is the one that works everywhere.
- **Never assume the workspace.** The Linear MCP has no workspace parameter — the caller's token binds the session to one workspace, which you can neither select nor assert. If the target project or team is not visible, the connector is bound to the wrong workspace: say so and STOP. Never hand-roll GraphQL to reach another one.

---

## Step 1: Resolve the Governing Workflow Config

Take the path from the user's argument. Otherwise look, in order, for the config that governs the target project:

- a path the user names in the invocation
- `$SYMPHONY_WORKFLOW` — `printenv SYMPHONY_WORKFLOW`. A repo that is always handed off to the same
  deployment can pin its config path in `.envrc` and skip discovery entirely. An unreadable pinned
  path is a **STOP**, not a fall-through to the search below: a stale pin resolving to a different
  deployment is the exact failure this whole step exists to prevent.
- otherwise search, and **do not restrict the search to repo roots** — a config commonly sits in the
  subdirectory of the language or service it governs (`elixir/WORKFLOW.md`), which a root-only glob
  misses while reporting "no config found":

  ```bash
  ls ~/Downloads/*-shipit.md 2>/dev/null
  find . ../*/ -maxdepth 3 \
       \( -name 'WORKFLOW.md' -o -name 'WORKFLOW.md.j2' -o -name '*-shipit.md' \) \
       -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null
  ```

  `../*/` is deliberate: an Ansible-rendered deployment lives in a **co-located infra repo**
  (`roles/symphony/templates/WORKFLOW.md.j2` plus `roles/symphony/vars/main.yml` — read both, the
  vars carry values the template does not), and that repo is a sibling of the one you are handing
  off, never inside it.

**Expect to find more than one** — several Symphony deployments coexist on a developer machine. **The discriminator is `hooks.after_create`, not the project slug:** the front matter names a Linear project, which tells you nothing about which repo the deployment builds. Read the clone URL out of every candidate and keep the one that clones the repo you are handing off. If the user named the target repo, match on that; otherwise match on the clone the spec lives in (Step 2).

**If no config is found, or none of them clones your target repo: STOP.** Say which repo you were targeting and which configs you checked. A config for a *different* deployment is worse than none — it looks authoritative and is wrong.

**If two candidates clone the same repo: STOP** and ask which governs. Do not pick the newer file, the one in `~/Downloads`, or the one that "looks live".

From the YAML front matter and the body, extract and **print** these six values before doing anything else:

| Value | Where | Used for |
|---|---|---|
| `tracker.provider.project_slug` (or `tracker.project_slug`) | front matter | Step 3 project match |
| `active_states` — the whole list, and which entry is the intake state | front matter (plus `symphony_intake_state` in `roles/symphony/vars/main.yml`, where the config is Ansible-rendered) | the arming state (Step 9); the rest tell you what the ticket will pass through |
| `hooks.after_create` clone URL | front matter | Step 2 repo identity check |
| spec path convention | body prose | Step 6 reconciliation |
| **whether the stage prompt renders attachments** — an `issue.attachments` loop, and an attachment-fetch tool in `allowed_tools` | body + front matter | Step 5's attachment note and Step 9's confirmation line |
| **whether the first stage guards against clobbering an existing spec** | the first active stage's body | "Companion Config Change" |

**`active_states[0]` is the arming state**, and where the config is rendered from Ansible vars the same value is named explicitly as `symphony_intake_state` — check both agree. Symphony treats `active_states` as a **filter set and ignores its order**, so the intake-first ordering is a convention for readers, not something the orchestrator enforces; the explicitly named intake state wins where one exists. Do not reason about which stage "makes sense" to enter at — a baseline run talked itself into skipping the first stage because that stage authors specs. The correct fix is the config guard (see "Companion Config Change"), not a different entry point.

**An intake state can be a published cross-repo contract rather than a local preference**, and you cannot tell from the config alone. Where anything outside the deployment files tickets *directly into* the intake state — an alerting job, a CI main-break automation, another repo's workflow pinning it as a `linear-active-state` — that name is an interface. Before proposing to rename it or demote it out of `active_states`, grep the org for the literal state name; a one-sided rename leaves Linear happily accepting those tickets while Symphony silently never polls them. **This skill never renames a state** — the rule exists so a run does not *suggest* one as a fix.

Print the derived values and continue. If the config's body does not state a spec path convention, STOP — that is the one value with no safe default. If you cannot tell whether attachments are rendered, record it as **unknown** and treat it as *not readable*: the branch push is required either way, so an unknown costs nothing but a line in the report.

## Step 2: Resolve the Target Repo and Spec

1. **Locate the clone, then check its identity.** Do not assume the current directory is the target repo — this skill is often invoked from elsewhere. Take `owner/repo` from the config's `after_create` clone URL and find the local clone of it (the user's argument, else the current repo if its `origin` matches, else search the usual roots for a clone whose `origin` matches). Compare `git remote get-url origin` against the config's clone URL, normalizing `git@github.com:owner/repo.git` and `https://…/owner/repo.git` to `owner/repo`. **No local clone, or a mismatch → STOP.** A spec committed in the wrong clone is invisible to the pipeline, and this is the only cheap check that catches it.
2. **Spec file.** In order: the user's argument; else `docs/superpowers/specs/<IDENT>-design.md` if the invocation named a ticket identifier — that is exactly what `/linear-spec-ticket` writes; else the newest `docs/superpowers/specs/*-design.md`. If none exists, STOP — "No design spec found. Run `/linear-spec-ticket <IDENT>` (or `/superpowers:brainstorming`) first."
3. **Committed or not, both are fine.** `/linear-spec-ticket` leaves the spec **uncommitted** by design, and an uncommitted file is pushable — Step 7 lands it on the ticket branch either way. Record which case you are in: `git log --oneline -1 -- <spec>` prints a commit, or it prints nothing. An earlier revision hard-STOPped on the uncommitted case, which made the documented `/linear-spec-ticket` → here handoff abort every time.
4. **Where that commit sits** (committed case only). If the spec commit is on the local default branch and unpushed, say so — Step 7 moves it onto the ticket branch and resets the local default back to its remote, so spec commits do not accumulate on `main`.
5. **Whose spec is it** (identifier-keyed filenames only). If the filename carries an `<IDENT>-` prefix, it must be the ticket resolved in Step 4. A mismatch means you are about to push one ticket's spec onto another ticket's branch — STOP. This check is free and catches the mistake nothing else would.

## Step 3: Resolve Linear Coordinates

List the projects the connected workspace can see and match by the slug from Step 1:

- `list_projects` — Linear slugs carry a hash suffix (`symphony-workflow-2f7600b452dc` matches the project named `symphony-workflow`); match on the leading segment or on the project id. From the match, take the project id/name and the team key.

The Linear MCP has **no workspace parameter**: the caller's token binds the session to exactly one workspace. If the project is not in the list, the connector is bound to the wrong workspace — say which project you were looking for and **STOP**.

Ambiguous or no match → STOP with the candidates listed.

Then resolve the **arming state** — **never hardcode it**; names differ per team down to the spacing (`Todo` on one team, `To Do` on another, and Linear treats those as different states):

- `list_issue_statuses(team: "<team key or id>")`
- **arming state** = the status whose `name` equals `active_states[0]` from Step 1, exactly

Missing → STOP. The tracker's GraphQL filter is an exact `state: {name: {in: [...]}}` match, so a near-miss name means the ticket looks armed and is never dispatched.

No backlog state is resolved any more: nothing here creates a ticket, so there is nothing to park. Where the ticket currently sits is read in Step 5, not chosen.

## Step 4: Resolve the Existing Ticket

Resolve the identifier, in order:

- the identifier in the invocation (`/spec-to-symphony MDZ-123`)
- the ticket the current worktree is about — its branch name, or its linked ticket
- the `<IDENT>-` prefix on the spec filename from Step 2

**None of those resolves an identifier ⇒ STOP.** Say that this skill continues an existing ticket and name the route in: `/to-linear` files it, `/linear-groom-ticket` grooms it, `/linear-spec-ticket` attaches the spec. Do **not** call `save_issue` without an `id`, and do not offer to — a ticket created here is a duplicate of one that either exists or should be filed properly.

Then read it once, and take everything Step 5 needs from that one response:

```
get_issue(id: "<IDENT>")
```

Take: `identifier`, `title`, `url`, `description`, `state.name`, the project, `branchName`, and the attachment list.

`issue` comes back empty or errors ⇒ **STOP.** The MCP has no workspace parameter, so a ticket in another workspace resolves to nothing — which is the safe direction of error, and the only signal you get.

## Step 5: Verify the Ticket Is the One Being Handed Off

Four checks on the Step 4 response. Each one catches a failure that is otherwise silent.

1. **`identifier` equals what you asked for.** The MCP cannot assert the workspace, so this is the only check that you are addressing the ticket you think you are.
2. **The ticket's project.** Three cases, and only one of them needs nothing done:
   - **It is the project resolved in Step 3** ⇒ continue.
   - **It is a different project** ⇒ this ticket belongs to a different deployment from the config you read in Step 1 — the spec would go onto a branch no poller watches, or worse, the wrong poller's. **STOP**, naming both projects. Never reassign a ticket out of one deployment into another to make this check pass.
   - **There is no project at all** ⇒ record it and continue; **Step 9 sets it, before the state, as part of arming.** Do not set it here — arming is one confirmed sequence, and a project written before Step 7's proof is a write the caller never approved.

   **A missing project is worse than a wrong state, and it is worse silently.** Symphony's tracker filters `project` first and `state` second, so a ticket with no project matches the poller's query in *no* state: arming it changes nothing, nothing is dispatched, and nothing is logged — the orchestrator simply looks idle. This is not hypothetical: MDZ-249 came out of the spec leg with no project and needed manual repair before its first run could start. A state you can see on the ticket; an empty project field reads like a cosmetic omission right up until it costs a run.
3. **`branchName` is present.** It is the branch Step 7 pushes (lowercased by Linear). Absent ⇒ re-read; still absent ⇒ STOP rather than deriving your own.
4. **Current state.** If it already equals the arming state from Step 3, **STOP and ask.** Either a poller already dispatched this ticket — in which case a stage has run *without* the spec on the branch and its output needs looking at before anything else — or someone moved it by hand. Re-arming an already-armed ticket is a no-op that reads as success. `/linear-spec-ticket` no longer transitions, so this is not the ordinary case.

Also note whether the attachment list carries `<IDENT>-design.md`. Its **absence is not a blocker** — a hand-written spec is legitimate — but it means two things at once: a human reading the ticket sees no spec, and on a deployment that renders attachments (Step 1) the pipeline loses its second copy too, leaving the branch as the only source. If the attachment is present, check it is the current one: `/linear-spec-ticket <IDENT> refresh` re-uploads after `/spec-review-codex`, and where the stage treats the attachment as outranking the description, a stale attachment is a stale instruction. Say either way at Step 9.

## Step 6: Reconcile the Spec Filename

**In the ordinary flow this step is a no-op — confirm it and move on.** `/linear-spec-ticket` writes `docs/superpowers/specs/<IDENT>-design.md`, which satisfies *both* known conventions: it is exactly the identifier-keyed path, and it ends in `-design.md` so it falls inside the date-slug glob. Check anyway — the config is the authority, not this paragraph — but expect no rename. The rename path below is for a hand-written or `/superpowers:brainstorming` spec.

Compare the spec's actual filename against the convention from Step 1.

- **Convention is date-slug** (`<YYYY-MM-DD>-<slug>-design.md`) → the stage resolves this with a **glob**, not an exact path, so only the `-design.md` suffix has to match. A file already under `docs/superpowers/specs/` ending in `-design.md` needs nothing done, whatever its date or slug. A file that does *not* end in `-design.md` falls outside the glob and must be renamed to.
- **Convention is identifier-keyed** (`<IDENTIFIER>-design.md`) and the file does not match → the file must be renamed, or the stage's hardcoded path will not resolve to it and it will seed a fresh spec instead.

Naming it what the stage computes is the deterministic fix — it makes the file *be* that path, rather than relying on a description instruction to argue a stage out of a hardcoded value. **The rename happens on the branch copy only**: Step 7 already writes the bytes to a destination of your choosing, so `<final-spec-path>` is where the rename lives. There is no `git mv`, the local file is never touched, and an untracked spec — the `/linear-spec-ticket` case — needs no special handling.

**Show it and get a yes before committing to it:**

```
The pipeline looks for:  docs/superpowers/specs/TRA-42-design.md
Your spec is at:         docs/superpowers/specs/2026-08-17-retry-backoff-design.md

Without this the Spec Review stage will not find your spec and will write its own
from the ticket description.

  Step 7 commits it to the ticket branch as
      docs/superpowers/specs/TRA-42-design.md
  Your local file keeps its own name and is left alone.

Land it under the pipeline's name? [y/N]
```

If declined, continue — but say plainly in the final report that the pipeline will author a competing spec.

Case matters when the convention matches a prefix: Linear's `branchName` is lowercased (`alejandrodelrio/tra-42-…`) while an `<IDENTIFIER>-*` remote match is uppercase. If the config derives its own branch name rather than using `issue.branch_name`, use the config's form, not Linear's.

## Step 7: Push the Ticket Branch

**Do not branch from local `<default>` and do not `git add -A`.** The spec may sit anywhere — uncommitted in the worktree (the `/linear-spec-ticket` case), committed on local `<default>`, on another branch, in a detached commit — and a fresh branch cut from `origin/<default>` contains it in none of those cases. **Capture the bytes first, branch, then write them back.** That works from every starting point and carries nothing but the spec:

```bash
git fetch origin                                        # origin/<default> is routinely stale
TMP=$(mktemp -d)
if [ -f "<spec>" ]; then                                # in the worktree: committed or not
  cp "<spec>" "$TMP/spec"
else                                                    # committed, but not in the tree
  git show "$(git log -1 --format=%H -- "<spec>"):<spec>" > "$TMP/spec"
fi
git switch -c "<branch>" "origin/<default>"             # branch per the config's convention
mkdir -p "$(dirname "<final-spec-path>")"
cp "$TMP/spec" "<final-spec-path>"                      # Step 6's name; the ONLY file that rides along
git add "<final-spec-path>" && git commit -m "docs: add <spec title> design spec"   # title from the spec's H1
git push -u origin "<branch>"
```

**`git add` takes exactly the one path, and that matters more than it looks.** `git switch` carries every dirty and untracked file in the worktree onto the new branch; staging a directory — let alone `-A` — commits whatever else was lying around into the branch a pipeline is about to build on.

**Then prove the spec is on the remote before anything else.** This is the one check that catches every way this step can silently half-work:

```bash
git ls-tree -r --name-only "origin/<branch>" -- docs/superpowers/specs/
```

The final spec path must appear. **If it does not, STOP** — do not arm. An armed ticket whose branch lacks the spec is the exact failure this skill exists to prevent, and it is indistinguishable from success until the pipeline finishes.

Only **after** that check passes, and only in the committed case, if Step 2.4 found the spec commit on an unpushed local `<default>`, reset it: `git branch -f <default> origin/<default>`. Resetting before the check would orphan the user's only copy of the spec to the reflog. In the uncommitted case there is nothing to reset — the file simply left the worktree's `<default>` and became a commit on the ticket branch.

If — and only if — the config matches its branch by prefix rather than using `issue.branch_name`, also verify exactly one remote branch matches:

```bash
git ls-remote --heads origin "<IDENT>-*"    # must return exactly one ref
```

More than one → STOP; "a branch matching `<IDENT>-*`" is ambiguous and the stage picks arbitrarily. Configs that use `{{ issue.branch_name }}` verbatim need no such check — skip it rather than inventing a prefix.

## Step 8: Make Sure the Description Names the Spec Path

The description is the Linear field that reaches a stage agent on **every** deployment — and it is also a **groomed artifact**, filed by `/to-linear` against a shared template and redrafted by `/linear-groom-ticket` against the same one. So: **append, never author.** An earlier revision wrote the body from scratch because it also created the ticket; doing that now discards the grooming.

Read the description captured in Step 4:

- **It already names the final spec path** ⇒ do nothing. No write.
- **It does not** ⇒ append exactly one line to the end: `Design spec: <final spec path>  (on branch <branch>)`

Append with `save_issue`'s `patch` parameter, which edits in place and never round-trips the body:
`save_issue(id: "<IDENT>", patch: [{op: "append", text: "\n\nDesign spec: <final spec path>  (on branch <branch>)"}])`.

Do **not** send `description` here. That parameter replaces the whole field, so "append" through it means re-sending the entire groomed body verbatim, and a dropped or reflowed template section is a silent loss of grooming. `patch` is atomic — one failing operation aborts the whole save — so the body is either appended to or untouched. Read the description back afterwards and confirm the line is there and nothing else moved.

This is belt-and-braces behind Step 6, not the primary mechanism, and it is **not** a delivery channel: it carries the spec's *path*, never its contents. The filename is what makes the handoff deterministic; the line makes the path legible to a human and agrees with the one the stage computes. **Never inline the spec into the description, and never use this line to argue a stage out of a hardcoded path** — where a stage cannot find the file, the fix is Step 6's rename or the attachment, not more prose in the body.

## Step 9: Confirm, Then Arm

Arming is the irreversible outward step — the pipeline begins on the next poll and starts committing. Present one confirmation and wait:

```
spec-to-symphony — ready to arm
-------------------------------
Config:     <path>            (<project slug>)
Ticket:     <IDENT> — <title>          (existing — groomed, not created here)
            <url>
Repo:       <owner/repo>      (origin verified against after_create)
Branch:     <branch>          pushed, 1 remote ref
Spec:       <final path>      on origin/<branch>, verified by git ls-tree
            <IDENT>-design.md also attached to the ticket | no spec attachment on the ticket
Reads:      the stage agent reads attachments on this deployment | description only
Project:    <current>  ->  unchanged | <project from Step 3>   (SET — the ticket had none)
State:      <current>  ->  <active_states[0]>   (poll every <interval>)

This starts the autonomous pipeline. Proceed? [y/N]
```

On yes, **two writes, in this order, each on its own** — the project first, because the state is the one that arms:

1. **Project, only if Step 5 found none.** `save_issue(id: "<IDENT>", project: "<project id from Step 3>")`, then read it back with `get_issue(id: "<IDENT>")` and confirm the project is the one you resolved. **Not the project you resolved, or still empty ⇒ STOP without touching the state.** An armed ticket outside the poller's project filter is the exact silent no-op this check exists to prevent, and the read-back is the only thing that catches a write the API accepted and dropped.
2. **State.** `save_issue(id: "<IDENT>", state: "<arming state name>")` — the state and nothing else, no `description`, no `patch` and no `project` in the same call. Then read it back too: **the state that comes back must equal `active_states[0]` exactly.** A `save_issue` that returns without error is not proof the field moved; MDZ-249 was reported as transitioned while sitting in `To Do`.

Never fold the two into one call. The project write is a repair; the state write arms an autonomous pipeline. Kept separate, a failed project write leaves the ticket exactly where it was — parked, visible, and safe to retry.

On no: stop. The ticket stays where it is, the branch stays pushed with the spec on it, and re-running **this step alone** is all that is needed to arm it later — Steps 6–8 are idempotent and Step 7's proof will simply pass again.

## Step 10: Report

```
spec-to-symphony complete
-------------------------
Ticket:  <IDENT> <url>  →  <arming state>
Branch:  <branch>       (your worktree is on it)
Spec:    <path>         committed and pushed
Watch:   <url>   (get_issue id: <IDENT>)
```

Name in the report anything that will make the run a silent no-op. A pipeline that runs and lands nothing looks identical to one that worked.

- A declined Step 6 rename — the pipeline will author a competing spec.
- **No `<IDENT>-design.md` attachment on the ticket** (Step 5). The pipeline has the spec on the branch; a human opening the ticket does not, and on an attachment-reading deployment the redundant copy is missing too. `/linear-spec-ticket <IDENT>` fixes it, and `/linear-spec-ticket <IDENT> refresh` is what keeps it current after `/spec-review-codex` edits the file.
- The worktree is left **on the ticket branch**, with the spec committed there. Say so — a caller who expected to be back on `<default>` will otherwise commit their next change onto a branch a pipeline is actively building.
- A dry-run flag **on the deployment you resolved in Step 1**, not on some other one. An Ansible-rendered deployment typically carries one in its role vars (e.g. `symphony_dry_run`), which turns every stage into a comment-only run that pushes nothing. A file-based config may have no such flag and need no such check — do not go reading another deployment's vars because you know the flag exists somewhere.

---

## Companion Config Change

**Read the first active stage's body in Step 1 and determine whether the guard is already there.** Report which, every time — never carry an answer over from a previous handoff or from this document. Configs drift, and a guard that *was* present is exactly the kind of thing a later edit removes without anyone noticing.

**A guard that is already present reads roughly like this** — an attachment-aware first stage whose spec write is conditional on absence:

> *"If `docs/superpowers/specs/{{ issue.identifier }}-design.md` does not exist, write it from the attached `{{ issue.identifier }}-design.md` if the ticket has one (fetch it first — it outranks the description), else from the ticket description…"*

Conditional on absence means a spec Step 7 already pushed is left alone. **Read the actual stage body and say which case you are in** rather than trusting this example; that is the whole point of the previous paragraph.

Where it is absent: this skill delivers a spec to a pipeline whose first stage is written to *author* one. That stage needs a guard, or it writes a second spec next to yours:

> If the branch already carries a design spec, do not write a new one. Validate it against the ticket description and advance.

Without the guard, entering at `active_states[0]` produces a competing spec, and the only alternatives are entering at a later stage (inference — forbidden by Step 1) or arguing the stage out of its hardcoded path via the description (unreliable).

**Where you have to write the guard, its selector must be branch-scoped, and this is where a plausible guard goes wrong.** `ls docs/superpowers/specs/*-design.md` and "take the newest by date prefix" both glob every spec in the repo, including ones from unrelated merged work — the moment any of them sorts later than yours, the stage hardens the wrong file and nothing errors. Two selectors are safe. The stronger one is an **exact identifier-keyed path**, which cannot pick up a neighbour at all. Where the convention is date-slug and no exact path exists, use the branch diff:

```bash
git diff --name-only $(git merge-base origin/<default> HEAD)...HEAD -- 'docs/superpowers/specs/*-design.md'
```

Step 7 exists partly to satisfy this: cutting the ticket branch from `origin/<default>` and landing the spec commit on it is what puts the spec in that diff. A spec already merged to the default branch is invisible to the selector — which is correct, since it does not belong to this ticket.

## Red Flags — STOP

- "I can't read the workflow config, but the convention is probably…"
- "I'll satisfy both conventions to be safe" — belt-and-braces is a guess wearing a hedge
- "I'll push the spec to `main` too, so it's there either way"
- "The Todo stage would overwrite it, so I'll enter at Spec Review instead"
- "I'll put the spec path in a Linear comment" — no stage reads comments, on any deployment
- "The project list came back non-empty, so I'm in the right workspace" — confirm the specific project is present; the MCP cannot select or assert a workspace
- "There's no ticket for this yet, I'll just create one" — that is a duplicate waiting to happen. `/to-linear`, then `/linear-groom-ticket`, then come back
- "The ticket has no project, but the state is what the poller filters on" — it filters `project` first. No project means no match in any state, and nothing anywhere says so
- "I'll set the project in Step 5 while I'm reading the ticket" — arming is one confirmed sequence; a write before Step 7's proof is one the caller never approved
- "`save_issue` returned without an error, so the ticket moved" — read it back. A ticket reported as armed and actually sitting in `To Do` is what MDZ-249 did
- "The ticket is already in the arming state, so this is already done" — it means a stage may have run with no spec on the branch. Look at what it produced before touching anything
- "The description is thin, I'll rewrite it properly while I'm here" — it is a groomed template artifact. Append the spec-path line, nothing more
- "The spec isn't committed, so I can't push it" — Step 7 commits it onto the ticket branch. `/linear-spec-ticket` leaves it uncommitted on purpose
- "Two configs matched; I'll take the one that looks live"

**All of these mean: go back to Step 1 and read the config.**

And on the push, where the failure is silent rather than inferential:

- "`git add -A` will pick the spec up" — not if you branched from `origin/<default>`; the file is not in the tree
- "The commit succeeded, so the spec is on the branch" — an empty commit succeeds too. Only `git ls-tree origin/<branch>` proves it
- "I'll reset `main` now and verify the push after" — that order orphans the user's only copy of the spec
- "`origin/<default>` is current enough" — it is routinely dozens of commits stale. `git fetch` first

**All of these mean: go back to Step 7 and prove the file is on the remote branch before arming.**
