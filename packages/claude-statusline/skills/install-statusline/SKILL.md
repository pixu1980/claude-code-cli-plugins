---
name: install-statusline
description: Install the claude-statusline plugin's script into the user's ~/.claude/settings.json statusLine field. Explicit, user-invoked only — never runs automatically.
disable-model-invocation: true
---

# Install claude-statusline

Wire this plugin's bundled statusline script into the user's global Claude Code settings. This is an explicit, user-invoked action — never trigger it on your own.

The bundled script's absolute path is:

```
${CLAUDE_PLUGIN_ROOT}/src/statusline.sh
```

## Steps

1. Read `~/.claude/settings.json`. If it doesn't exist, treat it as `{}`.
2. Build the desired block:
   ```json
   {
     "type": "command",
     "command": "bash \"${CLAUDE_PLUGIN_ROOT}/src/statusline.sh\"",
     "refreshInterval": 1
   }
   ```
   (with `${CLAUDE_PLUGIN_ROOT}` resolved to the literal absolute path).
3. If a top-level `statusLine` key already exists and differs from the block above, show the user the current value vs. the proposed value and ask for explicit confirmation before overwriting it. Do not overwrite silently.
4. Merge the `statusLine` key into the existing JSON — preserve every other top-level key untouched (`permissions`, `hooks`, `enabledPlugins`, etc.). Never replace the whole file.
5. Write the file back with 2-space indentation.
6. Tell the user it's installed and takes effect immediately (the statusline re-renders live per `refreshInterval`).

## Uninstall

To remove it later, delete the `statusLine` key from `~/.claude/settings.json` (or point it elsewhere).
