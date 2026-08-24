#!/usr/bin/env python3
"""Assemble duplicate candidates for the duplicates analyst to judge.

This script never talks to Linear and never decides what is a duplicate — it
only assembles the candidate set from part files the agent produced with the
Linear MCP, so the assembly (dedup, excerpts, shared-identifier extraction,
counts) stays deterministic and testable offline.

The Linear reads themselves are the agent's job (SKILL.md step 2): the MCP is
agent-only, so no script can call it. The agent runs `list_issues` for the
keyword query and once per open state, then `get_issue` for the first
LINEAR_GROOM_BODY_LIMIT candidates, and writes each response into
`<run-dir>/.candidate-parts/` in a small documented shape:

  search.json          {"result": {"issues": [{"identifier","title",
                                               "state": {"name"}, "url"}, ...]}}
  open-<N>.json        same shape, one file per open state listed
  body-<IDENT>.json    {"result": {"issue": {"description": "..."}}}
  bodyerr-<IDENT>.txt  (optional) one line explaining why a body read failed

This script reads those parts plus <run-dir>/ticket.json and writes
<run-dir>/candidates.json. The output shape is unchanged from the previous
orca-driven pipeline, so prompts/duplicates.md and 30-wave1.sh need no edits.
Python 3.9 compatible.
"""

import argparse
import glob
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "lib"))

import identifiers as ident_lib  # noqa: E402
import keywords as kw_lib  # noqa: E402


def die(message):
    sys.stderr.write("linear-groom: %s\n" % message)
    raise SystemExit(1)


def read_json(path):
    with open(path, "r") as handle:
        return json.load(handle)


def positive_int(name, raw):
    try:
        value = int(raw)
    except (TypeError, ValueError):
        die("%s must be a non-negative integer, got %r" % (name, raw))
    if value < 0:
        die("%s must be a non-negative integer, got %r" % (name, raw))
    return value


def collect(parts, ticket, query):
    """Dedup search + open-state issues into an ordered candidate list."""
    seen = set()
    candidates = []

    def add(issues, source):
        for issue in issues or []:
            ident = issue.get("identifier")
            if not ident or ident == ticket or ident in seen:
                continue
            seen.add(ident)
            candidates.append(
                {
                    "identifier": ident,
                    "title": issue.get("title") or "",
                    "state": (issue.get("state") or {}).get("name") or "",
                    "url": issue.get("url") or "",
                    "source": source,
                }
            )

    search_path = os.path.join(parts, "search.json")
    if os.path.exists(search_path):
        add(read_json(search_path)["result"].get("issues"), "search")

    # sorted() so open-2 never precedes open-10 in a way that reorders the set
    # run to run; the leading zero-free names sort lexically, which is stable
    # enough here because dedup is by identifier, not by position.
    for path in sorted(glob.glob(os.path.join(parts, "open-*.json"))):
        add(read_json(path)["result"].get("issues"), "open")

    return {"ticket": ticket, "query": query, "candidates": candidates}


def attach_bodies(doc, parts, ticket_desc, excerpt_chars, body_limit):
    """Attach per-candidate excerpts and identifiers from body part files.

    Mirrors the old orca pipeline's asymmetry: a candidate beyond the cap is
    marked `excerpt_skipped`, an unreadable body is marked `excerpt_error`, and
    neither aborts — only a genuinely broken candidate set (no ticket.json) does.
    """
    candidates = doc["candidates"]
    ticket_idents, ticket_trunc = ident_lib.extract(ticket_desc)

    fetched = failed = skipped = 0
    failed_ids = []

    for pos, cand in enumerate(candidates):
        ident = cand["identifier"]
        body_path = os.path.join(parts, "body-%s.json" % ident)
        err_path = os.path.join(parts, "bodyerr-%s.txt" % ident)
        if pos >= body_limit:
            skipped += 1
            cand["description_chars"] = None
            cand["excerpt"] = None
            cand["excerpt_skipped"] = (
                "beyond the body-read cap (LINEAR_GROOM_BODY_LIMIT=%d): the "
                "description was never fetched, so nothing is known about it"
                % body_limit
            )
            continue
        if os.path.exists(err_path):
            failed += 1
            failed_ids.append(ident)
            cand["description_chars"] = None
            cand["excerpt"] = None
            with open(err_path) as handle:
                cand["excerpt_error"] = handle.read().strip()
            continue
        try:
            desc = read_json(body_path)["result"]["issue"].get("description") or ""
        except (OSError, ValueError, KeyError, TypeError) as exc:
            failed += 1
            failed_ids.append(ident)
            cand["description_chars"] = None
            cand["excerpt"] = None
            cand["excerpt_error"] = "unreadable body part for %s: %s" % (ident, exc)
            continue
        fetched += 1
        cand_idents, cand_trunc = ident_lib.extract(desc)
        # description_chars is the length of the WHOLE description, never of the
        # excerpt: the analyst has to know how much it is NOT seeing before it
        # concludes anything from an absence.
        cand["description_chars"] = len(desc)
        cand["excerpt"] = ident_lib.excerpt(desc, excerpt_chars)
        cand["identifiers"] = cand_idents
        cand["identifiers_truncated"] = cand_trunc

    # The ticket's own identifiers, extracted by the same code from its full
    # description, so "shared identifier" is a set intersection the analyst can
    # perform mechanically rather than a judgement about prose.
    doc["ticket_identifiers"] = ticket_idents
    doc["ticket_identifiers_truncated"] = ticket_trunc
    doc["excerpt_chars"] = excerpt_chars
    doc["body_limit"] = body_limit
    doc["bodies_fetched"] = fetched
    doc["bodies_failed"] = failed
    doc["bodies_skipped_by_cap"] = skipped
    return fetched, failed, skipped, failed_ids


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-dir", required=True)
    parser.add_argument("--ticket", required=True, help="ticket identifier, for the record")
    parser.add_argument("--parts", default=None, help="parts dir (default <run-dir>/.candidate-parts)")
    args = parser.parse_args(argv)

    body_limit = positive_int("LINEAR_GROOM_BODY_LIMIT", os.environ.get("LINEAR_GROOM_BODY_LIMIT", "8"))
    excerpt_chars = positive_int(
        "LINEAR_GROOM_EXCERPT_CHARS", os.environ.get("LINEAR_GROOM_EXCERPT_CHARS", "400")
    )

    ticket_path = os.path.join(args.run_dir, "ticket.json")
    if not os.path.exists(ticket_path):
        die("missing %s — run the fetch step (SKILL.md step 1) first" % ticket_path)
    parts = args.parts or os.path.join(args.run_dir, ".candidate-parts")
    if not os.path.isdir(parts):
        die("missing %s — the agent must write the MCP candidate parts there (SKILL.md step 2)" % parts)

    issue = read_json(ticket_path)["result"]["issue"]
    title = issue.get("title") or ""
    ticket_desc = issue.get("description") or ""

    stopwords = kw_lib.load_stopwords(kw_lib.DEFAULT_STOPWORDS)
    query = " ".join(kw_lib.extract(title, stopwords, 6))
    if not query:
        die("could not derive a search query from the ticket title")

    doc = collect(parts, args.ticket, query)
    sys.stderr.write("candidates: %d unique\n" % len(doc["candidates"]))

    fetched, failed, skipped, failed_ids = attach_bodies(
        doc, parts, ticket_desc, excerpt_chars, body_limit
    )

    out = os.path.join(args.run_dir, "candidates.json")
    with open(out, "w") as handle:
        json.dump(doc, handle, indent=2, ensure_ascii=False)
        handle.write("\n")

    sys.stderr.write(
        "bodies: %d of %d candidates fetched, %d skipped by cap "
        "(LINEAR_GROOM_BODY_LIMIT=%d), %d failed\n"
        % (fetched, len(doc["candidates"]), skipped, body_limit, failed)
    )
    if failed_ids:
        sys.stderr.write("bodies: could not read: %s\n" % ", ".join(failed_ids))
    return 0


if __name__ == "__main__":
    sys.exit(main())
