#!/usr/bin/env python3
"""Extract deterministic search keywords from a ticket title.

Deterministic on purpose: the duplicate search must be reproducible, so the
keyword set is derived by rule (lowercase, split on non-alphanumerics, drop
stopwords, longest first) rather than chosen by a model.
Python 3.9 compatible.
"""

import argparse
import json
import os
import re
import sys

DEFAULT_STOPWORDS = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), os.pardir, os.pardir, "reference", "stopwords.txt"
)


def load_stopwords(path):
    words = set()
    with open(path, "r") as handle:
        for line in handle:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            for word in line.split():
                words.add(word.lower())
    return words


def extract(title, stopwords, limit):
    tokens = [t for t in re.split(r"[^0-9A-Za-zÁÉÍÓÚÑáéíóúñ_]+", title or "") if t]
    seen = set()
    kept = []
    for token in tokens:
        lowered = token.lower()
        if len(lowered) < 3 or lowered in stopwords or lowered in seen:
            continue
        seen.add(lowered)
        kept.append(token)
    # Longest first, then original order — stable for identical lengths.
    kept.sort(key=lambda t: (-len(t), tokens.index(t)))
    return kept[:limit]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ticket", required=True)
    parser.add_argument("--stopwords", default=DEFAULT_STOPWORDS)
    parser.add_argument("--max", type=int, default=6)
    args = parser.parse_args(argv)

    with open(args.ticket, "r") as handle:
        issue = json.load(handle)["result"]["issue"]
    for keyword in extract(issue.get("title"), load_stopwords(args.stopwords), args.max):
        sys.stdout.write(keyword + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
