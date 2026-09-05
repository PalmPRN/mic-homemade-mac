// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "mic-homemade-mac",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "mic-homemade-mac", targets: ["mic-homemade-mac"])
    ],
    targets: [
        .executableTarget(
            name: "mic-homemade-mac",
            path: "mic-homemade-mac",
            exclude: [
                "Info.plist",
                "mic-homemade-mac.entitlements",
                "README.md",
                "Resources"
            ]
        )
    ]
)
