#!/usr/bin/env python3
"""Is <model> @ <effort> entitled according to a codex models cache?

Usage: entitled.py <cache.json> <model> <effort>
Exit 0 = entitled, 1 = not entitled (or the cache cannot be read as expected).

Deliberately says nothing about an absent cache: the caller decides that a
missing cache means "skip the gate", because the file is a cache and not the
authority on what an account can run. This script is only asked the question
when the cache exists and is non-empty, so anything it cannot parse is a real
answer of "cannot confirm" — and the caller treats that as not entitled rather
than waving it through, since the alternative is spending three codex calls to
learn the same thing less clearly.

Python 3.9 compatible: no match statement, no PEP 604 unions.
"""
import json
import sys


def main(argv):
    if len(argv) != 4:
        sys.stderr.write("usage: entitled.py <cache.json> <model> <effort>\n")
        return 1
    cache_path, model, effort = argv[1], argv[2], argv[3]

    try:
        with open(cache_path) as fh:
            cache = json.load(fh)
    except (OSError, ValueError) as exc:
        sys.stderr.write("entitled: cannot read %s: %s\n" % (cache_path, exc))
        return 1

    models = cache.get("models")
    if not isinstance(models, list):
        sys.stderr.write("entitled: %s has no models list\n" % cache_path)
        return 1

    for entry in models:
        if not isinstance(entry, dict) or entry.get("slug") != model:
            continue
        levels = entry.get("supported_reasoning_levels")
        if not isinstance(levels, list):
            sys.stderr.write(
                "entitled: %s lists no reasoning levels for %s\n" % (cache_path, model)
            )
            return 1
        efforts = [
            lvl.get("effort") for lvl in levels if isinstance(lvl, dict)
        ]
        if effort in efforts:
            return 0
        sys.stderr.write(
            "entitled: %s supports efforts %s, not %r\n"
            % (model, sorted(e for e in efforts if e), effort)
        )
        return 1

    slugs = sorted(
        e.get("slug") for e in models if isinstance(e, dict) and e.get("slug")
    )
    sys.stderr.write(
        "entitled: %r is not in %s — entitled models: %s\n"
        % (model, cache_path, ", ".join(slugs) or "(none)")
    )
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
