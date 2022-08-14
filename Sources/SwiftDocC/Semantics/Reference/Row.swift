/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2022 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation
import Markdown

public final class Row: Semantic, AutomaticDirectiveConvertible {
    public let originalMarkup: BlockDirective
    
    @DirectiveArgumentWrapped
    public private(set) var numberOfColumns: Int? = nil
    
    @ChildDirective(requirements: .oneOrMore)
    public private(set) var columns: [Column]
    
    static var keyPaths: [String : AnyKeyPath] = [
        "numberOfColumns"   : \Row._numberOfColumns,
        "columns"           : \Row._columns,
    ]
    
    func validate(
        source: URL?,
        for bundle: DocumentationBundle,
        in context: DocumentationContext,
        problems: inout [Problem]
    ) -> Bool {
        let containsColumnWithSpecificSize = columns.contains { column in
            column.size != nil
        }
        
        if containsColumnWithSpecificSize && numberOfColumns == nil {
            let diagnostic = Diagnostic(
                source: source,
                severity: .warning,
                range: originalMarkup.nameRange,
                identifier: "org.swift.docc.Row.MissingNumberOfColumns",
                summary: "Missing required 'numberOfColumns' argument",
                explanation: """
                    The 'numberOfColumns' argument must be provided when creating a 'Row' \
                    that contains a 'Column' directive with a specified 'size'.
                    """
            )
            
            problems.append(Problem(diagnostic: diagnostic))
        }
        
        return true
    }
    
    @available(*, deprecated, message: "Do not call directly. Required for 'AutomaticDirectiveConvertible'.")
    init(originalMarkup: BlockDirective) {
        self.originalMarkup = originalMarkup
    }
}
