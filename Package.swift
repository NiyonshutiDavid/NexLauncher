// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NexLauncher",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "NexLauncher", targets: ["NexLauncher"])],
    targets: [
        .target(name: "NexCore"),
        .target(name: "NexProcess", dependencies: ["NexCore"]),
        .target(name: "NexGit", dependencies: ["NexCore"]),
        .target(name: "NexUI", dependencies: ["NexCore", "NexProcess", "NexGit"]),
        .executableTarget(name: "NexLauncher", dependencies: ["NexUI"]),
        .testTarget(name: "NexCoreTests", dependencies: ["NexCore"]),
        .testTarget(name: "NexProcessTests", dependencies: ["NexProcess", "NexCore"]),
        .testTarget(name: "NexGitTests", dependencies: ["NexGit"]),
        .testTarget(name: "NexUITests", dependencies: ["NexUI", "NexCore", "NexProcess", "NexGit"]),
    ],
    swiftLanguageModes: [.v5]
)
