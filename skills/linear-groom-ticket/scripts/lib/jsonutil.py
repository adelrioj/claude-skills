#!/usr/bin/env python3
"""JSON helpers shared by the linear-groom scripts. Python 3.9 compatible."""

import json
import re
import sys

_FENCE = re.compile(r"\A\s*```(?:json)?\s*\n(.*?)\n\s*```\s*\Z", re.S)


def strip_fence(text):
    """Return text with a single surrounding markdown code fence removed."""
    match = _FENCE.match(text)
    return match.group(1) if match else text


def load_lenient(text):
    """Parse JSON, tolerating one surrounding markdown fence."""
    return json.loads(strip_fence(text))


def _cmd_check_ok(payload):
    try:
        doc = json.loads(payload)
    except ValueError as exc:
        sys.stderr.write("jsonutil: unparseable JSON payload: %s\n" % exc)
        return 1
    return 0 if doc.get("ok") is True else 1


def _cmd_result(payload):
    doc = json.loads(payload)
    json.dump(doc["result"], sys.stdout)
    return 0


def main(argv):
    commands = {"check-ok": _cmd_check_ok, "result": _cmd_result}
    if len(argv) != 2 or argv[1] not in commands:
        sys.stderr.write("usage: jsonutil.py {check-ok|result} < payload\n")
        return 2
    return commands[argv[1]](sys.stdin.read())


if __name__ == "__main__":
    sys.exit(main(sys.argv))
