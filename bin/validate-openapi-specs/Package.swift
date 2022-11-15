// swift-tools-version: 5.7
/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2022 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageDescription

let package = Package(
    name: "validate-specs",
    platforms: [
        .macOS(.v10_15),
    ],
    products: [
        .executable(name: "validate-specs", targets: ["validate-specs"]),
    ],
    dependencies: [
        .package(name: "swift-docc", path: "../../"),
    ],
    targets: [
        .executableTarget(
            name: "validate-specs",
            dependencies: [
                .product(name: "SwiftDocCUtilities", package: "swift-docc"),
            ],
            path: "Sources",
            resources: [
                .copy("Fixtures"),
                .copy("OpenAPISchemaValidator")
            ]
        ),
    ]
)
