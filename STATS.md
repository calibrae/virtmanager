# Project Stats & Security

## Codebase

| Metric | Value |
|--------|-------|
| Source files | 77 Swift files |
| Lines of code | 11,700+ |
| SPM targets | 7 (CLibvirt, CSpice, LibvirtSwift, VirtManagerCore, VNCClient, SpiceClient, VirtManager) |
| Bundled dylibs | 40 (libvirt, spice-gtk, glib, openssl, gstreamer, etc.) |
| App bundle size | ~35 MB (all dependencies included) |

## Testing

| Suite | Count | Scope |
|-------|-------|-------|
| Unit tests | 38 | Models, XML parsing, validation, Codable round-trips |
| XCUITests | 14 | Full end-to-end: launch, connect, browse VMs, detail view, console |
| Integration tests | 1 | Live hypervisor: SSH connect, list VMs, verify state/graphics |
| **Total** | **53** | |

### Coverage

| Module | Coverage | Notes |
|--------|----------|-------|
| VirtManagerCore (models) | 77–100% | SavedConnection 100%, VMInfo 77%, VMState 100% |
| DomainConfig (XML parser) | 100% | Parsing, round-trip, device models |
| ConfigValidator | 100% | All 7 validation rule categories |
| LibvirtSwift | ~30% | Wrapper tested via integration; Swift Testing crashes with libvirt SSH |
| VNCClient | 0% (manual) | Protocol tested manually against live VMs |
| SpiceClient | 0% (manual) | Tested manually against live VMs |

## OWASP Security Audit

Full OWASP-style security review completed. Two passes — initial audit and re-audit after fixes.

### Results

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 5 | 5 | 0 |
| High | 4 | 4 | 0 |
| Medium | 8 | 7 | 1 |
| Low | 6 | 5 | 1 |
| Info | 3 | 3 | 0 |
| **Total** | **26** | **24** | **2** |

### Critical Findings (All Fixed)

| ID | Category | Issue | Fix |
|----|----------|-------|-----|
| C1 | Injection | SSH option injection via URI user/host | Strict allowlist sanitization |
| C2 | Misconfiguration | StrictHostKeyChecking=no on all SSH calls | Changed to accept-new |
| C3 | Injection | Remote command injection via SSH path args | Shell escaping |
| C4 | XML Injection | Unescaped XML in volume creation | escapeXML() applied |
| C5 | XML Injection | Unescaped XML in CDROM mount / pool creation | escapeXML() applied |

### High Findings (All Fixed)

| ID | Category | Issue | Fix |
|----|----------|-------|-----|
| H1 | XML Injection | Unescaped XML in all device toXML() methods | escapeXML() on 8 device types |
| H2 | Memory Safety | Use-after-free in GLib callbacks | Signal disconnection + destroyed flag |
| H3 | Data Exposure | VNC over plaintext TCP | Always SSH tunnel |
| H4 | Data Exposure | SPICE silent fallback to plaintext | Removed fallback |

### Accepted Risks

| ID | Severity | Issue | Reason |
|----|----------|-------|--------|
| M1 | Medium | Connection URIs in UserDefaults (unencrypted) | Low practical risk on macOS; passwords are in Keychain |
| M5 | Medium | Raw XML editor bypasses escaping | By design for power users; validated server-side by libvirt |

### Security Measures

- SSH host key verification with user prompt on first connect
- `StrictHostKeyChecking=accept-new` on all SSH/SCP subprocess calls
- `XMLHelpers.escapeXML()` on all user-derived values in libvirt XML
- `sanitizeSSHComponent()` — strict allowlist for URI-derived user/host
- `shellEscape()` — single-quote wrapping for all remote command arguments
- All VNC/SPICE console traffic tunneled through SSH (no plaintext path)
- `nodeLoadExternalEntitiesNever` on all XMLDocument parsing (XXE protection)
- Credentials stored exclusively in macOS Keychain
- `com.apple.security.cs.disable-library-validation` entitlement for Homebrew dylibs
- Hardened runtime enabled for notarization
