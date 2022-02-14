/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2022 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import SymbolKit

/// A navigation index of the content in a DocC archive.
///
/// The structure of this data is determined by the topic groups authored in
/// the processed documentation content.
///
/// This is an alternative representation of the data that is also handled by the
/// ``NavigatorIndex`` in a ``NavigatorTree``. This index is specifically designed to be emitted
/// to disk as JSON file and implements the Index JSON spec.
///
/// An OpenAPI specification for Index is available in the repo at
/// `Sources/SwiftDocC/SwiftDocC.docc/Resources/Index.spec.json`.
public struct Index: Codable, Equatable {
    /// The current schema version of the Index JSON spec.
    public static let currentSchemaVersion = SemanticVersion(major: 0, minor: 1, patch: 0)
    
    /// The version of the Index JSON spec that was followed when creating this Index.
    public let schemaVersion: SemanticVersion
    
    /// A mapping of interface languages to the index nodes they contain.
    public let interfaceLanguages: [String: [Node]]
    
    /// Creates a new Index with the given interface language to node mapping.
    public init(
        interfaceLanguages: [String: [Node]]
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.interfaceLanguages = interfaceLanguages
    }
}

extension Index {
    /// A documentation node in a navigator index.
    public struct Node: Codable, Hashable {
        /// The title of the node, suitable for presentation.
        public let title: String
        
        /// The relative path to the page represented by this node.
        public let path: String?
        
        /// The type of this node.
        ///
        /// This type can be used to determine what icon to display for this node.
        public let type: String?
        
        /// The children of this node.
        public let children: [Node]?
        
        /// A Boolean value that is true if the current node belongs to an external
        /// documentation archive.
        ///
        /// Allows renderers to use a specific design treatment for index nodes
        /// that lead to external documentation content.
        public let isExternal: Bool

        enum CodingKeys: String, CodingKey {
            case title
            case path
            case type
            case children
            case isExternal
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            
            try container.encode(title, forKey: .title)
            
            try container.encodeIfPresent(path, forKey: .path)
            try container.encodeIfPresent(type, forKey: .type)
            try container.encodeIfPresent(children, forKey: .children)
            
            // `isExternal` defaults to false so only encode it if it's true
            if isExternal {
                try container.encode(isExternal, forKey: .isExternal)
            }
        }
        
        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            
            title = try values.decode(String.self, forKey: .title)
            
            path = try values.decodeIfPresent(String.self, forKey: .path)
            type = try values.decodeIfPresent(String.self, forKey: .type)
            children = try values.decodeIfPresent([Node].self, forKey: .children)
            
            // `isExternal` defaults to false if it's not specified
            isExternal = try values.decodeIfPresent(Bool.self, forKey: .isExternal) ?? false
        }
        
        /// Creates a new node with the given title, path, type, and children.
        ///
        /// - Parameters:
        ///   - title: The title of the node, suitable for presentation.
        ///   - path: The relative path to the page represented by this node.
        ///   - type: The type of this node.
        ///   - children: The children of this node.
        ///   - isExternal: If the current node belongs to an external
        ///     documentation archive.
        public init(
            title: String,
            path: String?,
            type: String,
            children: [Node]?,
            isExternal: Bool
        ) {
            self.title = title
            self.path = path
            self.type = type
            self.children = children
            self.isExternal = isExternal
        }
        
        init(
            title: String,
            path: String,
            pageType: NavigatorIndex.PageType?,
            children: [Node]
        ) {
            self.title = title
            self.children = children.isEmpty ? nil : children
            
            // Currently Swift-DocC doesn't support resolving links to external DocC archives
            // so we default to `false` here.
            self.isExternal = false
            
            guard let pageType = pageType else {
                self.type = nil
                self.path = path
                return
            }
            
            self.type = pageType.indexPageType
            
            if pageType.pathShouldBeIncludedInIndex {
                self.path = path
            } else {
                self.path = nil
            }
        }
    }
}

extension Index {
    static func fromNavigatorIndex(_ navigatorIndex: NavigatorIndex) -> Index {
        // The immediate children of the root represent the interface languages
        // described in this navigator tree.
        let interfaceLanguageRoots = navigatorIndex.navigatorTree.root.children
        
        let languageMaskToLanguage = navigatorIndex.languageMaskToLanguage
        
        return Index(
            interfaceLanguages: Dictionary(
                interfaceLanguageRoots.compactMap { interfaceLanguageRoot in
                    // If an interface language in the given navigator tree does not exist
                    // in the given language mask to language mapping, something has gone wrong
                    // and we should crash.
                    let languageID = languageMaskToLanguage[interfaceLanguageRoot.item.languageID]!.id
                    
                    return (
                        language: languageID,
                        children: interfaceLanguageRoot.children.map(Index.Node.fromNavigatorTreeNode)
                    )
                },
                uniquingKeysWith: +
            )
        )
    }
}

extension Index.Node {
    static func fromNavigatorTreeNode(_ node: NavigatorTree.Node) -> Index.Node {
        return Index.Node(
            title: node.item.title,
            path: node.item.path,
            pageType: NavigatorIndex.PageType(rawValue: node.item.pageType),
            children: node.children.map(Index.Node.fromNavigatorTreeNode)
        )
    }
}

extension NavigatorIndex.PageType {
    var pathShouldBeIncludedInIndex: Bool {
        switch self {
        case .root, .section, .groupMarker:
            return false
        default:
            return true
        }
    }
    
    var indexPageType: String {
        switch self {
        case .root:
            return "root"
        case .article:
            return RenderNode.Kind.article.rawValue
        case .tutorial:
            return RenderNode.Kind.tutorial.rawValue
        case .section:
            return RenderNode.Kind.section.rawValue
        case .learn:
            return "learn"
        case .overview:
            return RenderNode.Kind.overview.rawValue
        case .resources:
            return "resources"
        case .symbol:
            return  RenderNode.Kind.symbol.rawValue
        case .framework:
            return SymbolGraph.Symbol.KindIdentifier.module.identifier
        case .class:
            return SymbolGraph.Symbol.KindIdentifier.class.identifier
        case .structure:
            return SymbolGraph.Symbol.KindIdentifier.struct.identifier
        case .protocol:
            return SymbolGraph.Symbol.KindIdentifier.protocol.identifier
        case .enumeration:
            return SymbolGraph.Symbol.KindIdentifier.enum.identifier
        case .function:
            return SymbolGraph.Symbol.KindIdentifier.func.identifier
        case .extension:
            return "extension"
        case .localVariable, .globalVariable, .instanceVariable:
            return SymbolGraph.Symbol.KindIdentifier.var.identifier
        case .typeAlias:
            return SymbolGraph.Symbol.KindIdentifier.typealias.identifier
        case .associatedType:
            return SymbolGraph.Symbol.KindIdentifier.associatedtype.identifier
        case .operator:
            return SymbolGraph.Symbol.KindIdentifier.operator.identifier
        case .macro:
            return "macro"
        case .union:
            return "union"
        case .enumerationCase:
            return SymbolGraph.Symbol.KindIdentifier.case.identifier
        case .initializer:
            return SymbolGraph.Symbol.KindIdentifier.`init`.identifier
        case .instanceMethod:
            return SymbolGraph.Symbol.KindIdentifier.method.identifier
        case .instanceProperty:
            return SymbolGraph.Symbol.KindIdentifier.property.identifier
        case .subscript:
            return SymbolGraph.Symbol.KindIdentifier.subscript.identifier
        case .typeMethod:
            return SymbolGraph.Symbol.KindIdentifier.typeMethod.identifier
        case .typeProperty:
            return SymbolGraph.Symbol.KindIdentifier.typeProperty.identifier
        case .buildSetting:
            return "buildSetting"
        case .propertyListKey:
            return "propertyListKey"
        case .sampleCode:
            return "sampleCode"
        case .httpRequest:
            return "httpRequest"
        case .dictionarySymbol:
            return "dictionarySymbol"
        case .propertyListKeyReference:
            return "propertyListKeyReference"
        case .languageGroup:
            return "languageGroup"
        case .container:
            return "container"
        case .groupMarker:
            return "groupMarker"
        }
    }
}
