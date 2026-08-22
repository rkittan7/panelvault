import SwiftUI

struct StockListView: View {
  let theme: WarehouseTheme
  @EnvironmentObject private var store: WarehouseStore
  @State private var query = ""
  @State private var addingPart = false
  @State private var showingStocktake = false

  private var filtered: [StockEntry] {
    let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
    guard !trimmed.isEmpty else { return store.entries }
    return store.entries.filter { $0.part.searchText.contains(trimmed) }
  }

  private var canRunStocktake: Bool {
    guard let role = store.account?.role else { return true }
    return role == "owner" || role == "manager"
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
      .searchable(text: $query, prompt: "Search model, serial, type, manufacturer")
      .toolbar {
        if canRunStocktake {
          ToolbarItem(placement: .topBarTrailing) {
            Button {
              showingStocktake = true
            } label: {
              Image(systemName: "barcode.viewfinder")
            }
            .accessibilityLabel("Barcode stocktake")
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            addingPart = true
          } label: {
            Image(systemName: "plus")
          }
        }
      }
      .fullScreenCover(isPresented: $showingStocktake) {
        BarcodeStocktakeView(theme: theme)
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
        CatalogPartThumb(theme: theme, part: entry.part)
        VStack(alignment: .leading, spacing: 4) {
          Text(entry.part.displayName)
            .font(.subheadline.weight(.heavy))
            .lineLimit(1)
          HStack(spacing: 6) {
            CatalogBrandMark(manufacturer: entry.part.manufacturer)
            Text("\(entry.part.type) • \(entry.part.rating)")
              .font(.caption.weight(.semibold))
              .foregroundStyle(theme.mutedText)
              .lineLimit(1)
          }
          if let serialNumber = entry.part.serialNumber, !serialNumber.isEmpty {
            Text("Serial: \(serialNumber)")
              .font(.caption2.weight(.bold))
              .foregroundStyle(theme.primary)
              .lineLimit(1)
          }
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

/// Searchable part picker used by "track a part", manual receive, and the scan
/// review screen's match correction. Covers the generated catalog plus the
/// user's own custom parts, and offers creating a new part when the search
/// comes up empty.
struct PartPickerSheet: View {
  let theme: WarehouseTheme
  let title: String
  let onPick: (CatalogPart) -> Void
  @EnvironmentObject private var store: WarehouseStore
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @State private var creating = false

  private var results: [CatalogPart] {
    let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
    guard !trimmed.isEmpty else { return store.allParts }
    return store.allParts.filter { $0.searchText.contains(trimmed) }
  }

  private var canCreatePart: Bool {
    guard let role = store.account?.role else { return true }
    return role == "owner" || role == "manager"
  }

  var body: some View {
    NavigationStack {
      List {
        if results.isEmpty && canCreatePart {
          Section {
            Button {
              creating = true
            } label: {
              Label("Create \"\(query)\" as a new part", systemImage: "plus.circle.fill")
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(theme.primary)
            }
            .listRowBackground(theme.surface)
          } footer: {
            Text("Not in the catalog? Add your own part — it works everywhere catalog parts do.")
          }
        }
        ForEach(results) { part in
          Button {
            onPick(part)
            dismiss()
          } label: {
            HStack(spacing: 10) {
              CatalogPartThumb(theme: theme, part: part, size: 34)
              VStack(alignment: .leading, spacing: 3) {
                Text(part.displayName)
                  .font(.subheadline.weight(.heavy))
                HStack(spacing: 6) {
                  CatalogBrandMark(manufacturer: part.manufacturer, height: 11)
                  Text("\(part.type) • \(part.rating)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.mutedText)
                }
              }
              if part.id.hasPrefix("custom-") {
                Spacer()
                Text("CUSTOM")
                  .font(.caption2.weight(.black))
                  .foregroundStyle(theme.secondary)
              }
            }
          }
          .listRowBackground(theme.surface)
        }
      }
      .scrollContentBackground(.hidden)
      .background(theme.background.ignoresSafeArea())
      .navigationTitle(title)
      .searchable(text: $query, prompt: "Search parts")
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { dismiss() }
        }
        if canCreatePart {
          ToolbarItem(placement: .topBarTrailing) {
            Button {
              creating = true
            } label: {
              Image(systemName: "plus")
            }
          }
        }
      }
      .sheet(isPresented: $creating) {
        NewPartSheet(theme: theme, suggestedModel: query) { part in
          onPick(part)
          dismiss()
        }
      }
    }
    .preferredColorScheme(.dark)
  }
}

/// Form for a part the catalog does not carry — any type, including ones the
/// catalog has never heard of.
struct NewPartSheet: View {
  let theme: WarehouseTheme
  var suggestedModel = ""
  let onCreate: (CatalogPart) -> Void
  @EnvironmentObject private var store: WarehouseStore
  @Environment(\.dismiss) private var dismiss

  @State private var model = ""
  @State private var manufacturer = ""
  @State private var type = ""
  @State private var rating = ""
  @State private var poles = ""
  @State private var serialNumber = ""
  @State private var notes = ""

  private var canSave: Bool {
    !model.trimmingCharacters(in: .whitespaces).isEmpty &&
    !type.trimmingCharacters(in: .whitespaces).isEmpty
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Part") {
          TextField("Model (e.g. XT2-160)", text: $model)
          TextField("Manufacturer", text: $manufacturer)
          HStack {
            TextField("Type (e.g. Cable Tray)", text: $type)
            Menu {
              ForEach(store.knownTypes, id: \.self) { known in
                Button(known) { type = known }
              }
            } label: {
              Image(systemName: "chevron.up.chevron.down")
                .foregroundStyle(theme.primary)
            }
          }
        }
        Section("Details (optional)") {
          TextField("Rating (e.g. 160A)", text: $rating)
          TextField("Poles / phase", text: $poles)
          TextField("Serial number", text: $serialNumber)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
          TextField("Notes — what is it for?", text: $notes, axis: .vertical)
            .lineLimit(3...6)
        }
      }
      .scrollContentBackground(.hidden)
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("New Part")
      .navigationBarTitleDisplayMode(.inline)
      .onAppear {
        if model.isEmpty { model = suggestedModel }
      }
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Add") {
            let part = store.addCustomPart(
              manufacturer: manufacturer.trimmingCharacters(in: .whitespaces),
              type: type.trimmingCharacters(in: .whitespaces),
              model: model.trimmingCharacters(in: .whitespaces),
              rating: rating.trimmingCharacters(in: .whitespaces),
              poles: poles.trimmingCharacters(in: .whitespaces),
              notes: notes.trimmingCharacters(in: .whitespaces),
              serialNumber: serialNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            onCreate(part)
            dismiss()
          }
          .fontWeight(.black)
          .disabled(!canSave)
        }
      }
    }
    .preferredColorScheme(.dark)
  }
}
