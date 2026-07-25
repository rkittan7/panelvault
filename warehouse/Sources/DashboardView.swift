import SwiftUI

struct DashboardView: View {
  let theme: WarehouseTheme
  @EnvironmentObject private var store: WarehouseStore

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          statsGrid
          if !store.lowStock.isEmpty {
            SectionHeading(title: "Low Stock")
            ForEach(store.lowStock) { entry in
              NavigationLink(value: entry.part.id) {
                LowStockRow(theme: theme, entry: entry)
              }
              .buttonStyle(.plain)
            }
          }
          SectionHeading(title: "Recent Activity")
          if store.recentMovements.isEmpty {
            GlassCard(theme: theme) {
              Text("No movements yet. Receive your first delivery from the Receive tab.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.mutedText)
            }
          } else {
            ForEach(store.recentMovements.prefix(8)) { movement in
              MovementRow(theme: theme, movement: movement)
            }
          }
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Warehouse")
      .navigationDestination(for: String.self) { partID in
        ItemDetailView(theme: theme, partID: partID)
      }
    }
  }

  private var statsGrid: some View {
    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
      StatTile(theme: theme, title: "Parts Stocked", value: "\(store.entries.count)", symbol: "shippingbox.fill", color: theme.primary)
      StatTile(theme: theme, title: "Units On Hand", value: "\(store.totalUnits)", symbol: "number.square.fill", color: theme.secondary)
      StatTile(theme: theme, title: "Low Stock", value: "\(store.lowStock.count)", symbol: "exclamationmark.triangle.fill", color: store.lowStock.isEmpty ? theme.positive : theme.warning)
      StatTile(theme: theme, title: "Movements", value: "\(store.movements.count)", symbol: "clock.arrow.circlepath", color: theme.positive)
    }
  }
}

struct LowStockRow: View {
  let theme: WarehouseTheme
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
  let theme: WarehouseTheme
  let movement: StockMovement

  private var partName: String {
    Catalog.part(for: movement.partID)?.displayName ?? movement.partID
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
