// Ported from warehouse/Sources by tools/port_warehouse.py so the worker app
// carries the warehouse itself. The standalone warehouse app is unchanged;
// see worker/README.md for how the two relate.

import SwiftUI

struct LowStockRow: View {
  let theme: PanelTheme
  let entry: StockEntry

  var body: some View {
    GlassCard(theme: theme, padding: 12) {
      HStack(spacing: 12) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(theme.warning)
        VStack(alignment: .leading, spacing: 4) {
          Text(entry.part.displayName)
            .font(.subheadline.weight(.heavy))
            .lineLimit(1)
          Text("\(entry.onHand) left • minimum \(entry.settings.minimumLevel ?? 0)")
            .font(.caption.weight(.semibold))
            .foregroundStyle(theme.mutedText)
        }
        Spacer()
        Image(systemName: "chevron.right")
          .foregroundStyle(theme.mutedText)
      }
    }
  }
}

struct MovementRow: View {
  let theme: PanelTheme
  let movement: StockMovement
  @EnvironmentObject private var store: WarehouseStore

  private var partName: String {
    store.part(for: movement.partID)?.displayName ?? movement.partID
  }

  private var symbol: (name: String, color: Color) {
    switch movement.kind {
    case .receive: return ("arrow.down.circle.fill", theme.positive)
    case .consume: return ("arrow.up.circle.fill", theme.secondary)
    case .adjust: return ("slider.horizontal.3", theme.warning)
    }
  }

  var body: some View {
    GlassCard(theme: theme, padding: 12) {
      HStack(spacing: 12) {
        Image(systemName: symbol.name)
          .font(.system(size: 20))
          .foregroundStyle(symbol.color)
        VStack(alignment: .leading, spacing: 3) {
          Text(partName)
            .font(.subheadline.weight(.heavy))
            .lineLimit(1)
          Text(movement.reference.isEmpty
               ? movement.date.formatted(date: .abbreviated, time: .shortened)
               : "\(movement.reference) • \(movement.date.formatted(date: .abbreviated, time: .shortened))")
            .font(.caption.weight(.semibold))
            .foregroundStyle(theme.mutedText)
            .lineLimit(1)
        }
        Spacer()
        Text(movement.delta > 0 ? "+\(movement.delta)" : "\(movement.delta)")
          .font(.headline.weight(.black))
          .foregroundStyle(movement.delta >= 0 ? theme.positive : theme.negative)
      }
    }
  }
}
