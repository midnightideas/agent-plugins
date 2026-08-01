# Implementation Notes

Hard decisions made by the `complete-tasks` skill. Read by Step 0a of subsequent runs (last 14 days). Older entries are kept in the file but omitted from the read filter.

## 2026-07-27 — issue #33 (IMPLEMENTATION_NOTES.md)
- Read filter uses awk + mktime so the read step has no extra dependencies (no `date -d`, no `jq` for parsing). `mktime` requires `YYYY MM DD HH MM SS` format, so the `YYYY-MM-DD` header is converted with `gsub("-", " ", ...)` before passing.
- Compression for 7-14 day old entries is at read-time only; the file on disk keeps full text. This avoids destructive edits that would lose context if the user later wants to grep the historical file.
- Step 7 sits AFTER Step 6 (review feedback) so the entry reflects the post-review state of the change — if the reviewer forced a re-design, the note describes what was actually merged, not the original draft.
- Concurrent PRs colliding on the file are resolved by the second PR's rebase onto main. Entries are append-only with date-stamped headers, so conflict markers are unambiguous and mechanical to resolve.
- Did not add a separate "summary" entry format to the write-side; the LLM is told to keep entries short (1-3 bullets), and the read-side's awk enforces the 7-day cutoff. Adding a write-side summary mode would double the schema for marginal benefit.
- Did not write a per-task script; the bash logic is inline in the SKILL.md because the skill is the source of truth and a separate script would risk drifting from the documented behaviour.
