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

struct CloudLoginResponse: Decodable {
  struct Company: Decodable { let code: String; let name: String }
  struct User: Decodable { let id: String; let name: String; let role: String }

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

struct CloudBarcodeResponse: Decodable {
  let barcodeMappings: [BarcodeMapping]
}

struct CloudPartsResponse: Decodable {
  let customParts: [CatalogPart]
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
    return WarehouseCloudAccount(
      baseURL: normalized.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
      token: response.token,
      expiresAt: response.expiresAt,
      companyCode: response.company.code,
      companyName: response.company.name,
      userID: response.user.id,
      userName: response.user.name,
      role: response.user.role
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
    return url
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
