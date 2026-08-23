import Foundation
import Security

struct WarehouseCloudAccount: Codable, Equatable {
  let baseURL: String
  let token: String
  let expiresAt: String
  let companyCode: String
  let companyName: String
  let userID: String
  let userName: String
  let role: String
  /// Sent by the server at sign-in. Optional so an account stored by an
  /// earlier build still decodes; `permissions` falls back to the role rules.
  var can: PanelCapabilities? = nil

  var permissions: PanelCapabilities { can ?? .forRole(role) }
  var roleLabel: String { PanelRole.label(role) }
}

enum WarehouseSyncPhase: Equatable {
  case signedOut
  case idle
  case syncing
  case failed(String)

  var title: String {
    switch self {
    case .signedOut: return "Not connected"
    case .idle: return "Up to date"
    case .syncing: return "Syncing"
    case .failed: return "Needs attention"
    }
  }
}

struct WarehouseSyncMetadata: Codable, Equatable {
  var companyCode = ""
  var syncedMovementIDs: Set<String> = []
  var lastSequence = 0
  var syncedDeliveryIDs: Set<String> = []
  var lastDeliverySequence = 0

  // Added after the first shipped version, so decoding an older file must not
  // fail — a phone that loses its metadata re-uploads everything it has.
  enum CodingKeys: String, CodingKey {
    case companyCode, syncedMovementIDs, lastSequence, syncedDeliveryIDs, lastDeliverySequence
  }

  init(companyCode: String = "") {
    self.companyCode = companyCode
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    companyCode = try container.decodeIfPresent(String.self, forKey: .companyCode) ?? ""
    syncedMovementIDs = try container.decodeIfPresent(Set<String>.self, forKey: .syncedMovementIDs) ?? []
    lastSequence = try container.decodeIfPresent(Int.self, forKey: .lastSequence) ?? 0
    syncedDeliveryIDs = try container.decodeIfPresent(Set<String>.self, forKey: .syncedDeliveryIDs) ?? []
    lastDeliverySequence = try container.decodeIfPresent(Int.self, forKey: .lastDeliverySequence) ?? 0
  }
}

struct CloudMovement: Codable {
  let id: String
  let partID: String
  let kind: StockMovement.Kind
  let quantity: Int
  let reference: String
  let date: String
  let deviceID: String?
  let sequence: Int?

  init(_ movement: StockMovement) {
    id = movement.id
    partID = movement.partID
    kind = movement.kind
    quantity = movement.quantity
    reference = movement.reference
    date = ISO8601DateFormatter.warehouse.string(from: movement.date)
    deviceID = movement.deviceID
    sequence = nil
  }

  var localMovement: StockMovement? {
    guard let parsedDate = ISO8601DateFormatter.warehouse.date(from: date)
      ?? ISO8601DateFormatter().date(from: date) else { return nil }
    return StockMovement(
      id: id,
      partID: partID,
      kind: kind,
      quantity: quantity,
      date: parsedDate,
      reference: reference,
      deviceID: deviceID ?? "cloud"
    )
  }
}

/// Wire shape of a confirmed delivery. Dates travel as strings, like movements,
/// so a server that only speaks ISO-8601 never has to guess an encoding.
struct CloudDeliveryBatch: Codable {
  struct Line: Codable {
    let rawText: String
    let quantity: Int
    let partID: String?
    let included: Bool
    let movementID: String?
  }

  let id: String
  let noteNumber: String
  let supplier: String
  let source: String
  let scannedAt: String
  let confirmedAt: String
  let pageCount: Int
  let lines: [Line]
  let movementIDs: [String]
  let deviceID: String?
  let sequence: Int?

  init(_ batch: DeliveryBatch) {
    id = batch.id
    noteNumber = batch.noteNumber
    supplier = batch.supplier
    source = batch.source.rawValue
    scannedAt = ISO8601DateFormatter.warehouse.string(from: batch.scannedAt)
    confirmedAt = ISO8601DateFormatter.warehouse.string(from: batch.confirmedAt)
    pageCount = batch.pageCount
    lines = batch.lines.map {
      Line(rawText: $0.rawText, quantity: $0.quantity, partID: $0.partID,
           included: $0.included, movementID: $0.movementID)
    }
    movementIDs = batch.movementIDs
    deviceID = batch.deviceID
    sequence = nil
  }

  var localBatch: DeliveryBatch? {
    guard let scanned = CloudDeliveryBatch.date(from: scannedAt),
          let confirmed = CloudDeliveryBatch.date(from: confirmedAt) else { return nil }
    return DeliveryBatch(
      id: id,
      noteNumber: noteNumber,
      supplier: supplier,
      source: DeliveryBatch.Source(rawValue: source) ?? .manual,
      scannedAt: scanned,
      confirmedAt: confirmed,
      pageCount: pageCount,
      lines: lines.enumerated().map { index, line in
        DeliveryBatch.Line(
          id: line.movementID ?? "\(id)-\(index)",
          rawText: line.rawText,
          quantity: line.quantity,
          partID: line.partID,
          included: line.included,
          movementID: line.movementID
        )
      },
      movementIDs: movementIDs,
      deviceID: deviceID ?? "cloud"
    )
  }

  private static func date(from text: String) -> Date? {
    ISO8601DateFormatter.warehouse.date(from: text) ?? ISO8601DateFormatter().date(from: text)
  }
}

struct CloudLoginResponse: Decodable {
  struct Company: Decodable { let code: String; let name: String }
  struct User: Decodable { let id: String; let name: String; let role: String }

  /// Absent when signing in to a PanelVault Cloud older than this app.
  let can: PanelCapabilities?

  let token: String
  let expiresAt: String
  let company: Company
  let user: User
}

struct CloudUploadResponse: Decodable {
  let acceptedIDs: [String]
  let duplicateIDs: [String]
  let latestSequence: Int
}

struct CloudDownloadResponse: Decodable {
  let movements: [CloudMovement]
  let latestSequence: Int
  let hasMore: Bool
  let customParts: [CatalogPart]
  let barcodeMappings: [BarcodeMapping]
}

struct CloudDeliveryUploadResponse: Decodable {
  let acceptedIDs: [String]
  let duplicateIDs: [String]
  let latestSequence: Int
}

struct CloudDeliveryDownloadResponse: Decodable {
  let deliveries: [CloudDeliveryBatch]
  let latestSequence: Int
  let hasMore: Bool
}

struct CloudBarcodeResponse: Decodable {
  let barcodeMappings: [BarcodeMapping]
}

struct CloudPartsResponse: Decodable {
  let customParts: [CatalogPart]
}

struct WarehouseCloudInvite {
  let companyCode: String
  let inviteCode: String

  static func parse(companyCode rawCompany: String, invite rawInvite: String) throws -> WarehouseCloudInvite {
    let fallbackCompany = rawCompany.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    let inviteText = rawInvite.trimmingCharacters(in: .whitespacesAndNewlines)
    if let url = URL(string: inviteText), let fragment = url.fragment {
      let parts = fragment.split(separator: "/").map(String.init)
      if parts.count >= 3, parts[0].lowercased() == "join" {
        return WarehouseCloudInvite(companyCode: parts[1].uppercased(), inviteCode: parts[2].uppercased())
      }
    }
    guard !fallbackCompany.isEmpty, !inviteText.isEmpty else {
      throw WarehouseCloudError.server("Paste the invite link, or enter both company and invite codes.")
    }
    return WarehouseCloudInvite(companyCode: fallbackCompany, inviteCode: inviteText.uppercased())
  }
}

enum WarehouseCloudError: LocalizedError {
  case invalidServer
  case server(String)
  case invalidResponse
  case companyConflict(String)

  var errorDescription: String? {
    switch self {
    case .invalidServer: return "Enter a valid PanelVault Cloud address."
    case .server(let message): return message
    case .invalidResponse: return "PanelVault Cloud returned an invalid response."
    case .companyConflict(let code):
      return "This phone's warehouse is already linked to company \(code)."
    }
  }
}

struct WarehouseCloudClient {
  private let session: URLSession = .shared

  func login(baseURL: String, companyCode: String, name: String, password: String) async throws -> WarehouseCloudAccount {
    let normalized = try normalizedBaseURL(baseURL)
    let payload = ["companyCode": companyCode, "name": name, "password": password]
    let response: CloudLoginResponse = try await request(
      baseURL: normalized,
      path: "/api/mobile/login",
      method: "POST",
      body: payload,
      token: nil
    )
    return account(from: response, baseURL: normalized)
  }

  func createCompany(baseURL: String, companyName: String, name: String, password: String) async throws -> WarehouseCloudAccount {
    let normalized = try normalizedBaseURL(baseURL)
    let payload = ["companyName": companyName, "name": name, "password": password]
    let response: CloudLoginResponse = try await request(
      baseURL: normalized,
      path: "/api/mobile/company",
      method: "POST",
      body: payload,
      token: nil
    )
    return account(from: response, baseURL: normalized)
  }

  func joinCompany(
    baseURL: String,
    companyCode: String,
    inviteCode: String,
    name: String,
    password: String
  ) async throws -> WarehouseCloudAccount {
    let normalized = try normalizedBaseURL(baseURL)
    let invite = try WarehouseCloudInvite.parse(companyCode: companyCode, invite: inviteCode)
    let payload = [
      "companyCode": invite.companyCode,
      "inviteCode": invite.inviteCode,
      "name": name,
      "password": password,
    ]
    let response: CloudLoginResponse = try await request(
      baseURL: normalized,
      path: "/api/mobile/join",
      method: "POST",
      body: payload,
      token: nil
    )
    return account(from: response, baseURL: normalized)
  }

  private func account(from response: CloudLoginResponse, baseURL: URL) -> WarehouseCloudAccount {
    WarehouseCloudAccount(
      baseURL: baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
      token: response.token,
      expiresAt: response.expiresAt,
      companyCode: response.company.code,
      companyName: response.company.name,
      userID: response.user.id,
      userName: response.user.name,
      role: response.user.role,
      can: response.can
    )
  }

  func upload(_ movements: [StockMovement], account: WarehouseCloudAccount) async throws -> CloudUploadResponse {
    try await request(
      baseURL: try normalizedBaseURL(account.baseURL),
      path: "/api/sync/movements",
      method: "POST",
      body: ["movements": movements.map(CloudMovement.init)],
      token: account.token
    )
  }

  func download(after sequence: Int, account: WarehouseCloudAccount) async throws -> CloudDownloadResponse {
    try await request(
      baseURL: try normalizedBaseURL(account.baseURL),
      path: "/api/sync/movements?after=\(sequence)",
      method: "GET",
      body: Optional<String>.none,
      token: account.token
    )
  }

  func uploadDeliveries(
    _ deliveries: [DeliveryBatch],
    account: WarehouseCloudAccount
  ) async throws -> CloudDeliveryUploadResponse {
    try await request(
      baseURL: try normalizedBaseURL(account.baseURL),
      path: "/api/sync/deliveries",
      method: "POST",
      body: ["deliveries": deliveries.map(CloudDeliveryBatch.init)],
      token: account.token
    )
  }

  func downloadDeliveries(
    after sequence: Int,
    account: WarehouseCloudAccount
  ) async throws -> CloudDeliveryDownloadResponse {
    try await request(
      baseURL: try normalizedBaseURL(account.baseURL),
      path: "/api/sync/deliveries?after=\(sequence)",
      method: "GET",
      body: Optional<String>.none,
      token: account.token
    )
  }

  func uploadBarcodeMappings(
    _ mappings: [BarcodeMapping],
    account: WarehouseCloudAccount
  ) async throws -> CloudBarcodeResponse {
    try await request(
      baseURL: try normalizedBaseURL(account.baseURL),
      path: "/api/sync/barcodes",
      method: "POST",
      body: ["barcodeMappings": mappings],
      token: account.token
    )
  }

  func uploadCustomParts(
    _ parts: [CatalogPart],
    account: WarehouseCloudAccount
  ) async throws -> CloudPartsResponse {
    try await request(
      baseURL: try normalizedBaseURL(account.baseURL),
      path: "/api/sync/parts",
      method: "POST",
      body: ["customParts": parts],
      token: account.token
    )
  }

  private func normalizedBaseURL(_ value: String) throws -> URL {
    var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if !text.contains("://") { text = "https://\(text)" }
    guard let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
      throw WarehouseCloudError.invalidServer
    }
    if url.scheme?.lowercased() == "http", !Self.isPrivateDevelopmentHost(url.host ?? "") {
      throw WarehouseCloudError.invalidServer
    }
    return url
  }

  private static func isPrivateDevelopmentHost(_ rawHost: String) -> Bool {
    let host = rawHost.lowercased()
    if host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".local") {
      return true
    }
    let octets = host.split(separator: ".").compactMap { Int($0) }
    guard octets.count == 4 else { return false }
    if octets[0] == 10 || (octets[0] == 192 && octets[1] == 168) { return true }
    return octets[0] == 172 && (16...31).contains(octets[1])
  }

  private func request<Response: Decodable, Body: Encodable>(
    baseURL: URL,
    path: String,
    method: String,
    body: Body?,
    token: String?
  ) async throws -> Response {
    guard let url = URL(string: path, relativeTo: baseURL) else { throw WarehouseCloudError.invalidServer }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = 30
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONEncoder.warehouse.encode(body)
    }

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw WarehouseCloudError.invalidResponse }
    guard 200..<300 ~= http.statusCode else {
      let message = (try? JSONDecoder().decode(CloudErrorResponse.self, from: data).error)
        ?? "PanelVault Cloud request failed (\(http.statusCode))."
      throw WarehouseCloudError.server(message)
    }
    guard let decoded = try? JSONDecoder.warehouse.decode(Response.self, from: data) else {
      throw WarehouseCloudError.invalidResponse
    }
    return decoded
  }
}

private struct CloudErrorResponse: Decodable { let error: String }

enum WarehouseAccountKeychain {
  private static let service = "com.panelvault.warehouse.cloud"
  private static let account = "active-account"

  static func load() -> WarehouseCloudAccount? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
          let data = result as? Data else { return nil }
    return try? JSONDecoder().decode(WarehouseCloudAccount.self, from: data)
  }

  static func save(_ value: WarehouseCloudAccount?) {
    let base: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    SecItemDelete(base as CFDictionary)
    guard let value, let data = try? JSONEncoder().encode(value) else { return }
    var insert = base
    insert[kSecValueData as String] = data
    insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    SecItemAdd(insert as CFDictionary, nil)
  }
}

extension ISO8601DateFormatter {
  static let warehouse: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()
}
