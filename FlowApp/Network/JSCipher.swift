import Foundation
import JavaScriptCore

enum JSCipherError: Error {
    case jsContextCreationFailed
    case scriptEvaluationFailed
    case decodingFailed
}

/// Extracted n-transform function metadata from YouTube player.js.
struct NFunctionInfo: Equatable {
    let name: String
    let arrayIndex: Int?
    let acceptsURL: Bool
}

final class JSCipher {
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

    /// Local n-parameter transform using player.js (PipePipe-independent fallback).
    func transformN(_ nValue: String, jsSource: String) throws -> String {
        guard let info = extractNFunctionInfo(from: jsSource) else {
            throw JSCipherError.decodingFailed
        }
        guard let context else { throw JSCipherError.jsContextCreationFailed }

        context.exception = nil
        context.evaluateScript(jsSource)
        if context.exception != nil {
            throw JSCipherError.scriptEvaluationFailed
        }

        let callable: JSValue?
        if let index = info.arrayIndex {
            let array = context.objectForKeyedSubscript(info.name)
            callable = array?.objectAtIndexedSubscript(Int(index))
        } else {
            callable = context.objectForKeyedSubscript(info.name)
        }

        guard let fn = callable, !fn.isUndefined else {
            throw JSCipherError.decodingFailed
        }

        let argument: Any = info.acceptsURL
            ? "https://www.youtube.com/watch?v=dQw4w9WgXcQ&n=\(nValue)"
            : nValue

        guard let result = fn.call(withArguments: [argument]), !result.isUndefined, !result.isNull else {
            throw JSCipherError.decodingFailed
        }

        var out = result.toString() ?? ""
        if info.acceptsURL, let extracted = Self.rawN(in: out) {
            out = extracted
        }
        guard !out.isEmpty, out != nValue else {
            throw JSCipherError.decodingFailed
        }
        return out
    }

    /// Port of Android FunctionNameExtractor n-function patterns.
    func extractNFunctionInfo(from js: String) -> NFunctionInfo? {
        let wrapperPatterns: [String] = [
            #"([a-zA-Z0-9$]+)\s*=\s*function\(([a-zA-Z0-9$]+)\)\s*\{\s*try\s*\{\s*var\s+[a-zA-Z0-9$]+\s*=\s*\(new\s+g\.[a-zA-Z0-9$]+\(\2\s*,\s*!0\)\)\.get\("n"\)"#,
            #"([a-zA-Z0-9$]+)\s*=\s*function\(([a-zA-Z0-9$]+)\)\s*\{[^{}]{0,300}\.get\("n"\)[^{}]{0,300}/\\?/n\\?/"#
        ]
        for pattern in wrapperPatterns {
            if let match = firstMatch(pattern, in: js),
               let name = group(1, in: match, js: js), !name.isEmpty {
                return NFunctionInfo(name: name, arrayIndex: nil, acceptsURL: true)
            }
        }

        // .get("n")&&(b=NAME[IDX](c)
        if let match = firstMatch(#"\.get\("n"\)\)&&\(b=([a-zA-Z0-9$]+)(?:\[(\d+)\])?\(([a-zA-Z0-9])\)"#, in: js),
           let name = group(1, in: match, js: js) {
            let idx = group(2, in: match, js: js).flatMap(Int.init)
            return NFunctionInfo(name: name, arrayIndex: idx, acceptsURL: false)
        }

        // .get("n")&&(a=NAME[IDX](a)
        if let match = firstMatch(#"\.get\("n"\)\)\s*&&\s*\(([a-zA-Z0-9$]+)\s*=\s*([a-zA-Z0-9$]+)(?:\[(\d+)\])?\(\1\)"#, in: js),
           let name = group(2, in: match, js: js) {
            let idx = group(3, in: match, js: js).flatMap(Int.init)
            return NFunctionInfo(name: name, arrayIndex: idx, acceptsURL: false)
        }

        if let match = firstMatch(#"([a-zA-Z0-9$]+)\s*=\s*function\([a-zA-Z0-9]\)\s*\{[^}]*?enhanced_except_"#, in: js),
           let name = group(1, in: match, js: js) {
            return NFunctionInfo(name: name, arrayIndex: nil, acceptsURL: false)
        }

        return nil
    }

    private func extractDecipherFunctionName(from js: String) -> String {
        let pattern = #"([a-zA-Z0-9$]+)\s*=\s*function\(\s*([a-zA-Z0-9$]+)\s*\)\s*\{\s*\2\s*=\s*\2\.split\(\s*""\s*\)"#
        if let match = firstMatch(pattern, in: js), let name = group(1, in: match, js: js) {
            return name
        }
        return ""
    }

    private func firstMatch(_ pattern: String, in js: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(js.startIndex..<js.endIndex, in: js)
        return regex.firstMatch(in: js, range: range)
    }

    private func group(_ index: Int, in match: NSTextCheckingResult, js: String) -> String? {
        guard match.numberOfRanges > index,
              let range = Range(match.range(at: index), in: js) else { return nil }
        let value = String(js[range])
        return value.isEmpty ? nil : value
    }

    private static let nParamRegex = try! NSRegularExpression(pattern: #"([?&])n=([^&]+)"#)

    static func rawN(in url: String) -> String? {
        let nsRange = NSRange(url.startIndex..<url.endIndex, in: url)
        guard let match = nParamRegex.firstMatch(in: url, range: nsRange),
              let nRange = Range(match.range(at: 2), in: url) else { return nil }
        let raw = String(url[nRange])
        return raw.removingPercentEncoding ?? raw
    }
}
