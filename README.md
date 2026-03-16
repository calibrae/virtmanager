# VirtManager for macOS

A native macOS application for managing remote virtual machines via [libvirt](https://libvirt.org/). Built in Swift, it connects to KVM/QEMU hypervisors over SSH and provides graphical (VNC/SPICE) and serial console access with full keyboard and mouse support.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 6](https://img.shields.io/badge/Swift-6.0-orange)
![License](https://img.shields.io/badge/license-MIT-green)
![CI](https://github.com/calibrae/virtmanager/actions/workflows/ci.yml/badge.svg)
![Tests](https://img.shields.io/badge/tests-53%20passing-brightgreen)
![OWASP](https://img.shields.io/badge/OWASP-24%2F26%20fixed-blue)

## Install

**Download the latest DMG from [Releases](https://github.com/calibrae/virtmanager/releases/latest)**, open it, and drag VirtManager to Applications. No Homebrew or dependencies needed — everything is bundled.

## Features

- **Connect to remote hypervisors** via `qemu+ssh://` with SSH key or agent authentication
- **List and manage VMs** — state indicators (running, paused, shut off, crashed), search/filter
- **VM lifecycle control** — start, shutdown, force off, pause, resume, reboot with confirmation dialogs
- **VNC console** — full graphical console with keyboard/mouse via custom RFB 3.8 protocol client
- **SPICE console** — graphical console via spice-client-glib with keyboard/mouse, USB redirection
- **Serial console** — full VT100/xterm terminal emulator via [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)
- **USB device redirection** — forward Mac USB devices to SPICE VMs, share ISOs as virtual USB CD-ROM
- **VM configuration editor** — GUI tabs (CPU, memory, disks, network, boot) + raw XML editor with validation
- **VM creation wizard** — 6-step wizard with OS variant defaults
- **ISO management** — upload from Mac via SCP, browse remote filesystem, CDROM attach/eject
- **Storage & network management** — create/delete/manage storage pools and virtual networks
- **Multiple connections** — manage VMs across several hypervisors simultaneously
- **Auto-refresh** — VM states update every 5 seconds
- **SSH host key verification** — warns on unknown or changed host keys
- **Keyboard grab** — CGEvent tap captures all keys including Cmd+Tab (Ctrl+Alt to release)
- **Native macOS UI** — SwiftUI sidebar + detail, dark mode, Retina, preferences

## Screenshots

*Connect to hypervisors, browse VMs, open graphical and serial consoles — all from a native macOS app.*

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon or Intel Mac
- SSH access to a libvirt hypervisor (KVM/QEMU)

**No Homebrew required** — all libraries (libvirt, spice-gtk, glib, openssl, etc.) are bundled in the app.

## Building from Source

For development, you'll need Homebrew dependencies:

```bash
brew install libvirt spice-gtk pkg-config xcodegen
git clone https://github.com/calibrae/virtmanager.git
cd virtmanager
swift build           # SPM library build
xcodegen generate     # Generate Xcode project
bash run.sh           # Build and launch via Xcode
```

## Architecture

```
Sources/
├── CLibvirt/              # System library wrapper for libvirt C API
├── CSpice/                # System library wrapper for spice-client-glib
├── LibvirtSwift/          # Swift wrapper: connection, domains, streams, storage, XML parsing
│   └── DomainConfig/      # Domain XML parser, device models, validation engine
├── VirtManagerCore/       # Shared models, errors, credential store, logging
├── VNCClient/             # Custom RFB 3.8 protocol client (pure Swift)
├── SpiceClient/           # SPICE client: GLib bridge, display, input, USB manager
└── VirtManager/           # SwiftUI app
    ├── Configuration/     # VM config editor (9 tab views + XML editor)
    ├── Creation/          # VM creation wizard (6 steps)
    ├── Management/        # Storage pool & network managers
    ├── Storage/           # ISO browser, remote filesystem browser
    ├── USB/               # USB device redirection view
    └── Windows/ConsoleWindow/  # VNC, SPICE, serial console views
```

### Key Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| UI | SwiftUI + AppKit | SwiftUI for main window, AppKit for console views |
| libvirt | C API via Swift interop | Blocking calls on GCD (not Swift async — crashes cooperative pool) |
| VNC | Custom Swift RFB 3.8 | Pure Swift, no C dependency, Network.framework transport |
| SPICE | spice-client-glib | GLib main loop on dedicated thread, `g_main_context_acquire` + polling |
| Serial | SwiftTerm | Full VT100/xterm emulator, blocking libvirt stream on dedicated thread |
| Console rendering | Core Graphics | CGImage from surface data, dirty-rect repainting |
| Credentials | macOS Keychain | Never stored in plaintext |
| ISO upload | SCP subprocess | 10-100x faster than libvirt streams over SSH |

## Testing

```bash
swift test                                          # Unit + integration tests
xcodebuild test -project VirtManager.xcodeproj \
  -scheme VirtManagerUITests -destination 'platform=macOS'  # 14 XCUITests
```

## CI/CD

- **CI** — On push/PR: SPM build, unit tests, integration tests, Xcode build, XCUITests
- **Release** — On tag (`v*`): build, bundle 40 dylibs, code sign, create DMG, notarize, GitHub Release
- **Security** — Weekly: dependency audit, SSH/XML/credential scans

All workflows run on a self-hosted macOS runner.

## Security & Stats

OWASP-audited — all Critical and High findings fixed. See **[STATS.md](STATS.md)** for full audit results, test coverage, and codebase metrics.

## License

MIT — see [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) for bundled library licenses.

## Acknowledgments

- [libvirt](https://libvirt.org/) — The virtualization API
- [virt-manager](https://github.com/virt-manager/virt-manager) — Inspiration and reference implementation
- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) — Terminal emulator for serial console
- [spice-gtk](https://www.spice-space.org/) — SPICE protocol client library
