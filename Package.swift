// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MoonEarthCore",
    products: [.library(name: "MoonEarthCore", targets: ["MoonEarthCore"])],
    targets: [
        .target(name: "MoonEarthCore", path: "MoonEarth/Core"),
        .testTarget(name: "MoonEarthCoreTests", dependencies: ["MoonEarthCore"], path: "Tests")
    ]
)
