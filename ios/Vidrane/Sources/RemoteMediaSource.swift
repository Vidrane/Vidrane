import Foundation

/// A seekable bounded remote file, independent of the network protocol.
/// Implementations never return more bytes than requested.
protocol RemoteMediaBytes: AnyObject {
    var length: Int64 { get }
    func read(offset: Int64, count: Int) async throws -> Data
    func close() async
}

