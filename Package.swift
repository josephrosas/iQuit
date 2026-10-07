// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "iQuit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "iQuit", targets: ["iQuit"])
    ],
    targets: [
        .executableTarget(
            name: "iQuit",
            path: "Sources/iQuit",
            exclude: ["Assets"],
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit"),
                .linkedFramework("AppIntents"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications")
            ]
        ),
        .testTarget(
            name: "iQuitTests",
            dependencies: ["iQuit"],
            path: "Tests/iQuitTests"
        )
    ]
)
