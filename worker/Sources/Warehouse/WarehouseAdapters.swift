// Bridges the ported warehouse screens onto PanelVault's design system.
//
// The standalone warehouse app carried its own `WarehouseTheme`, a hand copy of
// PanelTheme "Obsidian Blue". Inside the worker app there is only PanelTheme,
// so the warehouse now follows whichever skin the user picked in More. These
// four names are the ones the warehouse screens use that PanelTheme spells
// differently; mapping them here means the ported screens needed no edits.

import SwiftUI

extension PanelTheme {
  /// Stock arriving, counts that are healthy.
  var positive: Color { success }

  /// Stock that is low but not gone — the "look at me soon" state.
  var warning: Color { designAccent }

  /// Out of stock, failed sync, destructive confirmation.
  var negative: Color { danger }

  /// Secondary label color. Derived from the skin rather than fixed, so it
  /// stays readable on the light themes (Cupertino, Blueprint, Bubblegum).
  var mutedText: Color {
    colorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.55)
  }
}

extension WarehouseStore {
  /// On-hand count for a PanelVault catalog component.
  ///
  /// `StockMovement.partID` and `PanelComponent.id` are the same key — that is
  /// the whole point of generating the warehouse catalog from PanelVault's — so
  /// the equipment catalog can show live stock with no mapping layer.
  ///
  /// Returns nil when signed out, so the catalog hides stock entirely rather
  /// than claiming every part is at zero.
  func stock(for componentID: String) -> Int? {
    guard account != nil else { return nil }
    return onHand[componentID] ?? 0
  }

  /// Combined stock for a component group, for the catalog's category tiles.
  func totalStock(forComponentIDs ids: [String]) -> Int? {
    guard account != nil else { return nil }
    let counts = onHand
    return ids.reduce(0) { $0 + (counts[$1] ?? 0) }
  }
}

struct SectionHeading: View {
  let title: String

  var body: some View {
    Text(title)
      .font(.title2.weight(.heavy))
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct StatTile: View {
  let theme: PanelTheme
  let title: String
  let value: String
  let symbol: String
  let color: Color

  var body: some View {
    GlassCard(theme: theme, padding: 10) {
      VStack(alignment: .leading, spacing: 8) {
        Image(systemName: symbol)
          .font(.system(size: 22, weight: .semibold))
          .foregroundStyle(color)
        Text(title)
          .font(.caption.weight(.bold))
          .foregroundStyle(theme.mutedText)
          .lineLimit(2)
        Text(value)
          .font(.system(size: 26, weight: .black))
          .foregroundStyle(color)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
      }
    }
  }
}
