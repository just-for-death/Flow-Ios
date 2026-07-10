import Foundation
import JavaScriptCore

enum JSCipherError: Error {
    case jsContextCreationFailed
    case scriptEvaluationFailed
    case decodingFailed
}

class JSCipher {
    static let shared = JSCipher()
    
    private let context: JSContext?
    
    init() {
        if let ctx = JSContext() {
            self.context = ctx
            ctx.exceptionHandler = { _, exception in
                if let exception = exception {
                    print("JS Error: \(exception.toString() ?? "Unknown")")
                }
            }
        } else {
            self.context = nil
            print("[JSCipher] Failed to create JSContext")
        }
    }
    
    /// Deciphers a signature given the raw YouTube base.js source and the encrypted signature.
    func decipher(signature: String, jsSource: String) throws -> String {
        guard let context else { throw JSCipherError.jsContextCreationFailed }
        context.evaluateScript(jsSource)
        if context.exception != nil {
            throw JSCipherError.scriptEvaluationFailed
        }
        
        let functionName = extractDecipherFunctionName(from: jsSource)
        guard !functionName.isEmpty else {
            throw JSCipherError.decodingFailed
        }
        
        let decipherFunction = context.objectForKeyedSubscript(functionName)
        guard let result = decipherFunction?.call(withArguments: [signature]), !result.isUndefined else {
            throw JSCipherError.decodingFailed
        }
        
        return result.toString()
    }
    
    private func extractDecipherFunctionName(from js: String) -> String {
        let pattern = #"([a-zA-Z0-9$]+)\s*=\s*function\(\s*([a-zA-Z0-9$]+)\s*\)\s*\{\s*\2\s*=\s*\2\.split\(\s*""\s*\)"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsRange = NSRange(js.startIndex..<js.endIndex, in: js)
            if let match = regex.firstMatch(in: js, options: [], range: nsRange) {
                if let r = Range(match.range(at: 1), in: js) {
                    return String(js[r])
                }
            }
        }
        return ""
    }
}
