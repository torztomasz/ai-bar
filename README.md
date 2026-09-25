# AI Bar

macOS menu bar app showing how much of your AI provider rate limits you have used.
The first provider is Claude (via the Claude Code OAuth session); more providers plug in behind `UsageProvider`.

- Menu bar badge: 5-hour window usage in percent. Green when the current burn rate leaves headroom until the window resets, red when it will be drained before then.
- Left click: popover listing every limit window per provider (5-hour, weekly, weekly per-model).
- Right click: refresh now.

## Development

```
make build   # swift build
make test    # swift test
make app     # bundle dist/AI Bar.app
make run     # build and launch the app bundle
```

Tickets live in `tickets/`. Implementation order and dependencies are in each ticket header.
