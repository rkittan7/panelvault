// Copied from the PanelVault app (ios/Runner/SceneDelegate.swift) by
// tools/split_worker.py. The worker app is a deliberate copy of PanelVault's
// design system and data model, with manager-only creation removed and the
// warehouse added. Edit here; do not re-run the splitter over hand edits.

import SwiftUI
import PhotosUI

struct ComponentCatalogView: View {
  let theme: PanelTheme
  let groups: [ComponentGroup]
  var manufacturers: [ManufacturerItem] = ManufacturerItem.defaults
  var boardStore: Binding<[BoardDraft]>? = nil
  var onAddComponent: ((PanelComponent) -> Void)? = nil
  @State private var addedComponentIDs: Set<String> = []
  @State private var photoComponentIDs: Set<String> = []

  /// Component id -> image-store token.
  @State private var componentImages: [String: String] = [:]
  @State private var customComponents: [PanelComponent] = []
  @State private var componentToConfigure: PanelComponent?
  @State private var componentToDescribe: PanelComponent?
  @State private var componentToAssign: PanelComponent?
  @ObservedObject private var stockStore = WarehouseStore.shared

  private var visibleGroups: [ComponentGroup] {
    if customComponents.isEmpty { return groups }
    return [ComponentGroup(id: "custom-components", name: "Custom Components", items: customComponents)] + groups
  }

  /// An SF symbol that represents a catalog category, chosen from the parts it
  /// contains. Keeps the block grid readable at a glance.
  private func categorySymbol(for group: ComponentGroup) -> String {
    if group.id == "custom-components" { return "wrench.and.screwdriver.fill" }
    let key = (group.items.first?.type ?? group.name).lowercased()
    switch true {
    case key.contains("mccb"): return "bolt.shield.fill"
    case key.contains("mcb"): return "bolt.fill"
    case key.contains("rcbo"): return "shield.lefthalf.filled"
    case key.contains("rcd"), key.contains("rccb"), key.contains("rccb"): return "shield.fill"
    case key.contains("contactor"): return "square.stack.3d.up.fill"
    case key.contains("relay"): return "switch.2"
    case key.contains("vfd"), key.contains("drive"): return "gauge.with.dots.needle.67percent"
    case key.contains("psu"), key.contains("supply"): return "powerplug.fill"
    case key.contains("busbar"), key.contains("bus"): return "rectangle.split.3x1.fill"
    case key.contains("meter"): return "speedometer"
    case key.contains("spd"), key.contains("surge"): return "exclamationmark.shield.fill"
    case key.contains("terminal"): return "circle.grid.3x3.fill"
    case key.contains("transformer"), key.contains("ct"): return "circle.circle.fill"
    default: return "shippingbox.fill"
    }
  }

  /// One catalog part row. Extracted so both the (future) grid and the drill-in
  /// category page render parts identically.
  @ViewBuilder
  private func componentRow(for item: PanelComponent, in group: ComponentGroup) -> some View {
    let image = storedThumbnail(for: item)
    ComponentRow(
      theme: theme,
      component: item,
      manufacturer: manufacturer(for: item.manufacturer),
      storedImage: image,
      isAdded: addedComponentIDs.contains(item.id),
      hasPhoto: photoComponentIDs.contains(item.id) || image != nil,
      toggleAdded: {
        if addedComponentIDs.contains(item.id) {
          addedComponentIDs.remove(item.id)
        } else {
          componentToConfigure = item
        }
      },
      togglePhoto: {
        if photoComponentIDs.contains(item.id) {
          photoComponentIDs.remove(item.id)
        } else {
          photoComponentIDs.insert(item.id)
        }
      },
      savePhoto: { image in
        componentImages[item.imageStorageID] = ImageStore.shared.store(image)
        photoComponentIDs.insert(item.id)
        persistComponentImages()
      },
      showDetails: {
        componentToDescribe = item
      }
    )
  }

  /// One block of a drill-in page: the parts of a category that share a type.
  private struct CatalogSection: Identifiable {
    let id: String
    let title: String
    let items: [PanelComponent]
  }

  /// Splits a category into per-type sections, keeping the catalog order.
  /// Variant types fold into the plain family the category already lists
  /// ("Legacy ACB" under ACB, "SPD Type 2" under SPD), and leftover one-off
  /// types collect into a trailing "Other" block instead of each claiming a
  /// header. A category built from one family stays a single plain list.
  private func sections(for group: ComponentGroup) -> [CatalogSection] {
    let types = group.items.map { $0.type.trimmingCharacters(in: .whitespacesAndNewlines) }
    var order: [String] = []
    var buckets: [String: [PanelComponent]] = [:]
    for (item, type) in zip(group.items, types) {
      let title = familyTitle(for: type, within: types)
      if buckets[title] == nil { order.append(title) }
      buckets[title, default: []].append(item)
    }
    let singles = order.filter { buckets[$0]?.count == 1 }
    guard singles.count > 1 else {
      return order.map { CatalogSection(id: $0, title: $0, items: buckets[$0] ?? []) }
    }
    var sections = order
      .filter { !singles.contains($0) }
      .map { CatalogSection(id: $0, title: $0, items: buckets[$0] ?? []) }
    sections.append(CatalogSection(id: "other", title: "Other", items: singles.compactMap { buckets[$0]?.first }))
    return sections
  }

  /// The shortest type in the same category whose words all appear in `type`,
  /// so qualifiers ("Mini", "Legacy", "Type 2") do not split a family apart.
  /// Falls back to the type itself, and to "Other" when a part has no type.
  private func familyTitle(for type: String, within types: [String]) -> String {
    if type.isEmpty { return "Other" }
    let words = Set(type.lowercased().split { !$0.isLetter && !$0.isNumber })
    var family: String?
    for candidate in types where !candidate.isEmpty && candidate != type {
      let candidateWords = Set(candidate.lowercased().split { !$0.isLetter && !$0.isNumber })
      guard candidateWords.isSubset(of: words) else { continue }
      if family == nil || candidate.count < family!.count { family = candidate }
    }
    return family ?? type
  }

  /// The drill-in page for one category, listing every part under it grouped by
  /// type so mixed categories like "MCCBs & ACBs" read as separate blocks.
  @ViewBuilder
  private func categoryDetail(_ group: ComponentGroup) -> some View {
    let live = visibleGroups.first { $0.id == group.id } ?? group
    let blocks = sections(for: live)
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        ForEach(blocks) { block in
          VStack(alignment: .leading, spacing: 8) {
            if blocks.count > 1 {
              CatalogSectionHeader(theme: theme, title: block.title, count: block.items.count)
            }
            ForEach(block.items) { item in
              componentRow(for: item, in: live)
            }
          }
        }
        BottomTabClearance()
      }
      .padding(18)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .background(theme.background.ignoresSafeArea())
    .navigationTitle(live.name)
    .navigationBarTitleDisplayMode(.inline)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        EquipmentBrandBadge(name: groups.first?.items.first?.manufacturer ?? "ABB", image: manufacturerImage(for: groups.first?.items.first?.manufacturer ?? "ABB"))
        VStack(alignment: .leading) {
          Text("Equipment Catalog")
            .font(.headline)
          Text("Browse parts by type, amp rating, poles and model. Live warehouse stock shown where connected.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        // No "Add": custom components are defined in the manager app. A worker
        // who needs a part the catalog lacks adds it as a custom *warehouse*
        // part instead, from the Stock screen, where it becomes stockable.
      }

      LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
        ForEach(visibleGroups) { group in
          NavigationLink {
            categoryDetail(group)
          } label: {
            CatalogCategoryBlock(
              theme: theme,
              title: group.name,
              count: group.items.count,
              symbol: categorySymbol(for: group),
              stock: stockStore.totalStock(forComponentIDs: group.items.map(\.id))
            )
          }
          .buttonStyle(PanelPressButtonStyle())
        }
      }
    }
    .onAppear {
      loadComponentImagesIfNeeded()
    }
    .sheet(item: $componentToConfigure) { component in
      ComponentRatingSheet(theme: theme, component: component) { configured in
        handleAddedComponent(configured, sourceID: component.id)
      }
      .presentationDetents([.medium])
      .presentationDragIndicator(.visible)
    }
    .sheet(item: $componentToAssign) { component in
      if let boardStore {
        ComponentBoardPickerSheet(theme: theme, component: component, boards: boardStore) { boardID in
          assign(component, to: boardID, in: boardStore)
          componentToAssign = nil
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
      }
    }
    .sheet(item: $componentToDescribe) { component in
      ComponentDetailSheet(
        theme: theme,
        component: component,
        manufacturer: manufacturer(for: component.manufacturer),
        image: storedImage(for: component),
        onSaveImage: { image in
          componentImages[component.imageStorageID] = ImageStore.shared.store(image)
          photoComponentIDs.insert(component.id)
          persistComponentImages()
        },
        onRemoveImage: {
          for id in component.imageLookupIDs {
            if let token = componentImages.removeValue(forKey: id) {
              ImageStore.shared.delete(token)
            }
          }
          photoComponentIDs.remove(component.id)
          persistComponentImages()
        }
      )
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
  }

  private func handleAddedComponent(_ component: PanelComponent, sourceID: String) {
    if let onAddComponent {
      addedComponentIDs.insert(sourceID)
      onAddComponent(component)
    } else if boardStore != nil {
      componentToAssign = component
    } else {
      addedComponentIDs.insert(sourceID)
    }
  }

  private func assign(_ component: PanelComponent, to boardID: String, in boardStore: Binding<[BoardDraft]>) {
    guard let index = boardStore.wrappedValue.firstIndex(where: { $0.id == boardID }) else { return }
    if !boardStore.wrappedValue[index].componentTypes.contains(component.type) {
      boardStore.wrappedValue[index].componentTypes.append(component.type)
    }
    addedComponentIDs.insert(component.id)
  }

  private func manufacturer(for name: String) -> ManufacturerItem? {
    manufacturers.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
  }

  private func manufacturerImage(for name: String) -> UIImage? {
    manufacturer(for: name)?.thumbnail ?? CatalogImageLibrary.manufacturerThumbnail(name: name)
  }

  /// A photo of this part: the one taken on this device if there is one, and
  /// otherwise the catalog photo shipped in `assets/catalog`.
  private func storedImage(for component: PanelComponent) -> UIImage? {
    component.imageLookupIDs
      .lazy
      .compactMap { ImageStore.shared.image(for: componentImages[$0]) }
      .first
      ?? CatalogImageLibrary.componentImage(id: component.imageStorageID)
  }

  /// Row-sized variant, so scrolling the catalog does not decode full-size
  /// component photos.
  private func storedThumbnail(for component: PanelComponent) -> UIImage? {
    component.imageLookupIDs
      .lazy
      .compactMap { ImageStore.shared.thumbnail(for: componentImages[$0]) }
      .first
      ?? CatalogImageLibrary.componentThumbnail(ids: component.imageLookupIDs)
  }

  private func loadComponentImagesIfNeeded() {
    guard componentImages.isEmpty else { return }
    componentImages = ComponentImageStore.load()
    photoComponentIDs = photoComponentIDs.union(componentImages.keys)
  }

  private func persistComponentImages() {
    ComponentImageStore.save(componentImages)
  }
}

struct ComponentBoardPickerSheet: View {
  let theme: PanelTheme
  let component: PanelComponent
  @Binding var boards: [BoardDraft]
  let onSelect: (String) -> Void
  @Environment(\.dismiss) private var dismiss

  private var sortedBoards: [BoardDraft] {
    boards.sorted(by: boardPrioritySort)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          GlassCard(theme: theme) {
            VStack(alignment: .leading, spacing: 6) {
              Text("Add \(component.type)")
                .font(.headline)
              Text("\(component.manufacturer) \(component.model) • \(component.ratingLabel) • \(component.poles)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }

          if sortedBoards.isEmpty {
            EmptyStateCard(theme: theme, title: "No boards yet", subtitle: "Create a board first, then add catalog components to it.")
          } else {
            ForEach(sortedBoards) { board in
              Button {
                onSelect(board.id)
                dismiss()
              } label: {
                HStack(spacing: 12) {
                  BoardTypeIcon(board: iconType(for: board), size: 44, overrideColor: board.color)
                  VStack(alignment: .leading, spacing: 4) {
                    Text(board.name)
                      .font(.headline)
                      .lineLimit(1)
                      .minimumScaleFactor(0.75)
                    Text([board.number, board.type, board.componentTypes.joined(separator: ", ")]
                      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                      .joined(separator: " • "))
                      .font(.caption)
                      .foregroundStyle(.secondary)
                      .lineLimit(2)
                  }
                  Spacer()
                  Image(systemName: "plus.circle.fill")
                    .foregroundStyle(theme.primary)
                    .font(.title3)
                }
                .padding(14)
                .background(theme.surface.opacity(0.78))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
              }
              .buttonStyle(PanelPressButtonStyle())
            }
          }
        }
        .padding(18)
        .padding(.bottom, 28)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Choose Board")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Cancel") { dismiss() }
        }
      }
    }
  }

  private func iconType(for board: BoardDraft) -> BoardType {
    BoardType.samples.first { $0.name.localizedCaseInsensitiveCompare(board.type) == .orderedSame } ??
      BoardType(id: "component-target", name: board.type, subtitle: "", symbol: "rectangle.3.group.fill", color: board.color)
  }
}

/// A titled divider between part types inside a catalog category page.
struct CatalogSectionHeader: View {
  let theme: PanelTheme
  let title: String
  let count: Int

  var body: some View {
    HStack(alignment: .center, spacing: 10) {
      Text(title)
        .font(.system(size: 12, weight: .bold))
        .textCase(.uppercase)
        .kerning(0.6)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: true, vertical: false)
      Rectangle()
        .fill(theme.cardBorder)
        .frame(height: 1)
      Text("\(count)")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
    .padding(.bottom, 2)
  }
}

/// A catalog category tile. Tapping it drills into the parts under that type.
/// Kept deliberately simple so the catalog landing page reads as a clean grid
/// of categories (and can later sit alongside warehouse stock links).
struct CatalogCategoryBlock: View {
  let theme: PanelTheme
  let title: String
  let count: Int
  let symbol: String
  /// Total warehouse stock across the category, or nil when Cloud is not linked.
  var stock: Int? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Image(systemName: symbol)
          .font(.system(size: 20, weight: .semibold))
          .foregroundStyle(theme.primary)
          .frame(width: 44, height: 44)
          .background(theme.primary.opacity(0.14))
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        Spacer(minLength: 0)
        if let stock {
          StockBadge(theme: theme, count: stock, compact: true)
        }
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(.secondary)
      }
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(.primary)
          .lineLimit(2)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)
        Text(count == 1 ? "1 part" : "\(count) parts")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
    .padding(14)
    .background(theme.surface.opacity(0.78))
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(theme.cardBorder, lineWidth: 1)
    )
  }
}

struct ComponentRow: View {
  let theme: PanelTheme
  let component: PanelComponent
  let manufacturer: ManufacturerItem?
  let storedImage: UIImage?
  let isAdded: Bool
  let hasPhoto: Bool
  let toggleAdded: () -> Void
  let togglePhoto: () -> Void
  let savePhoto: (UIImage) -> Void
  let showDetails: () -> Void
  @State private var selectedPhotoItem: PhotosPickerItem?
  @ObservedObject private var stockStore = WarehouseStore.shared

  private var displayImage: UIImage? {
    storedImage
  }

  private var manufacturerColor: Color {
    if let manufacturer {
      return manufacturer.color
    }
    switch component.manufacturer {
    case "ABB": return Color(hex: 0xFF3B30)
    case "Schneider": return Color(hex: 0x35E177)
    case "Siemens": return Color(hex: 0x18D4E8)
    case "Eaton": return Color(hex: 0x5E78FF)
    default: return theme.primary
    }
  }

  var body: some View {
    GlassCard(theme: theme) {
      HStack(spacing: 12) {
        EquipmentBrandBadge(name: component.manufacturer, image: manufacturer?.thumbnail)
        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
          Group {
            if let displayImage {
              TransparentImageBubble(
                image: displayImage,
                width: 54,
                height: 54,
                cornerRadius: 12,
                glowColor: manufacturerColor
              )
            } else {
              ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                  .fill(manufacturerColor.opacity(0.10))
                VStack(spacing: 3) {
                  Image(systemName: "photo.badge.plus")
                  Text("Add")
                    .font(.caption2.bold())
                }
                .foregroundStyle(manufacturerColor.opacity(0.85))
              }
              .frame(width: 54, height: 54)
              .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
          }
          .frame(width: 54, height: 54)
        }
        .buttonStyle(.plain)
        .onChange(of: selectedPhotoItem) { item in
          loadComponentImage(from: item)
        }
        Button(action: showDetails) {
          VStack(alignment: .leading, spacing: 4) {
            Text(component.displayName)
              .font(.system(size: 16, weight: .bold))
              .lineLimit(1)
              .minimumScaleFactor(0.65)
            Text(component.detailLine)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .minimumScaleFactor(0.7)
            HStack(spacing: 6) {
              EquipmentPill(text: component.type, color: manufacturerColor)
              EquipmentPill(text: component.poles, color: Color(hex: 0x7FA6C9))
              EquipmentPill(text: component.ratingLabel, color: Color(hex: 0x7FAE9A))
              if let stock = stockStore.stock(for: component.id) {
                StockBadge(theme: theme, count: stock, compact: true)
              }
            }
          }
        }
        .buttonStyle(.plain)
        Spacer()
        Button(action: showDetails) {
          Image(systemName: "info.circle.fill")
            .foregroundStyle(manufacturerColor)
            .font(.title3)
            .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        Button(action: toggleAdded) {
          Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle.fill")
            .foregroundStyle(isAdded ? Color(hex: 0x7FAE9A) : manufacturerColor)
            .font(.title3)
            .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(minHeight: 74)
    }
    .background(manufacturerColor.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(manufacturerColor.opacity(0.18), lineWidth: 1)
    )
    .shadow(color: manufacturerColor.opacity(0.12), radius: 10, x: 0, y: 0)
  }

  private func loadComponentImage(from item: PhotosPickerItem?) {
    Task {
      guard let data = try? await item?.loadTransferable(type: Data.self),
            let image = (await ImageStore.imported(from: data))?.image else { return }
      await MainActor.run {
        selectedPhotoItem = nil
        savePhoto(image)
      }
    }
  }
}

struct ComponentRatingSheet: View {
  let theme: PanelTheme
  let component: PanelComponent
  let onAdd: (PanelComponent) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var rating: String
  @State private var poles: String
  @State private var serialNumber: String

  init(theme: PanelTheme, component: PanelComponent, onAdd: @escaping (PanelComponent) -> Void) {
    self.theme = theme
    self.component = component
    self.onAdd = onAdd
    _rating = State(initialValue: component.rating)
    _poles = State(initialValue: component.poles)
    _serialNumber = State(initialValue: component.serialNumber)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          GlassCard(theme: theme) {
            VStack(alignment: .leading, spacing: 10) {
              InfoLine(title: "Manufacturer", value: component.manufacturer)
              InfoLine(title: "Type", value: component.type)
              InfoLine(title: "Model", value: component.model)
            }
          }

          CreationTextInput(
            theme: theme,
            title: "Serial number",
            placeholder: "Optional",
            symbol: "number",
            text: $serialNumber,
            capitalization: .characters
          )

          RatingChipSection(
            theme: theme,
            title: "Ampere / Rating",
            options: AmpereRating.all,
            selection: $rating
          )

          RatingChipSection(
            theme: theme,
            title: "Poles / Phase",
            options: PoleRating.all,
            selection: $poles
          )
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Set Rating")
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Add") {
            let cleanedRating = normalizedRating
            onAdd(
              PanelComponent(
                id: "\(component.id)-\(cleanedRating)-\(UUID().uuidString)",
                manufacturer: component.manufacturer,
                type: component.type,
                model: component.model,
                rating: cleanedRating,
                poles: poles,
                curve: component.curve,
                sourceID: component.imageStorageID,
                about: component.about,
                serialNumber: serialNumber.trimmingCharacters(in: .whitespacesAndNewlines)
              )
            )
            dismiss()
          }
          .disabled(rating.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          .fontWeight(.bold)
        }
      }
    }
  }

  private var normalizedRating: String {
    let trimmed = rating.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return component.rating }
    if trimmed.rangeOfCharacter(from: .letters) == nil &&
        (component.type.localizedCaseInsensitiveContains("MCB") ||
         component.type.localizedCaseInsensitiveContains("MCCB") ||
         component.type.localizedCaseInsensitiveContains("Contactor")) {
      return "\(trimmed)A"
    }
    return trimmed
  }
}

struct RatingChipSection: View {
  let theme: PanelTheme
  let title: String
  let options: [String]
  @Binding var selection: String

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.headline)
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
        ForEach(options, id: \.self) { option in
          Button {
            withAnimation(.easeOut(duration: 0.14)) {
              selection = option
            }
          } label: {
            Text(option)
              .font(.system(size: 12, weight: .heavy))
              .lineLimit(1)
              .minimumScaleFactor(0.7)
              .foregroundStyle(selection == option ? .white : .primary)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 10)
              .background(selection == option ? theme.primary : theme.surface.opacity(0.84))
              .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
              .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                  .stroke(selection == option ? .clear : .white.opacity(0.08), lineWidth: 1)
              )
          }
          .buttonStyle(PanelPressButtonStyle())
        }
      }
    }
  }
}

struct ComponentDetailSheet: View {
  let theme: PanelTheme
  let component: PanelComponent
  let manufacturer: ManufacturerItem?
  let onSaveImage: (UIImage) -> Void
  let onRemoveImage: () -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var selectedImage: UIImage?
  @State private var selectedItem: PhotosPickerItem?
  @State private var previewImage: ImagePreviewItem?
  @State private var editorImage: ImagePreviewItem?

  init(
    theme: PanelTheme,
    component: PanelComponent,
    manufacturer: ManufacturerItem?,
    image: UIImage? = nil,
    onSaveImage: @escaping (UIImage) -> Void = { _ in },
    onRemoveImage: @escaping () -> Void = {}
  ) {
    self.theme = theme
    self.component = component
    self.manufacturer = manufacturer
    self.onSaveImage = onSaveImage
    self.onRemoveImage = onRemoveImage
    _selectedImage = State(initialValue: image)
  }

  private var manufacturerColor: Color {
    if let manufacturer {
      return manufacturer.color
    }
    switch component.manufacturer {
    case "ABB": return Color(hex: 0xFF3B30)
    case "Schneider": return Color(hex: 0x35E177)
    case "Siemens": return Color(hex: 0x18D4E8)
    case "Eaton": return Color(hex: 0x5E78FF)
    default: return theme.primary
    }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          componentPhotoSection

          HStack(spacing: 14) {
            Image(systemName: ComponentIcon.symbol(for: component.type))
              .font(.system(size: 30, weight: .bold))
              .foregroundStyle(theme.primary)
              .frame(width: 64, height: 64)
              .background(theme.primary.opacity(0.14))
              .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
              Text(component.model)
                .font(.largeTitle.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
              HStack(spacing: 8) {
                Image(systemName: "tag.fill")
                  .foregroundStyle(manufacturer?.color ?? theme.primary)
                Text(component.manufacturer)
                  .font(.headline)
                  .lineLimit(1)
                  .minimumScaleFactor(0.7)
              }
            }
          }

          BoardReferenceSection(theme: theme, title: "Description", symbol: "text.alignleft", color: theme.primary) {
            Text(ComponentIcon.description(for: component))
              .fixedSize(horizontal: false, vertical: true)
          }

          BoardReferenceSection(theme: theme, title: "Specification", symbol: "list.bullet.rectangle.fill", color: theme.primary) {
            VStack(alignment: .leading, spacing: 10) {
              InfoLine(title: "Type", value: component.type)
              InfoLine(title: "Rating", value: component.rating)
              InfoLine(title: "Poles / Phase", value: component.poles)
              if !component.serialNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                InfoLine(title: "Serial Number", value: component.serialNumber)
              }
              if !component.curve.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                InfoLine(title: "Curve / Notes", value: component.curve)
              }
            }
          }
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle(component.type)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
      .onChange(of: selectedItem) { item in
        loadImage(from: item)
      }
      .sheet(item: $previewImage) { item in
        ImagePreviewSheet(image: item.image)
      }
      .sheet(item: $editorImage) { item in
        CoverPhotoEditorSheet(theme: theme, image: item.image) { adjustedImage in
          selectedImage = adjustedImage
          onSaveImage(adjustedImage)
        }
      }
    }
  }

  private var componentPhotoSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let selectedImage {
        Button {
          previewImage = ImagePreviewItem(image: selectedImage)
        } label: {
          Image(uiImage: selectedImage)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .frame(minHeight: 180)
            .padding(14)
            .shadow(color: manufacturerColor.opacity(0.32), radius: 16, x: 0, y: 0)
            .shadow(color: manufacturerColor.opacity(0.16), radius: 32, x: 0, y: 0)
        }
        .buttonStyle(.plain)

        HStack(spacing: 14) {
          Button {
            previewImage = ImagePreviewItem(image: selectedImage)
          } label: {
            Label("View", systemImage: "photo.fill")
              .font(.caption.bold())
          }
          .buttonStyle(.plain)

          Button {
            editorImage = ImagePreviewItem(image: selectedImage)
          } label: {
            Label("Edit", systemImage: "crop")
              .font(.caption.bold())
          }
          .buttonStyle(.plain)

          PhotosPicker(selection: $selectedItem, matching: .images) {
            Label("Replace", systemImage: "arrow.triangle.2.circlepath.camera")
              .font(.caption.bold())
          }
          .buttonStyle(.plain)

          Spacer()

          Button(role: .destructive) {
            self.selectedImage = nil
            selectedItem = nil
            onRemoveImage()
          } label: {
            Label("Delete", systemImage: "trash")
              .font(.caption.bold())
          }
          .buttonStyle(.plain)
        }
        .foregroundStyle(manufacturerColor)
      } else {
        PhotosPicker(selection: $selectedItem, matching: .images) {
          VStack(spacing: 8) {
            Image(systemName: "photo.badge.plus")
              .font(.system(size: 30, weight: .bold))
            Text("Add Component Picture")
              .font(.headline)
            Text("Tap to attach a photo for this catalog item.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 34)
          .background(theme.surface.opacity(0.58))
          .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
              .stroke(manufacturerColor.opacity(0.16), lineWidth: 1)
          )
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func loadImage(from item: PhotosPickerItem?) {
    Task {
      guard let data = try? await item?.loadTransferable(type: Data.self),
            let image = (await ImageStore.imported(from: data))?.image else { return }
      await MainActor.run {
        selectedImage = image
        selectedItem = nil
        onSaveImage(image)
      }
    }
  }
}

struct ManufacturerDetailSheet: View {
  let theme: PanelTheme
  let manufacturer: ManufacturerItem
  @Environment(\.dismiss) private var dismiss

  private var components: [PanelComponent] {
    ComponentGroup.samples.flatMap(\.items).filter {
      $0.manufacturer.localizedCaseInsensitiveCompare(manufacturer.name) == .orderedSame
    }
  }

  private var filteredGroups: [ComponentGroup] {
    ComponentGroup.samples.compactMap { group in
      let items = group.items.filter {
        $0.manufacturer.localizedCaseInsensitiveCompare(manufacturer.name) == .orderedSame
      }
      guard !items.isEmpty else { return nil }
      return ComponentGroup(id: "\(manufacturer.id)-\(group.id)", name: group.name, items: items)
    }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          HStack(spacing: 14) {
            ManufacturerLogoView(manufacturer: manufacturer)
            VStack(alignment: .leading, spacing: 5) {
              Text(manufacturer.name)
                .font(.largeTitle.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
              Text("\(components.count) catalog item\(components.count == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
            }
          }

          BoardReferenceSection(theme: theme, title: "Manufacturer", symbol: "tag.fill", color: manufacturer.color) {
            BoardBulletList(items: [
              "Logo/color can be edited from the manufacturer list.",
              "This page shows every built-in catalog item currently assigned to this manufacturer.",
              "Custom components you add can also use this manufacturer name."
            ])
          }

          Text("Catalog Items")
            .font(.headline)

          if filteredGroups.isEmpty {
            EmptyStateCard(theme: theme, title: "No catalog items", subtitle: "Add custom components with this manufacturer name to start filling this section.")
          } else {
            ComponentCatalogView(theme: theme, groups: filteredGroups, manufacturers: [manufacturer])
          }
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle(manufacturer.name)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
    }
  }
}

struct ManufacturerSelection: Identifiable {
  let id: String
}

struct BoardIDSelection: Identifiable {
  let id: String
}
