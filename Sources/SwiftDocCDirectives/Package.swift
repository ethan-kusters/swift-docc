// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftDocCDirectives",
    platforms: [
        .macOS(.v12),
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "SwiftDocCDirectives",
            targets: ["SwiftDocCDirectives"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.1.3"),
        .package(url: "https://github.com/apple/swift-syntax", revision: "bf8db8d"),
    ],
    targets: [
        .target(name: "SwiftDocCDirectives"),
        
        .testTarget(
            name: "SwiftDocCDirectivesTests",
            dependencies: ["SwiftDocCDirectives"]
        ),
        
        .executableTarget(
            name: "DirectiveCodeGeneration",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
            ]
        ),
    ]
)
