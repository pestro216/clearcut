// swift-tools-version:5.9
// Clearcut's image engine as a package, so the exact code that ships in the app can be
// tested and benchmarked on a Mac (GitHub Actions). The app compiles the same Core/ sources.
import PackageDescription

let package = Package(
    name: "ClearcutCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "ClearcutCore", targets: ["ClearcutCore"])],
    targets: [
        .target(name: "ClearcutCore", path: "Core"),
        .executableTarget(name: "cutbench", dependencies: ["ClearcutCore"], path: "QA/cutbench"),
        .testTarget(name: "ClearcutCoreTests", dependencies: ["ClearcutCore"], path: "QA/Tests")
    ]
)
