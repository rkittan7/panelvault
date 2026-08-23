// The permission model, shared by every PanelVault client.
//
// tools/port_warehouse.py skips this file: the worker app already has these
// types from the PanelVault side, and porting it would redeclare them in the
// same target. Keep this in step with ios/Runner/SceneDelegate.swift.

import Foundation

/// What the signed-in user is allowed to do.
///
/// The server decides this and sends it at sign-in — see `capabilitiesFor` in
/// webapp/server.js — so the phone permits exactly what PanelVault Cloud will
/// accept. Deriving the rules a second time here is what let the apps drift:
/// they used to treat "owner or manager" as the admin set and locked out staff
/// managers, who the website has always allowed.
struct PanelCapabilities: Codable, Equatable {
  /// Change stock, manage parts, teach barcodes, create and assign boards.
  var administer = false
  /// See unit prices, stock value and board cost.
  var seeCosts = false
  var signOffQA = false
  var manageMembers = false

  /// The same role rules the server applies, for an account that was cached
  /// before the server started sending capabilities, or one signed in against
  /// an older PanelVault Cloud. Kept in step with the sets in server.js.
  static func forRole(_ role: String) -> PanelCapabilities {
    PanelCapabilities(
      administer: ["owner", "manager", "staff-manager"].contains(role),
      seeCosts: ["owner", "manager"].contains(role),
      signOffQA: ["owner", "manager", "staff-manager", "qa"].contains(role),
      manageMembers: role == "owner"
    )
  }

  /// Nobody is signed in. The phone is a local notebook: it may still record
  /// work, and the sync will reject anything the account is not allowed to
  /// push — which is why the sign-in state, not this, gates uploads.
  static let signedOut = PanelCapabilities(
    administer: true, seeCosts: true, signOffQA: true, manageMembers: false
  )
}

/// Role names as PanelVault Cloud spells them. `ROLE_LABELS` in server.js.
enum PanelRole {
  static func label(_ role: String) -> String {
    switch role {
    case "owner": return "Owner"
    case "manager": return "Manager"
    case "staff-manager": return "Staff Manager"
    case "qa": return "QA"
    case "staff": return "Staff"
    default: return role.capitalized
    }
  }
}
