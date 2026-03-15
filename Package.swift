// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VirtManager",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "VirtManager", targets: ["VirtManager"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.0.0"),
    ],
    targets: [
        // C shim for libvirt
        .systemLibrary(
            name: "CLibvirt",
            pkgConfig: "libvirt",
            providers: [
                .brew(["libvirt"]),
            ]
        ),

        // Swift wrapper around libvirt
        .target(
            name: "LibvirtSwift",
            dependencies: ["CLibvirt", "VirtManagerCore"]
        ),

        // Shared models, protocols, and infrastructure
        .target(
            name: "VirtManagerCore"
        ),

        // VNC client library (RFB 3.8 protocol)
        .target(
            name: "VNCClient"
        ),

        // C shim for spice-gtk
        .systemLibrary(
            name: "CSpice",
            pkgConfig: "spice-client-glib-2.0",
            providers: [
                .brew(["spice-gtk"]),
            ]
        ),

        // Swift wrapper around SPICE client
        .target(
            name: "SpiceClient",
            dependencies: ["CSpice"]
        ),

        // Main application (library — the @main entry point lives in the Xcode app target)
        .target(
            name: "VirtManager",
            dependencies: ["VirtManagerCore", "LibvirtSwift", "VNCClient", "SpiceClient", "SwiftTerm"]
        ),

        // Tests
        .testTarget(
            name: "VirtManagerCoreTests",
            dependencies: ["VirtManagerCore"]
        ),

        // Integration tests (require network access to jolyne)
        .testTarget(
            name: "IntegrationTests",
            dependencies: ["LibvirtSwift", "VirtManagerCore"]
        ),
    ]
)
