//
//  CodableGenerator.swift
//  Model Boiler
//
//  Created by Jakob Mygind on 09/03/2020.
//  Copyright © 2020 Nodes. All rights reserved.
//

import Foundation
import SwiftSyntax
import SwiftSemantics

class Generator {
    
    let source: String
    let mapUnderscoreToCamelCase: Bool
    
    init(source: String, mapUnderscoreToCamelCase: Bool = false) {
        self.source = source
        self.mapUnderscoreToCamelCase = mapUnderscoreToCamelCase
    }
    
    var encode: [String] = ["""
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
    """
    ]
    
    var initStrings: [String] = ["""
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
        """
    ]
    
    var codingKeys: [String] = ["""
            enum CodingKeys: String, CodingKey {
            """
    ]
    
   func addNode(name: String, type: String, isOptional: Bool = false) {
        encode.append("    try container.encode(\(name), forKey: .\(name))")
        if isOptional {
            initStrings.append("    \(name) = try container.decodeIfPresent(\(type.trimmingCharacters(in: .init(charactersIn: "?"))).self, forKey: .\(name))")
        } else {
            initStrings.append("    \(name) = try container.decode(\(type).self, forKey: .\(name))")
        }
       
        if mapUnderscoreToCamelCase {
             codingKeys.append("    case \(name) = \"\(mapCamelToUnderscore(name))\"")
        } else {
             codingKeys.append("    case \(name) = \"\(name)\"")
        }
    }
    
    func mapCamelToUnderscore(_ string: String) -> String {
        var res = ""

        var strCopy = string[...]
        while let match = parseWord(str: &strCopy) {
            res += "_" + match.lowercased()
        }
        return res.trimmingCharacters(in: CharacterSet.init(charactersIn: "_"))
    }
    
    func parseWord(str: inout Substring) -> String? {
        
        if let lowerMatch = Parser.lower.run(&str) {
            return lowerMatch
        }
        if let upperThenLower = zip(Parser.upper, Parser.lower).run(&str) {
            return upperThenLower.0 + upperThenLower.1
        }
        return Parser.upper.run(&str)
    }
    
    /// Generation is based on dumb pattern matchint
      func generate() throws -> String {
          var collector = DeclarationCollector()
          let tree = try SyntaxParser.parse(source: source)
          tree.walk(&collector)
          
          
          for v in collector.variables {
              let typeString: String
              
              switch (v.typeAnnotation, v.initializedValue) {
              case (.some(let type), _):
                  typeString = type
              case (_, .some(let value)) where value.contains("\""):
                  typeString = "String"
              case (_, .some(let value)) where value.contains(".") && Double(value) != nil:
                  typeString = "Double"
              case (_, .some(let value)) where Int(value) != nil:
                  typeString = "Int"
              case (_, .some(let value)) where Bool(value) != nil:
                  typeString = "Bool"
              case (_, .some(let value)) where Set(value.unicodeScalars).contains(where: CharacterSet.init(charactersIn: "()").contains):
                  typeString = value.replacingOccurrences(of: "()", with: "")
              default: throw NSError(domain: "dk.nodes.modelboiler", code: 1, userInfo: ["error": "Could not generate type for \(v)"])
                  
              }
              addNode(name: v.name, type: typeString, isOptional: typeString.contains("?"))
          }
          
          encode.append("}\n\n")
          initStrings.append("}")
          codingKeys.append("}\n\n")
          
          return codingKeys.joined(separator: "\n") + encode.joined(separator: "\n") + initStrings.joined(separator: "\n")
      }
}

struct Parser<A> {
    let run: (inout Substring) -> A?
}

extension Parser where A == String {
    
    static func predicate(_ predicate: @escaping (Character) -> Bool) -> Parser {
        Parser { str in
            let match = str.prefix(while: predicate)
            guard !match.isEmpty else { return nil }
            str.removeFirst(match.count)
            return String(match)
        }
    }
    
    static let upper: Parser = .predicate { $0.isUppercase }
    
    static let lower: Parser = .predicate { $0.isLowercase }
}

func zip<A, B>(_ pa: Parser<A>, _ pb: Parser<B>) -> Parser<(A, B)> {
    Parser { str in
        let originalString = str
        guard let a = pa.run(&str) else {
            return nil
        }
        guard let b = pb.run(&str) else {
            str = originalString
            return nil
        }
        return (a, b)
    }
}

