//
//  SwiftFileGenerator.swift
//  plank
//
//  Created by Rajat Kumar Gupta on 10/06/17.
//
//

import Foundation


struct SwiftFileGenerator: FileGeneratorManager {
    static func filesToGenerate(descriptor: SchemaObjectRoot, generatorParameters: GenerationParameters) -> [FileGenerator] {
        
        let renderer = SwiftRenderer(params: generatorParameters, rootSchema: descriptor)
        
//        let rootsRenderer = ObjCModelRenderer(rootSchema: descriptor, params: generatorParameters)
        
        return [
            SwiftFile(renderer: renderer, className: renderer.className)
//            ObjCHeaderFile(roots: rootsRenderer.renderRoots(), className: rootsRenderer.className),
//            ObjCImplementationFile(roots: rootsRenderer.renderRoots(), className: rootsRenderer.className)
        ]
    }
    
    static func runtimeFiles() -> [FileGenerator] {
//        fatalError("Swift models don't have separate runtime and header files")
        return [ObjCRuntimeHeaderFile(), ObjCRuntimeImplementationFile()]
    }
}


protocol SwiftFileRenderer {
    var rootSchema: SchemaObjectRoot { get }
    var params: GenerationParameters { get }
    
    func render() -> String
}

public struct SwiftRenderer: SwiftFileRenderer {
    var params: GenerationParameters
    var rootSchema: SchemaObjectRoot

    // Function t resolve class name
    // Copied from objective c renderer
    // move it to a utility rather
    func resolveClassName(_ schema: Schema?) -> String? {
        switch schema {
            // If schema is of type object, get class name with prefix if specified
        case .some(.object(let root)):
            return root.className(with: self.params)
            // If it's a ref, force load the schema and try to resolve class name
        case .some(.reference(with: let ref)):
            return resolveClassName(ref.force())
        default:
            return nil
        }
    }
    
    
    
    private func renderDeclaration() -> String {
        let parentClassName = resolveClassName(self.parentDescriptor)
        let className = self.className
        
        var declaration: String = "public struct \(className)"
        if let parent = parentClassName {
            declaration += ": \(parent)"
        }
        declaration += " {\n\n"
        
        return declaration
    }
    
    
    private func renderProperties() -> String {
        var propertiesContent: String = ""
        
        for (property, schema) in self.rootSchema.properties {
            propertiesContent += "let \(property): \(swiftClassFromSchema(property, schema))?\n"
        }
        
        return propertiesContent
    }
    
    
    func render() -> String {
        var renderingContent = "\n"
        
        let imports = renderReferencedClasses()
        
        for className in imports {
            renderingContent += "import \(className) \n"
        }
        
        renderingContent += "\n\n"
        
        renderingContent += renderDeclaration()
        
        renderingContent += renderProperties()
        
        renderingContent += "}\n\n"
        
        return renderingContent
    }

    // MARK: Properties
    
    var className: String {
        return self.rootSchema.className(with: self.params)
    }
    
//    var builderClassName: String {
//        return "\(self.className)Builder"
//    }
    
    var parentDescriptor: Schema? {
        return self.rootSchema.extends.flatMap { $0.force() }
    }
    
    var properties: [(Parameter, Schema)] {
        return self.rootSchema.properties.map { $0 }
    }
    
    var isBaseClass: Bool {
        return rootSchema.extends == nil
    }
    
    fileprivate func referencedClassNames(schema: Schema) -> [String] {
        switch schema {
        case .reference(with: let ref):
            switch ref.force() {
            case .some(.object(let schemaRoot)):
                return [schemaRoot.className(with: self.params)]
            default:
                fatalError("Bad reference found in schema for class: \(self.className)")
            }
        case .object(let schemaRoot):
            return [schemaRoot.className(with: self.params)]
        case .map(valueType: .some(let valueType)):
            return referencedClassNames(schema: valueType)
        case .array(itemType: .some(let itemType)):
            return referencedClassNames(schema: itemType)
        case .oneOf(types: let itemTypes):
            return itemTypes.flatMap(referencedClassNames)
        default:
            return []
        }
    }
    
    func renderReferencedClasses() -> Set<String> {
        return Set(rootSchema.properties.values.flatMap(referencedClassNames))
    }
    
    func swiftClassFromSchema(_ param: String, _ schema: Schema) -> String {
        switch schema {
        case .array(itemType: .none):
            return "[Any]"
        case .array(itemType: .some(let itemType)):
            return "[\(swiftClassFromSchema(param, itemType))]"
        case .map(valueType: .none):
            return "[AnyHashable: Any]"
        case .map(valueType: .some(let valueType)):
            return "[AnyHashable: \(swiftClassFromSchema(param, valueType))]"
        case .string(format: .none),
             .string(format: .some(.email)),
             .string(format: .some(.hostname)),
             .string(format: .some(.ipv4)),
             .string(format: .some(.ipv6)):
            return "String"
        case .string(format: .some(.dateTime)):
            return "Date"
        case .string(format: .some(.uri)):
            return "URL"
        case .integer:
            return "Int"
        case .float:
            return "Double"
        case .boolean:
            return "Bool"
        case .enumT(_):
            return enumTypeName(propertyName: param, className: className)
        case .object(let objSchemaRoot):
            return "\(objSchemaRoot.className(with: params))"
        case .reference(with: let ref):
            switch ref.force() {
            case .some(.object(let schemaRoot)):
                return swiftClassFromSchema(param, .object(schemaRoot))
            default:
                fatalError("Bad reference found in schema for class: \(className)")
            }
        case .oneOf(types:_):
            return "\(className)\(param.snakeCaseToCamelCase())"
        }
    }
}


public struct SwiftFile: FileGenerator {
    
    fileprivate let renderer: SwiftFileRenderer
    fileprivate let className: String
    
    public var fileName: String {
        get {
            return "\(className).swift"
        }
    }

    public func renderFile() -> String {
        return self.renderCommentHeader() + "\n" + renderer.render();
    }
}
