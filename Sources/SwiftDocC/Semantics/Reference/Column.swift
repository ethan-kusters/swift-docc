/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2022 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation
import Markdown

public final class Column: Semantic, AutomaticDirectiveConvertible {
    public let originalMarkup: BlockDirective
    
    @DirectiveArgumentWrapped
    public private(set) var size: Int? = nil
    
    @ChildMarkup(numberOfParagraphs: .oneOrMore)
    public private(set) var content: MarkupContainer
    
    static var keyPaths: [String : AnyKeyPath] = [
        "size"      : \Column._size,
        "content"   : \Column._content,
    ]
    
    @available(*, deprecated, message: "Do not call directly. Required for 'AutomaticDirectiveConvertible'.")
    init(originalMarkup: BlockDirective) {
        self.originalMarkup = originalMarkup
    }
}
