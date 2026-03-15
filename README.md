# VirtManager for macOS

A native macOS application for managing remote virtual machines via [libvirt](https://libvirt.org/). Built in Swift, it connects to KVM/QEMU hypervisors over SSH and provides graphical (VNC/SPICE) and serial console access with full keyboard and mouse support.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 6](https://img.shields.io/badge/Swift-6.0-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **Connect to remote hypervisors** via `qemu+ssh://` with SSH key or agent authentication
- **List and manage VMs** — see all VMs with state indicators (running, paused, shut off, crashed)
- **VM lifecycle control** — start, shutdown, force off, pause, resume, reboot with confirmation dialogs
- **VNC console** — full graphical console with keyboard/mouse support via custom RFB 3.8 protocol client
- **SPICE console** — graphical console via spice-client-glib with keyboard/mouse forwarding
- **Serial console** — full terminal emulator via [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) connected to libvirt console streams
- **Multiple connections** — manage VMs across several hypervisors simultaneously
- **Native macOS UI** — SwiftUI sidebar + detail layout, dark mode, Retina display support
- **Preferences** — configurable connection defaults, console behavior, keyboard shortcuts

## Screenshots

*Connect to hypervisors, browse VMs, open graphical and serial consoles — all from a native macOS app.*

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon or Intel Mac
- [Homebrew](https://brew.sh/) dependencies:

```bash
brew install libvirt spice-gtk pkg-config
```

## Building

### From Source (SPM)

```bash
git clone https://github.com/your-org/virtmanager.git
cd virtmanager
swift build
```

### Xcode

Open the project in Xcode (the `VirtManager.xcodeproj` wraps the SPM package):

```bash
xcodebuild build -project VirtManager.xcodeproj -scheme VirtManagerApp -destination 'platform=macOS'
```

### Run

```bash
bash run.sh
```

This builds via Xcode and launches the `.app` bundle.

## Architecture

The project is organized as a Swift Package with modular targets:

```
Sources/
├── CLibvirt/           # System library wrapper for libvirt C API
├── CSpice/             # System library wrapper for spice-client-glib
├── LibvirtSwift/       # Swift wrapper: connection, domain ops, streams, XML parsing
├── VirtManagerCore/    # Shared models, errors, credential store, logging
├── VNCClient/          # Custom RFB 3.8 protocol client (pure Swift)
├── SpiceClient/        # SPICE client via spice-client-glib (GLib bridge)
└── VirtManager/        # SwiftUI app: views, console windows, preferences
    └── Windows/
        └── ConsoleWindow/  # VNC, SPICE, and serial console view controllers

XcodeSupport/           # Thin @main entry point for Xcode app target
Tests/
├── VirtManagerCoreTests/   # Unit tests (models, state, Codable)
├── IntegrationTests/       # Integration tests against live hypervisor
└── UITests/                # XCUITest suite
```

### Key Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| UI Framework | SwiftUI + AppKit | SwiftUI for main window, AppKit for console views needing low-level control |
| libvirt binding | C API via Swift interop | Direct, no wrapper library needed; blocking calls dispatched to background threads |
| VNC protocol | Custom Swift RFB 3.8 | Simple protocol, avoids C dependency; supports Raw + CopyRect encodings |
| SPICE protocol | spice-client-glib | Too complex to reimplement; GLib main loop on dedicated thread |
| Serial console | SwiftTerm | Full VT100/xterm terminal emulator; handles all escape sequences |
| Console rendering | Core Graphics (CGImage) | Simple and correct; Metal upgrade path available |
| Keyboard capture | NSEvent monitoring | Per-window keyboard forwarding; CGEvent taps for future global grab |
| Credential storage | macOS Keychain | Platform standard; never stored in plaintext |
| Concurrency | Swift structured concurrency + GCD | Blocking libvirt calls on GCD; async/await for UI coordination |

## Testing

### Unit Tests

```bash
swift test --filter VirtManagerCoreTests
```

### Integration Tests

Requires a reachable libvirt hypervisor (configured for `jolyne` in tests):

```bash
swift test --filter IntegrationTests
```

### UI Tests (XCUITest)

Requires the Xcode project and a reachable hypervisor:

```bash
xcodebuild test -project VirtManager.xcodeproj -scheme VirtManagerUITests -destination 'platform=macOS'
```

**14 UI tests** covering: app launch, connection flow, VM discovery, VM detail, console buttons, VNC console window opening.

## Project Status

### Implemented (MVP)

| Feature | Status |
|---------|--------|
| SSH connection to hypervisors | Done |
| VM listing with state badges | Done |
| VM lifecycle (start/stop/pause/resume/reboot) | Done |
| VNC graphical console | Done |
| SPICE graphical console | Done |
| Serial console (SwiftTerm) | Done |
| Connection persistence | Done |
| Preferences window | Done |
| Multi-connection support | Done |
| XCUITest suite | Done |

### Planned (Post-MVP)

- VM creation wizard
- VM cloning
- Hardware configuration editing
- Storage and network management
- Performance monitoring graphs
- SPICE clipboard and USB redirection
- Multi-monitor support
- Menu bar widget

## Development

### Prerequisites

```bash
# Install dependencies
brew install libvirt spice-gtk pkg-config xcodegen

# Resolve SPM dependencies
swift package resolve

# Generate Xcode project (if needed)
xcodegen generate
```

### Project Structure

- `Package.swift` — SPM package definition (library targets)
- `project.yml` — XcodeGen spec for `.xcodeproj` (app + UI test targets)
- `run.sh` — Build and launch script
- `test-ui.sh` — osascript-based UI test runner (alternative to XCUITest)

## License

MIT

## Acknowledgments

- [libvirt](https://libvirt.org/) — The virtualization API
- [virt-manager](https://github.com/virt-manager/virt-manager) — Inspiration and reference implementation
- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) — Terminal emulator for serial console
- [spice-gtk](https://www.spice-space.org/) — SPICE protocol client library
