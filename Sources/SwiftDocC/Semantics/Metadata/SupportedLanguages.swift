//
//  File.swift
//  
//
//  Created by Ethan Kusters on 1/12/23.
//

import Foundation
import Markdown

public final class SupportedLanguages: Semantic, AutomaticDirectiveConvertible {
    public let originalMarkup: BlockDirective
    
    @DirectiveArgumentWrapped(name: .unnamed)
    public var languages: [String]
    
    static var keyPaths: [String : AnyKeyPath] = [
        "languages" : \SupportedLanguages._languages,
    ]
    
    @available(*, deprecated, message: "Do not call directly. Required for 'AutomaticDirectiveConvertible'.")
    init(originalMarkup: BlockDirective) {
        self.originalMarkup = originalMarkup
    }
}
