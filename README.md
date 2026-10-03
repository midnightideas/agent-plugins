[![Open in DevPod!](https://devpod.sh/assets/open-in-devpod.svg)](https://devpod.sh/open#https://github.com/kafilios/agent-plugins)

# agent-plugins

Distribution marketplace for Claude Code plugins (catalog name: `d-agent-plugins`).

This repo is **only** a distribution surface: each plugin's source lives
in its own repo, and pushes into this repo happen via that source repo's
`./scripts/publish`. Nothing in this repo builds or runs plugin logic;
the catalog at `.claude-plugin/marketplace.json` is the only thing
maintained by hand here.

## Available plugins

| Name | Description | Source |
| ---- | ----------- | ------ |
| `github-task-manager` | Manage and complete tasks tracked in GitHub issues. Provides the `/complete-tasks` skill. | [`kafilios/agent-plugin-github-task-manager`](https://github.com/kafilios/agent-plugin-github-task-manager) |

## Installation (end users)

Once this repo is registered as a marketplace in your `.claude/settings.json`,
install any plugin by name:

```json
{
  "extraKnownMarketplaces": {
    "d-agent-plugins": {
      "source": {
        "source": "git",
        "url": "https://github.com/kafilios/agent-plugins.git"
      }
    }
  },
  "enabledPlugins": {
    "github-task-manager@d-agent-plugins": true
  }
}
```

```
/plugin install github-task-manager@d-agent-plugins
```

## Plugin source repos

Each plugin in the catalog points at its own source repo via `homepage`.
That source repo owns:

- The plugin manifest (`<source>/plugins/<slug>/.claude-plugin/plugin.json`)
- The skill files (`<source>/plugins/<slug>/skills/<skill>/SKILL.md`)
- The `./scripts/publish` script that pushes new versions here

The publish script only copies the manifest and skills — it never edits
`.claude-plugin/marketplace.json` in this repo.

## Adding a new plugin

1. Stand up the source repo (e.g. `kafilios/agent-plugin-<your-plugin>`)
   with `plugins/<your-plugin>/.claude-plugin/plugin.json` and
   `plugins/<your-plugin>/skills/<your-skill>/SKILL.md`.
2. Add a `./scripts/publish` script in that repo, modelled on the one in
   `kafilios/agent-plugin-github-task-manager/scripts/publish`.
3. Run the script once to seed `plugins/<your-plugin>/` here.
4. Open a hand-edited PR against this repo adding a new entry to the
   `plugins` array in `.claude-plugin/marketplace.json`.

Step 4 is the only one that touches this repo's source-of-truth file.
The catalog is hand-curated on purpose — every entry is reviewed before
it ships to end users.

## Layout

```
agent-plugins/
├── .claude-plugin/
│   └── marketplace.json           # hand-curated catalog (`name: "d-agent-plugins"`)
├── plugins/
│   └── <plugin-slug>/             # one folder per plugin
│       ├── .claude-plugin/
│       │   └── plugin.json
│       └── skills/
│           └── <skill-name>/SKILL.md
├── README.md                      # this file
└── CLAUDE.md                      # agent guidance for working in this repo
```

No `IMPLEMENTATION_NOTES.md`, no `docs/`, no scripts. If something here
needs to change beyond the catalog, it almost certainly belongs in the
plugin's source repo instead.