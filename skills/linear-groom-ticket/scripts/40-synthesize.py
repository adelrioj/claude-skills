#!/usr/bin/env python3
"""Turn wave-1 findings plus the editor's draft into an applyable plan.

The deletion safeguard lives here, in code, rather than in an agent's
judgement: a false "delete this ticket" is the worst outcome this skill can
produce, so the rule must be inspectable and testable. Every degradation path
fails toward keeping the ticket.
Python 3.9 compatible.
"""

import argparse
import json
import os
import sys

DIMENSIONS = ("veracity", "duplicates", "feasibility")
EVIDENCE_KINDS = ("commit", "file", "issue")

# Precedence used to pick a single winning delete_reason when more than one
# available dimension coherently proposes deletion for a different reason.
# `duplicate` wins because it yields the strongest, most checkable artifact —
# a link to a canonical ticket a human can verify in one click. The rest
# descend by how independently verifiable they are. This never widens the
# four-condition rule; it only decides which already-qualifying dimension's
# reason gets surfaced when more than one qualifies.
REASON_PRECEDENCE = ("duplicate", "already-resolved", "obsolete", "unactionable")


# Markup that must never reach a real ticket description. `</invoke>`,
# `<invoke` and `</content>` are the closing/opening tags of an agent's own
# tool-call envelope; `antml` is the namespace prefix those tags carry. This is
# not a hypothetical: on the first live run the wave-2 editor subagent leaked
# `\n</content>\n</invoke>\n` into draft.md, this script copied the draft
# verbatim into description_new, and 90-apply.py wrote it to the real ticket.
FORBIDDEN_DRAFT_MARKUP = ("</invoke>", "<invoke", "</content>", "antml")

# The templates (to-linear/templates/{bug,story}.md — one source of truth, picked
# per ticket by 10-lint.py from its type label) each define several level-2
# headings, and prompts/editor.md tells the editor to fill them in. A draft
# with none at all is not a stylistic choice — it is an editor run that
# produced something other than a ticket description (a refusal, an apology, a
# bare sentence). This is the only structural check here on purpose: counting
# how MANY headings appeared, or which ones, would start second-guessing an
# editor that legitimately dropped a section, and that judgement belongs to
# the human at the approval gate.
MIN_LEVEL2_HEADINGS = 1


def draft_problem(draft):
    """Why this editor draft must not become a ticket description, or None.

    A HARD gate, not a warning: the draft is copied verbatim into
    description_new and written to a real person's ticket, so a contaminated
    draft means the editor step went wrong and a human should look at it.

    Nothing is stripped or repaired. Stripping the offending markup is
    precisely what would make the symptom disappear while leaving the cause —
    an editor run that went off the rails — unexamined, and the rest of that
    same draft unreviewed.
    """
    if not draft.strip():
        return (
            "the editor draft is empty or whitespace-only. Nothing was written; "
            "re-run the wave-2 editor (see SKILL.md step 4) rather than hand-writing "
            "a description here."
        )

    lines = draft.split("\n")
    for number, line in enumerate(lines, start=1):
        lowered = line.lower()
        for token in FORBIDDEN_DRAFT_MARKUP:
            if token in lowered:
                return (
                    "the editor draft contains agent tool-call markup: %r on line %d "
                    "(%r). This is the wave-2 editor leaking its own tool-call envelope "
                    "into its answer — it happened on the first live run and reached a "
                    "real ticket. Refusing to plan, and deliberately NOT stripping it: "
                    "a contaminated draft means the editor step went wrong, so re-run "
                    "the editor and read what it returns."
                    % (token, number, line.strip()[:120])
                )

    headings = sum(1 for line in lines if line.startswith("## "))
    if headings < MIN_LEVEL2_HEADINGS:
        return (
            "the editor draft has no level-2 (`## `) headings at all, but every "
            "template defines them. That is almost certainly a failed editor run rather "
            "than a deliberate choice — re-run the wave-2 editor and read its output."
        )
    return None


def default_run_dir(ticket):
    base = os.environ.get("XDG_STATE_HOME") or os.path.join(
        os.path.expanduser("~"), ".local", "state"
    )
    return os.path.join(base, "linear-groom", ticket)


def read_json(path):
    with open(path, "r") as handle:
        return json.load(handle)


def load_wave1(run_dir):
    """Return (available, unavailable) — dict of dimension->payload, list of names."""
    available = {}
    unavailable = []
    for dimension in DIMENSIONS:
        payload_path = os.path.join(run_dir, "wave1", dimension + ".json")
        if os.path.exists(payload_path):
            available[dimension] = read_json(payload_path)
        else:
            # Absent .json means unavailable, regardless of whether a
            # .UNAVAILABLE marker also exists — never require the marker.
            unavailable.append(dimension)
    return available, unavailable


def has_hard_evidence(payload):
    for item in payload.get("evidence") or []:
        if item.get("kind") in EVIDENCE_KINDS and (item.get("ref") or "").strip():
            return True
    return False


def reason_rank(reason):
    try:
        return REASON_PRECEDENCE.index(reason)
    except ValueError:
        return len(REASON_PRECEDENCE)  # unknown/None reason sorts last


def pick_winner(candidates, available):
    """Pick one dimension from `candidates` by delete_reason precedence,
    breaking ties on dimension name for determinism (never dict order)."""
    if not candidates:
        return None
    return sorted(
        candidates, key=lambda d: (reason_rank(available[d].get("delete_reason")), d)
    )[0]


def incoherence_reason(payload):
    """Why this dimension's delete-candidate answer contradicts itself, or None.

    Two shapes count as incoherent, and both are treated identically because
    both are the same kind of error — a structured answer that does not hold
    together:

    - `delete-candidate` with a `deletion_stance` that is not `supports`: the
      dimension says "delete this" and then declines to vote for deleting it.
    - `delete-candidate` with no `delete_reason`: a condemnation with nothing
      machine-readable behind it. The spec requires a reason of one of four
      values; a plan built from such an answer carries `reason: null` and its
      comment reads "proposed deletion for reason 'None'". Treating it as
      incoherent rather than as a special case is in the spirit of the
      existing ruling, and it fails toward KEEPING the ticket.

    An incoherent dimension is never a proposer, so it can never satisfy
    condition 1, and its presence blocks deletion run-wide (the sibling
    answers came from the same model under the same schema, so an incoherent
    answer is evidence about the whole run's reliability).
    """
    if payload.get("verdict") != "delete-candidate":
        return None
    stance = payload.get("deletion_stance")
    if stance != "supports":
        return "deletion_stance is %r, not 'supports'" % stance
    if not (payload.get("delete_reason") or "").strip():
        return "delete_reason is missing, so the deletion has no machine-readable reason"
    return None


def evaluate_safeguard(available, unavailable):
    """Return (deletion_allowed, proposer, blocked_by, coherent_proposers, incoherent).

    coherent_proposers: dimensions with verdict == delete-candidate whose
    answer holds together (see incoherence_reason) — the only ones eligible
    to satisfy condition 1. incoherent: delete-candidate answers that
    contradict themselves, never counted as proposers, and always recorded so
    a human can see the contradiction even when it changes nothing else.
    """
    blocked_by = []

    incoherence = dict(
        (d, incoherence_reason(p)) for d, p in available.items() if incoherence_reason(p)
    )
    incoherent = sorted(incoherence)
    if incoherent:
        blocked_by.append(
            "incoherent: %s returned delete-candidate but contradicted itself "
            "(model self-contradiction)"
            % ", ".join("%s — %s" % (d, incoherence[d]) for d in incoherent)
        )

    coherent_proposers = sorted(
        d
        for d, p in available.items()
        if p.get("verdict") == "delete-candidate" and not incoherence_reason(p)
    )
    if not coherent_proposers:
        # Nobody coherently proposed deletion. blocked_by may still carry the
        # incoherent-dimension note above; there is no winner either way.
        return False, None, blocked_by, coherent_proposers, incoherent

    confident = [d for d in coherent_proposers if available[d].get("confidence") == "high"]
    if not confident:
        blocked_by.append("confidence: no proposing dimension is at high confidence")

    evidenced = [d for d in confident if has_hard_evidence(available[d])]
    if confident and not evidenced:
        blocked_by.append("evidence: the proposing dimension cites no commit, file, or issue")

    opposers = sorted(d for d, p in available.items() if p.get("deletion_stance") == "opposes")
    if opposers:
        blocked_by.append("opposes: %s vote(s) against deletion" % ", ".join(opposers))

    if unavailable:
        blocked_by.append(
            "unavailable_dimensions: %s could not be analysed" % ", ".join(sorted(unavailable))
        )

    winner = pick_winner(evidenced, available)

    if blocked_by:
        fallback = winner or (evidenced[0] if evidenced else coherent_proposers[0])
        return False, fallback, blocked_by, coherent_proposers, incoherent
    return True, winner, [], coherent_proposers, incoherent


def build_comment(
    verdict,
    available,
    blocked_by,
    coherent_proposers,
    incoherent,
    proposer,
    duplicate_missing_link,
):
    lines = ["**linear-groom verdict: %s**" % verdict, ""]
    for dimension in DIMENSIONS:
        if dimension in available:
            payload = available[dimension]
            lines.append(
                "- **%s** — %s (confidence %s, stance %s)"
                % (
                    dimension,
                    payload.get("verdict"),
                    payload.get("confidence"),
                    payload.get("deletion_stance"),
                )
            )
            for finding in payload.get("findings") or []:
                lines.append("  - %s" % finding.get("summary"))
        else:
            lines.append("- **%s** — UNAVAILABLE (not analysed)" % dimension)

    if len(coherent_proposers) > 1:
        # More than one dimension agreed on "delete" but disagreed on "why" —
        # record the disagreement rather than hiding it. The human at the
        # approval gate must see every reason offered, not just the winner.
        offered = ", ".join(
            "%s=%s" % (d, available[d].get("delete_reason")) for d in coherent_proposers
        )
        lines += ["", "Multiple dimensions proposed deletion for different reasons: %s." % offered]
        if proposer:
            verb = "Would have been selected" if blocked_by else "Selected"
            lines.append(
                "%s reason '%s' (from %s) by precedence (%s)."
                % (
                    verb,
                    available[proposer].get("delete_reason"),
                    proposer,
                    " > ".join(REASON_PRECEDENCE),
                )
            )
    elif len(coherent_proposers) == 1:
        # The common case: exactly one proposer. This is the crux of the
        # proposal ("this analyst thinks the work is already done") and the
        # human's only window onto it is this comment — surface it even when
        # deletion ends up blocked, not only when more than one dimension
        # disagreed about the reason.
        d = coherent_proposers[0]
        line = "%s proposed deletion for reason '%s'" % (d, available[d].get("delete_reason"))
        duplicate_of = available[d].get("duplicate_of")
        if duplicate_of:
            line += " (duplicate_of: %s)" % duplicate_of
        lines += ["", line + "."]

    if incoherent:
        lines += [
            "",
            "Model self-contradiction: %s returned delete-candidate with an answer "
            "that does not hold together (%s) — not counted as proposing deletion."
            % (
                ", ".join(incoherent),
                "; ".join(
                    "%s: %s" % (d, incoherence_reason(available[d])) for d in incoherent
                ),
            ),
        ]

    if duplicate_missing_link:
        lines += [
            "",
            "Reason is 'duplicate' but no duplicate_of ticket was identified — "
            "no relation was created; a human must find and link the canonical ticket.",
        ]

    if blocked_by:
        lines += ["", "Deletion was proposed but **blocked**, so a human decides:"]
        lines += ["- %s" % reason_line for reason_line in blocked_by]

    unavailable_dims = sorted(d for d in DIMENSIONS if d not in available)
    if verdict == "READY" and unavailable_dims:
        # Ruling: READY must stay the "touch nothing" verdict, but silence
        # here would let a human believe grooming ran clean when a dimension
        # never executed. Say so in prose instead of inventing a new verdict.
        lines += [
            "",
            "This ticket looks ready based on the dimensions that ran (%s); "
            "%s did not run, so this analysis is incomplete."
            % (", ".join(sorted(available)), ", ".join(unavailable_dims)),
        ]

    evidence = [
        "- **%s** — `%s` %s — %s" % (dimension, item.get("kind"), item.get("ref"), item.get("note") or "")
        for dimension, payload in sorted(available.items())
        for item in payload.get("evidence") or []
    ]
    if evidence:
        lines += ["", "Evidence:"] + evidence
    return "\n".join(lines) + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ticket-id", required=True)
    parser.add_argument("--run-dir")
    parser.add_argument("--draft", required=True, help="wave-2 editor draft description")
    parser.add_argument("--triage-label", default="needs-triage")
    parser.add_argument("--out", required=True)
    args = parser.parse_args(argv)

    run_dir = args.run_dir or default_run_dir(args.ticket_id)
    issue = read_json(os.path.join(run_dir, "ticket.json"))["result"]["issue"]
    gaps = read_json(os.path.join(run_dir, "gaps.json"))
    available, unavailable = load_wave1(run_dir)
    if not available:
        sys.stderr.write("synthesize: every dimension is unavailable; refusing to plan\n")
        return 1

    with open(args.draft, "r") as handle:
        draft = handle.read()

    # Exit 2, distinct from the exit 1 above (every dimension unavailable), so
    # the caller can tell "the analysts could not answer" from "the editor's
    # output is not fit to write to a ticket".
    problem = draft_problem(draft)
    if problem is not None:
        sys.stderr.write("synthesize: %s\n" % problem)
        sys.stderr.write("synthesize: refusing to write a plan; nothing was written\n")
        return 2

    deletion_allowed, proposer, blocked_by, coherent_proposers, incoherent = evaluate_safeguard(
        available, unavailable
    )

    needs_work = bool(gaps.get("missing_required")) or any(
        payload.get("verdict") != "ok" for payload in available.values()
    )

    if deletion_allowed:
        verdict = "DELETE-CANDIDATE"
        reason = available[proposer].get("delete_reason")
    elif needs_work:
        verdict = "FIXABLE"
        reason = None
    else:
        verdict = "READY"
        reason = None

    labels_add = []
    relations = []
    description_new = None
    duplicate_missing_link = False

    if verdict == "DELETE-CANDIDATE":
        labels_add.append(args.triage_label)
        duplicate_of = available[proposer].get("duplicate_of")
        if reason == "duplicate":
            if duplicate_of:
                relations.append({"type": "duplicate-of", "related": duplicate_of})
            else:
                # Never fabricate a link and never silently fall back to a
                # different reason: keep the verdict, keep the label, drop
                # only the relation, and say so in the comment.
                duplicate_missing_link = True
    elif verdict == "FIXABLE":
        description_new = draft
        if blocked_by:
            labels_add.append(args.triage_label)

    evidence = [
        {
            "dimension": dimension,
            "kind": item.get("kind"),
            "ref": item.get("ref"),
            "note": item.get("note") or "",
        }
        for dimension, payload in sorted(available.items())
        for item in payload.get("evidence") or []
    ]

    comment_body = build_comment(
        verdict,
        available,
        blocked_by,
        coherent_proposers,
        incoherent,
        proposer,
        duplicate_missing_link,
    )

    plan = {
        "ticket": issue.get("identifier"),
        "verdict": verdict,
        "reason": reason,
        "original_description": issue.get("description") or "",
        "description_new": description_new,
        "labels_add": labels_add,
        "relations": relations,
        "comments": [{"body": comment_body}],
        "evidence": evidence,
        "unavailable_dimensions": sorted(unavailable),
        "safeguard": {
            "deletion_allowed": deletion_allowed,
            "blocked_by": blocked_by,
            # Task 8's schemas/plan.json does not exist yet at the time of
            # writing (additionalProperties:false at the top level would
            # need checking before adding a new top-level key); this
            # information is nested inside `safeguard`, which is typed
            # loosely as an object, so it survives into plan.json without
            # risking rejection by a schema this task cannot see yet.
            "proposers": [
                {
                    "dimension": d,
                    "delete_reason": available[d].get("delete_reason"),
                    "deletion_stance": available[d].get("deletion_stance"),
                    "confidence": available[d].get("confidence"),
                }
                for d in coherent_proposers
            ],
            "incoherent_dimensions": incoherent,
            # Ruling: unavailable dimensions never widen the safeguard (they
            # already force FIXABLE via condition 4 whenever deletion was
            # proposed), but a READY verdict with an unanalysed dimension is
            # a dishonest "nothing to fix" message. Record the fact plainly
            # here regardless of verdict; build_comment turns it into prose
            # for the human on the READY path specifically.
            "analysis_incomplete": bool(unavailable),
        },
    }

    with open(args.out, "w") as handle:
        json.dump(plan, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    sys.stderr.write("synthesize: %s (%d/3 dimensions)\n" % (verdict, len(available)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
