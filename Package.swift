// swift-tools-version: 6.2
import PackageDescription
import Foundation

// Shared on every system: the core and its tests.
var targets: [Target] = [
    .target(name: "NexCore"),
    .target(name: "NexProcess", dependencies: ["NexCore"]),
    .target(name: "NexGit", dependencies: ["NexCore"]),
    .target(name: "NexApp", dependencies: ["NexCore", "NexProcess", "NexGit"]),
    .target(name: "NexTestSupport", dependencies: ["NexGit", "NexApp"], path: "Tests/NexTestSupport"),
    .testTarget(name: "NexCoreTests", dependencies: ["NexCore"]),
    .testTarget(name: "NexProcessTests", dependencies: ["NexProcess", "NexCore"]),
    .testTarget(name: "NexGitTests", dependencies: ["NexGit", "NexTestSupport"]),
    .testTarget(name: "NexAppTests", dependencies: ["NexApp", "NexCore", "NexProcess", "NexGit", "NexTestSupport"]),
]
var products: [Product] = []
var dependencies: [Package.Dependency] = []

#if os(macOS)
// The Mac app: SwiftUI interface, SwiftTerm terminal, menu bar and widgets (built by build.sh).
dependencies += [.package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.5.0")]
products += [.executable(name: "NexLauncher", targets: ["NexLauncher"])]
targets += [
    .target(name: "NexTerminal", dependencies: [.product(name: "SwiftTerm", package: "SwiftTerm")]),
    .target(name: "NexUI", dependencies: ["NexCore", "NexProcess", "NexGit", "NexTerminal", "NexApp"]),
    .executableTarget(name: "NexLauncher", dependencies: ["NexUI"]),
    .testTarget(name: "NexTerminalTests", dependencies: ["NexTerminal"]),
    .testTarget(name: "NexUITests", dependencies: ["NexUI", "NexApp", "NexCore", "NexProcess", "NexGit", "NexTerminal", "NexTestSupport"]),
]
#endif

#if os(Linux)
// The Linux app: GTK 4 / libadwaita through Adwaita for Swift (needs Swift 6.3, GTK 4.20 and libadwaita 1.8, as in
// the GNOME 50 SDK). NEX_CORE_ONLY=1 leaves it out, for systems with older GTK that only test the shared core.
if ProcessInfo.processInfo.environment["NEX_CORE_ONLY"] == nil {
dependencies += [.package(url: "https://git.aparoksha.dev/aparoksha/adwaita-swift", revision: "af5598fbd6f2425841f426ad388d7a7edd6c90e6")]
products += [.executable(name: "NexLinux", targets: ["NexLinux"])]
targets += [
    .systemLibrary(name: "CVte", pkgConfig: "vte-2.91-gtk4", providers: [.apt(["libvte-2.91-gtk4-dev"])]),
    .executableTarget(name: "NexLinux", dependencies: [
        "NexApp", "NexCore", "NexProcess", "NexGit", "CVte",
        .product(name: "Adwaita", package: "adwaita-swift"),
        .product(name: "CAdw", package: "adwaita-swift"),
    ]),
    .testTarget(name: "NexLinuxTests", dependencies: ["NexLinux", "NexApp", "NexTestSupport"]),
]
}
#endif

let package = Package(
    name: "NexLauncher",
    platforms: [.macOS(.v14)],
    products: products,
    dependencies: dependencies,
    targets: targets,
    swiftLanguageModes: [.v5]
)
