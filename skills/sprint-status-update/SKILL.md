---
name: sprint-status-update
description: Use when generating a weekly or end-of-sprint status update Slack message, when asked to "write sprint update", "weekly update", "sprint recap", "status update for slack", or "sprint wrap-up message"
---

# Sprint Status Update

## Overview

Generates a company-wide Slack message summarizing the current sprint by querying the Notion sprint board, categorizing deliveries, and formatting a scannable update.

## Data Sources

### Sprint Board (features, user stories, improvements)
- **Database URL**: https://www.notion.so/302c6f23e3d480fbb773eacb31179145?v=302c6f23e3d480588517000cea59b39f
- **Current Sprint data source**: `collection://302c6f23-e3d4-8074-9e42-000b3d8506c0`

### Bug Reports
- **Database URL**: https://www.notion.so/302c6f23e3d48077aa17f31d042b3565
- **Bug reports data source**: `collection://302c6f23-e3d4-8013-9580-000b61343bcb`
- **Statuses**: Backlog, In progress, Needs Info, Code review, Can't reproduce, Not a bug, Done
- **Types**: Bug, Improvement

## Workflow

### 1. Identify Active Sprint

Fetch the database (which includes view configs) to check which sprints are filtered out. The sprint NOT in the exclusion filter is the active one.

```
Use: notion-fetch on https://www.notion.so/302c6f23e3d480fbb773eacb31179145?v=302c6f23e3d480588517000cea59b39f
```

Note: `view://` URLs are NOT supported by notion-fetch. Always use the full database URL with `?v=` parameter.

### 2. Query All Sprint Tasks

Query **both** data sources for the active sprint:

**Sprint Board** — Use `notion-search` on `collection://302c6f23-e3d4-8074-9e42-000b3d8506c0`. Fetch each task page to get properties: Task, Status, Type, Severity, Tags, Priority, Assigned To.

**Bug Reports** — Use `notion-search` on `collection://302c6f23-e3d4-8013-9580-000b61343bcb`. Fetch each bug page to get properties: Issue, Status, Type, Severity, Sprint, Tags.

The search may return items from other sprints — **filter results to only include items where Sprint matches the active sprint**. For bugs, exclude items with Status = "Not a bug" or "Can't reproduce" from the counts.

### 3. Categorize by Status

| Category | Statuses | Message section |
|----------|----------|-----------------|
**Sprint Board statuses:**
| Category | Statuses | Message section |
|----------|----------|-----------------|
| **Completed** | Ready to Prod, In Prod | "Completed deliveries" |
| **In progress** | In progress, Code Review, Ready for QA (in STG), QA (in STG) | "In progress" |
| **Blocked** | On hold/Blocked | "Blocked" (only if any exist) |
| **Planned** | Planned | "Not started" (only if relevant) |

**Bug Reports statuses:**
| Category | Statuses | Message section |
|----------|----------|-----------------|
| **Fixed** | Done | "Bugs squashed" |
| **In progress** | In progress, Code review | "Bugs in progress" |
| **Dismissed** | Not a bug, Can't reproduce | Exclude from message |

Within each category, sort: Bugs first (by severity ascending), then User Stories, then Improvements.

### 4. Enrich Descriptions

For each **completed** task, fetch the individual task page using `notion-fetch` on the task URL. Read the page content to write a 1-line description explaining **what was actually done/fixed**, not just the task title.

For in-progress items, titles are usually sufficient.

### 5. Compute Stats

- Total completed deliveries
- Items in progress
- Bug count with severity breakdown (e.g., "3 Sev 1, 4 Sev 2, 2 Sev 3")
- Do NOT include story points in the message

### 6. Format Slack Message

**Structure:**

```
Hey Tyrellers! Sprint [N] [wrap-up / mid-sprint update] [with a brief assessment].

Here's the [final scorecard / current status]:
  Completed deliveries:
  - [Task name] -- [1-line description of what was done]
  - ...

  Ready to ship (pending prod deploy):
  - [Task name] -- [brief description]
  - ...

  In progress:
  - [Task name] -- [brief status if available]
  - ...

  [Only if blocked items exist:]
  Blocked:
  - [Task name] -- [reason if available]

  Bugs squashed:
  - [Bug title] ([Severity]) -- [1-line description of what was fixed]
  - ...

  [Only if bugs still in progress:]
  Bugs in progress:
  - [Bug title] ([Severity]) -- [brief status]
  - ...

  Final numbers: [X] deliveries shipped or ready, [Y] in progress. [Z] bugs squashed ([severity breakdown]), [W] bugs in progress. [Brief closing remark]
```

### 7. Present for Review

Output the draft as **plain text** — no markdown quoting, no blockquotes, no code blocks. Emojis are allowed. The message should be copy-pasteable directly into Slack.

The user may want to:
- Adjust tone or emphasis
- Add context only they know
- Remove items that shouldn't be in the update
- Add a "coming next sprint" section

## Message Guidelines

- **Be specific**: Add "-- what was done" after each item, not just the title
- **Lead with impact**: Sev 1 bugs and major features first
- **Tag bug severity**: Always include (Sev 1), (Sev 2), etc.
- **Active past tense**: "fixed", "resolved", "added", "removed", "updated"
- **Scannable**: Each bullet self-contained, indented with 2 spaces
- **Close with stats**: Deliveries, in-progress count, bug breakdown
- **Tone**: Casual, team-friendly, celebratory for wrap-ups
- **Plain text only**: No markdown formatting, no blockquotes, no code fences. Output must be directly pasteable into Slack.

## Common Mistakes

- Listing task titles without explaining what was done
- Forgetting severity tags on bugs
- Not fetching task pages for description context
- Including sub-tasks that are part of a parent (only list the parent)
- Wrong sprint — always verify the active sprint from the view filter
- Including story points in the message — never show points in the Slack update
- Including items from previous sprints — always filter by the active sprint name
