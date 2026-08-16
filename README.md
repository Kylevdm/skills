# skills

Agent skills, one directory each. Everything a skill owns lives inside its own
directory — glossary, decision records, templates — so a skill can be copied out
whole.

## fog

Capture, route and maintain unresolved future work across sessions and Wayfinder
maps in a repository fog ledger. See [fog/SKILL.md](fog/SKILL.md); the reasoning
behind a standalone ledger is in
[fog/docs/adr/0001-standalone-cross-map-fog-ledger.md](fog/docs/adr/0001-standalone-cross-map-fog-ledger.md).

## Installing

Symlink a skill into your Claude Code skills directory, so edits here are live
without a copy step:

```sh
git clone git@github.com:Kylevdm/skills.git ~/skills
ln -s ~/skills/fog ~/.claude/skills/fog
```
