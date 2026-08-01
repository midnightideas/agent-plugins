# github-task-manager

A Claude Code plugin for managing tasks via GitHub issues in the current repository.

## What It Does

- Fetches and processes open GitHub issues from the repository where Claude is running
- Proposes solutions, provides updates, and suggests next steps for each issue
- Never closes issues — you remain solely responsible for closing
- Uses `needs-input` labels to mark issues blocked on your response
- Cleans up orphaned `needs-input` labels from closed issues

## Plugin Structure

```
github-task-manager/
├── .claude-plugin/
│   └── marketplace.json           # Marketplace catalog for local dev
├── plugins/
│   └── github-task-manager/
│       ├── .claude-plugin/
│       │   └── plugin.json        # Plugin manifest
│       └── skills/
│           └── complete-tasks/
│               └── SKILL.md       # The skill definition
└── README.md
```

## Installation (Local Development)

This repo is set up so that `.claude/settings.json` declares a project-local
marketplace pointing at the repo itself. Once `/reload-plugins` has been run in
Claude Code, the plugin is enabled automatically for this project — no
commit/push needed for inner dev loop.

```
/reload-plugins
```

Then use the skill directly:

```
/complete-tasks
```

Trigger phrases:
- "Please complete all the outstanding tasks in the GitHub issues for this repository."
- "What's the current status of all open issues?"
- "Work on your assigned issues"

## Installation (Published)

To publish the plugin for others to install via a marketplace, replace the
`directory` source in `.claude/settings.json` with a git URL:

```json
{
  "extraKnownMarketplaces": {
    "github-task-manager": {
      "source": {
        "source": "git",
        "url": "https://github.com/kafilios/agent-plugin-github-task-manager.git"
      }
    }
  }
}
```

Users can then install with:

```
/plugin install github-task-manager@github-task-manager
```

## Requirements

- `gh` CLI installed and authenticated
- GitHub authentication via `gh auth login`

## Workflow

1. Claude fetches all open issues assigned to the current user from the repo
2. Cleans up any `needs-input` labels on closed issues
3. Processes each issue in order (oldest first)
4. Adds progress comments and proposes solutions via PRs
5. Reports a summary when done
