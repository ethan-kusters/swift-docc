/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation
import Markdown

func unresolvedReferenceProblem(reference: TopicReference, source: URL?, range: SourceRange?, severity: DiagnosticSeverity, uncuratedArticleMatch: URL?, underlyingErrorMessage: String) -> Problem {
    let notes = uncuratedArticleMatch.map {
        [DiagnosticNote(source: $0, range: SourceLocation(line: 1, column: 1, source: nil)..<SourceLocation(line: 1, column: 1, source: nil), message: "This article was found but is not available for linking because it's uncurated")]
    } ?? []
    
    let diagnostic = Diagnostic(source: source, severity: severity, range: range, identifier: "org.swift.docc.unresolvedTopicReference", summary: "Topic reference \(reference.description.singleQuoted) couldn't be resolved. \(underlyingErrorMessage)", notes: notes)
    return Problem(diagnostic: diagnostic, possibleSolutions: [])
}

func unresolvedResourceProblem(resource: ResourceReference, source: URL?, range: SourceRange?, severity: DiagnosticSeverity) -> Problem {
    let diagnostic = Diagnostic(source: source, severity: severity, range: range, identifier: "org.swift.docc.unresolvedResource", summary: "Resource \(resource.path.singleQuoted) couldn't be found")
    return Problem(diagnostic: diagnostic, possibleSolutions: [])
}

/**
 Rewrites a `Semantic` tree by attempting to resolve `.unresolved(UnresolvedTopicReference)` references using a `DocumentationContext`.
 */
struct ReferenceResolver: SemanticWalker {
    /// The context to use to resolve references.
    var context: DocumentationContext
    
    /// The bundle in which visited documents reside.
    var bundle: DocumentationBundle
    
    /// The source document being analyzed.
    var source: URL?
    
    /// Problems found while trying to resolve references.
    var problems = [Problem]()
    
    var rootReference: ResolvedTopicReference
    
    /// If the documentation is inherited, the reference of the parent symbol.
    var inheritanceParentReference: ResolvedTopicReference?
    
    init(context: DocumentationContext, bundle: DocumentationBundle, source: URL?, rootReference: ResolvedTopicReference? = nil, inheritanceParentReference: ResolvedTopicReference? = nil) {
        self.context = context
        self.bundle = bundle
        self.source = source
        self.rootReference = rootReference ?? bundle.rootReference
        self.inheritanceParentReference = inheritanceParentReference
    }
    
    @discardableResult
    mutating func resolve(_ reference: TopicReference, in parent: ResolvedTopicReference, range: SourceRange?, severity: DiagnosticSeverity) -> TopicReferenceResolutionResult {
        switch context.resolve(reference, in: parent) {
        case .success(let resolved):
            return .success(resolved)
            
        case let .failure(unresolved, errorMessage):
            // FIXME: Provide near-miss suggestion here. The user is likely to make mistakes with capitalization because of character input.
            let uncuratedArticleMatch = context.uncuratedArticles[bundle.documentationRootReference.appendingPathOfReference(unresolved)]?.source
            problems.append(unresolvedReferenceProblem(reference: reference, source: source, range: range, severity: severity, uncuratedArticleMatch: uncuratedArticleMatch, underlyingErrorMessage: errorMessage))
            return .failure(unresolved, errorMessage: errorMessage)
        }
    }
    
    /**
    Returns a ``Problem`` if the resource cannot be found; otherwise `nil`.
    */
    private func resolve(resource: ResourceReference, range: SourceRange?, severity: DiagnosticSeverity) -> Problem? {
        if !context.resourceExists(with: resource) {
            return unresolvedResourceProblem(resource: resource, source: source, range: range, severity: severity)
        } else {
            return nil
        }
    }
    
    mutating func visitStep(_ step: Step) {
        visitMarkupContainer(step.content)
        visitMarkupContainer(step.caption)
        if let media = step.media, let problem = resolve(resource: media.source, range: step.originalMarkup.range, severity: .warning) {
            problems.append(problem)
        }
        if let code = step.code, let problem = resolve(resource: code.fileReference, range: step.originalMarkup.range, severity: .warning) {
            problems.append(problem)
        }
    }
        
    mutating func visitTutorialSection(_ tutorialSection: TutorialSection) {
        visitMarkupLayouts(tutorialSection.introduction)
        tutorialSection.stepsContent.map { visitSteps($0) }
    }
    
    mutating func visitTutorial(_ tutorial: Tutorial) {
        tutorial.requirements.forEach { visitXcodeRequirement($0) }
        visitIntro(tutorial.intro)
        tutorial.sections.forEach { visitTutorialSection($0) }
        tutorial.assessments.map { visitAssessments($0) }
        tutorial.callToActionImage.map { visitImageMedia($0) }
        
        // Change the context of the project file to `download`
        if let projectFiles = tutorial.projectFiles,
            var resolvedDownload = context.resolveAsset(named: projectFiles.path, in: bundle.rootReference) {
            resolvedDownload.context = .download
            context.updateAsset(named: projectFiles.path, asset: resolvedDownload, in: bundle.rootReference)
        }
    }
    
    mutating func visitIntro(_ intro: Intro) {
        intro.image.map { visitImageMedia($0) }
        intro.video.map { visitVideoMedia($0) }
        visitMarkupContainer(intro.content)
    }
    
    mutating func visitAssessments(_ assessments: Assessments) {
        assessments.questions.forEach { visitMultipleChoice($0) }
    }
    
    mutating func visitMultipleChoice(_ multipleChoice: MultipleChoice) {
        visitMarkupContainer(multipleChoice.questionPhrasing)
        visitMarkupContainer(multipleChoice.content)
        multipleChoice.choices.forEach { visitChoice($0) }
    }
    
    mutating func visitJustification(_ justification: Justification) {
        visitMarkupContainer(justification.content)
    }
    
    mutating func visitChoice(_ choice: Choice) {
        visitMarkupContainer(choice.content)
        visitJustification(choice.justification)
    }
    
    mutating func visitMarkupContainer(_ markupContainer: MarkupContainer) {
        var markupResolver = MarkupReferenceResolver(context: context, bundle: bundle, source: source, rootReference: rootReference)
        let parent = inheritanceParentReference
        let context = self.context
        
        markupResolver.problemForUnresolvedReference = { unresolved, source, range, fromSymbolLink, underlyingErrorMessage -> Problem? in
            // Verify we have all the information about the location of the source comment
            // and the symbol that the comment is inherited from.
            if let parent = parent, let range = range,
                let symbol = try? context.entity(with: parent).symbol,
                let docLines = symbol.docComment,
                let docStartLine = docLines.lines.first?.range?.start.line,
                let docStartColumn = docLines.lines.first?.range?.start.character {
                
                switch context.resolve(.unresolved(unresolved), in: parent, fromSymbolLink: fromSymbolLink) {
                    case .success(let resolved):
                        
                        // Make the range for the suggested replacement.
                        let start = SourceLocation(line: docStartLine + range.lowerBound.line, column: docStartColumn + range.lowerBound.column, source: range.lowerBound.source)
                        let end = SourceLocation(line: docStartLine + range.upperBound.line, column: docStartColumn + range.upperBound.column, source: range.upperBound.source)
                        let replacementRange = SourceRange(uncheckedBounds: (lower: start, upper: end))
                        
                        // Return a warning with a suggested change that replaces the relative link with an absolute one.
                        return Problem(diagnostic: Diagnostic(source: source,
                            severity: .warning, range: range,
                            identifier: "org.swift.docc.UnresolvableLinkWhenInherited",
                            summary: "This documentation block is inherited by other symbols where \(unresolved.topicURL.absoluteString.singleQuoted) fails to resolve."),
                            possibleSolutions: [
                                Solution(summary: "Use an absolute link path.", replacements: [
                                    Replacement(range: replacementRange, replacement: "<doc:\(resolved.path)>")
                                ])
                            ])
                    default: break
                }
            }
            return nil
        }
        
        markupContainer.elements.forEach { markupResolver.visit($0) }
        problems.append(contentsOf: markupResolver.problems)
    }
    
    mutating func visitMarkup(_ markup: Markup) {
        // Wrap in a markup container and the first child of the result.
        visitMarkupContainer(MarkupContainer(markup))
    }
    
    mutating func visitTechnology(_ technology: Technology) {
        visitIntro(technology.intro)
        technology.volumes.forEach { visitVolume($0) }
        technology.resources.map { visitResources($0) }
    }
    
    mutating func visitImageMedia(_ imageMedia: ImageMedia) {
        if let problem = resolve(resource: imageMedia.source, range: imageMedia.originalMarkup.range, severity: .warning) {
            problems.append(problem)
        }
    }
    
    mutating func visitVideoMedia(_ videoMedia: VideoMedia) {
        if let problem = resolve(resource: videoMedia.source, range: videoMedia.originalMarkup.range, severity: .warning) {
            problems.append(problem)
        }
    }
    
    mutating func visitContentAndMedia(_ contentAndMedia: ContentAndMedia) {
        visitMarkupContainer(contentAndMedia.content)
        
        contentAndMedia.media.map { media in
            if let problem = resolve(resource: media.source, range: contentAndMedia.originalMarkup.range, severity: .warning) {
                problems.append(problem)
            }
        }
    }
    
    mutating func visitVolume(_ volume: Volume) {
        volume.content.map { visitMarkupContainer($0) }
        volume.image.map { visitImageMedia($0) }
        volume.chapters.forEach { visitChapter($0) }
    }
    
    mutating func visitChapter(_ chapter: Chapter) {
        visitMarkupContainer(chapter.content)
        chapter.image.map { visitImageMedia($0) }
        chapter.topicReferences.forEach { visitTutorialReference($0) }
        
        var uniqueReferences = Set<TopicReference>()
        for newTutorialReference in chapter.topicReferences {
            guard !uniqueReferences.contains(newTutorialReference.topic) else {
                let diagnostic = Diagnostic(source: source, severity: .warning, range: newTutorialReference.originalMarkup.range, identifier: "org.swift.docc.\(Chapter.self).Duplicate\(TutorialReference.self)", summary: "Duplicate \(TutorialReference.directiveName.singleQuoted) directive refers to \(newTutorialReference.topic.description.singleQuoted)")
                let solutions = newTutorialReference.originalMarkup.range.map {
                    return [Solution(summary: "Remove duplicate \(TutorialReference.directiveName.singleQuoted) directive", replacements: [
                        Replacement(range: $0, replacement: "")
                    ])]
                } ?? []
                problems.append(Problem(diagnostic: diagnostic, possibleSolutions: solutions))
                continue
            }
            
            uniqueReferences.insert(newTutorialReference.topic)
        }
    }
    
    mutating func visitTutorialReference(_ tutorialReference: TutorialReference) {
        // This should always be an absolute topic URL rooted at the bundle, as there isn't necessarily one parent of a tutorial.
        // i.e. doc:/${SOME_TECHNOLOGY}/${PROJECT} or doc://${BUNDLE_ID}/${SOME_TECHNOLOGY}/${PROJECT}
        switch tutorialReference.topic {
        case .unresolved:
            let arguments = tutorialReference.originalMarkup.arguments()
            resolve(tutorialReference.topic, in: bundle.technologyTutorialsRootReference,
                                        range: arguments[TutorialReference.Semantics.Tutorial.argumentName]?.valueRange,
                                        severity: .warning)
        case .resolved:
            return
        }
    }

    mutating func visitResources(_ resources: Resources) {
        visitMarkupContainer(resources.content)
        resources.tiles.forEach { visitTile($0) }
    }
    
    mutating func visitTile(_ tile: Tile) {
        visitMarkupContainer(tile.content)
    }
    
    mutating func visitTutorialArticle(_ article: TutorialArticle) {
        article.intro.map { visitIntro($0) }
        visitMarkupLayouts(article.content)
        article.assessments.map { visitAssessments($0) }
        article.callToActionImage.map { visitImageMedia($0) }
    }
    
    mutating func visitArticle(_ article: Article) {
        article.abstractSection.map {
            visitMarkup($0.paragraph)
        }
        article.discussion.map {
            $0.content.forEach { visitMarkup($0) }
        }
        article.topics.map { topic in
            topic.content.forEach { visitMarkup($0) }
        }
        article.seeAlso.map {
            $0.content.forEach { visitMarkup($0) }
        }
        article.deprecationSummary.map {
            visitMarkupContainer($0)
        }
    }

    private mutating func visitMarkupLayouts<MarkupLayouts: Sequence>(_ markupLayouts: MarkupLayouts) where MarkupLayouts.Element == MarkupLayout {
        markupLayouts.forEach { content in
            switch content {
            case .markup(let markup): visitMarkupContainer(markup)
            case .contentAndMedia(let contentAndMedia): visitContentAndMedia(contentAndMedia)
            case .stack(let stack): visitStack(stack)
            }
        }
    }
    
    mutating func visitStack(_ stack: Stack) {
        stack.contentAndMedia.forEach { visitContentAndMedia($0) }
    }

    /// Returns a name that's suitable to use as a title for a given node.
    ///
    /// - Note: For symbols, this isn't the full declaration since that contains keywords and other characters that makes it less suitable as a title.
    ///
    /// - Parameter node: The node to return the title for.
    /// - Returns: The "title" for `node`.
    static func title(forNode node: DocumentationNode) -> String {
        switch node.name {
        case .conceptual(let documentTitle):
            return documentTitle
        case .symbol(let declaration):
            return node.symbol?.names.title ?? declaration.tokens.map { $0.description }.joined(separator: " ")
        }
    }
    
    mutating func visitComment(_ comment: Comment) -> Semantic {
        return comment
    }
    
    mutating func visitSymbol(_ symbol: Symbol) {
        symbol.abstractSectionVariants.allValues.map(\.variant).forEach {
            visitMarkup($0.paragraph)
        }
        symbol.discussionVariants.allValues.map(\.variant).forEach {
            $0.content.forEach { visitMarkup($0) }
        }
        symbol.topicsVariants.allValues.map(\.variant).forEach { topic in
            topic.content.forEach { visitMarkup($0) }
        }
        symbol.seeAlsoVariants.allValues.map(\.variant).forEach {
            $0.content.forEach { visitMarkup($0) }
        }
        symbol.returnsSectionVariants.allValues.map(\.variant).forEach {
            $0.content.forEach { visitMarkup($0) }
        }
        symbol.parametersSectionVariants.allValues.map(\.variant).forEach { parametersSection in
            parametersSection.parameters.forEach {
                $0.contents.forEach { visitMarkup($0) }
            }
        }
    }
    
    mutating func visitDeprecationSummary(_ summary: DeprecationSummary) {
        visitMarkupContainer(summary.content)
    }
}

fileprivate extension URL {
    var isLikelyWebURL: Bool {
        if let scheme = scheme, scheme.hasPrefix("http") {
            return true
        }
        return false
    }
}

extension Image {
    func reference(in bundle: DocumentationBundle) -> ResourceReference? {
        guard let source = source else {
            return ResourceReference(bundleIdentifier: bundle.identifier, path: "")
        }
        
        if let url = URL(string: source), url.isLikelyWebURL {
            return nil
        } else {
            return ResourceReference(bundleIdentifier: bundle.identifier, path: source)
        }
    }
}
