import Foundation

enum AkaiCommandBuilder {
    static func validate(_ command: String) throws -> String {
        guard !command.isEmpty,
              !command.contains("\n"),
              !command.contains("\r"),
              command.utf8.allSatisfy({ $0 >= 0x20 && $0 != 0x7f })
        else {
            throw AppError.unsafeCommand("Commands must be a single printable line.")
        }
        return command
    }

    static func externalToken(_ value: String) throws -> String {
        guard !value.isEmpty, !value.contains(where: \.isWhitespace) else {
            throw AppError.unsafeCommand("AKAI Util cannot parse spaces in local paths. A safe temporary alias is required.")
        }
        guard !value.contains("\n"), !value.contains("\r") else {
            throw AppError.unsafeCommand("The path contains a line break.")
        }
        return value
    }

    static func akaiPathToken(_ value: String) throws -> String {
        guard !value.contains("\n"), !value.contains("\r") else {
            throw AppError.unsafeCommand("The AKAI path contains a line break.")
        }
        return value.replacingOccurrences(of: " ", with: "_")
    }

    static func changeDirectory(_ path: String) throws -> String {
        "cd \(try akaiPathToken(path))"
    }

    static func localDirectory(_ path: String) throws -> String {
        "lcd \(try externalToken(path))"
    }

    static func delete(index: Int) throws -> String {
        guard index > 0 else { throw AppError.unsafeCommand("File indexes start at 1.") }
        return "deli \(index)"
    }

    static func delete(path: String) throws -> String {
        "del \(try akaiPathToken(path))"
    }

    static func importWAV(filename: String, options: ImportOptions) throws -> String {
        let command = options.compressedS900 ? "wav2sample9c" : "wav2sample9"
        return "\(command) \(try externalToken(filename))"
    }

    static func exportWAV(index: Int) throws -> String {
        guard index > 0 else { throw AppError.unsafeCommand("File indexes start at 1.") }
        return "sample2wavi \(index)"
    }

    static func importNative(filename: String) throws -> String {
        "put \(try externalToken(filename))"
    }

    static func exportNative(index: Int) throws -> String {
        guard index > 0 else { throw AppError.unsafeCommand("File indexes start at 1.") }
        return "geti \(index)"
    }

    static func fileInformation(index: Int) throws -> String {
        guard index > 0 else {
            throw AppError.unsafeCommand("File indexes start at 1.")
        }
        return "infoi \(index)"
    }

    static func fixRAMName(index: Int) throws -> String {
        guard index > 0 else { throw AppError.unsafeCommand("File indexes start at 1.") }
        return "fixramnamei \(index)"
    }

    static func deletionOrder(_ indexes: [Int]) -> [Int] {
        Array(Set(indexes.filter { $0 > 0 })).sorted(by: >)
    }

    static func modifiesImage(_ command: String) -> Bool {
        guard let verb = command.split(whereSeparator: \.isWhitespace).first
        else { return false }
        return [
            "del",
            "deli",
            "fixramnameall",
            "fixramnamei",
            "formatfloppyh9",
            "formatfloppyl9",
            "formatharddisk9",
            "mkvol9",
            "put",
            "wav2sample9",
            "wav2sample9c"
        ].contains(verb.lowercased())
    }
}

enum AkaiFilename {
    private static let s950AllowedCharacters = Set(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
    )

    static func sanitizedBase(_ name: String, family: AkaiFamily, maximumLength: Int = 12) -> String {
        let stem = (name as NSString).deletingPathExtension
        let folded = stem.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
        var result = folded.uppercased().map {
            s950AllowedCharacters.contains($0) ? $0 : "_"
        }
        while result.first == "_" { result.removeFirst() }
        while result.last == "_" { result.removeLast() }
        if result.isEmpty { result = Array("SAMPLE") }
        let familyLimit = min(maximumLength, 10)
        return String(result.prefix(familyLimit))
    }

    static func normalizedS950Base(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    static func s950BaseValidationError(_ name: String) -> String? {
        let normalized = normalizedS950Base(name)
        guard !normalized.isEmpty else {
            return "Enter a sample name."
        }
        guard normalized.count <= 10 else {
            return "S950 names are limited to 10 characters."
        }
        guard normalized.allSatisfy({ s950AllowedCharacters.contains($0) }) else {
            return "Use only A–Z, 0–9, underscore or hyphen."
        }
        guard normalized.first != "_", normalized.last != "_" else {
            return "An S950 name cannot begin or end with an underscore."
        }
        return nil
    }

    static func validatedS950Base(_ name: String) throws -> String {
        if let validationError = s950BaseValidationError(name) {
            throw AppError.verificationFailed(validationError)
        }
        return normalizedS950Base(name)
    }

    static func uniqueName(base: String, existing: Set<String>, maximumLength: Int = 12) -> String {
        guard existing.contains(base.uppercased()) else { return base }
        for number in 2...999 {
            let suffix = "_\(number)"
            let prefix = String(base.prefix(max(1, maximumLength - suffix.count)))
            let candidate = prefix + suffix
            if !existing.contains(candidate.uppercased()) { return candidate }
        }
        return String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(maximumLength))
    }
}

/// The one naming pipeline used by new S950 P9 programs. Native P9 names may
/// contain spaces; AKAI Util represents those spaces as underscores only in the
/// local staging filename supplied to `put`.
struct P9CanonicalName: Equatable {
    static let maximumLength = 10

    let base: String

    var filename: String { "\(base).P9" }
    var stagingFilename: String {
        "\(base.replacingOccurrences(of: " ", with: "_")).P9"
    }
    var lookupKey: String { Self.lookupKey(filename) }

    static func resolve(
        _ proposedName: String,
        existingFilenames: [String] = []
    ) throws -> P9CanonicalName {
        let initial = try canonicalBase(proposedName)
        let existing = Set(existingFilenames.map(lookupKey))
        guard existing.contains(lookupKey("\(initial).P9")) else {
            return P9CanonicalName(base: initial)
        }

        for number in 2...999 {
            let suffix = "-\(number)"
            let prefix = String(initial.prefix(maximumLength - suffix.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: " -"))
            let candidate = String((prefix + suffix).prefix(maximumLength))
            if !existing.contains(lookupKey("\(candidate).P9")) {
                return P9CanonicalName(base: candidate)
            }
        }
        throw AppError.verificationFailed(
            "No unique S950 P9 name is available for \(initial)."
        )
    }

    static func canonicalBase(_ proposedName: String) throws -> String {
        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let stem: String
        if (trimmed as NSString).pathExtension.caseInsensitiveCompare("p9") == .orderedSame {
            stem = (trimmed as NSString).deletingPathExtension
        } else {
            stem = trimmed
        }
        let folded = stem.folding(
            options: [.diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).uppercased()

        var result = ""
        var pendingSeparator: Character?
        for character in folded {
            if character.isASCII, character.isLetter || character.isNumber {
                if let separator = pendingSeparator, !result.isEmpty {
                    result.append(separator)
                }
                pendingSeparator = nil
                result.append(character)
            } else if character == " " || character == "_" || character.isWhitespace {
                if pendingSeparator == nil { pendingSeparator = " " }
            } else if character == "-" {
                pendingSeparator = "-"
            } else {
                // Illegal punctuation is made visible and deterministic rather
                // than silently falling back to a generic program name.
                pendingSeparator = "-"
            }
            if result.count >= maximumLength { break }
        }
        let canonical = String(result.prefix(maximumLength))
            .trimmingCharacters(in: CharacterSet(charactersIn: " -"))
        guard !canonical.isEmpty else {
            throw AppError.verificationFailed("Enter a program name containing a letter or number.")
        }
        return canonical
    }

    static func lookupKey(_ filename: String) -> String {
        let stem: String
        if (filename as NSString).pathExtension.caseInsensitiveCompare("p9") == .orderedSame {
            stem = (filename as NSString).deletingPathExtension
        } else {
            stem = filename
        }
        return stem.uppercased()
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
