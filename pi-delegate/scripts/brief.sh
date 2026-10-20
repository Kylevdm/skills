#!/usr/bin/env bash
# brief.sh: assemble one batch ticket's brief from a batch notes directory.
#
#   brief.sh <notes-dir> <ticket> [continuation-file] > <notes-dir>/brief-<ticket>.md
#
# Reads from <notes-dir>:
#   preamble.md      shared brief with {SPEC} and {TICKET} placeholders (required)
#   spec.md          the parent spec issue, substituted for {SPEC} (required)
#   ticket-<N>.md    the ticket issue text, substituted for {TICKET} (required)
#   notes-<N>.md     the orchestrator's evidence and pointers for this ticket (optional)
# A continuation file (a reviewer's ruling, or what the previous attempt missed)
# is appended last, verbatim; give it its own "## CONTINUATION" heading.
set -euo pipefail

[ $# -ge 2 ] && [ $# -le 3 ] || {
  echo "usage: brief.sh <notes-dir> <ticket> [continuation-file]" >&2; exit 2; }

python3 -I - "$1" "$2" "${3:-}" <<'PY'
import pathlib, sys

notes, ticket, cont = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]

def need(name):
    path = notes / name
    if not path.is_file():
        sys.exit(f"brief.sh: missing {path}")
    return path.read_text().strip()

preamble = need("preamble.md")
for placeholder in ("{SPEC}", "{TICKET}"):
    if placeholder not in preamble:
        sys.exit(f"brief.sh: preamble.md has no {placeholder} placeholder")

body = need(f"ticket-{ticket}.md")
extra = notes / f"notes-{ticket}.md"
if extra.is_file():
    body += "\n\n## Orchestrator notes (evidence and pointers)\n" + extra.read_text().strip()
if cont:
    body += "\n\n" + pathlib.Path(cont).read_text().strip()

print(preamble.replace("{SPEC}", need("spec.md")).replace("{TICKET}", body))
PY
