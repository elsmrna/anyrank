import Foundation

/// Minimal CSV reader/writer. The spec is intentionally tight: fields
/// separated by commas, quoted with double-quotes when they contain a
/// comma, newline, or double-quote; embedded double-quotes are escaped by
/// doubling (`""`); rows terminated by `\n`. UTF-8 throughout. No BOM.
///
/// This implementation handles the cases an English-language single-user
/// app actually produces. It does not handle Excel's full CSV dialect
/// (carriage returns inside fields, multi-line headers, BOM markers).
enum CSV {

    /// Encode a list of rows (each row a list of field strings) into a CSV
    /// document. Quotes each field defensively to keep round-tripping safe.
    static func encode(rows: [[String]]) -> String {
        var output = ""
        for row in rows {
            output += row.map(quote).joined(separator: ",")
            output += "\n"
        }
        return output
    }

    /// Decode a CSV document into rows. Returns an empty array for an
    /// empty input. Tolerates trailing newlines and ignores empty trailing
    /// rows. Throws `CSVError.malformed` if an opening quote is never closed.
    static func decode(_ text: String) throws -> [[String]] {
        var rows: [[String]] = []
        var current: [String] = []
        var field = ""
        var inQuotes = false
        var i = text.startIndex

        while i < text.endIndex {
            let c = text[i]
            if inQuotes {
                if c == "\"" {
                    let next = text.index(after: i)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        i = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"":
                    inQuotes = true
                case ",":
                    current.append(field)
                    field = ""
                case "\n":
                    current.append(field)
                    field = ""
                    rows.append(current)
                    current = []
                case "\r":
                    break // skip carriage returns; we treat \n as the row terminator
                default:
                    field.append(c)
                }
            }
            i = text.index(after: i)
        }

        if inQuotes {
            throw CSVError.malformed("Unterminated quoted field")
        }

        // Flush trailing field/row if the document didn't end with a newline.
        if !field.isEmpty || !current.isEmpty {
            current.append(field)
            rows.append(current)
        }

        // Drop fully-empty trailing rows that some editors produce.
        while let last = rows.last, last.count == 1, last[0].isEmpty {
            rows.removeLast()
        }

        return rows
    }

    /// Wrap a field in double-quotes if it contains a comma, newline, or
    /// quote; otherwise return it unchanged. We over-quote any field with
    /// internal quotes for safety.
    private static func quote(_ field: String) -> String {
        let needsQuoting = field.contains(",")
            || field.contains("\n")
            || field.contains("\"")
        if !needsQuoting { return field }
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}

enum CSVError: LocalizedError {
    case malformed(String)

    var errorDescription: String? {
        switch self {
        case .malformed(let detail): return "Malformed CSV: \(detail)"
        }
    }
}
