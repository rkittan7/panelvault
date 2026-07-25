import SwiftUI

@main
struct WarehouseApp: App {
  @StateObject private var store = WarehouseStore()

  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(store)
        .preferredColorScheme(.dark)
    }
  }
}

struct RootView: View {
  @EnvironmentObject private var store: WarehouseStore
  private let theme = WarehouseTheme.standard

  var body: some View {
    TabView {
      DashboardView(theme: theme)
        .tabItem { Label("Dashboard", systemImage: "square.grid.2x2.fill") }
      StockListView(theme: theme)
        .tabItem { Label("Stock", systemImage: "shippingbox.fill") }
      ReceiveView(theme: theme)
        .tabItem { Label("Receive", systemImage: "doc.viewfinder.fill") }
      ActivityView(theme: theme)
        .tabItem { Label("Activity", systemImage: "clock.arrow.circlepath") }
    }
    .tint(theme.primary)
  }
}
