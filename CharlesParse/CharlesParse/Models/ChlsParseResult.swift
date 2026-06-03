import Foundation

struct ChlsParseResponse: Codable {
    let parts: [ChlsGzipPart]
}

struct ChlsGzipPart: Codable, Identifiable {
    let index: Int
    let gzipSize: Int
    let decompressedText: String
    let fields: [String: String]
    let gzipBase64: String

    var id: Int { index }

    var gzipData: Data? {
        Data(base64Encoded: gzipBase64)
    }

    var fieldsJSON: String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: fields,
            options: [.prettyPrinted, .sortedKeys]
        ),
        let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }
}

struct FieldRow: Identifiable {
    let key: String
    let value: String
    var id: String { key }
}

extension ChlsGzipPart {
    var fieldRows: [FieldRow] {
        fields.keys.sorted().map { FieldRow(key: $0, value: fields[$0] ?? "") }
    }
}
