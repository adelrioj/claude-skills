#!/usr/bin/env python3
"""Deterministic template-completeness check for a Linear ticket.

Reads the required section list from the template file — never hardcoded,
because the template is user-editable and teams want different shapes.
No LLM involvement: the same input always produces the same output.
Python 3.9 compatible.
"""

import argparse
import json
import os
import re
import sys

HEADING_RE = re.compile(r"^##\s+(.+?)\s*$", re.M)
OPTIONAL_MARKER = "<!-- optional -->"
LINK_RE = re.compile(r"https?://\S+")
BULLET_RE = re.compile(r"^\s*[-*]\s+\S", re.M)

# The templates are owned by the `to-linear` skill, which files the tickets this
# one grooms. One source of truth on purpose: a ticket filed against one shape and
# linted against another reports every section missing and gets restructured on its
# first grooming. Located relative to this file rather than through
# ${CLAUDE_PLUGIN_ROOT}, like every other path here — see SKILL.md step 1.
DEFAULT_TEMPLATE_DIR = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), os.pardir, os.pardir, "to-linear", "templates"
)

# Which template a ticket is measured against comes from its type label. Only `bug`
# is matched by name; everything else — `Feature`, `Story`, an unlabelled ticket —
# is a story, which is also to-linear's own rule ("is it broken for someone today?
# if not, it is a story"). Epics are Linear projects, not issues, so they never
# reach this script.
TEMPLATE_BY_TYPE = {"bug": "bug.md"}
STORY_TEMPLATE = "story.md"


def template_for(issue, templates_dir):
    """Resolve the template path for a ticket from its type label."""
    for label in issue.get("labels") or []:
        name = (label.get("name") or "").strip().lower()
        if name in TEMPLATE_BY_TYPE:
            return os.path.join(templates_dir, TEMPLATE_BY_TYPE[name])
    return os.path.join(templates_dir, STORY_TEMPLATE)


def normalise(heading):
    """Heading -> stable key. Emoji and punctuation drift cannot break matching."""
    return re.sub(r"[^0-9a-z]", "", heading.lower())


def split_sections(markdown):
    """Return an ordered list of (heading, body) for every level-2 heading."""
    matches = list(HEADING_RE.finditer(markdown or ""))
    sections = []
    for index, match in enumerate(matches):
        start = match.end()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(markdown)
        sections.append((match.group(1), markdown[start:end]))
    return sections


def parse_template(path):
    """Return an ordered list of {heading, key, required} from the template."""
    with open(path, "r") as handle:
        text = handle.read()
    required = []
    for heading, body in split_sections(text):
        required.append(
            {
                "heading": heading,
                "key": normalise(heading),
                "required": OPTIONAL_MARKER not in body,
            }
        )
    return required


def body_of(sections, key):
    for heading, body in sections:
        if normalise(heading) == key:
            return body
    return None


def lint(ticket_doc, template_path=None, templates_dir=DEFAULT_TEMPLATE_DIR):
    issue = ticket_doc["result"]["issue"]
    template_path = template_path or template_for(issue, templates_dir)
    description = issue.get("description") or ""
    present = split_sections(description)

    sections = []
    missing_required = []
    for spec in parse_template(template_path):
        body = body_of(present, spec["key"])
        if body is None:
            status = "absent"
            chars = 0
        else:
            stripped = body.strip()
            status = "empty" if not stripped else "present"
            chars = len(stripped)
        if status != "present" and spec["required"]:
            missing_required.append(spec["heading"])
        sections.append(
            {
                "heading": spec["heading"],
                "key": spec["key"],
                "status": status,
                "chars": chars,
                "required": spec["required"],
            }
        )

    dod_body = ""
    for spec in parse_template(template_path):
        if spec["key"].startswith("definitionofdone"):
            dod_body = body_of(present, spec["key"]) or ""
            break

    return {
        "ticket": issue.get("identifier"),
        "template": os.path.basename(template_path),
        "template_path": os.path.abspath(template_path),
        "sections": sections,
        "missing_required": missing_required,
        "signals": {
            "title_chars": len(issue.get("title") or ""),
            "description_chars": len(description),
            "link_count": len(LINK_RE.findall(description)),
            "dod_bullets": len(BULLET_RE.findall(dod_body)),
        },
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ticket", required=True, help="path to the Linear issue JSON envelope")
    parser.add_argument(
        "--template", help="force one template file, bypassing type-label selection"
    )
    parser.add_argument("--templates-dir", default=DEFAULT_TEMPLATE_DIR)
    parser.add_argument("--out", required=True)
    args = parser.parse_args(argv)

    with open(args.ticket, "r") as handle:
        ticket_doc = json.load(handle)

    result = lint(ticket_doc, args.template, args.templates_dir)
    with open(args.out, "w") as handle:
        json.dump(result, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    sys.stderr.write(
        "lint: %d/%d required sections missing (template: %s)\n"
        % (
            len(result["missing_required"]),
            sum(1 for s in result["sections"] if s["required"]),
            result["template"],
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
