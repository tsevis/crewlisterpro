import Foundation

/// A zip archive of uncompressed ("stored") entries — all an `.xlsx` needs,
/// and all Foundation lacks a writer for on both macOS and iOS.
///
/// Every entry carries the same fixed timestamp, so the same manifest always
/// produces the same bytes.
enum ZipArchive {
    static func stored(_ entries: [(name: String, data: Data)]) -> Data {
        var archive = Data()
        var directory = Data()
        for entry in entries {
            let name = Data(entry.name.utf8)
            let crc = crc32(entry.data)
            let offset = UInt32(archive.count)

            archive.append(le32(0x0403_4B50))
            archive.append(commonHeader(name: name, crc: crc, size: UInt32(entry.data.count)))
            archive.append(name)
            archive.append(entry.data)

            directory.append(le32(0x0201_4B50))
            directory.append(le16(20))                    // made by
            directory.append(commonHeader(name: name, crc: crc, size: UInt32(entry.data.count)))
            directory.append(le16(0))                     // comment length
            directory.append(le16(0))                     // disk number
            directory.append(le16(0))                     // internal attributes
            directory.append(le32(0))                     // external attributes
            directory.append(le32(offset))
            directory.append(name)
        }
        let directoryOffset = UInt32(archive.count)
        archive.append(directory)
        archive.append(le32(0x0605_4B50))
        archive.append(le16(0))
        archive.append(le16(0))
        archive.append(le16(UInt16(entries.count)))
        archive.append(le16(UInt16(entries.count)))
        archive.append(le32(UInt32(directory.count)))
        archive.append(le32(directoryOffset))
        archive.append(le16(0))
        return archive
    }

    /// The fields a local header and its central-directory entry share, from
    /// "version needed" through "extra field length".
    private static func commonHeader(name: Data, crc: UInt32, size: UInt32) -> Data {
        var header = Data()
        header.append(le16(20))          // version needed
        header.append(le16(0x0800))      // flags: name is UTF-8
        header.append(le16(0))           // method: stored
        header.append(le16(0))           // time 00:00
        header.append(le16(0x0021))      // date 1980-01-01
        header.append(le32(crc))
        header.append(le32(size))        // compressed
        header.append(le32(size))        // uncompressed
        header.append(le16(UInt16(name.count)))
        header.append(le16(0))           // extra length
        return header
    }

    private static let crcTable: [UInt32] = (0..<256).map { index in
        (0..<8).reduce(UInt32(index)) { crc, _ in crc & 1 == 1 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1 }
    }

    static func crc32(_ data: Data) -> UInt32 {
        ~data.reduce(~UInt32(0)) { crc, byte in crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
    }

    private static func le16(_ value: UInt16) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
    private static func le32(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
}
