/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2022 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation
import Markdown

public final class TabNavigator: Semantic, AutomaticDirectiveConvertible {
    public let originalMarkup: BlockDirective
    
    @ChildDirective(requirements: .oneOrMore)
    public private(set) var tabs: [Tab]
    
    static var keyPaths: [String : AnyKeyPath] = [
        "tabs" : \TabNavigator._tabs,
    ]
    
    @available(*, deprecated, message: "Do not call directly. Required for 'AutomaticDirectiveConvertible'.")
    init(originalMarkup: BlockDirective) {
        self.originalMarkup = originalMarkup
    }
}
