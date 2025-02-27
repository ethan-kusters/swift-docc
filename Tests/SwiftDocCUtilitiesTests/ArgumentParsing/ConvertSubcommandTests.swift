/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021-2023 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
@testable import SwiftDocCUtilities
@testable import SwiftDocC
import SwiftDocCTestUtilities

class ConvertSubcommandTests: XCTestCase {
    private let testBundleURL = Bundle.module.url(
        forResource: "TestBundle", withExtension: "docc", subdirectory: "Test Bundles")!
    
    private let testTemplateURL = Bundle.module.url(
        forResource: "Test Template", withExtension: nil, subdirectory: "Test Resources")!
    
    override func setUp() {
        // By default, send all warnings to `.none` instead of filling the
        // test console output with unrelated messages.
        Docc.Convert._errorLogHandle = .none
    }
    
    func testOptionsValidation() throws {
        // create source bundle directory
        let sourceURL = try createTemporaryDirectory(named: "documentation")
        try "".write(to: sourceURL.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        
        // create template dir
        let rendererTemplateDirectory = try createTemporaryDirectory()
        try "".write(to: rendererTemplateDirectory.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        
        // Tests a single input.
        do {
            SetEnvironmentVariable(TemplateOption.environmentVariableKey, rendererTemplateDirectory.path)
            XCTAssertNoThrow(try Docc.Convert.parse([
                sourceURL.path,
            ]))
        }
        
        // Test no inputs.
        do {
            UnsetEnvironmentVariable(TemplateOption.environmentVariableKey)
            XCTAssertNoThrow(try Docc.Convert.parse([]))
        }
        
        // Test missing input folder throws
        do {
            SetEnvironmentVariable(TemplateOption.environmentVariableKey, rendererTemplateDirectory.path)
            XCTAssertThrowsError(try Docc.Convert.parse([
                URL(fileURLWithPath: "123").path,
            ]))
        }
        
        // Test input folder is file throws
        do {
            let sourceAsSingleFileURL = sourceURL.appendingPathComponent("file-name.txt")
            try "some text".write(to: sourceAsSingleFileURL, atomically: true, encoding: .utf8)
            defer {
                try? FileManager.default.removeItem(at: sourceAsSingleFileURL)
            }
            
            SetEnvironmentVariable(TemplateOption.environmentVariableKey, rendererTemplateDirectory.path)
            XCTAssertThrowsError(try Docc.Convert.parse([
                sourceAsSingleFileURL.path,
            ]))
        }
        
        
        // Test no template folder does not throw
        do {
            UnsetEnvironmentVariable(TemplateOption.environmentVariableKey)
            XCTAssertNoThrow(try Docc.Convert.parse([
                sourceURL.path,
            ]))
        }
        
        // Test default template
        do {
            UnsetEnvironmentVariable(TemplateOption.environmentVariableKey)
            let tempFolder = try createTemporaryDirectory()
            let doccExecutableLocation = tempFolder
                .appendingPathComponent("bin")
                .appendingPathComponent("docc-executable-name")
            let defaultTemplateDir = tempFolder
                .appendingPathComponent("share")
                .appendingPathComponent("docc")
                .appendingPathComponent("render", isDirectory: true)
            let originalDoccExecutableLocation = TemplateOption.doccExecutableLocation
            
            TemplateOption.doccExecutableLocation = doccExecutableLocation
            defer {
                TemplateOption.doccExecutableLocation = originalDoccExecutableLocation
            }
            try FileManager.default.createDirectory(at: defaultTemplateDir, withIntermediateDirectories: true, attributes: nil)
            defer {
                try? FileManager.default.removeItem(at: defaultTemplateDir)
            }
            try "".write(to: defaultTemplateDir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
            
            let convert = try Docc.Convert.parse([
                testBundleURL.path,
            ])
            XCTAssertEqual(
                convert.templateOption.templateURL?.standardizedFileURL,
                defaultTemplateDir.standardizedFileURL
            )
            let action = try ConvertAction(fromConvertCommand: convert)
            XCTAssertEqual(
                action.htmlTemplateDirectory?.standardizedFileURL,
                defaultTemplateDir.standardizedFileURL
            )
        }
        
        // Test bad template folder throws
        do {
            SetEnvironmentVariable(TemplateOption.environmentVariableKey, URL(fileURLWithPath: "123").path)
            XCTAssertThrowsError(try Docc.Convert.parse([
                sourceURL.path,
            ]))
        }
        
        // Test default target folder.
        do {
            SetEnvironmentVariable(TemplateOption.environmentVariableKey, rendererTemplateDirectory.path)
            let parseResult = try Docc.Convert.parse([
                sourceURL.path,
            ])
            
            XCTAssertEqual(parseResult.outputURL, sourceURL.appendingPathComponent(".docc-build"))
        }
    }

    func testDefaultCurrentWorkingDirectory() {
        SetEnvironmentVariable(TemplateOption.environmentVariableKey, testTemplateURL.path)

        XCTAssertTrue(
            FileManager.default.changeCurrentDirectoryPath(testBundleURL.path),
            "The test env is invalid if the current working directory is not set to the current working directory"
        )

        do {
            // Passing no argument should default to the current working directory.
            let convert = try Docc.Convert.parse([])
            let convertAction = try ConvertAction(fromConvertCommand: convert)
            XCTAssertEqual(convertAction.rootURL?.absoluteURL, testBundleURL.absoluteURL)
        } catch {
            XCTFail("Failed to run docc convert without arguments.")
        }
    }

    func testInvalidTargetPathOptions() throws {
        let fakeRootPath = "/nonexistentrootfolder/subfolder"
        // Test throws on non-existing parent folder.
        for outputOption in ["-o", "--output-path"] {
            for path in ["/tmp/output", "/tmp", "/"] {
                SetEnvironmentVariable(TemplateOption.environmentVariableKey, testTemplateURL.path)
                XCTAssertThrowsError(try Docc.Convert.parse([
                    outputOption, fakeRootPath + path,
                    testBundleURL.path,
                ]), "Did not refuse target folder path '\(path)'")
            }
        }
    }

    func testAnalyzerIsTurnedOffByDefault() throws {
        SetEnvironmentVariable(TemplateOption.environmentVariableKey, testTemplateURL.path)
        let convertOptions = try Docc.Convert.parse([
            testBundleURL.path,
        ])
        
        XCTAssertFalse(convertOptions.analyze)
    }
    
    func testInfoPlistFallbacks() throws {
        SetEnvironmentVariable(TemplateOption.environmentVariableKey, testTemplateURL.path)
        
        // Default to nil when not passed
        do {
            let convertOptions = try Docc.Convert.parse([
                testBundleURL.path,
            ])
            
            XCTAssertNil(convertOptions.fallbackBundleDisplayName)
            XCTAssertNil(convertOptions.fallbackBundleIdentifier)
            XCTAssertNil(convertOptions.defaultCodeListingLanguage)
        }
        
        // Are set when passed (old name, to be removed rdar://72449411)
        do {
            let convertOptions = try Docc.Convert.parse([
                testBundleURL.path,
                "--display-name", "DisplayName",
                "--bundle-identifier", "com.example.test",
                "--bundle-version", "1.2.3",
                "--default-code-listing-language", "swift",
            ])
            
            XCTAssertEqual(convertOptions.fallbackBundleDisplayName, "DisplayName")
            XCTAssertEqual(convertOptions.fallbackBundleIdentifier, "com.example.test")
            XCTAssertEqual(convertOptions.defaultCodeListingLanguage, "swift")
        }
        
        // Are set when passed
        do {
            let convertOptions = try Docc.Convert.parse([
                testBundleURL.path,
                "--fallback-display-name", "DisplayName",
                "--fallback-bundle-identifier", "com.example.test",
                "--fallback-bundle-version", "1.2.3",
                "--default-code-listing-language", "swift",
            ])
            
            XCTAssertEqual(convertOptions.fallbackBundleDisplayName, "DisplayName")
            XCTAssertEqual(convertOptions.fallbackBundleIdentifier, "com.example.test")
            XCTAssertEqual(convertOptions.defaultCodeListingLanguage, "swift")
        }
    }
    
    func testAdditionalSymbolGraphFiles() throws {
        SetEnvironmentVariable(TemplateOption.environmentVariableKey, testTemplateURL.path)
        
        // Default to [] when not passed
        do {
            let convertOptions = try Docc.Convert.parse([
                testBundleURL.path,
            ])
            
            XCTAssertEqual(convertOptions.additionalSymbolGraphDirectory, nil)
        }
        
        // Is set when passed
        do {
            let convertOptions = try Docc.Convert.parse([
                testBundleURL.path,
                "--additional-symbol-graph-dir",
                "/path/to/folder-of-symbol-graph-files",
            ])
            
            XCTAssertEqual(
                convertOptions.additionalSymbolGraphDirectory,
                URL(fileURLWithPath: "/path/to/folder-of-symbol-graph-files")
            )
        }
        
        // Is recursively scanned to find symbol graph files set when passed
        do {
            let convertOptions = try Docc.Convert.parse([
                testBundleURL.path,
                "--additional-symbol-graph-dir",
                testBundleURL.path,
            ])
            
            let action = try ConvertAction(fromConvertCommand: convertOptions)
            XCTAssertEqual(action.converter.bundleDiscoveryOptions.additionalSymbolGraphFiles.map { $0.lastPathComponent }.sorted(), [
                "FillIntroduced.symbols.json",
                "MyKit@SideKit.symbols.json",
                "mykit-iOS.symbols.json",
                "sidekit.symbols.json",
            ])
        }
        
        // Deprecated option is still supported
        do {
            let convertOptions = try Docc.Convert.parse([
                testBundleURL.path,
                "--additional-symbol-graph-files",
                "/path/to/first.symbols.json",
                "/path/to/second.symbols.json",
            ])
            
            XCTAssertEqual(convertOptions.additionalSymbolGraphFiles, [
                URL(fileURLWithPath: "/path/to/first.symbols.json"),
                URL(fileURLWithPath: "/path/to/second.symbols.json"),
            ])
            
            let action = try ConvertAction(fromConvertCommand: convertOptions)
            XCTAssertEqual(action.converter.bundleDiscoveryOptions.additionalSymbolGraphFiles, [
                URL(fileURLWithPath: "/path/to/first.symbols.json"),
                URL(fileURLWithPath: "/path/to/second.symbols.json"),
            ])
        }
    }
    
    func testIndex() throws {
        SetEnvironmentVariable(TemplateOption.environmentVariableKey, testTemplateURL.path)
        
        let convertOptions = try Docc.Convert.parse([
            testBundleURL.path,
            "--index",
        ])
        
        XCTAssertTrue(convertOptions.emitLMDBIndex)
        
        let action = try ConvertAction(fromConvertCommand: convertOptions)
        
        XCTAssertEqual(action.buildLMDBIndex, true)
    }
    
    func testEmitLMDBIndex() throws {
        let convertOptions = try Docc.Convert.parse([
            testBundleURL.path,
            "--emit-lmdb-index",
        ])
        
        XCTAssertTrue(convertOptions.emitLMDBIndex)
        
        let action = try ConvertAction(fromConvertCommand: convertOptions)
        
        XCTAssertTrue(action.buildLMDBIndex)
    }
    
    func testWithoutBundle() throws {
        SetEnvironmentVariable(TemplateOption.environmentVariableKey, testTemplateURL.path)
        
        let convertOptions = try Docc.Convert.parse([
            "--fallback-display-name", "DisplayName",
            "--fallback-bundle-identifier", "com.example.test",
            "--fallback-bundle-version", "1.2.3",
            
            "--additional-symbol-graph-dir",
            testBundleURL.path,
        ])
        
        // Verify the options
        
        XCTAssertNil(convertOptions.documentationCatalog.url)
        
        XCTAssertEqual(convertOptions.fallbackBundleDisplayName, "DisplayName")
        XCTAssertEqual(convertOptions.fallbackBundleIdentifier, "com.example.test")
        
        XCTAssertEqual(
            convertOptions.additionalSymbolGraphDirectory,
            testBundleURL
        )
        
        // Verify the action
        
        let action = try ConvertAction(fromConvertCommand: convertOptions)
        XCTAssertNil(action.rootURL)
        XCTAssertNil(action.converter.rootURL)
        
        XCTAssertEqual(action.converter.bundleDiscoveryOptions.additionalSymbolGraphFiles.map { $0.lastPathComponent }.sorted(), [
            "FillIntroduced.symbols.json",
            "MyKit@SideKit.symbols.json",
            "mykit-iOS.symbols.json",
            "sidekit.symbols.json",
        ])
    }

    func testExperimentalEnableCustomTemplatesFlag() throws {
        let commandWithoutFlag = try Docc.Convert.parse([testBundleURL.path])
        let actionWithoutFlag = try ConvertAction(fromConvertCommand: commandWithoutFlag)
        XCTAssertFalse(commandWithoutFlag.experimentalEnableCustomTemplates)
        XCTAssertFalse(actionWithoutFlag.experimentalEnableCustomTemplates)

        let commandWithFlag = try Docc.Convert.parse([
            "--experimental-enable-custom-templates",
            testBundleURL.path,
        ])
        let actionWithFlag = try ConvertAction(fromConvertCommand: commandWithFlag)
        XCTAssertTrue(commandWithFlag.experimentalEnableCustomTemplates)
        XCTAssertTrue(actionWithFlag.experimentalEnableCustomTemplates)
    }
    
    func testExperimentalEnableDeviceFrameSupportFlag() throws {
        let originalFeatureFlagsState = FeatureFlags.current
        
        defer {
            FeatureFlags.current = originalFeatureFlagsState
        }
        
        let commandWithoutFlag = try Docc.Convert.parse([testBundleURL.path])
        _ = try ConvertAction(fromConvertCommand: commandWithoutFlag)
        XCTAssertFalse(commandWithoutFlag.enableExperimentalDeviceFrameSupport)
        XCTAssertFalse(FeatureFlags.current.isExperimentalDeviceFrameSupportEnabled)

        let commandWithFlag = try Docc.Convert.parse([
            "--enable-experimental-device-frame-support",
            testBundleURL.path,
        ])
        _ = try ConvertAction(fromConvertCommand: commandWithFlag)
        XCTAssertTrue(commandWithFlag.enableExperimentalDeviceFrameSupport)
        XCTAssertTrue(FeatureFlags.current.isExperimentalDeviceFrameSupportEnabled)
    }
    
    func testTransformForStaticHostingFlagWithoutHTMLTemplate() throws {
        UnsetEnvironmentVariable(TemplateOption.environmentVariableKey)
        
        // Since there's no custom template set (and relative HTML template lookup isn't
        // supported in the test harness), we expect `transformForStaticHosting` to
        // be false in every possible scenario of the flag, even when explicitly requested.
        
        do {
            let convertOptions = try Docc.Convert.parse([
                testBundleURL.path,
            ])
            
            XCTAssertFalse(convertOptions.transformForStaticHosting)
        }
        
        do {
            let convertOptions = try Docc.Convert.parse([
                testBundleURL.path,
                "--transform-for-static-hosting",
            ])
            
            XCTAssertFalse(convertOptions.transformForStaticHosting)
        }
        
        do {
            let convertOptions = try Docc.Convert.parse([
                testBundleURL.path,
                "--no-transform-for-static-hosting",
            ])
            
            XCTAssertFalse(convertOptions.transformForStaticHosting)
        }
    }
    
    func testTransformForStaticHostingFlagWithHTMLTemplate() throws {
        SetEnvironmentVariable(TemplateOption.environmentVariableKey, testTemplateURL.path)
        
        // Since we've provided an HTML template, we expect `transformForStaticHosting`
        // to be true by default, and when explicitly requested. It should only be false
        // when `--no-transform-for-static-hosting` is passed.
        
        do {
            let convertOptions = try Docc.Convert.parse([
                testBundleURL.path,
            ])
            
            XCTAssertTrue(convertOptions.transformForStaticHosting)
        }
        
        do {
            let convertOptions = try Docc.Convert.parse([
                testBundleURL.path,
                "--transform-for-static-hosting",
            ])
            
            XCTAssertTrue(convertOptions.transformForStaticHosting)
        }
        
        do {
            let convertOptions = try Docc.Convert.parse([
                testBundleURL.path,
                "--no-transform-for-static-hosting",
            ])
            
            XCTAssertFalse(convertOptions.transformForStaticHosting)
        }
    }
    
    func testTreatWarningAsrror() throws {
        SetEnvironmentVariable(TemplateOption.environmentVariableKey, testTemplateURL.path)
        do {
            // Passing no argument should default to the current working directory.
            let convert = try Docc.Convert.parse([])
            let convertAction = try ConvertAction(fromConvertCommand: convert)
            XCTAssertEqual(convertAction.treatWarningsAsErrors, false)
        } catch {
            XCTFail("Failed to run docc convert without arguments.")
        }
        do {
            // Passing no argument should default to the current working directory.
            let convert = try Docc.Convert.parse([
                "--warnings-as-errors"
            ])
            let convertAction = try ConvertAction(fromConvertCommand: convert)
            XCTAssertEqual(convertAction.treatWarningsAsErrors, true)
        } catch {
            XCTFail("Failed to run docc convert without arguments.")
        }
    }
}
