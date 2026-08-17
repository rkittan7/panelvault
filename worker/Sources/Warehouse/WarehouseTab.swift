// The warehouse tab — the worker app's centre tab, where the "+" creation hub
// sits in the manager app.
//
// The standalone warehouse app spreads this across five tabs (Dashboard, Stock,
// Receive, Activity, Cloud). Here there is one tab, so the summary is the
// screen and the other four open as sheets. That is PanelVault's own pattern —
// the manager app presents projects, boards and the component catalog the same
// way — and it means the ported screens needed no changes to their navigation.

import SwiftUI

struct WarehouseTabView: View {
  let theme: PanelTheme
  @EnvironmentObject private var store: WarehouseStore

  @State private var sheet: WarehouseSheet?

  var body: some View {
    NavigationStack {
      ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: 18) {
          syncStatus
          statsGrid
          actions

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
              Text("No movements yet. Tap Receive to scan your first delivery note.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.mutedText)
            }
          } else {
            ForEach(store.recentMovements.prefix(8)) { movement in
              MovementRow(theme: theme, movement: movement)
            }
            if store.recentMovements.count > 8 {
              Button {
                sheet = .activity
              } label: {
                Text("See all \(store.recentMovements.count) movements")
                  .font(.system(size: 14, weight: .bold))
                  .foregroundStyle(theme.primary)
              }
              .buttonStyle(.plain)
            }
          }

          BottomTabClearance()
        }
        .padding(18)
        .padding(.top, 6)
      }
      .background(theme.background.ignoresSafeArea())
      .overlay(alignment: .top) { TopScrollBlur(theme: theme) }
      .navigationTitle("Warehouse")
      // `navigationDestination(for:)` rather than the iOS 17 `item:` overload —
      // the app targets iOS 16, same as the warehouse app it came from.
      .navigationDestination(for: String.self) { partID in
        ItemDetailView(theme: theme, partID: partID)
      }
    }
    .sheet(item: $sheet) { which in
      // The store is injected explicitly on each sheet rather than relying on
      // the presentation inheriting it: an @EnvironmentObject that fails to
      // propagate is a crash, not a blank screen.
      Group {
        switch which {
        case .stock:
          StockListView(theme: theme)
        case .receive:
          ReceiveView(theme: theme)
        case .activity:
          ActivityView(theme: theme)
        case .cloud:
          AccountView(theme: theme)
        }
      }
      .environmentObject(store)
    }
  }

  // MARK: - Sections

  private var syncStatus: some View {
    HStack(spacing: 9) {
      Image(systemName: store.account == nil ? "icloud.slash" : "icloud.fill")
        .foregroundStyle(store.account == nil ? theme.mutedText : theme.secondary)
      Text(store.syncPhase.title)
        .font(.footnote.weight(.bold))
      if store.pendingMovementCount > 0 {
        Text("\(store.pendingMovementCount) waiting")
          .font(.caption.weight(.bold))
          .foregroundStyle(theme.warning)
      }
      Spacer()
      if store.syncPhase == .syncing {
        ProgressView().controlSize(.small).tint(theme.secondary)
      } else {
        Button {
          sheet = .cloud
        } label: {
          Text(store.account == nil ? "Sign in" : "Cloud")
            .font(.caption.weight(.heavy))
            .foregroundStyle(theme.primary)
        }
        .buttonStyle(.plain)
      }
    }
    .foregroundStyle(theme.mutedText)
    .padding(.horizontal, 4)
  }

  private var statsGrid: some View {
    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
      StatTile(theme: theme, title: "Parts Stocked", value: "\(store.entries.count)", symbol: "shippingbox.fill", color: theme.primary)
      StatTile(theme: theme, title: "Units On Hand", value: "\(store.totalUnits)", symbol: "number.square.fill", color: theme.secondary)
      StatTile(theme: theme, title: "Low Stock", value: "\(store.lowStock.count)", symbol: "exclamationmark.triangle.fill", color: store.lowStock.isEmpty ? theme.positive : theme.warning)
      StatTile(theme: theme, title: "Movements", value: "\(store.movements.count)", symbol: "clock.arrow.circlepath", color: theme.positive)
    }
  }

  /// Receive is the loud one on purpose: taking a delivery is the job this app
  /// exists for, and it happens with a phone in one hand and a box in the other.
  private var actions: some View {
    VStack(spacing: 10) {
      Button {
        sheet = .receive
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "doc.viewfinder.fill")
            .font(.system(size: 20, weight: .bold))
          Text("Receive Delivery")
            .font(.system(size: 17, weight: .heavy))
          Spacer()
          Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .bold))
            .opacity(0.7)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(height: 58)
        .frame(maxWidth: .infinity)
        .background(
          LinearGradient(
            colors: [theme.primary, theme.primary.opacity(0.78)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
        .clipShape(RoundedRectangle(cornerRadius: theme.radiusCard, style: .continuous))
      }
      .buttonStyle(PanelPressButtonStyle())

      HStack(spacing: 10) {
        secondaryAction("Stock", symbol: "shippingbox.fill", color: theme.secondary) { sheet = .stock }
        secondaryAction("Activity", symbol: "clock.arrow.circlepath", color: theme.info) { sheet = .activity }
      }
    }
  }

  private func secondaryAction(
    _ title: String,
    symbol: String,
    color: Color,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(spacing: 7) {
        Image(systemName: symbol)
          .font(.system(size: 21, weight: .semibold))
          .foregroundStyle(color)
        Text(title)
          .font(.system(size: 14, weight: .heavy))
      }
      .frame(maxWidth: .infinity)
      .frame(height: 74)
      .background(theme.surface.opacity(0.78))
      .clipShape(RoundedRectangle(cornerRadius: theme.radiusCard, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: theme.radiusCard, style: .continuous)
          .stroke(theme.cardBorder, lineWidth: 1)
      )
    }
    .buttonStyle(PanelPressButtonStyle())
  }
}

enum WarehouseSheet: String, Identifiable {
  case stock
  case receive
  case activity
  case cloud

  var id: String { rawValue }
}
