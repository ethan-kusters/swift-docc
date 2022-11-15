/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import ArgumentParser
import Foundation
import SwiftDocCUtilities

@main
struct ValidateOpenAPISpecs {
    static let testableSpecs: [DocCOpenAPISpec] = [
        renderIndexSpec,
        linkableEntitiesSpec,
        metadataSpec,
        indexingRecordsSpec,
        // TODO: Fix the RenderNode spec and enable this test.
        //  renderNodeSpec,
    ]
    
    static func main() throws {
        guard let schemaValidator = Bundle.module.url(forResource: "OpenAPISchemaValidator", withExtension: nil) else {
            fatalError("Failed to find 'OpenAPISchemaValidator' in bundle resources.")
        }
        
        // Install open api schema validator requirements into the local directory.
        try shell(
            "pip3 install -r requirements.txt -t .",
            workingDirectory: schemaValidator,
            suppressOutput: true,
            requireSuccess: true
        )
        
        guard let mixedLanguageFrameworkCatalog = Bundle.module.url(
            forResource: "MixedLanguageFramework",
            withExtension: "docc",
            subdirectory: "Fixtures"
        ) else {
            fatalError("Failed to find 'MixedLanguageFramework.docc' text fixture in bundle resources.")
        }
        
        let outputDirectory = temporaryDirectory
            .appendingPathComponent("MixedLanguageFramework.doccarchive", isDirectory: true)
        
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        
        setenv("DOCC_JSON_PRETTYPRINT", "YES", 1)
        let convertCommand = try Docc.Convert.parse(
            [
                mixedLanguageFrameworkCatalog.path,
                "--emit-digest",
                "--output-path", outputDirectory.path,
                "--no-transform-for-static-hosting"
            ]
        )
        
        var convertAction = try ConvertAction(fromConvertCommand: convertCommand)
        let result = try convertAction.perform(logHandle: .none)
        guard !result.didEncounterError, let generatedDocCArchive = result.outputs.first else {
            print(result.problems)
            fatalError("Failed to convert 'MixedLanguageFramework.docc' test fixture into a DocC archive.")
        }
        
        var encounteredFailure = false
        
        print()
        print(String(repeating: "-", count: 50), terminator: "\n\n")
        
        for spec in testableSpecs {
            let specURL = swiftDocCSpecsDirectory
                .appendingPathComponent(spec.fileName, isDirectory: false)
                .appendingPathExtension("json")
            
            let specName = spec.fileName.split(separator: ".").first!
            
            print("Beginning validation for \(specURL.path)")
            
            for conformingJSON in try spec.conformingJSONInDocCArchive(generatedDocCArchive) {
                print("Validating \(conformingJSON.path) against \(spec.fileName):", terminator: "\n\n")
                
                let validationExitStatus = try shell(
                    "python3 validate.py \(specURL.path) \(conformingJSON.path) \(specName)",
                    workingDirectory: schemaValidator
                )
                
                print()
                
                guard validationExitStatus == EXIT_SUCCESS else {
                    encounteredFailure = true
                    break
                }
            }
            
            print(String(repeating: "-", count: 50), terminator: "\n\n")
        }
        
        guard !encounteredFailure else {
            exit(EXIT_FAILURE)
        }
    }
}

struct DocCOpenAPISpec {
    /// The file name for this spec.
    let fileName: String
    
    /// A closure that returns all of the JSON documents that should conform to this spec
    /// in a given DocC archive.
    let conformingJSONInDocCArchive: (_ doccArchive: URL) throws -> [URL]
}

let renderIndexSpec = DocCOpenAPISpec(
    fileName: "RenderIndex.spec",
    conformingJSONInDocCArchive: { archiveURL in
        return [
            archiveURL
                .appendingPathComponent("index", isDirectory: true)
                .appendingPathComponent("index", isDirectory: false)
                .appendingPathExtension("json")
        ]
    }
)

let linkableEntitiesSpec = DocCOpenAPISpec(
    fileName: "LinkableEntities",
    conformingJSONInDocCArchive: { archiveURL in
        return [
            archiveURL
                .appendingPathComponent("linkable-entities", isDirectory: false)
                .appendingPathExtension("json")
        ]
    }
)

let metadataSpec = DocCOpenAPISpec(
    fileName: "Metadata",
    conformingJSONInDocCArchive: { archiveURL in
        return [
            archiveURL
                .appendingPathComponent("metadata", isDirectory: false)
                .appendingPathExtension("json")
        ]
    }
)

let indexingRecordsSpec = DocCOpenAPISpec(
    fileName: "IndexingRecords.spec",
    conformingJSONInDocCArchive: { archiveURL in
        return [
            archiveURL
                .appendingPathComponent("indexing-records", isDirectory: false)
                .appendingPathExtension("json")
        ]
    }
)

let renderNodeSpec = DocCOpenAPISpec(
    fileName: "RenderNode.spec",
    conformingJSONInDocCArchive: { archiveURL in
        let dataDirectory = archiveURL.appendingPathComponent("data", isDirectory: true)
        
        return FileManager.default.enumerator(
            at: dataDirectory,
            includingPropertiesForKeys: nil
        )!
        .compactMap { $0 as? URL }
        .filter { $0.pathExtension.lowercased() == "json" }
    }
)

let swiftDocCSpecsDirectory = URL(fileURLWithPath: #file)
    .deletingLastPathComponent() // Sources
    .deletingLastPathComponent() // validate-openapi-specs
    .deletingLastPathComponent() // bin
    .deletingLastPathComponent() // swift-docc
    .appendingPathComponent("Sources", isDirectory: true)
    .appendingPathComponent("SwiftDocC", isDirectory: true)
    .appendingPathComponent("SwiftDocC.docc", isDirectory: true)
    .appendingPathComponent("Resources", isDirectory: true)

var temporaryDirectory: URL {
    let directory = Bundle.module.resourceURL!.appendingPathComponent("TemporaryOutputDirectory", isDirectory: true)
    
    try? FileManager.default.removeItem(at: directory)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    
    return directory
}

@discardableResult
func shell(
    _ command: String,
    workingDirectory: URL,
    suppressOutput: Bool = false,
    requireSuccess: Bool = false
) throws -> Int {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"]!)
    process.arguments = ["-c", command]
    process.currentDirectoryURL = workingDirectory
    
    if suppressOutput {
        process.standardOutput = nil
        process.standardError = nil
    }
    
    try process.run()
    process.waitUntilExit()
    
    guard requireSuccess else {
        return Int(process.terminationStatus)
    }
    
    guard process.terminationStatus == EXIT_SUCCESS else {
        fatalError("'\(command)' terminated unsuccessfully.")
    }
    
    return Int(process.terminationStatus)
}
