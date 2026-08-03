# claude-code-cli-plugins

Monorepo of plugins for [Claude Code](https://code.claude.com), doubling as their own plugin marketplace.

## Structure

```
.claude-plugin/
└── marketplace.json      # marketplace manifest — lists every plugin below
packages/
└── claude-statusline/     # adaptive statusline (git, model, effort, context usage)
    └── ...                # more plugins go here, one directory each
```

Each package in `packages/` is an independent Claude Code plugin: its own `.claude-plugin/plugin.json`, its own version, its own `CHANGELOG.md`.

## Install a plugin

```
/plugin marketplace add https://github.com/pixu1980/claude-code-cli-plugins
/plugin install claude-statusline@claude-code-cli-plugins
```

Some plugins (like `claude-statusline`) ship a setup skill to run once after install — see that plugin's README for details.

## Development

Each package is self-contained; no cross-package linking is needed. To work on one:

```bash
cd packages/<name>
```

## Release

Every package is independently versioned and tagged (`<name>@<version>`), following [Conventional Commits](https://www.conventionalcommits.org/). Claude Code plugins install from git, not npm, so releasing means: bump + changelog + sync the plugin manifest and marketplace listing + tag + push — no registry publish.

```bash
pnpm install

# Release every package with changes since its last tag
pnpm release

# Preview what would happen, no changes made
pnpm release:dry

# Release even without detected changes
node scripts/release.mjs --force
```

## License

MIT
