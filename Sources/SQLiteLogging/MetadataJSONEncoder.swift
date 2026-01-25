import Foundation
import Logging

enum MetadataJSONEncoder {
    static func encode(_ metadata: Logger.Metadata) -> String {
        guard !metadata.isEmpty else { return "{}" }
        let object = encodeValue(.dictionary(metadata))
        guard JSONSerialization.isValidJSONObject(object) else { return "{}" }
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            return String(decoding: data, as: UTF8.self)
        } catch {
            return "{}"
        }
    }

    private static func encodeValue(_ value: Logger.MetadataValue) -> Any {
        switch value {
        case .string(let string):
            return string
        case .stringConvertible(let convertible):
            return String(describing: convertible)
        case .array(let array):
            return array.map { encodeValue($0) }
        case .dictionary(let dictionary):
            return dictionary.mapValues { encodeValue($0) }
        }
    }
}
