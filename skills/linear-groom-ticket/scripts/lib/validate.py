#!/usr/bin/env python3
"""Validate a JSON file against a JSON Schema.

Exit codes are distinct on purpose: 2 (unparseable) means the model produced
garbage, 1 (schema-invalid) means it produced the wrong shape. 30-wave1.sh
retries both but reports them differently.
Python 3.9 compatible.
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import jsonutil  # noqa: E402


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--schema", required=True)
    parser.add_argument("--file", required=True)
    args = parser.parse_args(argv)

    try:
        import jsonschema
    except ImportError:
        sys.stderr.write("validate: python3 module 'jsonschema' is required\n")
        return 3

    with open(args.schema, "r") as handle:
        schema = json.load(handle)
    with open(args.file, "r") as handle:
        raw = handle.read()

    try:
        instance = jsonutil.load_lenient(raw)
    except ValueError as exc:
        sys.stderr.write("validate: %s is not JSON: %s\n" % (args.file, exc))
        return 2

    validator = jsonschema.Draft7Validator(schema)
    errors = sorted(validator.iter_errors(instance), key=lambda e: list(e.path))
    if errors:
        first = errors[0]
        location = "/".join(str(p) for p in first.path) or "(root)"
        sys.stderr.write("validate: %s at %s: %s\n" % (args.file, location, first.message))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
