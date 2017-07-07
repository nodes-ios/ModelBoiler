//
//  Service.swift
//  Model Boiler
//
//  Created by Dominik Hádl on 25/01/16.
//  Copyright © 2016 Nodes. All rights reserved.
//

import Foundation
import ModelGenerator
import Cocoa

struct Service {

    static let errorSound   = NSSound(named: NSSound.Name(rawValue: "Basso"))
    static let successSound = NSSound(named: NSSound.Name(rawValue: "Pop"))

    // MARK: - Main Function -

    static func generate(_ pasteboard: NSPasteboard = NSPasteboard.general) {
    
        guard let source = pasteboard.string(forType: NSPasteboard.PasteboardType.string), (pasteboard.pasteboardItems?.count == 1) else {
            NSUserNotification.display(title: "No text selected",
                                       andMessage: "Nothing was found in the pasteboard.")
            playSound(Service.errorSound)
            return
        }
        
        // Setup the model generator
        var generatorSettings = ModelGeneratorSettings()
        generatorSettings.moduleName = nil
        generatorSettings.noConvertCamelCase = SettingsManager.isSettingEnabled(.NoCamelCaseConversion)
        generatorSettings.useNativeDictionaries = SettingsManager.isSettingEnabled(.UseNativeDictionaries)
        generatorSettings.onlyCreateInitializer = SettingsManager.isSettingEnabled(.OnlyCreateInitializer)
        
        do {
            // Try to generate the code bodies
            guard let extensions = try extensionBodies(fromSource: source, generatorSettings: generatorSettings) else { throw ModelParserError.NoModelNameFound }
            
            //Concatenate the extensions
            let code = extensionCode(fromBodies: extensions)
            
            // Play success sound
            playSound(Service.successSound)
            
            // Copy back to pasteboard
            NSPasteboard.general.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
            NSPasteboard.general.setString(code, forType: NSPasteboard.PasteboardType.string)

            // Success, show notification
            NSUserNotification.display(
                title: "Code generated",
                andMessage: "The code has been copied to the clipboard.")
        } catch {
            
            // Show error notification
            NSUserNotification.display(
                title: "Code generation failed",
                andMessage: "Error: \((error as? ModelGeneratorErrorType)?.description() ?? "Unknown error.")")
            
            // Play error sound
            playSound(Service.errorSound)
        }
    }
    
    static func extensionCode(fromBodies bodies: [String]) -> String {
        var bodiesMutating = bodies
        var retVal = ""
        if !bodies.isEmpty {
            retVal = bodiesMutating.removeFirst()
        }
        for body in bodiesMutating {
            retVal.append("\n\n\(body)")
        }
        
        return retVal
    }
    
    static func extensionBodies(fromSource source: String, generatorSettings:  ModelGeneratorSettings) throws -> [String]? {
        if let codes = try codeStrings(fromSourceCode: source) {
            var retVal = [String]()
            var outerModelPrefix = ""
            for (index, code) in codes.enumerated() {
                var codeToParse = code
                if index == 0, let outerName = modelName(fromSourceCode: codeToParse)?.0 {
                    outerModelPrefix = outerName + "."
                } else if let range = modelName(fromSourceCode: codeToParse)?.1 {
                    codeToParse = ""
                    for (index, character) in code.enumerated() {
                        if index == range.lowerBound {
                            codeToParse.append(" \(outerModelPrefix)")
                        }
                        codeToParse.append(character)
                    }
                }
                let newCode = try ModelGenerator.modelCode(fromSourceCode: codeToParse, withSettings: generatorSettings)
                retVal.append(newCode)
            }
            return retVal
        }
        return nil
    }
    
    static func modelName(fromSourceCode code: String) -> (String, NSRange)? {
        let range = NSMakeRange(0, code.characters.count)
        let match = modelNameRegex?.firstMatch(in: code, options: NSRegularExpression.MatchingOptions(rawValue: 0), range: range)
        
        // If we found model name
        if let match = match {
            return ((code as NSString).substring(with: match.range), match.range)
        }
        
        return nil
    }
    
    static func missingEndBrackets(inCode code: String) -> String {
        let startBrackets = code.components(separatedBy: "{").count - 1
        let endBrackets = code.components(separatedBy: "}").count - 1
        let difference = startBrackets - endBrackets
        
        var addition = ""
        if difference > 0 {
            
            for _ in 0..<difference {
                addition.append("}")
            }
        }
        return addition
    }
    
    static func codeStrings(fromSourceCode code: String) throws -> [String]? {
        let range = NSMakeRange(0, code.characters.count)
        
        // Check if struct
        let structMatches = structRegex?.numberOfMatches(in: code, options: NSRegularExpression.MatchingOptions(rawValue: 0), range: range)
        if let matches = structMatches,
            matches == 1 {
            
            return [code + missingEndBrackets(inCode: code)]
            
        } else if let matches = structMatches,
            matches > 1,
            let allMatches = structRegex?.matches(in: code, options: NSRegularExpression.MatchingOptions(rawValue: 0), range: range) {
            let rangeToRemove = NSMakeRange(0, allMatches[1].range.location)
            let string = (code as NSString).substring(to: rangeToRemove.length) as String
            let restRange = NSMakeRange(rangeToRemove.length, range.length - rangeToRemove.length)
            let restCode = (code as NSString).substring(with: restRange) as String
            do {
                
                if let strings = try codeStrings(fromSourceCode: restCode) {
                    return [string + missingEndBrackets(inCode: string)] + strings
                }
            }
        }
        
        //Check if final class
        
        let finalClassMatches = finalClassRegex?.numberOfMatches(in: code, options: NSRegularExpression.MatchingOptions(rawValue: 0), range: range)
        if let matches = finalClassMatches,
            matches == 1 {
            
            return [code + missingEndBrackets(inCode: code)]
            
        } else if let matches = finalClassMatches,
            matches > 1,
            let allMatches = finalClassRegex?.matches(in: code, options: NSRegularExpression.MatchingOptions(rawValue: 0), range: range) {
            let rangeToRemove = NSMakeRange(0, allMatches[1].range.location)
            let string = (code as NSString).substring(to: rangeToRemove.length) as String
            let restRange = NSMakeRange(rangeToRemove.length, range.length - rangeToRemove.length)
            let restCode = (code as NSString).substring(with: restRange) as String
            do {
                
                if let strings = try codeStrings(fromSourceCode: restCode) {
                    return [string + missingEndBrackets(inCode: string)] + strings
                }
            }
            
        } else if code.contains("class") {
            throw ModelParserError.ClassShouldBeDeclaredAsFinal
        }
        
        // If no struct or class was found
        return nil
    }
    //
    
    static func playSound(_ sound: NSSound?) {
        if !UserDefaults.standard.bool(forKey: "muteSound") {
            sound?.play()
        }
    }
}
// Regular expression used for parsing
extension Service {
    
    static var modelBodyRegex: NSRegularExpression? {
        do {
            let regex = try NSRegularExpression(
                pattern: "struct.*\\{(.*)\\}|class.*\\{(.*)\\}",
                options: [.dotMatchesLineSeparators])
            return regex
        } catch {
            print("Couldn't create model body regex.")
            return nil
        }
    }
    static var finalClassRegex: NSRegularExpression? {
        do {
            let regex = try NSRegularExpression(
                pattern: "final.*class(?=.*\\{)",
                options: NSRegularExpression.Options(rawValue: 0))
            return regex
        } catch {
            print("Couldn't create final class regex.")
            return nil
        }
    }
    
    static var structRegex: NSRegularExpression? {
        do {
            let regex = try NSRegularExpression(
                pattern: "struct(?=.*\\{)",
                options: NSRegularExpression.Options(rawValue: 0))
            return regex
        } catch {
            print("Couldn't create struct regex.")
            return nil
        }
    }
    
    static var modelNameRegex: NSRegularExpression? {
        do {
            let regex = try NSRegularExpression(
                pattern: "\\S+(?=\\s*\\:)|\\S+(?=\\s*\\{)",
                options: NSRegularExpression.Options(rawValue: 0))
            return regex
        } catch {
            print("Couldn't create model name regex.")
            return nil
        }
    }
}


