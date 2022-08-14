/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation
import Markdown

/**
 An instructional step to complete as a part of a ``TutorialSection``. ``DirectiveConvertible``
 */
public final class Step: Semantic, AutomaticDirectiveConvertible {
    /// The original `Markup` node that was parsed into this semantic step,
    /// or `nil` if it was created elsewhere.
    public let originalMarkup: BlockDirective
    
    /// A piece of media associated with the step to display when selected.
    @ChildDirective
    public private(set) var image: ImageMedia? = nil
    
    @ChildDirective
    public private(set) var video: VideoMedia? = nil
    
    public var media: Media? {
        return image ?? video
    }
    
    /// A code file associated with the step to display when selected.
    @ChildDirective
    public private(set) var code: Code? = nil
    
    /// `Markup` content inside the step.
    @ChildMarkup(numberOfParagraphs: .custom(1))
    public private(set) var content: MarkupContainer
    
    /// The step's caption.
    @ChildMarkup(numberOfParagraphs: .zeroOrOne)
    public private(set) var caption: MarkupContainer
    
    static var keyPaths: [String : AnyKeyPath] = [
        "image"     : \Step._image,
        "video"     : \Step._video,
        "code"      : \Step._code,
        "content"   : \Step._content,
        "caption"   : \Step._caption,
    ]
    
    override var children: [Semantic] {
        let contentChild: [Semantic] = [content]
        let captionChild: [Semantic] = [caption]
        let codeChild: [Semantic] = code.map { [$0] } ?? []
        return contentChild + captionChild + codeChild
    }
    
    init(originalMarkup: BlockDirective, media: Media?, code: Code?, content: MarkupContainer, caption: MarkupContainer) {
        self.originalMarkup = originalMarkup
        super.init()
        
        if let image = media as? ImageMedia {
            self.image = image
        } else if let video = media as? VideoMedia {
            self.video = video
        }
        
        self.code = code
        self.content = content
        self.caption = caption
    }
    
    @available(*, deprecated, message: "Do not call directly. Required for 'AutomaticDirectiveConvertible'.")
    init(originalMarkup: BlockDirective) {
        self.originalMarkup = originalMarkup
    }
    
    func validate(
        source: URL?,
        for bundle: DocumentationBundle,
        in context: DocumentationContext,
        problems: inout [Problem]
    ) -> Bool {
        _ = Semantic.Analyses.HasExactlyOneMedia<Step>(severityIfNotFound: nil).analyze(
            originalMarkup,
            children: originalMarkup.children,
            source: source,
            for: bundle,
            in: context,
            problems: &problems
        )
        
        return true
    }
    
    func parseChildMarkup(
        from children: MarkupContainer,
        source: URL?,
        for bundle: DocumentationBundle,
        in context: DocumentationContext,
        problems: inout [Problem]
    ) -> Bool {
        var remainder = children
        
        let paragraphs: [Paragraph]
        (paragraphs, remainder) = Semantic.Analyses.ExtractAllMarkup<Paragraph>().analyze(originalMarkup, children: remainder, source: source, for: bundle, in: context, problems: &problems)
        
        let content: MarkupContainer
        let caption: MarkupContainer
        
        func diagnoseExtraneousContent(element: Markup) -> Problem {
            let diagnostic = Diagnostic(source: source, severity: .warning, range: element.range, identifier: "org.swift.docc.\(Step.self).ExtraneousContent", summary: "Extraneous element: \(Step.directiveName.singleQuoted) directive should only have a single paragraph for its instructional content and an optional paragraph to serve as a caption")
            let solutions = element.range.map {
                return [Solution(summary: "Remove extraneous element", replacements: [Replacement(range: $0, replacement: "")])]
            } ?? []
            return Problem(diagnostic: diagnostic, possibleSolutions: solutions)
        }
        
        // The first paragraph participates in the step's main `content`.
        // The second paragraph becomes the step's caption.
        // Only ``Aside``s may also additionally participate in the step's main `content`.
        
        switch paragraphs.count {
        case 0:
            content = MarkupContainer()
            caption = MarkupContainer()
        case 1:
            content = MarkupContainer(paragraphs[0])
            caption = MarkupContainer()
        case 2:
            content = MarkupContainer(paragraphs[0])
            caption = MarkupContainer(paragraphs[1])
        default:
            content = MarkupContainer(paragraphs[0])
            caption = MarkupContainer(paragraphs[1])
            for extraneousElement in paragraphs.suffix(from: 2) {
                problems.append(diagnoseExtraneousContent(element: extraneousElement))
            }
        }
        
        let blockQuotes: [BlockQuote]
        (blockQuotes, remainder) = Semantic.Analyses.ExtractAllMarkup<BlockQuote>().analyze(originalMarkup, children: remainder, source: source, for: bundle, in: context, problems: &problems)
        
        for extraneousElement in remainder {
            guard (extraneousElement as? BlockDirective)?.name != Comment.directiveName else {
                continue
            }
            problems.append(diagnoseExtraneousContent(element: extraneousElement))
        }
        
        if content.isEmpty {
            let diagnostic = Diagnostic(source: source, severity: .warning, range: originalMarkup.range, identifier: "org.swift.docc.HasContent", summary: "\(Step.directiveName.singleQuoted) has no content; \(Step.directiveName.singleQuoted) directive should at least have an instructional sentence")
            problems.append(Problem(diagnostic: diagnostic, possibleSolutions: []))
        }
        
        self.content = content
        self.caption = MarkupContainer(caption.elements + blockQuotes as [Markup])
        
        return true
    }
    
    public override func accept<V: SemanticVisitor>(_ visitor: inout V) -> V.Result {
        return visitor.visitStep(self)
    }
}

