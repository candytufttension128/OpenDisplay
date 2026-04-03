# OpenDisplay

An open-source macOS menu bar utility for display management. A free alternative to BetterDisplay, MonitorControl, and Lunar.

## Features

### DDC/CI Monitor Control
- Brightness, contrast, volume, sharpness via hardware DDC
- Input source switching (HDMI, DisplayPort, USB-C, VGA, DVI)
- Monitor power control (on, standby, off)
- Color gain (RGB) adjustment

### Resolution & Display
- All resolutions including hidden HiDPI modes
- Refresh rate switching
- Display mirroring configuration
- EDID reading (manufacturer, model, serial, year, physical size)
- Display info panel (vendor, model, color profile, rotation)

### Software Dimming
- Gamma-based software dimming (works on all displays including built-in)
- Overlay-based dimming (black window overlay)
- Combined hardware + software dimming below 0%
- Dim to complete black

### Night Shift
- Scheduled color temperature adjustment
- Configurable start/end hours
- Adjustable warmth (Kelvin)

### Color Management
- Color temperature control via gamma tables
- Color profile listing and detection
- Per-display color space info

### Profiles & Persistence
- Save/load display profiles (brightness, contrast, volume, resolution)
- Apply profiles with one click
- Launch at login support

### Keyboard Shortcuts
- Global hotkeys for brightness, contrast, volume
- Input switching, mute toggle
- Configurable via Carbon hot keys

### Sleep Prevention
- Prevent display sleep while external monitors connected
- Uses native caffeinate

### CLI Integration
- Full command-line interface for scripting
- Control brightness, contrast, volume, input, power, resolution
- List displays and available modes

### Native OSD
- macOS-native on-screen display for brightness/volume changes

## Build & Run

```bash
cd OpenDisplay
swift build
swift run
```

Or open in Xcode: `open Package.swift`

## CLI Usage

```bash
# List displays
swift run OpenDisplay --list

# Set brightness on first external display
swift run OpenDisplay --display 1 --brightness 70

# Switch input to HDMI 1
swift run OpenDisplay --display 1 --input hdmi1

# Set resolution
swift run OpenDisplay --display 0 --resolution 2560x1440

# List available modes
swift run OpenDisplay --display 0 --modes

# Full help
swift run OpenDisplay --help
```

## Requirements

- macOS 14+
- Swift 5.9+
- External monitor via DisplayPort/HDMI/USB-C for DDC features

## Architecture

```
OpenDisplay/
├── App.swift               # Entry point, menu bar, CLI routing, hotkey wiring
├── MainView.swift          # Full UI (Displays, Night Shift, Profiles, Settings tabs)
├── DisplayManager.swift    # Display enumeration, resolution, mirroring, refresh rates
├── DDCBrightness.swift     # DDC/CI protocol (brightness, contrast, volume, input, power, color)
├── GammaDimmer.swift       # Software dimming & color temperature via gamma tables
├── OverlayDimmer.swift     # Overlay-based screen dimming
├── NightShiftScheduler.swift # Scheduled color temperature shifts
├── BrightnessSync.swift    # Multi-display brightness synchronization
├── HotkeyManager.swift     # Global keyboard shortcuts (Carbon)
├── EDIDReader.swift        # EDID parsing (manufacturer, model, serial, name)
├── ColorProfileManager.swift # Color profile listing & detection
├── ProfileManager.swift    # Display profiles & launch-at-login persistence
├── CLIHandler.swift        # Command-line interface
├── NativeOSD.swift         # macOS native OSD notifications
├── SleepPreventer.swift    # Prevent display sleep (caffeinate)
└── Entitlements.plist      # Sandbox disabled for IOKit
```

## Roadmap

- [ ] Virtual/dummy display creation for HiDPI
- [ ] XDR/HDR brightness upscaling
- [ ] Picture-in-Picture windows
- [ ] Display arrangement editor
- [ ] Ambient light sensor sync
- [ ] LG webOS / Samsung Tizen TV control
- [ ] EDID override
- [ ] Teleprompter mode (screen flipping)
- [ ] Shortcuts app integration (App Intents)

## License

MIT
