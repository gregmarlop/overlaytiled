# OverlayTiled

A macOS menu bar application that creates a floating, transparent overlay window with tiled text pattern. Useful for displaying watermarks, copyright notices, or text overlays on your screen.

## Features

- Floating overlay window with customizable tiled text pattern
- Adjustable text angle rotation (-90° to 90°)
- Variable font size (10-120pt)
- Opacity control for transparency
- Customizable text color
- Adjustable spacing between text repetitions
- Click-through mode (lock/unlock)
- Resizable and movable overlay window
- Persistent settings between sessions
- Menu bar access for quick control

## System Requirements

- macOS 10.15 or later
- macOS 11.0 or later for menu bar icon support

## Installation

### Build and Run Without Xcode

#### Requirements
- macOS 10.15 or later
- Command Line Tools (`xcode-select --install`)

#### Compile

```bash
swiftc -O \
  -framework AppKit \
  -o OverlayTiled \
  OverlayTiled_context.swift
```

#### Run

```bash
./OverlayTiled &
```

The app will appear in your **menu bar** (no Dock icon).  
Settings are saved automatically to:
```
~/Library/Application Support/OverlayTiled/settings.json
```

#### (Optional) Create an `.app` Bundle

```bash
mkdir -p ~/Applications/OverlayTiled.app/Contents/MacOS
cp OverlayTiled ~/Applications/OverlayTiled.app/Contents/MacOS/
```

Create a minimal `Info.plist`:

```bash
cat > ~/Applications/OverlayTiled.app/Contents/Info.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>OverlayTiled</string>
  <key>CFBundleIdentifier</key><string>ch.gregmarlop.overlaytiled</string>
  <key>CFBundleExecutable</key><string>OverlayTiled</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
EOF
```

Then run:
```bash
open ~/Applications/OverlayTiled.app
```

## Usage

1. Launch OverlayTiled - it will appear in your menu bar  
2. Click the menu bar icon to access controls  
3. Select "Show Overlay" to display the overlay window  
4. Configure the overlay through "Settings":
   - Text: The text to display (default: "© COPYRIGHT")
   - Angle: Rotation angle in degrees
   - Font size: Size of the text
   - Opacity: Transparency level
   - Spacing: Distance between text repetitions
   - Color: Text color
   - Click-through: Enable/disable mouse interaction

### Controls

**Menu Bar Options:**
- Show/Hide Overlay
- Lock/Unlock (toggle click-through)
- Settings window
- Center Overlay
- Quit

**Window Interaction:**
- Drag to move (when unlocked)
- Drag edges/corners to resize (when unlocked)
- Right-click for context menu

## Configuration

Settings are automatically saved to:
```
~/Library/Application Support/OverlayTiled/settings.json
```

### Default Settings

- Text: "© COPYRIGHT"
- Angle: -30°
- Font Size: 36pt
- Opacity: 0.15
- Spacing: 24pt
- Color: White
- Locked: false

## Development

The application is built as a single Swift file using AppKit, making it lightweight and easy to modify.

### Architecture

- `OverlaySettings`: Model for persistent settings storage
- `TiledOverlayView`: Custom NSView for rendering tiled text
- `OverlayWindowController`: Manages the floating overlay window
- `SettingsWC`: Settings window controller
- `AppDelegate`: Menu bar application controller

## Author

Gregori M.

## Version

Current version: 1.3

## License

Copyright © 2025 Gregori M.
