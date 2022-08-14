/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation
import Markdown

/// A multiple-choice question.
///
/// A collection of multiple-choice questions that form an ``Assessments``.
public final class MultipleChoice: Semantic, AutomaticDirectiveConvertible {
    /// The phrasing of the question.
    @ChildMarkup(numberOfParagraphs: .custom(1), index: 0)
    public private(set) var questionPhrasing: MarkupContainer
    
    public let originalMarkup: BlockDirective
    
    /// Additional introductory content.
    ///
    /// Typically, this content represents a question's code block.
    @ChildMarkup(numberOfParagraphs: .zeroOrMore, index: 1)
    public private(set) var content: MarkupContainer
    
    /// An optional image associated with the question's introduction.
    @ChildDirective
    public private(set) var image: ImageMedia? = nil
    
    /// The possible answers to the question.
    @ChildDirective
    public private(set) var choices: [Choice]
    
    static var keyPaths: [String : AnyKeyPath] = [
        "questionPhrasing"  : \MultipleChoice._questionPhrasing,
        "content"           : \MultipleChoice._content,
        "image"             : \MultipleChoice._image,
        "choices"           : \MultipleChoice._choices,
    ]
    
    override var children: [Semantic] {
        var elements: [Semantic] = [content]
        if let image = image {
            elements.append(image)
        }
        elements.append(contentsOf: choices)
        return elements
    }
    
    init(originalMarkup: BlockDirective, questionPhrasing: MarkupContainer, content: MarkupContainer, image: ImageMedia?, choices: [Choice]) {
        self.originalMarkup = originalMarkup
        super.init()
        self.questionPhrasing = questionPhrasing
        self.content = content
        self.image = image
        self.choices = choices
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
        if choices.count < 2 || choices.count > 4 {
            let diagnostic = Diagnostic(source: source, severity: .warning, range: originalMarkup.range, identifier: "org.swift.docc.\(MultipleChoice.self).CorrectNumberOfChoices", summary: "`\(MultipleChoice.directiveName)` should contain 2-4 `\(Choice.directiveName)` child directives")
            problems.append(Problem(diagnostic: diagnostic, possibleSolutions: []))
        }
        
        let correctAnswers = choices.filter({ $0.isCorrect })
        
        if correctAnswers.isEmpty {
            let diagnostic = Diagnostic(source: source, severity: .warning, range: originalMarkup.range, identifier: "org.swift.docc.\(MultipleChoice.self).CorrectChoiceProvided", summary: "`\(MultipleChoice.directiveName)` should contain `\(Choice.directiveName)` directive marked as the correct option")
            problems.append(Problem(diagnostic: diagnostic, possibleSolutions: []))
        } else if correctAnswers.count > 1 {
            var diagnostic = Diagnostic(source: source, severity: .warning, range: originalMarkup.range, identifier: "org.swift.docc.\(MultipleChoice.self).MultipleCorrectChoicesProvided", summary: "`\(MultipleChoice.directiveName)` should contain exactly one `\(Choice.directiveName)` directive marked as the correct option")
            for answer in correctAnswers {
                guard let range = answer.originalMarkup.nameRange else {
                    continue
                }
                if let source = source {
                    let note = DiagnosticNote(source: source, range: range, message: "This `\(Choice.directiveName)` directive is marked as the correct option")
                    diagnostic.notes.append(note)
                }
            }
            problems.append(Problem(diagnostic: diagnostic, possibleSolutions: []))
        }
        
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
        
        let requiredPhrasing: Paragraph?
        if let paragraph = remainder.first as? Paragraph {
            requiredPhrasing = paragraph
            remainder = MarkupContainer(remainder.elements.suffix(from: 1))
        } else {
            let diagnostic = Diagnostic(source: source, severity: .warning, range: originalMarkup.range, identifier: "org.swift.docc.\(MultipleChoice.self).missingPhrasing", summary: " \(MultipleChoice.directiveName.singleQuoted) directive is missing its initial paragraph that serves as a question's title phrasing")
            problems.append(Problem(diagnostic: diagnostic, possibleSolutions: []))
            requiredPhrasing = nil
        }
        
        let codeBlocks = children.compactMap { $0 as? CodeBlock }
        
        if codeBlocks.count > 1 {
            for extraneousCode in codeBlocks.suffix(from: 1) {
                guard let range = extraneousCode.range else {
                    continue
                }
                let diagnostic = Diagnostic(source: source, severity: .warning, range: originalMarkup.range, identifier: "org.swift.docc.\(MultipleChoice.self).ExtraneousCode", summary: "`\(MultipleChoice.directiveName)` may contain only one markup code block following the question's phrasing.")
                problems.append(Problem(diagnostic: diagnostic, possibleSolutions: [removeExtraneous("code block", range: range)]))
            }
        }
        
        func removeExtraneous(_ elementName: String, range: SourceRange) -> Solution {
            return Solution(summary: "Remove extraneous code", replacements: [
                Replacement(range: range, replacement: "")
            ])
        }
        
        if codeBlocks.count == 1, let image = image {
            let codeBlock = codeBlocks.first!
            let diagnostic = Diagnostic(source: source, severity: .warning, range: originalMarkup.range, identifier: "org.swift.docc.\(MultipleChoice.self).CodeOrImage", summary: "`\(MultipleChoice.directiveName)` may contain an `\(ImageMedia.directiveName)` or markup code block following the question's phrasing")
            let solutions = [
                codeBlock.range.map { range -> Solution in
                    removeExtraneous("code", range: range)
                },
                image.originalMarkup.range.map { range -> Solution in
                    removeExtraneous(ImageMedia.directiveName, range: range)
                },
            ].compactMap { $0 }
            problems.append(Problem(diagnostic: diagnostic, possibleSolutions: solutions))
        }
        
        guard let questionPhrasing = requiredPhrasing else {
            return false
        }
        
        self.questionPhrasing = MarkupContainer(questionPhrasing)
        self.content = remainder
        
        return true
    }
    
    public override func accept<V: SemanticVisitor>(_ visitor: inout V) -> V.Result {
        return visitor.visitMultipleChoice(self)
    }
}
