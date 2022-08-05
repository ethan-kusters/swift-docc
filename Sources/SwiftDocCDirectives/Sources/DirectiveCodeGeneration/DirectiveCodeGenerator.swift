import ArgumentParser
import Foundation
import SwiftSyntaxBuilder

@main struct DirectiveCodeGenerator: ParsableCommand {
    func run() throws {
        let source = SourceFile {
            ImportDecl(path: "Foundation")
            ImportDecl(path: "Markdown")
            
            ClassDecl(
                classOrActorKeyword: .class,
                identifier: "Metadata",
                inheritanceClause: TypeInheritanceClause {
                    InheritedType(typeName: "Semantic", trailingComma: .comma)
                    InheritedType(typeName: "DirectiveConvertible")
                }
            ) {
                DeclModifier(name: .public)
                DeclModifier(name: .unknown("final"))
                " "
            } membersBuilder: {
                VariableDecl(
                    letOrVarKeyword: .let,
                    modifiersBuilder: {
                        DeclModifier(name: .public)
                        DeclModifier(name: .static)
                    },
                    bindingsBuilder: {
                        PatternBinding(
                            pattern: "directiveName",
                            initializer: InitializerClause(value: StringLiteralExpr("Metadata"))
                        )
                    }
                )
                
                VariableDecl(.let, name: "originalMarkup", type: "BlockDirective")
                
                InitializerDecl(
                    attributes: nil,
                    parameters: ParameterClause {
                        FunctionParameter(firstName: .identifier("directiveName"), type: "String")
                    }
                )
            }
        }
        
        let syntax = source.buildSyntax(format: Format(indentWidth: 4))
        var text = ""
        syntax.write(to: &text)

        print(text)
    }
}
