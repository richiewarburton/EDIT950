import Foundation

enum Tools950Interop {
    // Protocol-v1 wire identifiers remain unchanged so existing suite builds
    // continue to exchange request documents during the product-name migration.
    static let protocolIdentifier = "com.e45recordings.akai-tools"
    static let supportedProtocolVersion = 1
    static let requestUTI = "com.e45recordings.akai-tools.request"
    static let requestExtension = "akaitoolsrequest"
    static let maximumDocumentBytes = 65_536
    static let maximumDependencyCount = 128
    static let maximumPathLength = 4_096
    static let maximumVolumePathLength = 1_024
    static let maximumNativeNameLength = 64
    static let maximumSourceBytes: UInt64 = 34_359_738_368
    static let maximumLifetime: TimeInterval = 24 * 60 * 60

    enum MessageType: String, Codable {
        case exportProgramRequest = "aim.export-program.request"
        case exportCollectionRequest = "aim.export-collection.request"
        case openContentRequest = "aim.open-content.request"
    }

    struct Sender: Codable, Equatable {
        let productID: String
        let version: String
        let build: String?
    }

    struct ResponseTransport: Codable, Equatable {
        let path: String
        let expiresAt: Date
    }

    struct Source: Codable, Equatable {
        let path: String
        let sha256: String
        let byteSize: UInt64?
        let modifiedAt: Date?

        var url: URL { URL(fileURLWithPath: path).standardizedFileURL }
    }

    struct NativeProgram: Codable, Equatable {
        let volumePath: String
        let directoryIndex: Int
        let filename: String
        let internalName: String?
    }

    struct Dependency: Codable, Equatable, Hashable {
        let directoryIndex: Int?
        let filename: String
        let internalName: String?
    }

    struct Request: Codable, Equatable {
        let protocolIdentifier: String
        let protocolVersion: Int
        let messageType: MessageType
        let requestID: UUID
        let createdAt: Date
        let sender: Sender
        let response: ResponseTransport?
        let source: Source
        let program: NativeProgram
        let observedDependencies: [Dependency]?
        let openInPLAY950AfterExport: Bool?
        let exportMode: String?

        enum CodingKeys: String, CodingKey {
            case protocolIdentifier = "protocol"
            case protocolVersion
            case messageType
            case requestID
            case createdAt
            case sender
            case response
            case source
            case program
            case observedDependencies
            case openInPLAY950AfterExport = "openInTRUE950AfterExport"
            case exportMode
        }
    }

    struct CollectionItem: Codable, Equatable, Hashable {
        let sourceIndex: Int
        let volumePath: String
        let directoryIndex: Int
        let filename: String
        let kind: String
    }

    struct CollectionRequest: Codable, Equatable {
        let protocolIdentifier: String
        let protocolVersion: Int
        let messageType: MessageType
        let requestID: UUID
        let createdAt: Date
        let sender: Sender
        let response: ResponseTransport
        let sources: [Source]
        let items: [CollectionItem]

        enum CodingKeys: String, CodingKey {
            case protocolIdentifier = "protocol"
            case protocolVersion
            case messageType
            case requestID
            case createdAt
            case sender
            case response
            case sources
            case items
        }
    }

    struct ExportVerification: Codable, Equatable {
        let sourceSHA256: String
        let destinationSHA256: String
        let sourceUnchanged: Bool
        let exactDirectoryVerified: Bool
        let nativeBytesVerified: Bool
        let backupVerified: Bool
        let rollbackPerformed: Bool
        let sourceByteSize: UInt64
        let destinationByteSize: UInt64
        let importedFileCount: Int
    }

    struct ExportProgramResult: Codable, Equatable {
        let resultingImage: Source
        let resolvedVolumePath: String
        let program: NativeProgram
        let dependencies: [Dependency]
        let backupPath: String?
        let verification: ExportVerification
        let warnings: [String]
    }

    enum ResponseStatus: String, Codable {
        case accepted
        case completed
        case failed
        case rejected
    }

    struct OperationResponse: Codable, Equatable {
        let protocolIdentifier: String
        let protocolVersion: Int
        let messageType: String
        let requestID: UUID
        let createdAt: Date
        let sender: Sender
        let status: ResponseStatus
        let operationType: String
        let summary: String?
        let errorCode: String?
        let details: [String: String]?
        let result: ExportProgramResult?

        enum CodingKeys: String, CodingKey {
            case protocolIdentifier = "protocol"
            case protocolVersion
            case messageType
            case requestID
            case createdAt
            case sender
            case status
            case operationType
            case summary
            case errorCode
            case details
            case result
        }
    }

    struct RequestProbe: Equatable {
        let requestID: UUID
        let response: ResponseTransport
    }

    enum ValidationError: LocalizedError, Equatable {
        case unreadableRequest(String)
        case oversizedDocument(Int)
        case unsupportedProtocol(String)
        case unsupportedVersion(Int)
        case wrongMessageType
        case invalidRequestID
        case invalidTimestamp
        case invalidSender
        case invalidResponseTransport
        case invalidSourcePath
        case invalidSourceHash
        case invalidSourceSize
        case invalidProgramIdentity
        case invalidDependency
        case invalidCollection
        case tooManyDependencies
        case missingDependencies
        case unexpectedField(String)

        var errorCode: String {
            switch self {
            case .unsupportedProtocol: return "unsupportedProtocol"
            case .unsupportedVersion: return "unsupportedVersion"
            case .oversizedDocument: return "oversizedRequest"
            case .invalidSourcePath: return "invalidSourcePath"
            case .invalidSourceHash: return "invalidSourceFingerprint"
            case .invalidResponseTransport: return "invalidResponseTransport"
            case .invalidProgramIdentity: return "invalidProgramIdentity"
            case .invalidDependency, .tooManyDependencies, .missingDependencies:
                return "invalidObservedDependencies"
            case .invalidCollection: return "invalidCollection"
            default: return "malformedRequest"
            }
        }

        var errorDescription: String? {
            switch self {
            case .unreadableRequest(let detail):
                return "The 950TOOLS request could not be read. \(detail)"
            case .oversizedDocument(let count):
                return "The 950TOOLS request is \(count) bytes; protocol v1 permits at most 65,536 bytes."
            case .unsupportedProtocol(let value):
                return "The request uses an unsupported protocol: \(value)."
            case .unsupportedVersion(let value):
                return "950TOOLS request version \(value) is not supported. This version of EDIT950 accepts version 1."
            case .wrongMessageType:
                return "The request message type is not supported by this open-document flow."
            case .invalidRequestID:
                return "The request ID is not a valid UUID."
            case .invalidTimestamp:
                return "The request timestamp or bounded expiry is invalid."
            case .invalidSender:
                return "The request sender identity is outside protocol-v1 bounds."
            case .invalidResponseTransport:
                return "The response path must be a safe sibling of the opened request document."
            case .invalidSourcePath:
                return "The request does not contain a valid bounded absolute source IMG path."
            case .invalidSourceHash:
                return "The request does not contain a valid lowercase SHA-256 source fingerprint."
            case .invalidSourceSize:
                return "The requested source size is outside protocol-v1 bounds."
            case .invalidProgramIdentity:
                return "The request does not contain a complete bounded native P9 identity."
            case .invalidDependency:
                return "An observed dependency is outside protocol-v1 native S9 identity bounds."
            case .invalidCollection:
                return "The collection does not contain a valid bounded set of exact native P9/S9 identities."
            case .tooManyDependencies:
                return "The request contains more than 128 observed dependencies."
            case .missingDependencies:
                return "An export request must include dependencies observed by the sender, even when that list is empty."
            case .unexpectedField(let field):
                return "The request contains an unexpected protocol-v1 field: \(field)."
            }
        }
    }

    static func decodeRequest(from url: URL, now: Date = Date()) throws -> Request {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values?.isRegularFile == true else {
            throw ValidationError.unreadableRequest("The request is not a regular file.")
        }
        if let count = values?.fileSize, count > maximumDocumentBytes {
            throw ValidationError.oversizedDocument(count)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw ValidationError.unreadableRequest(error.localizedDescription)
        }
        return try decodeRequest(data, requestURL: url, now: now)
    }

    static func messageType(from url: URL) throws -> MessageType {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values?.isRegularFile == true else {
            throw ValidationError.unreadableRequest("The request is not a regular file.")
        }
        if let count = values?.fileSize, count > maximumDocumentBytes {
            throw ValidationError.oversizedDocument(count)
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = object["messageType"] as? String,
              let messageType = MessageType(rawValue: raw)
        else { throw ValidationError.wrongMessageType }
        return messageType
    }

    static func decodeCollectionRequest(
        from url: URL,
        now: Date = Date()
    ) throws -> CollectionRequest {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values?.isRegularFile == true else {
            throw ValidationError.unreadableRequest("The request is not a regular file.")
        }
        if let count = values?.fileSize, count > maximumDocumentBytes {
            throw ValidationError.oversizedDocument(count)
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let object: [String: Any]
        guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw ValidationError.unreadableRequest("The top level is not an object.") }
        object = parsed
        try validateCollectionJSONShape(object)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let request: CollectionRequest
        do {
            request = try decoder.decode(CollectionRequest.self, from: data)
        } catch {
            throw ValidationError.unreadableRequest(error.localizedDescription)
        }
        guard request.protocolIdentifier == protocolIdentifier else {
            throw ValidationError.unsupportedProtocol(request.protocolIdentifier)
        }
        guard request.protocolVersion == supportedProtocolVersion else {
            throw ValidationError.unsupportedVersion(request.protocolVersion)
        }
        guard request.messageType == .exportCollectionRequest else {
            throw ValidationError.wrongMessageType
        }
        guard request.createdAt <= now.addingTimeInterval(5 * 60),
              request.createdAt >= now.addingTimeInterval(-maximumLifetime)
        else { throw ValidationError.invalidTimestamp }
        let validSenderBuild = request.sender.build.map {
            bounded($0, maximum: 64, allowEmpty: true)
        } ?? true
        guard bounded(request.sender.productID, maximum: 128, allowEmpty: false),
              bounded(request.sender.version, maximum: 64, allowEmpty: false),
              validSenderBuild
        else { throw ValidationError.invalidSender }
        try validateResponse(
            request.response,
            requestURL: url,
            createdAt: request.createdAt,
            now: now
        )
        guard !request.sources.isEmpty,
              request.sources.count <= 64,
              !request.items.isEmpty,
              request.items.count <= 64,
              Set(request.sources.map(\.path)).count == request.sources.count
        else { throw ValidationError.invalidCollection }
        for source in request.sources {
            guard validAbsolutePath(source.path),
                  source.url.pathExtension.caseInsensitiveCompare("img") == .orderedSame,
                  source.url.path != "/",
                  validSHA256(source.sha256),
                  source.byteSize.map({ $0 > 0 && $0 <= maximumSourceBytes }) ?? true
            else { throw ValidationError.invalidCollection }
        }
        var identities = Set<String>()
        for item in request.items {
            let extensionName = (item.filename as NSString).pathExtension.uppercased()
            let validKind = (item.kind == "program" && extensionName == "P9")
                || (item.kind == "sample" && extensionName == "S9")
            let identity = "\(item.sourceIndex)|\(item.volumePath)|\(item.directoryIndex)|\(item.filename.uppercased())"
            guard request.sources.indices.contains(item.sourceIndex),
                  item.directoryIndex > 0,
                  item.directoryIndex <= 65_535,
                  item.volumePath.hasPrefix("/"),
                  bounded(item.volumePath, maximum: maximumVolumePathLength, allowEmpty: false),
                  bounded(item.filename, maximum: maximumNativeNameLength, allowEmpty: false),
                  validKind,
                  identities.insert(identity).inserted
            else { throw ValidationError.invalidCollection }
        }
        return request
    }

    static func decodeRequest(
        _ data: Data,
        requestURL: URL? = nil,
        now: Date = Date()
    ) throws -> Request {
        guard data.count <= maximumDocumentBytes else {
            throw ValidationError.oversizedDocument(data.count)
        }
        let object: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { throw ValidationError.unreadableRequest("The top level is not an object.") }
            object = parsed
            try validateJSONShape(object)
        } catch let error as ValidationError {
            throw error
        } catch {
            throw ValidationError.unreadableRequest(error.localizedDescription)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let request: Request
        do {
            request = try decoder.decode(Request.self, from: data)
        } catch {
            throw ValidationError.unreadableRequest(error.localizedDescription)
        }
        try validate(request, requestURL: requestURL, now: now)
        return request
    }

    static func probe(_ data: Data, requestURL: URL, now: Date = Date()) throws -> RequestProbe {
        guard data.count <= maximumDocumentBytes,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let requestIDText = object["requestID"] as? String,
              let requestID = UUID(uuidString: requestIDText),
              let responseObject = object["response"] as? [String: Any],
              let responsePath = responseObject["path"] as? String,
              let expiryText = responseObject["expiresAt"] as? String,
              let expiry = ISO8601DateFormatter().date(from: expiryText)
        else { throw ValidationError.invalidResponseTransport }
        let response = ResponseTransport(path: responsePath, expiresAt: expiry)
        try validateResponse(response, requestURL: requestURL, createdAt: now, now: now)
        return RequestProbe(requestID: requestID, response: response)
    }

    static func validate(
        _ request: Request,
        requestURL: URL? = nil,
        now: Date = Date()
    ) throws {
        guard request.protocolIdentifier == protocolIdentifier else {
            throw ValidationError.unsupportedProtocol(request.protocolIdentifier)
        }
        guard request.protocolVersion == supportedProtocolVersion else {
            throw ValidationError.unsupportedVersion(request.protocolVersion)
        }
        guard request.createdAt <= now.addingTimeInterval(5 * 60),
              request.createdAt >= now.addingTimeInterval(-maximumLifetime)
        else { throw ValidationError.invalidTimestamp }
        let validSenderBuild = request.sender.build.map {
            bounded($0, maximum: 64, allowEmpty: true)
        } ?? true
        guard bounded(request.sender.productID, maximum: 128, allowEmpty: false),
              bounded(request.sender.version, maximum: 64, allowEmpty: false),
              validSenderBuild
        else { throw ValidationError.invalidSender }
        guard validAbsolutePath(request.source.path),
              request.source.url.pathExtension.caseInsensitiveCompare("img") == .orderedSame,
              request.source.url.path != "/"
        else { throw ValidationError.invalidSourcePath }
        guard validSHA256(request.source.sha256) else {
            throw ValidationError.invalidSourceHash
        }
        if let size = request.source.byteSize,
           size == 0 || size > maximumSourceBytes {
            throw ValidationError.invalidSourceSize
        }
        let validProgramInternalName = request.program.internalName.map {
            bounded($0, maximum: maximumNativeNameLength, allowEmpty: true)
        } ?? true
        guard request.program.directoryIndex > 0,
              request.program.directoryIndex <= 65_535,
              request.program.volumePath.hasPrefix("/"),
              bounded(request.program.volumePath, maximum: maximumVolumePathLength, allowEmpty: false),
              bounded(request.program.filename, maximum: maximumNativeNameLength, allowEmpty: false),
              (request.program.filename as NSString).pathExtension.caseInsensitiveCompare("P9") == .orderedSame,
              validProgramInternalName
        else { throw ValidationError.invalidProgramIdentity }

        if request.messageType == .exportProgramRequest {
            guard let response = request.response,
                  let requestURL
            else {
                if requestURL == nil, request.response != nil {
                    // Data-only unit decoding cannot enforce sibling location.
                } else {
                    throw ValidationError.invalidResponseTransport
                }
                try validateDependencies(request.observedDependencies)
                return
            }
            try validateResponse(
                response,
                requestURL: requestURL,
                createdAt: request.createdAt,
                now: now
            )
            try validateDependencies(request.observedDependencies)
        }
    }

    private static func validateDependencies(_ dependencies: [Dependency]?) throws {
        guard let dependencies else { throw ValidationError.missingDependencies }
        guard dependencies.count <= maximumDependencyCount else {
            throw ValidationError.tooManyDependencies
        }
        for dependency in dependencies {
            let validInternalName = dependency.internalName.map {
                bounded($0, maximum: maximumNativeNameLength, allowEmpty: true)
            } ?? true
            guard dependency.directoryIndex.map({ $0 > 0 && $0 <= 65_535 }) ?? true,
                  bounded(dependency.filename, maximum: maximumNativeNameLength, allowEmpty: false),
                  (dependency.filename as NSString).pathExtension.caseInsensitiveCompare("S9") == .orderedSame,
                  validInternalName
            else { throw ValidationError.invalidDependency }
        }
    }

    private static func validateResponse(
        _ response: ResponseTransport,
        requestURL: URL,
        createdAt: Date,
        now: Date
    ) throws {
        guard validAbsolutePath(response.path),
              response.expiresAt > now,
              response.expiresAt > createdAt,
              response.expiresAt.timeIntervalSince(createdAt) <= maximumLifetime
        else { throw ValidationError.invalidResponseTransport }
        let requestParent = requestURL.deletingLastPathComponent()
            .standardizedFileURL.resolvingSymlinksInPath()
        let responseURL = URL(fileURLWithPath: response.path).standardizedFileURL
        let responseParent = responseURL.deletingLastPathComponent()
            .standardizedFileURL.resolvingSymlinksInPath()
        guard requestParent == responseParent,
              responseURL.lastPathComponent.hasSuffix(".json"),
              responseURL.path != requestURL.standardizedFileURL.path
        else { throw ValidationError.invalidResponseTransport }
        if FileManager.default.fileExists(atPath: responseURL.path) {
            let values = try? responseURL.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey
            ])
            guard values?.isRegularFile == true, values?.isSymbolicLink != true else {
                throw ValidationError.invalidResponseTransport
            }
        }
    }

    private static func validateJSONShape(_ object: [String: Any]) throws {
        let allowed = Set([
            "protocol", "protocolVersion", "messageType", "requestID", "createdAt",
            "sender", "response", "source", "program", "observedDependencies",
            "openInTRUE950AfterExport", "exportMode"
        ])
        try rejectUnknown(object, allowed: allowed)
        if let sender = object["sender"] as? [String: Any] {
            try rejectUnknown(sender, allowed: ["productID", "version", "build"])
        }
        if let response = object["response"] as? [String: Any] {
            try rejectUnknown(response, allowed: ["path", "expiresAt"])
        }
        if let source = object["source"] as? [String: Any] {
            try rejectUnknown(source, allowed: ["path", "sha256", "byteSize", "modifiedAt"])
        }
        if let program = object["program"] as? [String: Any] {
            try rejectUnknown(program, allowed: ["volumePath", "directoryIndex", "filename", "internalName"])
        }
        if let dependencies = object["observedDependencies"] as? [[String: Any]] {
            for dependency in dependencies {
                try rejectUnknown(dependency, allowed: ["directoryIndex", "filename", "internalName"])
            }
        }
    }

    private static func validateCollectionJSONShape(_ object: [String: Any]) throws {
        try rejectUnknown(
            object,
            allowed: [
                "protocol", "protocolVersion", "messageType", "requestID",
                "createdAt", "sender", "response", "sources", "items"
            ]
        )
        if let sender = object["sender"] as? [String: Any] {
            try rejectUnknown(sender, allowed: ["productID", "version", "build"])
        }
        if let response = object["response"] as? [String: Any] {
            try rejectUnknown(response, allowed: ["path", "expiresAt"])
        }
        if let sources = object["sources"] as? [[String: Any]] {
            for source in sources {
                try rejectUnknown(source, allowed: ["path", "sha256", "byteSize", "modifiedAt"])
            }
        }
        if let items = object["items"] as? [[String: Any]] {
            for item in items {
                try rejectUnknown(
                    item,
                    allowed: ["sourceIndex", "volumePath", "directoryIndex", "filename", "kind"]
                )
            }
        }
    }

    private static func rejectUnknown(_ object: [String: Any], allowed: Set<String>) throws {
        if let key = object.keys.first(where: { !allowed.contains($0) }) {
            throw ValidationError.unexpectedField(key)
        }
    }

    static func makeResponse(
        requestID: UUID,
        status: ResponseStatus,
        operationType: String = "aim.export-program",
        summary: String? = nil,
        errorCode: String? = nil,
        details: [String: String]? = nil,
        result: ExportProgramResult? = nil,
        now: Date = Date()
    ) -> OperationResponse {
        OperationResponse(
            protocolIdentifier: protocolIdentifier,
            protocolVersion: supportedProtocolVersion,
            messageType: "operation.response",
            requestID: requestID,
            createdAt: now,
            sender: responseSender(),
            status: status,
            operationType: operationType,
            summary: summary,
            errorCode: errorCode,
            details: details,
            result: result
        )
    }

    static func responseSender(
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) -> Sender {
        let version = (infoDictionary["CFBundleShortVersionString"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? "development"
        let build = (infoDictionary["CFBundleVersion"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
        return Sender(
            productID: "com.e45recordings.EDIT950",
            version: version,
            build: build
        )
    }

    static func writeResponse(
        _ response: OperationResponse,
        transport: ResponseTransport,
        requestURL: URL
    ) throws {
        try validateResponse(
            transport,
            requestURL: requestURL,
            createdAt: response.createdAt.addingTimeInterval(-1),
            now: response.createdAt.addingTimeInterval(-1)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(response)
        guard data.count <= maximumDocumentBytes else {
            throw ValidationError.oversizedDocument(data.count)
        }
        try data.write(
            to: URL(fileURLWithPath: transport.path),
            options: [.atomic]
        )
    }

    static func readResponse(from url: URL) throws -> OperationResponse {
        let data = try Data(contentsOf: url)
        guard data.count <= maximumDocumentBytes else {
            throw ValidationError.oversizedDocument(data.count)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(OperationResponse.self, from: data)
    }

    static func validSHA256(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy(
            CharacterSet(charactersIn: "0123456789abcdef").contains
        )
    }

    private static func validAbsolutePath(_ path: String) -> Bool {
        guard path.hasPrefix("/"), bounded(path, maximum: maximumPathLength, allowEmpty: false),
              !path.contains("\0")
        else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return !components.contains("..")
    }

    private static func bounded(_ value: String, maximum: Int, allowEmpty: Bool) -> Bool {
        (allowEmpty || !value.isEmpty)
            && value.count <= maximum
            && !value.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7f }
    }
}
