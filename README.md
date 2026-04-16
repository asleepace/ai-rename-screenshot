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

## Haiku 4.5 pricing

$1/MTok input, $5/MTok output

## Token breakdown per screenshot

**Image input tokens:** Anthropic's formula is `tokens ≈ (width × height) / 750`. The script resizes to max 1024px on the longest side. For a typical 16:10 macOS screenshot, that's ~1024×640 → **~875 tokens**. Square-ish screenshots hit the worst case at 1024×1024 → **~1,400 tokens**.

**Text input tokens:**
- System/user prompt: ~25 tokens
- Fixed API overhead (message wrapper, role tokens): ~10 tokens
- **Total text: ~35 tokens**

**Output tokens:** `max_tokens: 64`, but filenames are 2–6 words hyphenated → actual output ~**8–15 tokens**.

## Cost math

| Component | Tokens | Cost |
|---|---|---|
| Image (typical 1024×640) | ~875 | $0.000875 |
| Image (worst case 1024×1024) | ~1,400 | $0.0014 |
| Text input | ~35 | $0.000035 |
| Output (~12 tokens) | 12 | $0.00006 |

**Per screenshot: ~$0.001 (one-tenth of a cent)**

At 50 screenshots/day → **~$0.05/day, ~$1.50/month**. You'd need to take ~1,000 screenshots to spend a dollar.

## Full Tutorial

For a detailed walkthrough see the full blog post at https://asleepace.com/blog/how-to-automate-screenshot-naming-macos

## License

MIT
