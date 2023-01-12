/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2022 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation

protocol _DirectiveArgumentProtocol {
    var typeDisplayName: String { get }
    var storedAsOptional: Bool { get }
    var required: Bool { get }
    var name: _DirectiveArgumentName { get }
    var allowedValues: [String]? { get }
    var hiddenFromDocumentation: Bool { get }
    
    var parseArgument: (_ bundle: DocumentationBundle, _ argumentValue: String) -> (Any?) { get }
    
    func setProperty<T>(
        on containingDirective: T,
        named propertyName: String,
        to any: Any
    ) where T: AutomaticDirectiveConvertible
}

enum _DirectiveArgumentName {
    case unnamed
    case custom(String)
    case inferredFromPropertyName
}

/// A property wrapper that represents a directive argument.
///
/// This property wrapper is used internally in Swift-DocC when declaring directives
/// that accept arguments.
///
/// For example, this code snippet declares a `@CustomDisplayName` directive that accepts
/// a `name` argument with a `String` type.
///
///     class CustomDisplayName: Semantic, AutomaticDirectiveConvertible {
///         let originalMarkup: BlockDirective
///
///         @DirectiveArgumentWrapper(name: .unnamed)
///         private(set) var name: String
///
///         static var keyPaths: [String : AnyKeyPath] = [
///             "name" : \CustomDisplayName._name,
///         ]
///
///         init(originalMarkup: BlockDirective) {
///             self.originalMarkup = originalMarkup
///         }
///     }
///
/// > Warning: This property wrapper is exposed as public API of SwiftDocC so that clients
/// > have access to its projected value, but it is unsupported to attach this property
/// > wrapper to new declarations outside of SwiftDocC.
@propertyWrapper
public struct DirectiveArgumentWrapped<Value>: _DirectiveArgumentProtocol {
    let name: _DirectiveArgumentName
    let typeDisplayName: String
    let allowedValues: [String]?
    let hiddenFromDocumentation: Bool
    
    let parseArgument: (_ bundle: DocumentationBundle, _ argumentValue: String) -> (Any?)
    
    let defaultValue: Value?
    var storedAsOptional: Bool {
        return defaultValue != nil
    }
    
    let required: Bool
    
    var parsedValue: Value?
    public var wrappedValue: Value {
        get {
            parsedValue ?? defaultValue!
        } set {
            parsedValue = newValue
        }
    }
    
    @available(*, unavailable,
        message: "The value type must conform to 'DirectiveArgumentValueConvertible'."
    )
    public init() {
        fatalError()
    }
    
    private init(
        value: Value?,
        name: _DirectiveArgumentName,
        transform: @escaping (_ bundle: DocumentationBundle, _ argumentValue: String) -> (Value?),
        allowedValues: [String]?,
        required: Bool?,
        hiddenFromDocumentation: Bool
    ) {
        self.name = name
        self.defaultValue = value
        if let optionallyWrappedValue = Value.self as? OptionallyWrapped.Type {
            self.typeDisplayName = String(describing: optionallyWrappedValue.baseType()) + "?"
        } else {
            self.typeDisplayName = String(describing: Value.self)
        }
        
        if let required = required {
            self.required = required
        } else {
            self.required = defaultValue == nil
        }
        
        self.parseArgument = transform
        self.allowedValues = allowedValues
        self.hiddenFromDocumentation = hiddenFromDocumentation
    }
    
    @_disfavoredOverload
    init(
        wrappedValue: Value,
        name: _DirectiveArgumentName = .inferredFromPropertyName,
        parseArgument: @escaping (_ bundle: DocumentationBundle, _ argumentValue: String) -> (Value?),
        allowedValues: [String]? = nil,
        required: Bool? = nil,
        hiddenFromDocumentation: Bool = false
    ) {
        self.init(
            value: wrappedValue,
            name: name,
            transform: parseArgument,
            allowedValues: allowedValues,
            required: required,
            hiddenFromDocumentation: hiddenFromDocumentation
        )
    }
    
    @_disfavoredOverload
    init(
        name: _DirectiveArgumentName = .inferredFromPropertyName,
        parseArgument: @escaping (_ bundle: DocumentationBundle, _ argumentValue: String) -> (Value?),
        allowedValues: [String]? = nil,
        required: Bool? = nil,
        hiddenFromDocumentation: Bool = false
    ) {
        self.init(
            value: nil,
            name: name,
            transform: parseArgument,
            allowedValues: allowedValues,
            required: required,
            hiddenFromDocumentation: hiddenFromDocumentation
        )
    }
    
    func setProperty<T>(
        on containingDirective: T,
        named propertyName: String,
        to any: Any
    ) where T: AutomaticDirectiveConvertible {
        let path = T.keyPaths[propertyName] as! ReferenceWritableKeyPath<T, DirectiveArgumentWrapped<Value>>
        let wrappedValuePath = path.appending(path: \Self.parsedValue)
        containingDirective[keyPath: wrappedValuePath] = any as! Value?
    }
}

extension DirectiveArgumentWrapped where Value: DirectiveArgumentValueConvertible {
    init(
        name: _DirectiveArgumentName = .inferredFromPropertyName,
        hiddenFromDocumentation: Bool = false
    ) {
        self.init(value: nil, name: name, hiddenFromDocumentation: hiddenFromDocumentation)
    }
    
    init(
        wrappedValue: Value,
        name: _DirectiveArgumentName = .inferredFromPropertyName,
        hiddenFromDocumentation: Bool = false
    ) {
        self.init(value: wrappedValue, name: name, hiddenFromDocumentation: hiddenFromDocumentation)
    }
    
    private init(
        value: Value?,
        name: _DirectiveArgumentName,
        hiddenFromDocumentation: Bool
    ) {
        self.name = name
        self.defaultValue = value
        
        if let value = value {
            self.typeDisplayName = String(describing: Value.self) + " = " + String(describing: value)
        } else {
            self.typeDisplayName = String(describing: Value.self)
        }
        
        self.parseArgument = { _, argument in
            Value.init(rawDirectiveArgumentValue: argument)
        }
        self.allowedValues = Value.allowedValues()
        self.required = value == nil
        self.hiddenFromDocumentation = hiddenFromDocumentation
    }
}

protocol OptionallyWrappedDirectiveArgumentValueConvertible: OptionallyWrapped {}
extension Optional: OptionallyWrappedDirectiveArgumentValueConvertible where Wrapped: DirectiveArgumentValueConvertible {}
extension DirectiveArgumentWrapped where Value: OptionallyWrappedDirectiveArgumentValueConvertible {
    init(
        wrappedValue: Value,
        name: _DirectiveArgumentName = .inferredFromPropertyName,
        required: Bool = false,
        hiddenFromDocumentation: Bool = false
    ) {
        let argumentValueType = Value.baseType() as! DirectiveArgumentValueConvertible.Type
        
        self.name = name
        self.defaultValue = wrappedValue
        if required {
            self.typeDisplayName = String(describing: argumentValueType)
        } else {
            self.typeDisplayName = String(describing: argumentValueType) + "?"
        }
        
        self.parseArgument = { _, argument in
            argumentValueType.init(rawDirectiveArgumentValue: argument)
        }
        self.allowedValues = argumentValueType.allowedValues()
        self.required = required
        self.hiddenFromDocumentation = hiddenFromDocumentation
    }
}

protocol CollectionWrappedArgumentValueConvertible: CollectionWrapped {}
extension Array: CollectionWrappedArgumentValueConvertible where Element: DirectiveArgumentValueConvertible {}
extension DirectiveArgumentWrapped where Value: CollectionWrappedArgumentValueConvertible {
    init(
        name: _DirectiveArgumentName = .inferredFromPropertyName
    ) {
        
        // TODO: Set some flag here to indicate that this is a variadic argument.
        fatalError("implement me")
    }
    
    init(
        wrappedValue: Value,
        name: _DirectiveArgumentName = .inferredFromPropertyName
    ) {
        fatalError("implement me")
    }
}
