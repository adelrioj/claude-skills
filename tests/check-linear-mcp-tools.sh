#!/usr/bin/env bash
# Self-check for the Linear MCP tool names the skills tell the agent to call.
#
# An audit pass found four skills instructing the agent to call `create_issue`, `update_issue`,
# `create_comment` and `create_project` long after the server collapsed that family
# into `save_*`. A skill naming a tool the server does not expose is a skill whose
# writes silently do not happen — so pin the contract the way tests/check-codex-knob.sh
# pins the codex one.
#
# Two asserts, because the two failure modes are different:
#   1. Every Linear-MCP-shaped tool name in the skill prose is one the server exposes.
#      Catches a rename on Linear's side, and a half-finished rename on ours.
#   2. The four retired names appear nowhere as bare names. Deliberately bare-only:
#      the mcp__*_linear__-prefixed form has no word boundary before the verb, and
#      check (1) already fails on it after stripping the prefix. Redundant with (1) for a bare mention,
#      but it also catches them inside prose ("never call create_issue") where the
#      damage is a prohibition that no longer prohibits anything.
#
# KNOWN is the surface of the connected `linear` server (tools `mcp__linear__*`).
# When Linear ships a tool a skill starts using, add it here — that edit is the
# point at which someone consciously accepts the new name.
#
# Scope: *.md under skills/ and docs/skills/ — the prose an agent follows.
# docs/superpowers/ is deliberately excluded: specs and plans are a historical
# record, and the old names in them are what was true when they were written.
#
# Run: bash tests/check-linear-mcp-tools.sh

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
fails=0
ok()   { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }

# Not tool names, but they match the verb-prefix shape below — analyst-prompt JSON
# fields. Exempt them by name rather than loosening the pattern, which would also
# stop the pattern catching a real bad name.
ALLOW_NONTOOL="
delete_reason
"

KNOWN="
create_attachment create_attachment_from_upload create_issue_label
delete_attachment delete_comment delete_diff_comment delete_status_update
extract_images
get_agent_skill get_attachment get_diff get_diff_threads get_document get_issue
get_issue_status get_milestone get_project get_release get_release_note
get_status_updates get_team get_user get_workspace
list_agent_skills list_comments list_cycles list_diffs list_documents
list_issue_labels list_issue_statuses list_issues list_milestones
list_project_labels list_projects list_release_notes list_release_pipelines
list_releases list_teams list_users
merge_diff prepare_attachment_upload resolve_diff_thread
save_comment save_diff_comment save_document save_issue save_milestone
save_project save_release save_release_note save_status_update
search_documentation submit_diff_review
"

# An array, so the file list is never re-split by the shell.
files=()
while IFS= read -r f; do files+=("$f"); done < <(find skills docs/skills -name '*.md' | sort)
[ "${#files[@]}" -gt 0 ] || { echo "  FAIL no .md files found — wrong working directory?"; exit 1; }

echo "1. every Linear-MCP-shaped name in the prose is a tool the server exposes"
# The shape: a backticked token starting with an MCP verb, e.g. `save_issue(id: ...)`
# or a bare `list_teams` in a transport list. Anchored at the token start, so
# after_create / attachment_create / issueRelationCreate do not match.
found=$(grep -ohE '`(mcp__[a-z_-]*linear[a-z_-]*__)?(get|list|save|create|update|delete|prepare|search|submit|merge|resolve|extract)_[a-z_]+' "${files[@]}" \
        | sed 's/^`//; s/^mcp__.*linear[a-z_-]*__//' | sort -u)
unknown=""
for name in $found; do
  case " ${KNOWN//$'\n'/ } ${ALLOW_NONTOOL//$'\n'/ } " in
    *" $name "*) ;;
    *) unknown="$unknown $name" ;;
  esac
done
if [ -n "$unknown" ]; then
  fail "names no connected Linear MCP tool matches:$unknown"
  for name in $unknown; do grep -nH -- "$name" "${files[@]}" | sed 's/^/         /'; done
else
  ok "$(echo "$found" | wc -w | tr -d ' ') distinct names, all in the known surface"
fi

echo "2. the retired create_*/update_* names are gone"
for retired in create_issue update_issue create_comment create_project; do
  # create_issue_label is a real tool and a prefix match for create_issue.
  hits=$(grep -nHE "\b${retired}\b" "${files[@]}" | grep -v "${retired}_")
  if [ -z "$hits" ]; then
    ok "no \`$retired\`"
  else
    fail "\`$retired\` still referenced"
    echo "$hits" | sed 's/^/         /'
  fi
done

echo
[ "$fails" -eq 0 ] && { echo "All Linear MCP tool-name checks passed."; exit 0; }
echo "$fails check(s) failed."
exit 1
