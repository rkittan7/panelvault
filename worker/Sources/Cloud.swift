// Copied from the PanelVault app (ios/Runner/SceneDelegate.swift) by
// tools/split_worker.py. The worker app is a deliberate copy of PanelVault's
// design system and data model, with manager-only creation removed and the
// warehouse added. Edit here; do not re-run the splitter over hand edits.

import SwiftUI
import Foundation
import Security

/// Credentials and identity for a PanelVault Cloud session. Mirrors the
/// warehouse app's `WarehouseCloudAccount` so both clients speak one contract.
struct PanelCloudAccount: Codable, Equatable {
  let baseURL: String
  let token: String
  let expiresAt: String
  let companyCode: String
  let companyName: String
  let userName: String
  let role: String
}

struct PanelCloudLoginResponse: Decodable {
  struct Company: Decodable { let code: String; let name: String }
  struct User: Decodable { let id: String; let name: String; let role: String }
  let token: String
  let expiresAt: String
  let company: Company
  let user: User
}

/// One movement as Cloud returns it, narrowed to what stock derivation needs.
struct PanelCloudMovement: Decodable {
  let id: String
  let partID: String
  let kind: String
  let quantity: Int
  let sequence: Int?

  /// Effect on the on-hand count. Matches `StockMovement.delta` in the
  /// warehouse app: receive adds, consume subtracts, adjust carries a signed
  /// delta.
  var delta: Int {
    switch kind {
    case "receive": return quantity
    case "consume": return -quantity
    default: return quantity
    }
  }
}

struct PanelCloudDownloadResponse: Decodable {
  let movements: [PanelCloudMovement]
  let latestSequence: Int
  let hasMore: Bool
}

enum PanelCloudError: LocalizedError {
  case invalidServer
  case server(String)
  case invalidResponse

  var errorDescription: String? {
    switch self {
    case .invalidServer: return "Enter a valid PanelVault Cloud address."
    case .server(let message): return message
    case .invalidResponse: return "PanelVault Cloud returned an invalid response."
    }
  }
}

/// What PanelVault Cloud read out of an AutoCAD board scheme.
///
/// Every field is optional in practice: the server is told to return an empty
/// string rather than infer a value it cannot see on the drawing, because a
/// blank a manager fills in takes seconds and a confident wrong one gets built.
struct BoardSchemeReading: Decodable {
  struct Board: Decodable {
    var number = ""
    var name = ""
    var customer = ""
    var project = ""
    var type = ""
    var manufacturer = ""
    var mainBreakerType = ""
    var mainBreakerModel = ""
    var mainBreakerAmpere = ""
    var cabinetCount = 1
    var notes = ""
  }

  /// A schedule line matched to a catalog part.
  struct Component: Decodable, Identifiable {
    let partID: String
    var manufacturer = ""
    var model = ""
    var type = ""
    var quantity = 1
    var reference = ""

    var id: String { reference.isEmpty ? partID : "\(partID)-\(reference)" }
    var displayName: String { "\(manufacturer) \(model)".trimmingCharacters(in: .whitespaces) }
  }

  /// A schedule line the catalog has no confident match for. Shown so nobody
  /// assumes the board is complete when part of the schedule was not placed.
  struct Unmatched: Decodable, Identifiable {
    var description = ""
    var type = ""
    var quantity = 1
    var reference = ""

    var id: String { "\(description)-\(reference)" }
  }

  var board = Board()
  var components: [Component] = []
  var unmatched: [Unmatched] = []
  var model: String?

  var componentCount: Int { components.reduce(0) { $0 + $1.quantity } }
  var isEmpty: Bool {
    board.number.isEmpty && board.name.isEmpty && components.isEmpty && unmatched.isEmpty
  }
}

struct PanelCloudClient {
  func login(baseURL: String, companyCode: String, name: String, password: String) async throws -> PanelCloudAccount {
    let normalized = try PanelCloudClient.normalizedBaseURL(baseURL)
    let response: PanelCloudLoginResponse = try await request(
      baseURL: normalized,
      path: "/api/mobile/login",
      method: "POST",
      body: ["companyCode": companyCode, "name": name, "password": password],
      token: nil
    )
    return PanelCloudAccount(
      baseURL: normalized.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
      token: response.token,
      expiresAt: response.expiresAt,
      companyCode: response.company.code,
      companyName: response.company.name,
      userName: response.user.name,
      role: response.user.role
    )
  }

  func download(after sequence: Int, account: PanelCloudAccount) async throws -> PanelCloudDownloadResponse {
    try await request(
      baseURL: try PanelCloudClient.normalizedBaseURL(account.baseURL),
      path: "/api/sync/movements?after=\(sequence)",
      method: "GET",
      body: Optional<[String: String]>.none,
      token: account.token
    )
  }

  /// Send an AutoCAD scheme to PanelVault Cloud and get the board it describes.
  ///
  /// The drawing itself goes up — Gemini reads PDFs natively, so nothing is
  /// rasterised or OCR'd here. Reading a large multi-page scheme is slow by
  /// nature, hence the long timeout; the caller shows progress for it.
  func readBoardScheme(
    fileName: String,
    mimeType: String,
    data: Data,
    account: PanelCloudAccount
  ) async throws -> BoardSchemeReading {
    try await request(
      baseURL: try PanelCloudClient.normalizedBaseURL(account.baseURL),
      path: "/api/ai/board-scheme",
      method: "POST",
      body: [
        "fileName": fileName,
        "mimeType": mimeType,
        "data": data.base64EncodedString(),
      ],
      token: account.token,
      timeout: 180
    )
  }

  private static func normalizedBaseURL(_ value: String) throws -> URL {
    var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if !text.contains("://") { text = "https://\(text)" }
    guard let url = URL(string: text),
          ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
          url.host != nil else { throw PanelCloudError.invalidServer }
    return url
  }

  private func request<Response: Decodable, Body: Encodable>(
    baseURL: URL,
    path: String,
    method: String,
    body: Body?,
    token: String?,
    timeout: TimeInterval = 30
  ) async throws -> Response {
    guard let url = URL(string: path, relativeTo: baseURL) else { throw PanelCloudError.invalidServer }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = timeout
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONEncoder().encode(body)
    }

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw PanelCloudError.invalidResponse }
    guard 200..<300 ~= http.statusCode else {
      let message = (try? JSONDecoder().decode(PanelCloudErrorBody.self, from: data).error)
        ?? "PanelVault Cloud request failed (\(http.statusCode))."
      throw PanelCloudError.server(message)
    }
    guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
      throw PanelCloudError.invalidResponse
    }
    return decoded
  }
}

struct PanelCloudErrorBody: Decodable { let error: String }

/// The session token lives in the keychain, not UserDefaults. Its service id is
/// distinct from the warehouse app's so the two never fight over one entry.
enum PanelCloudKeychain {
  private static let service = "com.panelvault.ios.cloud"
  private static let account = "active-account"

  static func load() -> PanelCloudAccount? {
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
    return try? JSONDecoder().decode(PanelCloudAccount.self, from: data)
  }

  static func save(_ value: PanelCloudAccount?) {
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

/// Small pill showing on-hand stock for a catalog part.
struct StockBadge: View {
  let theme: PanelTheme
  let count: Int
  var compact = false

  private var color: Color {
    if count <= 0 { return theme.danger }
    if count <= 5 { return theme.designAccent }
    return theme.success
  }

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: "shippingbox.fill")
        .font(.system(size: compact ? 8 : 9, weight: .bold))
      Text(count <= 0 ? "None" : "\(count)")
        .font(.system(size: compact ? 10 : 11, weight: .heavy))
    }
    .foregroundStyle(color)
    .lineLimit(1)
    .padding(.horizontal, 7)
    .frame(height: compact ? 19 : 21)
    .background(color.opacity(0.14))
    .clipShape(Capsule())
  }
}
