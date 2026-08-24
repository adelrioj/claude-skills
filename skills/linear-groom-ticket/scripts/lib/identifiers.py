#!/usr/bin/env python3
"""Extract high-signal, checkable identifiers from a ticket description.

Why this exists: the duplicates analyst used to judge overlap from titles
alone, and "both titles concern the deploy failing" is not evidence — it got
the strongest duplicate this tool has ever seen stuck at confidence: medium.
A token that appears verbatim in two bodies (the same Actions run, the same
commit, the same URL, the same referenced ticket) is objective and re-checkable
in a way prose similarity never is. This module produces those tokens.

Extraction is deliberately conservative: a false identifier is worse than a
missing one, because a shared identifier is the thing the prompt now allows to
justify `confidence: high`.

Classes extracted:
  url          http(s) URLs, trailing punctuation trimmed
  actions run  `actions/runs/<digits>`, normalised so a bare "run 123..."
               mention and a pasted workflow URL yield the SAME token
  commit sha   hex runs of 7-40 chars carrying at least one digit AND at least
               one hex letter (a pure-word run like "effaced" and a pure-digit
               run like a timestamp are both rejected)
  linear ref   [A-Z]{2,5}-<digits>
  repo path    slash-separated path-looking token with a short extension

Order is first appearance in the text; the list is de-duplicated and bounded.
"""
import re
import sys

MAX_IDENTIFIERS = 30

_URL = re.compile(r'https?://[^\s<>()\[\]"\'`]+')
_ACTIONS_RUN_PATH = re.compile(r'actions/runs/(\d+)')
# A bare run id: 9+ digits within ~24 chars after a run/job/workflow cue. Keeps
# the "run 32082281184" phrasing matchable against a pasted run URL without
# treating every long number in a body as an identifier.
_ACTIONS_RUN_BARE = re.compile(
    r'\b(?:runs?|run[ _-]?id|job|workflow)\b[^0-9\n]{0,24}?(\d{9,})',
    re.IGNORECASE,
)
_SHA = re.compile(r'(?<![0-9A-Za-z])([0-9a-fA-F]{7,40})(?![0-9A-Za-z])')
_LINEAR = re.compile(r'(?<![0-9A-Za-z])([A-Z]{2,5}-\d+)(?![0-9A-Za-z])')
_PATH = re.compile(r'(?<![\w./-])((?:[\w.-]+/){1,12}[\w-]+\.[A-Za-z0-9]{1,8})(?![\w/])')
_WS = re.compile(r'\s+')


def _sha_plausible(token: str) -> bool:
    lowered = token.lower()
    return any(c.isdigit() for c in lowered) and any(c in "abcdef" for c in lowered)


def extract(text):
    """Return (identifiers, truncated) for `text`."""
    text = text or ""
    found = []

    def push(token):
        if token and token not in found:
            found.append(token)

    # Actions runs first: they are the highest-signal class, so they should
    # survive the cap even in a body dense with URLs.
    for match in _ACTIONS_RUN_PATH.finditer(text):
        push("actions/runs/%s" % match.group(1))
    for match in _ACTIONS_RUN_BARE.finditer(text):
        push("actions/runs/%s" % match.group(1))

    urls = []
    for match in _URL.finditer(text):
        urls.append(match.group(0))
        push(match.group(0).rstrip('.,;:!?)]}\'"'))

    # Paths and SHAs are scanned with URLs removed: a URL's own path segments
    # are already covered by the URL token, and re-emitting them as "repo
    # paths" would manufacture spurious shared identifiers between two tickets
    # that merely link the same host.
    stripped = text
    for url in urls:
        stripped = stripped.replace(url, " ")

    for match in _LINEAR.finditer(stripped):
        push(match.group(1))
    for match in _SHA.finditer(stripped):
        token = match.group(1)
        if _sha_plausible(token):
            push(token.lower())
    for match in _PATH.finditer(stripped):
        push(match.group(1))

    truncated = len(found) > MAX_IDENTIFIERS
    return found[:MAX_IDENTIFIERS], truncated


def excerpt(text, limit):
    """First `limit` characters of `text` with whitespace collapsed."""
    collapsed = _WS.sub(" ", (text or "")).strip()
    return collapsed[:limit]


if __name__ == "__main__":
    # Test/debug entry point: reads text on stdin, prints one identifier per
    # line. Not used by the pipeline.
    idents, was_truncated = extract(sys.stdin.read())
    for ident in idents:
        print(ident)
    if was_truncated:
        sys.stderr.write("identifiers: truncated at %d\n" % MAX_IDENTIFIERS)
