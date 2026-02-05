# ClawUsage - Claude Rate Limit Monitor for Mac

**macOS menu bar app to track your Claude AI usage limits in real-time.**

Monitor your Anthropic Claude API rate limits, session usage, weekly quotas, and reset times - all from your Mac menu bar.

![ClawUsage Menu Bar](assets/menubar.png)

## What It Does

ClawUsage sits in your macOS menu bar and shows your **Claude Pro** and **Claude Max** subscription usage at a glance:

- **5-Hour Session Limit** - Track your rolling 5-hour usage window
- **7-Day Weekly Limit** - Monitor your weekly Claude quota
- **Visual Progress Bars** - Two stacked bars show both limits simultaneously
- **Color-Coded Status** - Green (low), Yellow (moderate), Red (high usage)
- **Reset Countdown** - See exactly when your limits reset

Perfect for Claude Code users, Claude API developers, and anyone who wants to avoid hitting rate limits.

## Features

### Menu Bar Integration
- Minimal footprint - just two small progress bars in your menu bar
- Adapts to macOS dark mode and light mode
- Click to expand detailed usage breakdown

### Real-Time Monitoring
- Automatic refresh every 3 minutes
- Manual refresh button for instant updates
- Shows exact percentage and reset times

### Secure Authentication
- OAuth PKCE flow with Claude/Anthropic
- Tokens stored securely in macOS Keychain
- No passwords stored, no data collected

### Auto-Updates
- Checks GitHub releases for new versions
- One-click download when updates available
- Version displayed in app

## Screenshots

| Menu Bar | Expanded View | Sign In |
|----------|---------------|---------|
| ![Menu Bar](assets/menubar.png) | ![Expanded](assets/expanded.png) | ![Login](assets/login.png) |

## Installation

### Download (Recommended)
1. Go to [**Releases**](https://github.com/peter-jammable/mac-menu-bar-claude-usage/releases/latest)
2. Download `ClawUsage-vX.X.X.dmg`
3. Open DMG, drag **ClawUsage** to **Applications**
4. Launch from Applications (may need to right-click → Open first time)

### Build from Source
```bash
# Requires Xcode 15+ and Homebrew
brew install xcodegen
git clone https://github.com/peter-jammable/mac-menu-bar-claude-usage.git
cd mac-menu-bar-claude-usage
xcodegen generate
open ClawUsage.xcodeproj
# Press Cmd+R to build and run
```

## Usage

1. **Launch** ClawUsage - appears in menu bar as two stacked bars
2. **Click** the icon to open the dropdown
3. **Sign in** with your Claude account
4. **Authorize** the app in your browser
5. **Monitor** your usage from the menu bar

The bars update automatically. Top bar = 5-hour session, bottom bar = 7-day weekly.

## Requirements

- **macOS 13.0** (Ventura) or later
- **Claude Pro** or **Claude Max** subscription
- Internet connection for OAuth and usage updates

## Keywords

Claude usage tracker, Claude rate limit monitor, Anthropic API usage, Claude Pro limits, Claude Max quota, macOS menu bar app, Claude Code usage, AI assistant limits, Claude session tracker, weekly limit monitor, Claude API monitor, rate limit checker, usage dashboard, Claude subscription tracker

## FAQ

**Q: Is this an official Anthropic app?**
A: No, this is an independent third-party app that uses Claude's OAuth to display your usage.

**Q: Does it work with Claude Free tier?**
A: It requires Claude Pro or Max subscription which have rate limits to track.

**Q: Is my data safe?**
A: Yes. OAuth tokens are stored in your macOS Keychain. No usage data is sent anywhere except to Anthropic's API to fetch your current limits.

**Q: Why two bars?**
A: Claude has two rate limit windows - a 5-hour session limit and a 7-day weekly limit. Both matter!

## License

MIT License - see [LICENSE](LICENSE)

## Contributing

Issues and PRs welcome at [GitHub](https://github.com/peter-jammable/mac-menu-bar-claude-usage)

---

Made for Claude power users who want to stay on top of their usage.
