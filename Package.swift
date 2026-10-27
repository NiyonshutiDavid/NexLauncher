// swift-tools-version: 6.2
import PackageDescription

// Shared on every system: the core and its tests.
var targets: [Target] = [
    .target(name: "NexCore"),
    .target(name: "NexProcess", dependencies: ["NexCore"]),
    .target(name: "NexGit", dependencies: ["NexCore"]),
    .target(name: "NexTestSupport", dependencies: ["NexGit"], path: "Tests/NexTestSupport"),
    .testTarget(name: "NexCoreTests", dependencies: ["NexCore"]),
    .testTarget(name: "NexProcessTests", dependencies: ["NexProcess", "NexCore"]),
    .testTarget(name: "NexGitTests", dependencies: ["NexGit", "NexTestSupport"]),
]
var products: [Product] = []
var dependencies: [Package.Dependency] = []

#if os(macOS)
// The Mac app: SwiftUI interface, SwiftTerm terminal, menu bar and widgets (built by build.sh).
dependencies += [.package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.5.0")]
products += [.executable(name: "NexLauncher", targets: ["NexLauncher"])]
targets += [
    .target(name: "NexTerminal", dependencies: [.product(name: "SwiftTerm", package: "SwiftTerm")]),
    .target(name: "NexUI", dependencies: ["NexCore", "NexProcess", "NexGit", "NexTerminal"]),
    .executableTarget(name: "NexLauncher", dependencies: ["NexUI"]),
    .testTarget(name: "NexTerminalTests", dependencies: ["NexTerminal"]),
    .testTarget(name: "NexUITests", dependencies: ["NexUI", "NexCore", "NexProcess", "NexGit", "NexTestSupport"]),
]
#endif

let package = Package(
    name: "NexLauncher",
    platforms: [.macOS(.v14)],
    products: products,
    dependencies: dependencies,
    targets: targets,
    swiftLanguageModes: [.v5]
)
