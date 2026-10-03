# Distribution Marketplace (`d-agent-plugins`)

Distribution marketplace (catalog `name: "d-agent-plugins"`). Plugins
from source repos (e.g. `kafilios/agent-plugin-github-task-manager`)
are pushed here by their own `./scripts/publish` scripts — this repo
does not run a publish script.

# CLAUDE.md

## Skills

- Skills live in `plugins/github-task-manager/skills/<skill-name>/SKILL.md`
- This repo distributes the `github-task-manager` plugin (marketplace `d-agent-plugins`); the source repo is `kafilios/agent-plugin-github-task-manager`

## Skill Development

- Test skill prompts in `/tmp/<skill-name>-workspace/iteration-N/`
- Use `git remote -v` to re-derive repo context per invocation

## Plugin Distribution

- Plugin lives at `plugins/<name>/.claude-plugin/plugin.json` + `plugins/<name>/skills/`
- Marketplace catalog at `.claude-plugin/marketplace.json` (`name: "d-agent-plugins"`, lists each plugin with `source: "./plugins/<name>"`)
- Catalog is hand-curated. Adding a new plugin means a hand-edited PR adding an entry to `plugins[]`; the publish script does not edit this file.
- For published distribution, swap the `directory` source for `git` (URL or `github` repo)
- Plugins are not auto-enabled by being declared in a marketplace; `enabledPlugins: true` is required

## How plugins land here

- Source repos push via their own `./scripts/publish`. That script only copies `plugins/<slug>/.claude-plugin/plugin.json` and `plugins/<slug>/skills/*` — it never touches `marketplace.json`.
- Catalog entries (the `plugins` array in `.claude-plugin/marketplace.json`) are added by hand when adopting a new plugin from a new source repo.

## GitHub Integration

- Use `git remote -v` to derive `owner/repo` for GitHub API calls
- Use `gh` CLI (available and authenticated in this environment)
- Authentication via `GITHUB_TOKEN` environment variable

## Git Commit Gotchas

- Sandbox blocks git operations by default — use `dangerouslyDisableSandbox: true`
- GitHub rejects pushes with private email addresses — use `users.noreply.github.com` format
- `user.name`/`user.email` config overrides `GIT_AUTHOR_*` env vars

## github-task-manager Skill

- Label `needs-input` marks issues blocked on user input
- Cleanup pass removes `needs-input` labels from closed issues
- Never closes issues — user is solely responsible for closing