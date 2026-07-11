import Foundation
import zlib

// MARK: - FlowGzip (RFC 1952 — matches Java GZIPOutputStream / GZIPInputStream)
enum FlowGzip {
    static func compress(_ data: Data) throws -> Data {
        if data.isEmpty {
            // Empty gzip member
            return Data([
                0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff,
                0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
            ])
        }
        var stream = z_stream()
        let initStatus = deflateInit2_(
            &stream,
            Z_DEFAULT_COMPRESSION,
            Z_DEFLATED,
            15 + 16, // gzip wrapper
            8,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initStatus == Z_OK else { throw SyncError.peerError(code: "gzip", message: "deflateInit2 failed") }
        defer { deflateEnd(&stream) }

        var output = Data()
        let chunk = 16 * 1024
        try data.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
            guard let base = src.bindMemory(to: Bytef.self).baseAddress else { return }
            stream.next_in = UnsafeMutablePointer(mutating: base)
            stream.avail_in = uInt(src.count)
            var buffer = [UInt8](repeating: 0, count: chunk)
            repeat {
                let status: Int32 = buffer.withUnsafeMutableBufferPointer { buf in
                    stream.next_out = buf.baseAddress
                    stream.avail_out = uInt(buf.count)
                    return deflate(&stream, Z_FINISH)
                }
                let produced = chunk - Int(stream.avail_out)
                if produced > 0 { output.append(contentsOf: buffer.prefix(produced)) }
                if status == Z_STREAM_END { break }
                guard status == Z_OK else { throw SyncError.peerError(code: "gzip", message: "deflate failed") }
            } while true
        }
        return output
    }

    static func decompress(_ data: Data) throws -> Data {
        var stream = z_stream()
        let initStatus = inflateInit2_(
            &stream,
            15 + 16, // gzip
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initStatus == Z_OK else { throw SyncError.peerError(code: "gzip", message: "inflateInit2 failed") }
        defer { inflateEnd(&stream) }

        var output = Data()
        let chunk = 16 * 1024
        try data.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
            guard let base = src.bindMemory(to: Bytef.self).baseAddress else { return }
            stream.next_in = UnsafeMutablePointer(mutating: base)
            stream.avail_in = uInt(src.count)
            var buffer = [UInt8](repeating: 0, count: chunk)
            repeat {
                let status: Int32 = buffer.withUnsafeMutableBufferPointer { buf in
                    stream.next_out = buf.baseAddress
                    stream.avail_out = uInt(buf.count)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                let produced = chunk - Int(stream.avail_out)
                if produced > 0 { output.append(contentsOf: buffer.prefix(produced)) }
                if status == Z_STREAM_END { break }
                guard status == Z_OK else { throw SyncError.peerError(code: "gzip", message: "inflate failed") }
            } while true
        }
        return output
    }
}
