# VirtManager for macOS

A native macOS application for managing remote virtual machines via [libvirt](https://libvirt.org/). Connect to KVM/QEMU hypervisors over SSH, manage VMs, configure networks, and get full graphical and serial console access — all from a single app.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 6](https://img.shields.io/badge/Swift-6.0-orange)
![License](https://img.shields.io/badge/license-MIT-green)
![CI](https://github.com/calibrae/virtmanager/actions/workflows/ci.yml/badge.svg)

## Install

Download the latest DMG from [Releases](https://github.com/calibrae/virtmanager/releases/latest), open it, and drag VirtManager to Applications. All dependencies are bundled — no Homebrew, no Xcode, nothing extra.

## Features

### VM Management
- **Connect to remote hypervisors** via `qemu+ssh://` with SSH key, agent, or password authentication
- **List and manage VMs** — state indicators (running, paused, shut off, crashed), search/filter, auto-refresh
- **VM lifecycle control** — start, shutdown, force off, pause, resume, reboot with confirmation dialogs
- **VM configuration editor** — tabbed GUI (CPU, memory, disks, network, boot, graphics) + raw XML editor with validation
- **VM creation wizard** — 6-step wizard with OS variant defaults (Linux gets virtio, Windows gets SATA + e1000)
- **Multiple connections** — manage VMs across several hypervisors simultaneously

### Consoles
- **VNC console** — custom pure-Swift RFB 3.8 client, Metal rendering, full keyboard/mouse
- **SPICE console** — spice-client-glib integration with keyboard/mouse and USB redirection
- **Serial console** — VT100/xterm terminal emulator via [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)
- **Keyboard grab** — CGEvent tap captures all keys including Cmd+Tab (Ctrl+Alt to release)

### Network Management
- **All 9 libvirt forward modes** — NAT, routed, isolated, open, bridge, macvtap (bridge/vepa/private/passthrough), Open vSwitch
- **Network configuration editor** — tabbed GUI (Overview, IPv4, IPv6, DNS, DHCP, Port Forwarding, QoS, XML)
- **DNS management** — forwarders, host records, TXT/SRV records
- **DHCP management** — ranges, static host entries (MAC/IP/hostname), BOOTP/PXE, active lease monitoring
- **Port forwarding** — NAT DNAT rules via native `<portForward>` XML (libvirt 9.4+)
- **IPv6** — dual-stack with independent DHCPv6 and Router Advertisement configuration
- **Bandwidth QoS** — inbound/outbound limits per network
- **Network creation wizard** — multi-step, mode-adaptive (bridge/macvtap skip IP steps)
- **Network topology** — interactive graph visualization showing VMs, networks, and NIC connections
- **OVS auto-detection** — Open vSwitch options shown only when available on the hypervisor

### Storage & ISO
- **ISO management** — upload from Mac via SCP, browse remote filesystem, CDROM attach/eject
- **Storage pool management** — create, delete, start, stop, browse volumes

### Platform
- **Native macOS UI** — SwiftUI + AppKit, dark mode, Retina, VoiceOver accessible
- **SSH host key verification** — warns on unknown or changed host keys
- **Keychain integration** — credentials stored securely, never in plaintext
- **Code signed and notarized** — no Gatekeeper warnings

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon or Intel Mac
- SSH access to a libvirt hypervisor (KVM/QEMU)

## Building from Source

All C dependencies (libvirt, spice-gtk, glib, etc.) are bundled in the app bundle for distribution. For development builds, you need them installed locally:

```bash
brew install libvirt spice-gtk pkg-config
git clone https://github.com/calibrae/virtmanager.git
cd virtmanager
swift build
open VirtManager.xcodeproj
```

## Architecture

```
Sources/
├── CLibvirt/              # libvirt C API wrapper
├── CSpice/                # spice-client-glib wrapper
├── LibvirtSwift/          # Swift wrapper: connections, domains, streams, storage
│   ├── DomainConfig/      # Domain XML parser, device models, validation
│   └── NetworkConfig/     # Network XML parser, DNS/DHCP/QoS models, validation
├── VirtManagerCore/       # Shared models, errors, credential store, logging
├── VNCClient/             # Pure Swift RFB 3.8 protocol client
├── SpiceClient/           # SPICE: GLib bridge, display, input, USB
└── VirtManager/           # SwiftUI app
    ├── Configuration/     # VM config editor (9 tabs + XML)
    ├── Creation/          # VM creation wizard (6 steps)
    ├── Network/           # Network management
    │   ├── Tabs/          # Network config editor tabs (8 tabs)
    │   ├── Topology/      # Interactive network topology graph
    │   └── Wizard/        # Network creation wizard (5 steps)
    ├── Storage/           # ISO browser, remote filesystem browser
    └── Windows/           # VNC, SPICE, serial console windows
```

| Decision | Choice | Why |
|----------|--------|-----|
| UI | SwiftUI + AppKit | SwiftUI for forms/lists, AppKit for console windows |
| libvirt | C API via GCD | Swift async cooperative pool crashes with libvirt's signal handlers |
| VNC | Pure Swift RFB 3.8 | No C dependency, Network.framework transport |
| SPICE | spice-client-glib | GLib main loop on dedicated thread |
| Rendering | Metal / Core Graphics | CAMetalLayer for consoles, Canvas for topology |
| Credentials | macOS Keychain | Never stored in plaintext or config files |
| ISO upload | SCP subprocess | 10-100x faster than libvirt streams over SSH |

## Testing

```bash
swift test    # 62 unit + integration tests (no live hypervisor needed)
```

## CI/CD

- **CI** — On push/PR: SPM build, unit tests, integration tests, Xcode build
- **Release** — On tag (`v*`): build, bundle dylibs, code sign, create DMG, notarize, GitHub Release

All workflows run on a self-hosted macOS runner.

## License

MIT — see [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) for bundled library licenses.

## Acknowledgments

- [libvirt](https://libvirt.org/) — The virtualization API
- [virt-manager](https://github.com/virt-manager/virt-manager) — Inspiration and reference
- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) — Terminal emulator
- [spice-gtk](https://www.spice-space.org/) — SPICE protocol client
