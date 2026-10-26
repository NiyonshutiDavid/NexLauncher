// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NexLauncher",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "NexLauncher", targets: ["NexLauncher"])],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.5.0"),
    ],
    targets: [
        .target(name: "NexCore"),
        .target(name: "NexProcess", dependencies: ["NexCore"]),
        .target(name: "NexGit", dependencies: ["NexCore"]),
        .target(name: "NexTerminal", dependencies: [.product(name: "SwiftTerm", package: "SwiftTerm")]),
        .target(name: "NexUI", dependencies: ["NexCore", "NexProcess", "NexGit", "NexTerminal"]),
        .executableTarget(name: "NexLauncher", dependencies: ["NexUI"]),
        .target(name: "NexTestSupport", dependencies: ["NexGit"], path: "Tests/NexTestSupport"),
        .testTarget(name: "NexCoreTests", dependencies: ["NexCore"]),
        .testTarget(name: "NexProcessTests", dependencies: ["NexProcess", "NexCore"]),
        .testTarget(name: "NexGitTests", dependencies: ["NexGit", "NexTestSupport"]),
        .testTarget(name: "NexTerminalTests", dependencies: ["NexTerminal"]),
        .testTarget(name: "NexUITests", dependencies: ["NexUI", "NexCore", "NexProcess", "NexGit", "NexTestSupport"]),
    ],
    swiftLanguageModes: [.v5]
)
