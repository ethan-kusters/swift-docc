protocol Directive: DirectiveBodyContent {
    var supportedChildren: [DirectiveBodyContent.Type] { get }
    var parameters: [DirectiveParameter] { get }
}

protocol DirectiveBodyContent {}

enum MarkdownContent: DirectiveBodyContent {}

struct DirectiveParameter {
    enum ParameterType {
        case string
        case boolean
        case enumeration([String])
        case enumerationWithDefault([String], default: String)
        case url
    }
    
    let name: String?
    let type: ParameterType
    let required: Bool
    
    init(name: String? = nil, type: ParameterType, required: Bool = false) {
        self.name = name
        self.type = type
        self.required = required
    }
}

let topLevelMarkdownDirectives: [Directive] = [
    Metadata(),
    Comment(),
]

let topLevelTutorialDirectives: [Directive] = [
    Tutorial(),
    Comment(),
]

public struct Tutorial: Directive {
    let supportedChildren: [DirectiveBodyContent.Type] = []
    
    let parameters: [DirectiveParameter] = []
}

/// Captures a writer comment that’s not visible in the rendered documentation.
///
/// Use a comment directive to include author notes,
/// like reminders to add more content,
/// in your reference documentation or tutorial.
/// DocC ignores comments when your documentation builds,
/// and they don’t appear in the rendered content.
///
///     @Comment {
///         Add lots more photos of sloths here!
///     }
public struct Comment: Directive {
    let supportedChildren: [DirectiveBodyContent.Type] = [
        MarkdownContent.self,
    ]
    
    let parameters: [DirectiveParameter] = []
}

public struct Metadata: Directive {
    let supportedChildren: [DirectiveBodyContent.Type] = [
        DocumentationExtension.self,
        TechnologyRoot.self,
        DisplayName.self,
    ]
    
    let parameters: [DirectiveParameter] = []
}

public struct DocumentationExtension: Directive {
    let supportedChildren: [DirectiveBodyContent.Type] = []
    let parameters: [DirectiveParameter] = []
}

public struct TechnologyRoot: Directive {
    let supportedChildren: [DirectiveBodyContent.Type] = []
    let parameters: [DirectiveParameter] = []
}

public struct DisplayName: Directive {
    let supportedChildren: [DirectiveBodyContent.Type] = []
    
    let parameters: [DirectiveParameter] = [
        DirectiveParameter(type: .string, required: true),
        
        DirectiveParameter(
            type: .enumerationWithDefault(["symbol", "conceptual"],
                default: "conceptual"
            ),
            required: true
        ),
    ]
}


