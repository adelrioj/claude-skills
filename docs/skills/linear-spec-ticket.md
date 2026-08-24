# `/linear-spec-ticket`

Takes one Linear ticket that `/linear-groom-ticket` has already made coherent, drafts its design spec, and uploads that spec to the ticket as a file attachment. It stops there — the review is `/spec-review-codex`, invoked by the caller. **The ticket's state is never touched** (see *Revision 4* below), and a second mode re-uploads the hardened spec once that review has edited the file.

**Binding design authority:** `docs/superpowers/specs/2026-08-19-linear-spec-ticket-design.md`. This document is the long-form *why*; that one is what the skill is held to. Read its **Revision 3** section (then *Revision 2*) before changing anything here.

```
/linear-groom-ticket → /linear-spec-ticket → /spec-review-codex → /linear-spec-ticket refresh → /spec-to-symphony
   ticket coherent       ticket has a spec      spec hardened       ticket has the hardened spec   on the remote, armed
```

`/spec-to-symphony` is no longer the twin that *creates* a ticket for an existing spec — it continues this skill's ticket, pushing the spec to the remote and arming the pipeline. Neither skill creates tickets; `/to-linear` does.

**Which Linear states this line runs through, and what a Symphony stage can actually read, are per-deployment facts with no portable answer** — `/spec-to-symphony` Step 1 resolves both from the governing workflow config and refuses to run without it. This skill leaves the ticket wherever it found it, so nothing here depends on knowing them.

---

## The three things a reader needs to know first

### 1. The transport is the Linear MCP, and there is no fallback

Every Linear read and write is an MCP tool call on the same `linear` server every sibling skill uses. The skill ships **no scripts**, uses **no `orca`**, and holds **no API key** — *Revision 5* removed the GraphQL transport once the MCP grew attachment upload. The single non-tool step is the signed `PUT` of the spec's bytes, because no tool ships bytes. No usable MCP is a stop naming the missing tool, not a prompt to find another route.

| Operation | Use |
|---|---|
| `get_issue(id)` | Preflight read; attachment list; post-upload proof |
| `list_issue_statuses(team)` | The team's workflow states, for the read-only state check |
| `prepare_attachment_upload(issue, filename, contentType, size)` | Signed upload URL + headers + `assetUrl` |
| signed `PUT` (`curl`) | The raw bytes, sent outside the MCP to the storage URL |
| `create_attachment_from_upload(issue, assetUrl)` | Link the uploaded asset to the ticket |
| `delete_attachment(id)` | Only to replace a stale spec attachment, only on the caller's say-so |
| ~~`save_issue`~~ | **Never called.** No state transition, no description write — see *Revision 4* |

No issue UUID is resolved anywhere: `get_issue` and `prepare_attachment_upload` both take the human identifier.

### 2. One channel: a file attachment

The spec is uploaded as `<IDENT>-design.md` (`text/markdown`). The ticket's `description` is never touched. Nothing is committed, branched or pushed. No snapshot comment is posted.

A local copy lives at `docs/superpowers/specs/<IDENT>-design.md` for two mechanical reasons — `prepare_attachment_upload` needs the exact byte count and the `PUT` needs a file, and `/spec-review-codex` reviews a file on disk rather than a Linear attachment. It is **not** a delivery channel and it is deliberately **uncommitted**.

### 3. Whether a Symphony pipeline can read the attachment is per deployment

The old text here said a stage agent could not read it *"by any path"*. That is
true of some builds and **false of others**, so the honest statement is a split
one — and it is a property of the Symphony **build**, not of the config file:

| Symphony build | Can a stage agent read the attachment? |
|---|---|
| One whose `Tracker.Issue` carries an `attachments` field | **Yes.** The stage prompt renders the list, an attachment-fetch tool downloads one, and a first stage so equipped writes the attached `<IDENT>-design.md` into the repo and treats it as **outranking the description** |
| One without that field | **No.** No attachments field, no fetch tool, nothing rendered. `issue.description` is the only channel |

The two markers to look for are an `issue.attachments` loop in the stage prompt
body and an attachment-fetch tool in `allowed_tools`. `/spec-to-symphony` Step 1
resolves them from the governing config and prints the answer; from inside *this*
skill the config is usually not visible at all, so it assumes **not readable**
and says so at the gate. An assumed capability must never be the reason the
branch push is skipped.

Two things did not change and are still absolute:

- **Linear comments reach no stage, on any deployment.**
- **Symphony contains no git code.** The clone is the config's `after_create`
  hook, which runs **once** on first workspace creation, so a spec absent from the
  remote at first dispatch never arrives by the filesystem path either. This skill
  pushes nothing, which is why `/spec-to-symphony` exists.

**What this changes for the skill: the reason it does not transition, not the
behaviour.** Revisions 2 and 3 justified the ban with *"the pipeline cannot see
the spec"*; that justification is now deployment-specific, and the ban is not.
What holds everywhere is that arming is a single confirmed sequence which also
has to set the ticket's project — Symphony filters `project` before `state`, so a
ticket armed without one is dispatched in **no** state, silently — observed. That
sequence lives in `/spec-to-symphony` Step 9, behind `git ls-tree` proof. A
transition from here would skip the project check and arm an autonomous run from
behind a gate whose text promises it arms nothing.

---

## Revision 4 — the transition moved out, and refresh moved in

Two changes, both consequences of `/spec-to-symphony` being reshaped from *create a ticket for a spec* into *finish this ticket's handoff*.

| Change | Why |
|---|---|
| **The state transition is gone.** No issue write, at all | `Ready for Spec Review` is a real deployment's intake state. Transitioning from a skill that pushes nothing was justified at the time by *"the pipeline cannot see the spec"*; that half is now deployment-specific (see section 3), and the decision stands on the half that is not — arming also has to set the ticket's project and prove the spec landed, and only the leg that pushes can do either |
| **A refresh mode was added** | `/spec-review-codex` edits the spec file in place and nothing re-uploaded it, so the ticket's *one channel* held the unreviewed draft for the life of the ticket. Refresh skips drafting and the blind-spot pass and uploads what is on disk |
| **The old attachment is deleted after the new one is proven**, not before | Refresh makes a collision the normal case rather than the exception. Deleting first means a failed burst leaves the ticket with no spec at all; deleting after means the worst case is a stale one |
| **The proof matches the new attachment's `id`**, not its title | In refresh mode the old attachment carries the same title and is still on the ticket at proof time, so a title match would be satisfied by the very attachment about to be deleted |

**What this costs, stated plainly.** Nothing on the local build path advances the Linear ticket any more. `/ship-it` never touches Linear, and this skill no longer does either, so a ticket built locally sits in `To Do` until a person moves it or `/spec-to-symphony` runs. That is the price of never arming a pipeline from a leg that cannot prove what it armed, and the closing report says so rather than leaving it as drift.

---

## Why the shape is what it is

### Why both gates precede the upload

`prepare_attachment_upload` returns a signed URL with a short (about 60 seconds) lifetime, and the raw bytes travel to the storage URL in a `PUT` whose every header is part of the signature. Prepare → `PUT` → finalize is therefore one uninterrupted burst. A gate inside it burns the fuse and costs a retry of all three steps, so both gates sit in front of it. A caller who declines has cost nothing at all.

The corollary is worth stating: **the gate text is the whole protection.** Revision 1 let a caller inspect the exact planned writes with `--dry-run`; neither the MCP nor the GraphQL API has an equivalent, so what the caller reads at Gate 2 is all they get before a live write.

### Why proving precedes everything that follows it

`get_issue` is read again after the burst and the **`id` returned by `create_attachment_from_upload`** must appear in its attachment list. A finalize call that returned without an error is not proof of that; the read-back is. Nothing is reported as landed, and no previous attachment is deleted, before that read.

Through revisions 2 and 3 this guarded the transition. With the transition gone (*Revision 4*) it guards the delete, which is the remaining irreversible write: a burst that failed silently plus an eager delete equals a ticket with no spec. In revision 1 a script enforced the order and could not be made to do otherwise. **Now nothing enforces it but the instruction.**

### Why the issue itself is never written

`save_issue` takes `description` and `state` in the same call — as `issueUpdate` did before it. The orca `save-issue` could not touch the state at all, which made "write the spec" and "arm the pipeline" impossible to fuse by construction. That protection disappeared when the writes left the script, so it became an explicit prohibition — first on fusing the two fields, and since *Revision 4* on the whole write. There is no field of the issue this skill is allowed to write; its only Linear write is the attachment. Note that `save_issue` is also the create tool (it creates whenever `id` is absent), which is a second reason it has no business being called here.

### Why the attachment list is the resume record

There is no `applied.json` any more, and nothing is lost. The attachment list read in preflight *is* the live state of the thing being changed, which is strictly better than a local note about it.

It has one honest limit, and the skill asks rather than assumes because of it: an attachment left by an earlier run holds **that run's** spec, not this one's. So in draft mode "an attachment exists" means *decide* — replace or abort — never *done*. Uploading alongside leaves two specs and no way for a reader to tell which is current. In refresh mode a collision is the expected case and the answer is always replace, with the delete deferred to after the proof.

### Why states are read and never written

There is no target state to resolve since *Revision 4*, but the team's workflow states are still fetched in the preflight (`list_issue_statuses`), for two read-only checks: an unexpected initial state (anything other than `To Do`) is worth asking about in draft mode, and a ticket already sitting in an active-looking state is worth reporting at Gate 2, because a poller may already be running against a different spec. Both print real state names because the API is the authority.

A design note worth keeping: the originating ticket asked for a state by a name **no team actually had** (it differed from the real one by word order alone). The API won over the ticket text then, and the whole question is now moot since nothing here writes a state — but the lesson generalizes to every state name in this plugin: `list_issue_statuses` is the authority, prose naming a state is not.

### Why no Symphony config is read

`/spec-to-symphony` reads the governing workflow config and stops if it cannot, so departing from that is worth justifying:

- Since *Revision 4* the skill arms nothing, so the config has no decision left to inform at all. Before that, the only thing it would have decided was the **wording** of the arming warning, and an unconditional warning is strictly safer than a conditional one.
- An Ansible-rendered deployment's config is readable only *as a template*: the `WORKFLOW.md.j2` plus its role vars sit in an infra clone that may or may not be on the machine, and the rendered `WORKFLOW.md` lives on the server with its secrets in vault. `/spec-to-symphony` Step 1 reads the template because it must; this skill would gain nothing by trying and would have to define a behaviour for the common case where the infra clone is absent.
- What *is* readable locally is whatever the discovery globs happen to find, and several deployments coexist on a developer machine — a candidate that clones **a different repo** is a different deployment entirely. An imperfect matcher would find it and leave the skill confident and wrong. **A config for another deployment is worse than no config.**
- Revision 2 removed the last two things a config could have informed. There is no spec path on a remote and no branch to key off, so nothing is left for it to decide.

### Why there is no workspace parameter

`orca` took `--workspace <id>` and several workspaces could be connected at once, so the old rule was "never omit it". Neither the API key nor the MCP has such a parameter: the credential binds the session to exactly one workspace, which is why `/to-linear` *reads the workspace back and shows it* rather than selecting one, and treats `$LINEAR_WORKSPACE` as a STOP-guard rather than a selector. *Revision 5* is a strict improvement here — there is now one credential to bind rather than an OAuth session and an API key that could point at two different workspaces.

The skill can neither select nor assert a workspace. What replaces the parameter is a read-back — the ticket `get_issue` returns must carry the identifier that was asked for, and the resolved team is shown at Gate 2. A session pointing elsewhere resolves to nothing rather than writing in the wrong place, which is the safe direction of error. A caller holding the same identifier in two workspaces has no guard at all.

### Why "the caller", not "the human"

The gates do not assume a person. The caller may be another agent, and the skill is written so that being driven by one is a supported case rather than an accident.

The gate does not weaken into a formality because of it: it still means **stop, present, wait for an explicit affirmative**. An agent caller's affirmative is its explicit yes, never an inference that it would probably agree. That said, an agent caller approving its own gates is a genuinely weaker guarantee than a person doing it, and with `--dry-run` gone there is no inspection mechanism to compensate. It is in the spec's known gaps.

---

## What was removed in revision 2, and what it cost

Revision 1 shipped and was reviewed in full: `orca` transport, `scripts/apply.py` owning every Linear write, `scripts/lib/linear_write.py` carrying primitives copied from the groom skill, and a six-file offline suite with an honest `orca` double. All of it is deleted.

Tool calls cannot be made from a script, so moving the transport off `orca` — to the MCP, briefly out to direct GraphQL calls, and back to the MCP in *Revision 5* — moved the writes into the agent's hands. Four invariants went with them:

| Lost | Replacement |
|---|---|
| Deterministic ordering enforced by code | A rule in `SKILL.md` — enforced by nothing |
| `--dry-run` | Nothing. Neither the MCP nor the GraphQL API has such a mode |
| `applied.json` resume | The ticket's attachment list, which is better for this narrower job |
| Offline tests + the CI gate | The spec's *Failure modes* table, the FORBIDDEN list, and the live end-to-end run |

The CI step in `.github/workflows/tests.yml` is removed with the suite it ran. `tests/check-codex-knob.sh` is unaffected: this skill has no `codex` call site.

**This is a real loss, not a simplification in disguise.** Nothing in the skill can now be exercised without a real Linear workspace.

Two things did get genuinely better. The design's worst defect, found by revision 1's final whole-branch review, was a branch-convention mismatch: the skill pushed to Linear's `branchName` while the deployment arming at `Ready for Spec Review` derives `<IDENTIFIER>-<slug>`, so a green run could arm a pipeline that could not see the spec. Revision 2 pushes nothing, so there is no branch to choose wrongly, and the guard built to catch it is unnecessary. But the hazard it described was not *solved* — it was **superseded by a larger one**, since no branch and no description means the pipeline cannot see the spec whichever branch it resolves. And the description is no longer overwritten, so the one destructive step is gone and with it the snapshot comment that existed to make it reversible.

### Revision 3: the MCP could not carry the attachment

The bundled Linear remote MCP has no attachment-upload tool — no `fileUpload`, no `attachmentCreate` — so the one thing this skill exists to do cannot be done over it. Rather than run the reads and the transition over the MCP while uploads went through a second credential (two tokens that can bind to two workspaces), the whole skill moved to Linear's GraphQL API with a personal API key. The revision-2 losses above still stand: the writes are still agent-driven — now `curl` calls rather than tool calls — so ordering is still enforced by instruction and there is still no dry run. What changed is only the wire, and that attachments are possible again.

**Superseded by Revision 5.** This premise was true when written and is not any more.

### Revision 5: back to the MCP, because it grew the tool

An audit pass found four skills still calling the retired create/update tools by name after Linear collapsed that family into `save_*`, and three "the MCP cannot do X" premises that had gone stale underneath their workarounds. This skill's whole transport was one of them: `prepare_attachment_upload` → signed `PUT` → `create_attachment_from_upload` is the same three-step burst Revision 3 hand-rolled, and `delete_attachment` retires the old copy, so the API key was buying nothing but a second credential.

What the migration deleted: `LINEAR_API_KEY` and its preflight, four GraphQL mutations and two queries, the `Authorization`-header convention, the `errors`-array-with-HTTP-200 caveat, the issue-UUID plumbing (both MCP tools take the identifier), and the FORBIDDEN entry that read *"never fall back to the Linear MCP"*. What it kept unchanged: both gates, the uninterrupted burst, the verbatim signed headers, the byte-exact `wc -c` size, prove-before-retire, and no state transition.

What it did **not** buy back: there is still no dry run and still no offline test, so Revision 2's losses stand. And the read-back in 8.5 now depends on `get_issue`'s attachment entries carrying their own `id` — the burst is unaffected, but retiring an old attachment needs that id, so Step 1.3 stops rather than guessing if one is absent. **That is the one thing to watch on the first live run.**

---

## The flow, in nine steps

1. **Preflight** — a git repo; the Linear MCP authenticated; the ticket resolved from the argument or the worktree; `get_issue` succeeds and returns the identifier asked for; the description is non-empty; no colliding spec attachment (or the caller chose to replace it).
2. **Read the current state** against the team's workflow states (from `list_issue_statuses`). Nothing is written: an initial state other than `To Do` needs explicit confirmation in draft mode, and a ticket already in an active-looking state is reported at Gate 2 because a poller may already be running against a different spec. No state UUID is ever resolved — needing one means a transition is about to happen, and none is allowed.
3. **Repo identity** — the worktree answers it when no identifier was given; otherwise `origin` is printed beside the identifier at Gate 1 for the caller to confirm. The drafting pass reads the codebase, so it must read the right one.
4. **`/blind-spot`** — one pass. *(draft mode only)* The report path is resolved into a variable *before* dispatch and read from that exact path: never globbed (a glob adopts a stale report from another task), never reconstructed from the subagent's final message (a subagent that finishes and idles sends none).
5. **Draft** *(draft mode only)* — a fresh-context subagent, handed expanded absolute paths, because a subagent cannot expand `${CLAUDE_PLUGIN_ROOT}`. Every high-impact unknown from the blind-spot report must appear as a resolved or explicitly deferred decision. Output gated hard: empty, tool-call markup (`</invoke>`, `<invoke`, `</content>`, `antml`), or no `## ` heading ⇒ one re-dispatch, then stop. Contamination is never stripped and salvaged — it means the step went wrong.
6. **Gate 1** — the spec.
7. **Gate 2** — the one Linear write, stating that the state is unchanged, that arming (with its project check and push proof) belongs to `/spec-to-symphony`, and which deployments can read the attachment as delivered.
8. **Upload burst → prove → retire** — no interruption inside the burst; the `get_issue` read-back proves the new attachment's `id` before the previous one is deleted.
9. **Report** — with `/spec-review-codex <spec-path>` passed **explicitly** (that skill auto-discovers by *date-prefixed* filename and this spec is identifier-keyed), then `/linear-spec-ticket <IDENT> refresh` and `/spec-to-symphony <IDENT>`, and a line saying the ticket state was not moved.

**Refresh mode is the same nine steps with 4 and 5 removed.** It requires the local spec file to exist — absent is a stop, not a licence to draft a replacement — and it runs the same three output checks against the file on disk, since `/spec-review-codex` edits it in place.

## Known gaps

The full list is in the spec. The ones that matter most to anyone changing this skill:

- **On a build that cannot read attachments, the attachment is not a delivery channel at all.** A build carrying an `attachments` field on `Tracker.Issue` reads it (section 3); one without does not, and there is no way to tell from here which a ticket is bound for — so this skill assumes not readable. `/spec-to-symphony`'s branch push is what closes that case.
- **Ordering is enforced by instruction, not code.** An agent that deletes the old attachment before proving the new one can leave a ticket with no spec, and no test will catch it.
- **The attachment is not versioned, diffable, or reviewable in a PR.** The spec is a blob on a ticket; the local file is uncommitted until `/spec-to-symphony` commits it to the ticket branch, and does not survive a clean checkout before that.
- **Refresh is manual.** Nothing detects that `/spec-review-codex` has edited the file, so a caller who skips the refresh step leaves the unreviewed draft on the ticket — and the ticket looks complete either way.
- **Nothing on the local build path moves the ticket** now that the transition is gone. `/ship-it` never touches Linear.
- **A caller that is an agent can approve its own gates**, with no dry run to compensate.

## Deviation from the ticket's DoD, recorded deliberately

The originating ticket asked for both state names to be resolved *"desde la configuración de deployment de Symphony"*. The intent — do not hardcode state names — is met, and met better: they are resolved against the team's own workflow states, which is authoritative where the config is not.

The config does not even list `To Do`, and a real deployment's states (`Ready for Planning`, `Ready for Development`, `Ready for PR Review`) already diverged from the template's (`Spec Reviewed`, `Implemented`). When the hardened spec is mirrored back to the ticket, that DoD line is rewritten to "resolved at runtime against the team's workflow states".
