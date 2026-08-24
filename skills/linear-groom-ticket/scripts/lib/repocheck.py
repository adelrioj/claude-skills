#!/usr/bin/env python3
"""Decide whether a Linear ticket plausibly belongs to a given repository.

A Linear ticket does not record its repository. Without this gate, running the
skill from an unrelated repo makes the veracity agent correctly report "the
cited file does not exist" and produce a false deletion candidate. Exit 3 on
mismatch so the caller can offer an override instead of treating it as a crash.
Python 3.9 compatible.
"""

import argparse
import json
import os
import re
import subprocess
import sys


def _git(repo, args):
    try:
        out = subprocess.run(
            ["git", "-C", repo] + args,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except OSError:
        return ""
    return out.stdout.decode("utf-8", "replace")


def _token_regex(token):
    # Match `token` as a whole token: not preceded/followed by another
    # alphanumeric character. Separators like '-', '_', '.' (and string
    # edges) count as boundaries, unlike a bare `in` substring check, which
    # would let a short key like "OM" match inside "github.com".
    return re.compile(
        r"(?<![A-Za-z0-9])%s(?![A-Za-z0-9])" % re.escape(token), re.I
    )


def _repo_path_of(url):
    """Strip scheme/host from a git remote URL, leaving the repo path.

    Handles both `https://host/org/repo.git` and `git@host:org/repo.git`
    forms so a hostname like "github.com" can never itself contribute a
    token hit for a short team key.
    """
    match = re.match(r"^[^@/\s]+@[^:/\s]+:(.+)$", url)
    if match:
        return match.group(1)
    match = re.match(r"^\w+://[^/]+/(.+)$", url)
    if match:
        return match.group(1)
    return url


def _name_hit(team_name, basename):
    """Signal 2: does the repo basename carry the WHOLE team name?

    It used to be `any(token matches)`, and that was a hole in the dangerous
    direction: one tokenized word of the team name was enough, and team names
    are full of common words. Verified by probe — team name "Data Platform"
    matched the basename `customer-data-warehouse` on "data", and "Core"
    matched `core-utils`. Word-boundary anchoring does not help when the token
    IS a whole word, just a common one. Since `matched = any(signal)`, one such
    hit opened the gate for an unrelated repository — exactly the failure this
    gate exists to prevent, since a false MATCH is what lets a wrong-codebase
    veracity analysis produce a false deletion candidate.

    Two rules now, split on how distinctive the name can possibly be:

    - Multi-word names ("Data Platform") must appear IN FULL, in order, with
      any separators between the words: distinctive enough that finding the
      whole phrase in a repo name is real evidence.
    - Single-word names ("Core", "Nimbus") must EQUAL the basename once
      separators are collapsed. A one-word name embedded in a longer repo name
      carries no information — that is the `core-utils` case.

    Both directions were considered: rejecting a legitimate repo (say
    `nimbus-backend`) only prompts the human, who has the other three
    signals and `--skip-repo-check`. Accepting an unrelated one risks a
    ticket. The commit-subject signal remains the strong one.

    This makes the rule's strictness depend on how the team happened to be
    named, not on the strength of the evidence: a legitimate sibling repo like
    `nimbus-sap-plugin` fails this signal for the one-word team
    "Nimbus" (embedding isn't equality), while a multi-word team like
    "Acme Data Platform" still matches `acme-data-platform`. This asymmetry is
    accepted deliberately, not an oversight — loosening the single-word case
    to allow embedding reopens the `core-utils` hole above, and tightening the
    multi-word case to require equality would lose real matches like
    `acme-data-platform`. Do not "fix" it into consistency.
    """
    if not team_name:
        return False
    tokens = re.findall(r"[A-Za-z0-9]+", team_name)
    if not tokens:
        return False
    if len(tokens) == 1:
        collapsed = re.sub(r"[^A-Za-z0-9]+", "", basename)
        return collapsed.lower() == tokens[0].lower()
    pattern = r"(?<![A-Za-z0-9])%s(?![A-Za-z0-9])" % r"[^A-Za-z0-9]*".join(
        re.escape(t) for t in tokens
    )
    return bool(re.search(pattern, basename, re.I))


def evaluate(team_key, team_name, repo):
    basename = os.path.basename(os.path.abspath(repo)).lower()
    remote = _git(repo, ["remote", "get-url", "origin"]).strip().lower()
    remote_path = _repo_path_of(remote) if remote else ""
    subjects = _git(repo, ["log", "-200", "--format=%s"])
    key_in_basename = _token_regex(team_key).search(basename) if team_key else None
    key_in_remote_path = (
        _token_regex(team_key).search(remote_path) if team_key and remote_path else None
    )
    token = re.compile(r"\b%s-\d+\b" % re.escape(team_key), re.I)
    token_hit = token.search(subjects)

    signals = [
        {
            "name": "team_key_in_repo_basename",
            "hit": bool(key_in_basename),
            "detail": basename,
        },
        {
            "name": "team_name_in_repo_basename",
            "hit": _name_hit(team_name, basename),
            "detail": "%s vs %s" % (team_name, basename),
        },
        {
            "name": "team_key_in_origin_url",
            "hit": bool(key_in_remote_path),
            "detail": remote_path or remote or "(no origin)",
        },
        {
            "name": "ticket_token_in_commit_subjects",
            "hit": bool(token_hit),
            "detail": token_hit.group(0) if token_hit else "(none in last 200)",
        },
    ]
    return {
        "matched": any(s["hit"] for s in signals),
        "team_key": team_key,
        "team_name": team_name,
        "repo": os.path.abspath(repo),
        "signals": signals,
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ticket", required=True)
    parser.add_argument("--repo", default=".")
    args = parser.parse_args(argv)

    with open(args.ticket, "r") as handle:
        issue = json.load(handle)["result"]["issue"]
    team = issue.get("team") or {}
    report = evaluate(team.get("key") or "", team.get("name") or "", args.repo)

    json.dump(report, sys.stdout, indent=2, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0 if report["matched"] else 3


if __name__ == "__main__":
    sys.exit(main())
