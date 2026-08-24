---
name: linear-spec-ticket
description: 'Use when a Linear ticket has been groomed and now needs a design spec written onto it so work can start — drafts the spec from the ticket and the codebase and uploads it to the ticket as a file attachment. Also refreshes that attachment after /spec-review-codex hardens the spec. Never changes the ticket state. Triggers on: add a spec to this ticket, write the spec for MDZ-123, deja el ticket listo para trabajar, añade spec al ticket, adjunta la spec al ticket, prepare this ticket for work, spec this ticket, refresh the spec attachment, re-upload the hardened spec, linear-spec-ticket.'
user-invocable: true
---

# Add a Spec to a Linear Ticket

Close the gap between *"ticket groomed"* and *"ticket with a reviewable spec"*: draft the spec and attach it to the ticket as a file. **The ticket's state is never touched** — advancing it is `/spec-to-symphony`'s job, and it advances it only after proving the spec is on the remote.

**Two modes.** *Draft* (the default) writes the spec and attaches it. *Refresh* re-uploads the local spec file over the existing attachment after `/spec-review-codex` has hardened it. Refresh skips Steps 4–5 entirely and uploads what is on disk; everything else — both gates, the burst, the read-back proof — is identical.

**Sibling skills, and the leg each one owns:**

| Skill | Owns |
|---|---|
| `/linear-groom-ticket` | before: makes the ticket coherent |
| **this skill** | the attachment, in both directions. No state change, no git writes |
| `/spec-review-codex` | after: hardens the spec on disk — **this skill never runs it** |
| `/spec-to-symphony` | after that: puts the spec on the remote, then advances the state |

`/spec-to-symphony` used to be the near-twin that *created* a ticket for an existing spec. It no longer creates anything — it continues this skill's ticket. Nothing here creates a ticket either; that is `/to-linear`.

**The transport is the Linear MCP — the same server every sibling skill uses.** Every Linear read and write here is an MCP tool call (`get_issue`, `list_issue_statuses`, `prepare_attachment_upload`, `create_attachment_from_upload`, `delete_attachment`); load them with ToolSearch if they are deferred. The one thing that is *not* a tool call is the signed `PUT` of the spec's bytes, because no tool ships bytes — that stays a `curl`. There is **no** `orca` command here and **no** hand-rolled GraphQL; both were transports of earlier revisions and both were removed by decision.

**Why the MCP, since it used to be GraphQL.** Revision 3 moved this skill onto Linear's GraphQL API with a personal `LINEAR_API_KEY` for one reason: the MCP had no attachment-upload tool. It has one now — `prepare_attachment_upload` → signed `PUT` → `create_attachment_from_upload` is the identical three-step burst, and `delete_attachment` retires the old copy. So the API key bought nothing except a second credential that could bind to a different workspace than the OAuth session. TRA-11 removed it. **One credential, one workspace binding, shared with every sibling skill** — and if a future Linear release drops attachment upload from the MCP again, that is a decision to re-open, not a reason to quietly hand-roll GraphQL mid-run.

**One channel: a file attachment.** The spec is uploaded to the ticket as `<IDENT>-design.md`. The ticket's `description` is never touched, its state is never touched, nothing is committed, nothing is pushed, and no snapshot comment is posted. A local copy at `docs/superpowers/specs/<IDENT>-design.md` is left behind, uncommitted, and three things read it: the upload needs bytes on disk, `/spec-review-codex` reviews a file rather than an attachment, and `/spec-to-symphony` is what eventually commits and pushes it. **This skill still makes no git writes** — it leaves the file where the next leg expects to find it.

---

## Read this before the first gate

**Whether a Symphony stage agent can read this attachment is a property of the deployment, not of Symphony.** Do not carry either answer over as a general fact:

- **A build whose `Tracker.Issue` carries an `attachments` field can read it.** There, the stage prompt renders the attachment list, an attachment-fetch tool downloads one, and a first stage so equipped writes the attached `<IDENT>-design.md` into the repo and treats it as **outranking the description**.
- **A build without that field cannot.** No attachments field, no fetch tool, nothing rendered — `issue.description` is the only channel that reaches the agent. Linear **comments** reach no stage on any deployment.

**Which one you are on is a runtime read, not a remembered fact.** The two markers are an `issue.attachments` loop in the stage prompt body and an attachment-fetch tool in `allowed_tools`; `/spec-to-symphony` Step 1 resolves them from the governing config and prints the answer. From *this* skill you usually cannot see the config at all — so **assume not readable**, say so at the gate, and never let an assumed capability be the reason the branch push is skipped.

Symphony has no git code on either: the clone is the config's `after_create` hook, which runs **once**, so a spec absent from the remote at first dispatch never arrives by that path either. This skill pushes nothing, so on a deployment that cannot read attachments the spec reaches the pipeline only through `/spec-to-symphony`'s branch push.

**None of that changes what this skill does, and it does not move the ticket.** The reason it does not has changed, so state the current one rather than the retired one: arming is a single confirmed sequence that also has to set the ticket's project and verify its branch, and `/spec-to-symphony` Step 9 is where that sequence lives. **A ticket armed with no project is dispatched in no state** — Symphony filters `project` before `state` — so a transition from here can be a silent no-op even where the attachment is perfectly readable. It would also arm an autonomous run from behind a gate whose text promises the opposite.

So two things are true at once: **the attachment is the human-readable artifact on the ticket**, and **arming belongs to the next leg**. Do not push, do not write the description, do not transition.

## The Job

1. Preflight — a git repo, the Linear MCP, the ticket, and which mode
2. Sanity-check the ticket's current state — read it, never write it
3. Establish which repo this ticket is about
4. Run `/blind-spot` over the task     *(draft mode only)*
5. Draft the spec to disk              *(draft mode only)*
6. **Gate 1** — the caller approves the spec
7. **Gate 2** — the caller approves the Linear write
8. Upload burst → prove → retire the old attachment
9. Report, naming the next step

**Both gates precede step 8, and that is forced, not stylistic.** `prepare_attachment_upload` returns a signed URL that is short-lived (Linear's upload URLs expire in about 60 seconds). Prepare → `PUT` → finalize is one uninterrupted burst; a gate inside it burns the fuse.

**Inside step 8, proving precedes retiring.** The new attachment is proven on the ticket before the old one is deleted, so a failed burst leaves the previous spec in place rather than a ticket with no spec at all. Nothing enforces that order but you.

**Refresh exists because `/spec-review-codex` rewrites the spec file in place and nothing else re-uploads it.** Without this mode the ticket's attachment stays the unreviewed draft for the life of the ticket, while the line map's next station is called *Spec hardened*.

## The caller may be an agent

"The caller" is whoever invoked this skill — a person at a terminal, or another agent. The gates do not assume a person, but they are still gates: **stop, present, and wait for an explicit affirmative.** An agent caller's affirmative is its explicit yes, not your inference that it would probably agree. There is no `--dry-run` to inspect with; the earlier revision had one and the API offers no equivalent, so the gate text is the only thing standing between a draft and a live write.

## FORBIDDEN

- **Never call `save_issue` at all.** Not with `description`, not with `state`, not with `patch`, not with anything. This skill's only Linear write is the attachment. Moving the ticket belongs to `/spec-to-symphony`, which arms only after setting the ticket's project and proving the spec on the remote — a transition from here skips both and can dispatch nothing at all.
- **Never report success, and never delete the previous attachment, before a read-back has shown the new one on the ticket.** A successful `create_attachment_from_upload` is not proof; the read-back is.
- **Never re-draft in refresh mode.** Refresh uploads the bytes on disk. Re-drafting there discards whatever `/spec-review-codex` just fixed, which is the one thing refresh exists to preserve.
- **Never put a gate, a question, or any unrelated call between `prepare_attachment_upload` and `create_attachment_from_upload`.** The signed URL expires in about a minute.
- **Never modify, re-case, drop or add to the headers `prepare_attachment_upload` returns.** They are part of the signed request; any change returns HTTP 403.
- **Never base64-encode the spec, and never embed it as a `data:` URL.** Use `prepare_attachment_upload` + direct `PUT` + `create_attachment_from_upload`.
- **Never leave two spec attachments on the ticket.** In refresh mode the old one is deleted in Step 8.6, after the new one is proven — never before, and never not at all. In draft mode a pre-existing attachment is the caller's decision (Step 1.3).
- **Never commit, branch or push.** No git writes at all — the local spec file stays uncommitted.
- **Never use `orca`, and never hand-roll GraphQL against `api.linear.app`.** The transport is the Linear MCP. A missing tool is a STOP that names the tool, not a licence to reach for another wire mid-run.
- **Never invent a second delivery channel.** No description rewrite, no snapshot comment, no push. The attachment is the channel; where a deployment cannot read attachments, `/spec-to-symphony`'s branch push is the one that reaches it. Name it as the next step and stop.
- **Never glob for the blind-spot report** and never rebuild it from the subagent's final message.
- **Never run `/spec-review-codex`.** It is the caller's next step.

---

## Step 1: Preflight

```bash
git rev-parse --show-toplevel >/dev/null || { echo "not a git repo"; exit 1; }
```

The Linear MCP is the other half of the preflight: the five tools named above must be available. If the only Linear tools visible are `authenticate`/`complete_authentication`, the connector is not authenticated — ask the user to run `/mcp`, select the Linear connector, and retry. There is no second transport: no `orca`, no API key, no GraphQL. **No usable MCP ⇒ STOP**, naming the tool that was missing.

There is **no workspace parameter**. The OAuth session binds to exactly one workspace, which you can neither select nor assert, so the only check available is reading the identifier back (1.1) and confirming it is the one you asked for.

### 1.0 — which mode

**Refresh** when the caller says so — `refresh`, `re-upload`, "the spec has been reviewed", "update the attachment" — or when the caller reaches Step 1.3's collision question and chooses *replace*. **Draft** otherwise. The mode decides one thing only: whether Steps 4–5 run.

Refresh has one extra precondition: `docs/superpowers/specs/<IDENT>-design.md` must exist on disk. **Absent ⇒ STOP** — there is nothing to re-upload, and drafting a fresh spec is not a substitute for the hardened one that went missing. Say which path was empty and let the caller decide whether to re-run in draft mode.

### 1.1 — resolve the ticket

Resolve the identifier from the invocation's argument, else from the worktree (its branch name or its linked ticket). Then two reads, which is everything Steps 1.3 and 2 need:

```
get_issue(id: "<IDENT>")                     -> identifier, title, url, description,
                                                status, team, attachments
list_issue_statuses(team: "<team from get_issue>")   -> the team's workflow states
```

`get_issue`'s `id` accepts the human identifier (`MDZ-123`) directly. **No issue UUID is needed anywhere in this skill** — `prepare_attachment_upload` takes the identifier too, which is one fewer thing to carry through the burst than the GraphQL revision needed.

- **`get_issue` errors or returns nothing ⇒ STOP.** Nothing else in this skill is safe without it.
- **The returned `identifier` must equal the one you asked for.** The session binds to one workspace and you can neither select nor assert it. This read-back is the only check that you are writing where you think you are — a ticket in another workspace simply does not resolve.
- **An empty description ⇒ STOP.** This skill's premise is a groomed ticket; there is nothing to draft from.

### 1.2 — the description is read, not written

Do not capture it as a baseline, do not diff it later, do not snapshot it. It is input to the drafting pass and nothing else. The previous revision overwrote it and needed all three of those; this one does not.

### 1.3 — attachment collision

Look for an attachment titled `<IDENT>-design.md` in `get_issue`'s `attachments` from 1.1.

**Each entry must carry its own `id`** — Step 8.6 deletes by that id and there is no other way to address an attachment. An entry with a title but no id ⇒ say so and treat the collision as unresolvable: continue only in draft mode with the caller's explicit go-ahead to leave both copies on the ticket, and name the leftover in the report.

In **refresh** mode its presence is expected: keep its id for Step 8.6 and continue.

In **draft** mode, **present ⇒ STOP and ask the caller**, showing the existing attachment's title and creation date:

- **replace** — continue in refresh mode if the local hardened spec is what they want uploaded, or in draft mode if they want a new spec drafted. Either way keep the old attachment id for Step 8.6; or
- **abort** — stop here.

Either way the delete happens in **Step 8.6, after the new attachment is proven** — never up front, with `delete_attachment(id: "<old attachment id>")`.

Deleting first would mean a failed burst leaves the ticket with **no** spec at all, which is worse than a stale one. Never a silent second copy either: two attachments named alike leave the next reader guessing which spec is current. An attachment from an earlier run holds *that run's* spec, so its presence means **decide**, not *done*.

## Step 2: Sanity-Check the Current State — Read Only

There is no target state to resolve, because there is no transition. What is left is one read-only look at where the ticket already sits, using `get_issue`'s `status` and `list_issue_statuses`' names from Step 1.1:

- **Expected initial state**: default `To Do`. In **draft** mode, if the ticket is in any other state, say so and **ask** before continuing — a ticket already in `In Progress` or `Done` probably should not be re-specced. In **refresh** mode this is looser: a ticket mid-flight is the normal case, so report the state and continue.
- **If the ticket already sits in an active-looking state** — `Ready for Spec Review`, `Ready for Planning`, anything past the backlog — say so at Gate 2. A Symphony poller may already be running, and on a deployment that reads attachments an upload now changes the artifact a stage that has not run yet will fetch. You cannot know any deployment's intake state from here, so do not try to work it out, do not move the ticket back, and do not treat it as a blocker: report it and let the caller decide.

**Never resolve a state UUID.** Needing one means you are about to call `save_issue`, which this skill does not do. `list_issue_statuses` is called only so the check above can print real names instead of guesses.

## Step 3: Establish the Repo

The drafting pass reads the codebase, so it must read the right one, and Linear has no field naming the repo a ticket belongs to. Two honest cases:

- **Invoked with no identifier** (the worktree's own ticket): the checkout *is* the answer. Continue.
- **Invoked with an explicit identifier**: the repo cannot be derived. Print `git remote get-url origin` next to the identifier at Gate 1 and let the caller confirm it. Declined ⇒ **STOP**.

A spec drafted against the wrong clone describes the wrong system, and the caller reading two lines is the only check available.

## Step 4: Blind-Spot Pass — Draft Mode Only

**Refresh mode skips this step and Step 5 entirely: go straight to Gate 1 with the file on disk.** Re-running a blind-spot pass over an already-hardened spec buys nothing and costs a subagent.

Resolve the report path **into a variable, before dispatch**, and read that exact path afterwards:

```bash
REPORT_PATH="${TMPDIR:-/tmp}/linear-spec-blind-spot-$(date +%s).md"
```

Dispatch one `Agent` subagent following `/blind-spot`'s contract: read-only tools plus a single `Write` carve-out for `$REPORT_PATH`, given the ticket description and the repo. **Substitute the expanded path into the prompt** — a subagent cannot expand `${CLAUDE_PLUGIN_ROOT}` or a shell variable.

Then read `$REPORT_PATH`. Do **not** glob `*blind-spot*.md`: a glob silently adopts a stale report from a different task. Do **not** reconstruct the report from the subagent's final message: a subagent that finishes its pass and idles sends none. Missing file ⇒ say so and **STOP**; never re-dispatch and never re-ask.

## Step 5: Draft the Spec — Draft Mode Only

Dispatch a second, fresh-context `Agent` subagent. Give it, as expanded absolute paths or inline content: the ticket description, `$REPORT_PATH`, and the repo root.

Its instructions:

- Write a design spec for this ticket, in the language the ticket is written in.
- Every high-impact unknown from the blind-spot report must appear either as a **resolved decision** or as an **explicitly deferred** one that says what was deferred and why. Silence about an unknown is a defect.
- Sections: purpose, decisions taken, the approach, failure modes, non-goals, definition of done, known gaps.
- Return the spec as markdown. Nothing else.

Write the returned markdown to `docs/superpowers/specs/<IDENT>-design.md`.

**Gate the output hard** before it goes anywhere:

| Condition | Meaning |
|---|---|
| empty | the step went wrong |
| contains `</invoke>`, `<invoke`, `</content>` or `antml` | tool-call markup leaked; a wave-2 editor once leaked its own closing tags into a live ticket |
| no `## ` heading anywhere | not a spec |

Any of these ⇒ **re-dispatch once**. A second failure ⇒ **STOP** with nothing written to Linear. Never strip the contamination and continue: contaminated output means the step went wrong, not that the text needs cleaning.

**In refresh mode, run the same three checks against the file on disk** — `/spec-review-codex` edits it in place, so a leak or a truncation is possible there too. There is nothing to re-dispatch, so any failure is an immediate **STOP**: fix the file, then re-run.

Leave the file **uncommitted**. This skill makes no git writes; `/spec-to-symphony` is what commits it, onto the ticket branch.

## Step 6: Gate 1 — the Spec

Show the caller: the mode, the spec path, its headings, the repo `origin` next to the ticket identifier (Step 3), and — in draft mode — the blind-spot report path. In **refresh** mode say plainly that the file on disk is being uploaded as it stands and name the attachment it will replace, with that attachment's creation date, so the caller can tell a hardened spec from a stale one. Ask whether to proceed. Declined ⇒ **STOP**; the spec stays on disk and re-running is cheap.

## Step 7: Gate 2 — the Linear Writes

**This is the only thing that stops an unapproved Linear write.** There is no dry run. Present this and wait for an explicit yes:

```
linear-spec-ticket — ready to write
-----------------------------------
Mode:     draft | refresh
Ticket:   <IDENT> — <title>
          <url>
Team:     <team>                  (the workspace your Linear MCP session is bound to)
Repo:     <owner/repo>            (origin)
Spec:     docs/superpowers/specs/<IDENT>-design.md   (local, uncommitted)
Attach:   <IDENT>-design.md       (text/markdown, <N> bytes)
          [refresh: replaces the attachment created <date>, after the new one is proven]
State:    <current>  ->  unchanged
Writes:   one file attachment. [refresh: and one delete of the old one.] Nothing else.

The ticket state is NOT changed, the description is NOT modified, and nothing is
committed or pushed — so this write arms nothing, and nothing here starts a run.
On a deployment whose Symphony build renders attachments, a stage agent CAN read
this attachment and treats it as outranking the description; on a build without
that support the spec reaches the pipeline only via the branch push.
Either way the ticket is armed by /spec-to-symphony, which sets the project and
proves the spec first — moving the ticket yourself starts an autonomous run and
may dispatch nothing at all. Proceed? [y/N]
```

If Step 2 found the ticket already in an active-looking state, add one line above the question: `Note: <IDENT> is already in <state> — a pipeline may already be running against a different spec.`

Declined ⇒ **STOP**. The spec stays on disk; re-running this step later is all that is needed.

## Step 8: Upload, Prove, Retire

Everything from here to the end of the burst runs without interruption.

### 8.1 — measure

`prepare_attachment_upload` turns this number into a signed `x-goog-content-length-range: <N>,<N>` header, exact on both bounds. A spec with any non-ASCII character in it — an accent, an em dash — has more bytes than characters, so a size measured with `wc -m` returns **403** on the `PUT`. Use the byte count:

```bash
SPEC="docs/superpowers/specs/<IDENT>-design.md"
wc -c < "$SPEC"        # exact byte SIZE — never wc -m
```

### 8.2 — request the signed upload URL

```
prepare_attachment_upload(
  issue:       "<IDENT>",
  filename:    "<IDENT>-design.md",
  contentType: "text/markdown",
  size:        <exact bytes from 8.1>,
  title:       "<IDENT>-design.md",
  subtitle:    "Design spec — /linear-spec-ticket"
)
```

Keep `assetUrl`, `uploadRequest.url` and `uploadRequest.headers`. **The clock starts now** — the signed URL is good for about 60 seconds, so do nothing between here and 8.4 but the `PUT`. An error here ⇒ the burst never started and the ticket is untouched; fix the input and re-issue.

**One file, one burst.** Never prepare a second upload before this one is finalized — the first signed URL expires while the second is being prepared.

### 8.3 — PUT the raw bytes

One `-H` per header in `uploadRequest.headers`, **verbatim, casing included** — that set already carries the content type, so add nothing to it. Send no other headers, in particular **no `Authorization`**: this is a signed storage URL, not the API. Drop none, re-case none. Do not transform the file: no base64, no re-encoding.

Send every returned header even though not all are signed. A live run returned several headers while `X-Goog-SignedHeaders` listed only a subset, so the rest were almost certainly droppable. **Do not start dropping them.** Which headers Google signs is Google's decision and can change between runs; sending exactly what the response returned costs nothing and never needs revisiting.

```bash
curl -sS -f -X PUT --data-binary @"$SPEC" \
  -H "<header-1-name>: <header-1-value>" \
  -H "<header-2-name>: <header-2-value>" \
  ...                                       # one per returned header, verbatim
  "<uploadRequest.url>"
```

Non-zero exit or a 403 ⇒ the burst failed. **An unused upload URL creates nothing on the ticket**, so the ticket is untouched: go back to 8.2 and repeat the burst. Do not proceed.

### 8.4 — create the attachment

```
create_attachment_from_upload(
  issue:    "<IDENT>",
  assetUrl: "<assetUrl from 8.2>",
  title:    "<IDENT>-design.md",
  subtitle: "Design spec — /linear-spec-ticket"
)
```

**Keep the returned attachment `id`.** Step 8.5 proves that id, not the title — in refresh mode the old attachment carries the same title and is still on the ticket at that moment, so a title match would be satisfied by the very attachment you are about to delete.

An error here ⇒ the asset is uploaded but unreferenced, so nothing is visible on the ticket. Retry this call with the same `assetUrl`; if that fails too, repeat the whole burst from 8.2.

### 8.5 — prove it

Re-run `get_issue(id: "<IDENT>")` and look at its `attachments`.

**The attachment `id` returned by 8.4 must appear in that list. Absent ⇒ STOP.** Do not delete anything, do not report success. A `create_attachment_from_upload` that returned without error is not proof — this read is.

### 8.6 — retire the previous attachment

Only if Step 1.3 found one and the caller chose replace. Now that 8.5 has proven the new attachment, delete the old one by the id kept in Step 1.3:

```
delete_attachment(id: "<old attachment id>")
```

**This is the last write, and it is the only order that is safe.** Deleting before the burst risks a ticket with no spec at all; skipping it leaves two attachments with the same title and no way for a reader to tell which is current.

Fails ⇒ report it plainly. The ticket then carries both, the new one is the later of the two, and deleting the old one by hand is a ten-second fix. Do not retry in a loop and do not delete the new one to "restore consistency".

### 8.7 — the state stays where it is

There is no transition. If the caller's workflow tracks a "spec attached" state, moving the ticket is theirs to do; if the build is going to a Symphony pipeline, `/spec-to-symphony` moves it after proving the spec is on the remote. Say which in the report — a ticket that silently never advances is its own kind of drift.

## Step 9: Report

Draft mode:

```
linear-spec-ticket complete  (draft)
-----------------------------------
Ticket:  <IDENT> <url>   state unchanged: <state>
Attach:  <IDENT>-design.md  (on the ticket)
Spec:    docs/superpowers/specs/<IDENT>-design.md   (local, uncommitted)
Next:    /spec-review-codex docs/superpowers/specs/<IDENT>-design.md
         then /linear-spec-ticket <IDENT> refresh    — re-upload the hardened spec
         then /spec-to-symphony <IDENT>              — push it to the remote and arm

Nothing was armed: the ticket state is unchanged. If your workflow tracks a
"spec attached" state, move it by hand — no skill on the local build path does.
```

Refresh mode: same block headed `(refresh)`, with `Attach:` reading `<IDENT>-design.md  (replaced the copy from <date>)` and `Next:` reading `/spec-to-symphony <IDENT>` alone.

**Pass the path explicitly** on that `Next` line. `/spec-review-codex` auto-discovers specs by *date-prefixed* filename, and this one is identifier-keyed, so its scan will not find it on its own.

**Name the refresh step every time, in draft mode.** `/spec-review-codex` rewrites the file in place, so without it the attachment on the ticket is the draft nobody reviewed — and the ticket looks complete either way.

If `command -v codex` fails, add one line saying that next step needs `codex` on PATH and authenticated. This skill itself never invokes `codex`.

## Red Flags — STOP

- "The spec is attached, so I'll move it to `Ready for Spec Review` while I'm here" — that is a real deployment's intake state, and nothing has verified the ticket's project. `/spec-to-symphony` moves it, after that check and the push proof
- "It's only a state change, not a real write" — it is the one write that can start an autonomous run
- "`create_attachment_from_upload` returned without an error, so the spec is on the ticket" — only the read-back proves it
- "The read-back shows an attachment with the right title, so the new one landed" — in refresh mode that title belongs to the old one too. Prove the **id** 8.4 returned
- "I'll delete the old attachment first so there's only ever one" — a failed burst then leaves the ticket with no spec at all. Delete in 8.6, after the proof
- "Refresh mode, so I'll re-draft the spec to be safe" — that discards exactly what `/spec-review-codex` just fixed
- "The hardened spec is on disk, so the ticket is up to date" — the ticket holds whatever was uploaded. Run refresh
- "I'll ask the caller to confirm before I PUT" — the signed URL dies in about a minute; both gates are behind you by then
- "I'll add a `Content-Length` header to be safe" — the header set is signed as returned; adding one returns 403
- "I'll put `Authorization` on the PUT too" — the PUT goes to a signed storage URL, not the API. There is no key to send anyway, and an extra header breaks the signature
- "`wc -m` gives me the size" — it gives characters, not bytes. Any accent makes the two differ and the signed range is exact on both bounds, so the `PUT` returns 403
- "`orca` or a raw GraphQL call would be easier here" — the MCP carries the whole burst, and it is the transport by decision (TRA-11). A tool that is missing is a STOP naming it, not a second wire
- "There's already a spec attachment, I'll just upload the new one alongside" — two specs, and no reader can tell which is current
- "There's already a spec attachment, so this ticket is done" — an attachment holds *its own run's* spec. Its presence means decide (Step 1.3), not done
- "Symphony might not see the attachment, so I'll also push the spec / also write the description" — a second channel here is the removed revision, whichever way the deployment reads. `/spec-to-symphony` owns the push, and it is the next step, not a gap to patch here
- "I'll commit the spec so it isn't lost" — this skill makes no git writes
- "The caller is an agent, so the gate is a formality" — the gate is the only thing between a draft and a live write, and there is no dry run
- "I'll glob for the blind-spot report" — a glob adopts a stale report from another task
- "I'll just run `/spec-review-codex` too while I'm here" — out of scope, by decision
