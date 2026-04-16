# ai-rename-screenshot

Automatically rename macOS screenshots using Claude AI. Watches `~/Desktop` for new screenshots and uses Claude's vision API to generate a descriptive filename.

```bash
Screenshot 2026-04-16 at 7.05.51 AM.png  →  swift-script-screenshot-watcher.png
```

## Files

- `ai-rename-screenshot.swift` — Swift program that watches for screenshots and renames them
- `example.plist` — launchd plist for running the program automatically on login
- `LICENSE` — MIT License

## Requirements

- macOS
- Xcode Command Line Tools (`xcode-select --install`)
- Anthropic API key ([get one here](https://console.anthropic.com))

## Setup

**1. Store your API key in Keychain:**
```bash
security add-generic-password -a "$USER" -s "CLAUDE_API_KEY" -w "sk-ant-..."
```

**2. Compile the binary:**
```bash
xcrun swiftc ai-rename-screenshot.swift -o ai-rename-screenshot
```

**3. Test it:**
```bash
./ai-rename-screenshot
```
Take a screenshot with `Cmd + Shift + 4` and watch it get renamed.

**4. Add to launchd (run on startup):**
```bash
cp example.plist ~/Library/LaunchAgents/com.asleepace.ai-rename-screenshot.plist

# edit the plist to point to your binary path, then:
launchctl load ~/Library/LaunchAgents/com.asleepace.ai-rename-screenshot.plist
```

## Configuration

Edit the top of `ai-rename-screenshot.swift` to customize behavior:

```swift
let anthropicModel: String = "claude-haiku-4-5"
let folderName: String = "Desktop"
let delayInSeconds: UInt64 = 1
let systemPrompt: String = "..."

func isScreenshot(_ filename: String) -> Bool {
    filename.hasPrefix("Screenshot") && filename.hasSuffix(".png")
}
```

## Useful Commands

```bash
# stop the launchd process
launchctl unload ~/Library/LaunchAgents/com.asleepace.ai-rename-screenshot.plist

# start the launchd process
launchctl load ~/Library/LaunchAgents/com.asleepace.ai-rename-screenshot.plist

# view logs
tail -f /tmp/ai-rename-screenshot.log

# check process is running
launchctl list | grep asleepace
```

## Full Tutorial

For a detailed walkthrough see the full blog post at https://asleepace.com/blog/how-to-automate-screenshot-naming-macos

## License

MIT