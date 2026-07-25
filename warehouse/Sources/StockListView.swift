import SwiftUI

struct StockListView: View {
  let theme: WarehouseTheme
  @EnvironmentObject private var store: WarehouseStore
  @State private var query = ""
  @State private var addingPart = false

  private var filtered: [StockEntry] {
    let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
    guard !trimmed.isEmpty else { return store.entries }
    return store.entries.filter { $0.part.searchText.contains(trimmed) }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 10) {
          if store.entries.isEmpty {
            GlassCard(theme: theme) {
              VStack(alignment: .leading, spacing: 8) {
                Text("No stock yet")
                  .font(.headline.weight(.heavy))
                Text("Add a part to track, or receive a delivery from the Receive tab.")
                  .font(.subheadline.weight(.semibold))
                  .foregroundStyle(theme.mutedText)
              }
            }
          }
          ForEach(filtered) { entry in
            NavigationLink(value: entry.part.id) {
              StockRow(theme: theme, entry: entry)
            }
            .buttonStyle(.plain)
          }
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Stock")
      .searchable(text: $query, prompt: "Search model, type, manufacturer")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            addingPart = true
          } label: {
            Image(systemName: "plus")
          }
        }
      }
      .sheet(isPresented: $addingPart) {
        PartPickerSheet(theme: theme, title: "Track a Part") { part in
          // Tracking with no stock yet: settings entry makes it visible.
          store.updateSettings(for: part.id, PartSettings(minimumLevel: 0, location: ""))
        }
      }
      .navigationDestination(for: String.self) { partID in
        ItemDetailView(theme: theme, partID: partID)
      }
    }
  }
}

struct StockRow: View {
  let theme: WarehouseTheme
  let entry: StockEntry

  var body: some View {
    GlassCard(theme: theme, padding: 12) {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text(entry.part.displayName)
            .font(.subheadline.weight(.heavy))
            .lineLimit(1)
          Text("\(entry.part.type) • \(entry.part.rating)")
            .font(.caption.weight(.semibold))
            .foregroundStyle(theme.mutedText)
            .lineLimit(1)
          if !entry.settings.location.isEmpty {
            Text(entry.settings.location)
              .font(.caption2.weight(.bold))
              .foregroundStyle(theme.secondary)
          }
        }
        Spacer()
        VStack(alignment: .trailing, spacing: 4) {
          Text("\(entry.onHand)")
            .font(.title3.weight(.black))
            .foregroundStyle(entry.isLow ? theme.warning : theme.positive)
          Text("on hand")
            .font(.caption2.weight(.bold))
            .foregroundStyle(theme.mutedText)
        }
        Image(systemName: "chevron.right")
          .foregroundStyle(theme.mutedText)
      }
    }
  }
}

/// Searchable catalog picker used by both "track a part" and the scan review
/// screen's manual match correction.
struct PartPickerSheet: View {
  let theme: WarehouseTheme
  let title: String
  let onPick: (CatalogPart) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""

  private var results: [CatalogPart] {
    let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
    guard !trimmed.isEmpty else { return Catalog.allParts }
    return Catalog.allParts.filter { $0.searchText.contains(trimmed) }
  }

  var body: some View {
    NavigationStack {
      List(results) { part in
        Button {
          onPick(part)
          dismiss()
        } label: {
          VStack(alignment: .leading, spacing: 3) {
            Text(part.displayName)
              .font(.subheadline.weight(.heavy))
            Text("\(part.type) • \(part.rating)")
              .font(.caption.weight(.semibold))
              .foregroundStyle(theme.mutedText)
          }
        }
        .listRowBackground(theme.surface)
      }
      .scrollContentBackground(.hidden)
      .background(theme.background.ignoresSafeArea())
      .navigationTitle(title)
      .searchable(text: $query, prompt: "Search 199 catalog parts")
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { dismiss() }
        }
      }
    }
    .preferredColorScheme(.dark)
  }
}
