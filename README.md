# FosMouseFix

A lightweight open-source replacement for Mac Mouse Fix — remap extra mouse buttons and control smooth scrolling on macOS 13+.

Supports MX Master 3S, Logitech, and any HID mouse with extra buttons.

## Quick Start

```bash
# Build from source
git clone https://github.com/gabriel-rivero/fosmousefix
cd fosmousefix
swift build -c release

# Install daemon to /usr/local/bin and start it
.build/arm64-apple-macosx/release/MouseFix --install
```

After installing, **grant Accessibility permission**:

1. Open **System Settings → Privacy & Security → Accessibility**
2. Click **+** and add `/usr/local/bin/mousefix`
3. Toggle the checkbox next to it

Then:

```bash
# Build the Preferences app
swift build -c release --target Preferences

# Or use the drag-to-Applications bundle
scripts/create-app-bundle.sh
```

## Usage

```
MouseFix --install           Install daemon & launch agent
MouseFix --uninstall         Remove daemon & launch agent
MouseFix --status            Check installation state
MouseFix --validate          Run self-tests
MouseFix --listen            Identify button numbers
MouseFix --config <path>     Custom config path
MouseFix --verbose           Verbose logging
```

### Preferences UI

Open `MouseFix Preferences.app` to configure:
- **Scrolling** — toggle smooth scrolling (experimental) + intensity
- **Scroll Direction** — flip vertical/horizontal independently
- **Button Mappings** — assign actions to each button/trigger

After saving, the daemon is signaled to reload config.

### Button Discovery

```bash
MouseFix --listen
# Press each button — output shows:
#   button=3 down  x=1234 y=567
#   button=3 up    x=1234 y=567
```

MX Master 3S defaults: 0=left, 1=right, 2=middle, 3=back, 4=forward, 5=thumb

## Default Config

~/.config/mousefix/config.json:

```json
{
  "smooth_scrolling": { "enabled": false, "intensity": 0.7 },
  "scroll_direction": { "flip_vertical": false, "flip_horizontal": false },
  "mappings": [
    { "button": 3, "trigger": "click", "action": "back" },
    { "button": 4, "trigger": "click", "action": "forward" },
    { "button": 5, "trigger": "click", "action": "mission_control" }
  ]
}
```

### Triggers

click, double_click, hold, hold_scroll_up, hold_scroll_down, drag_up, drag_down, drag_left, drag_right, drag

### Actions

mission_control, launchpad, show_desktop, screenshot, spotlight, back, forward, zoom_in, zoom_out, dashboard, brightness_up, brightness_down, volume_up, volume_down, mute, app_expose

Or a key combo:

```json
{ "button": 5, "trigger": "click", "action": { "key_code": 12, "modifiers": ["command", "shift"] } }
```

## Uninstall

```bash
mousefix --uninstall
```

To also remove the config:
```bash
rm ~/.config/mousefix/config.json
```

## Build from Source

Requires Xcode 15+ / Swift 5.9+.

```bash
git clone https://github.com/gabriel-rivero/fosmousefix
cd fosmousefix
swift build -c release
```

Debug build (faster iteration):
```bash
swift build
swift build --target Preferences
```

## How It Works

- **MouseFix** — daemon that runs a CGEventTap at session level, intercepting scroll wheel, other mouse buttons, and drag events
- **MouseFixCore** — shared library with config parsing, action execution (AppleScript key combos), button gesture state machine, scroll smoothing, and scroll direction flipping
- **MouseFix Preferences** — SwiftUI app for editing config and sending SIGHUP to the daemon
- **LaunchAgent** — starts the daemon at login and keeps it alive

The daemon communicates with the system via:
- CGEventTap for event interception
- osascript (AppleScript → System Events) for keyboard shortcuts that CGEventPost couldn't trigger (Mission Control, etc.)
- SIGHUP for config reload (KeepAlive auto-restarts on exit)

## License

MIT
