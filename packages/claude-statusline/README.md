# claude-statusline

Adaptive, width-aware statusline for [Claude Code](https://code.claude.com) — project path, git branch/status, model, effort, and context usage with gradient colors.

## Features

Re-evaluated on every render, adapting to the current terminal width (`$COLUMNS`, Claude Code v2.1.153+). On resize the TUI redraws and the tier recomputes live.

Degradation ladder, richest first — the first form that fits the terminal width wins:

```
1  Project: Projects/my-app › Branch: main Status: !1 › Model: Opus 4.8 (1M context) Effort: xHigh › Context: 150k/1M (15%)
2  P: Projects/my-app › B: main S: !1 › M: Opus 4.8 (1M context) E: xHigh › C: 150k/1M (15%)
3  P: my-app › B: main S: !1 › M: Opus 4.8 E: xHigh › C: 150k/1M (15%)
4  my-app | main !1 | Opus 4.8 - xHigh | 150k/1M (15%)
5  my-app | main | Opus 4.8 - xHigh | 150k/1M (15%)
6  my-app | Opus 4.8 | 150k/1M (15%)          (floor)
```

- Directory: path under `~/Projects` (prefix stripped) or `~`-relative, plus basename.
- Git: current branch (or `detached@<sha>`), ahead/behind counts, powerlevel10k-style staged/modified/untracked counts.
- Model: display name, with a short form (any `(… context)` tag stripped) at lower tiers.
- Effort: reasoning effort level (`Low`/`Medium`/`High`/`xHigh`/`Max`).
- Context: used/max tokens and used % (e.g. `150k/1M (15%)`), colored on a green→yellow→red gradient.

## Install

```
/plugin marketplace add https://github.com/pixu1980/claude-code-cli-plugins
/plugin install claude-statusline@claude-code-cli-plugins
/claude-statusline:install-statusline
```

The last command wires the bundled script into `~/.claude/settings.json`'s `statusLine` field — it asks for confirmation and never touches your other settings.

## Requirements

`jq` and `git` on `$PATH`. Reads the Claude Code statusline JSON payload on stdin ([schema](https://code.claude.com/docs/en/statusline.md)).

## Uninstall

Remove the `statusLine` key from `~/.claude/settings.json`.

## License

MIT
