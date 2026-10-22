// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Macphin",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "Macphin",
            dependencies: ["SwiftTerm"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MacphinTests",
            dependencies: ["Macphin"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
