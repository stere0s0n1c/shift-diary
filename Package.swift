// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ShiftDiary",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "shift-server", targets: ["ShiftServer"]),
        .executable(name: "shift-diary", targets: ["ShiftClient"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.110.0"),
    ],
    targets: [
        // Domain: trips, day summary, validation, idempotent store. No dependencies.
        .target(name: "ShiftCore"),
        // HTTP layer on top of ShiftCore.
        .target(
            name: "ShiftAPI",
            dependencies: [
                "ShiftCore",
                .product(name: "Vapor", package: "vapor"),
            ]
        ),
        .executableTarget(name: "ShiftServer", dependencies: ["ShiftAPI"]),
        .executableTarget(name: "ShiftClient", dependencies: ["ShiftCore"]),
        .testTarget(name: "ShiftCoreTests", dependencies: ["ShiftCore"]),
        .testTarget(
            name: "ShiftAPITests",
            dependencies: [
                "ShiftAPI",
                .product(name: "XCTVapor", package: "vapor"),
            ]
        ),
    ]
)
