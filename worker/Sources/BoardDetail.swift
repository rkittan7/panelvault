// Copied from the PanelVault app (ios/Runner/SceneDelegate.swift) by
// tools/split_worker.py. The worker app is a deliberate copy of PanelVault's
// design system and data model, with manager-only creation removed and the
// warehouse added. Edit here; do not re-run the splitter over hand edits.

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct BoardScreen: View {
  let theme: PanelTheme
  @Binding var board: BoardDraft
  var boardTypes: [BoardType] = BoardType.samples
  var manufacturers: [ManufacturerItem] = ManufacturerItem.defaults
  let onDone: () -> Void
  @State private var catalogOpen = false
  @State private var componentTypes: [String] = []
  @State private var addedComponentsByType: [String: [PanelComponent]] = [:]
  @State private var cabinetChecklists: [Set<String>] = []
  @State private var selectedCabinet: Int = 0
  @State private var personalChecklistItems: [PersonalChecklistItem] = []
  @State private var localBoardLoaded = false
  @State private var pendingBoardSyncWorkItem: DispatchWorkItem?
  @State private var selectedComponentType: String?
  @State private var finishRecordOpen = false

  private var displayBoard: BoardDraft {
    var copy = board
    copy.componentTypes = componentTypes
    copy.cabinetChecklists = cabinetChecklists
    copy.personalChecklistItems = personalChecklistItems
    return copy
  }

  private var cabinetBinding: Binding<Set<String>> {
    Binding {
      let idx = min(max(selectedCabinet, 0), max(cabinetChecklists.count - 1, 0))
      return cabinetChecklists.indices.contains(idx) ? cabinetChecklists[idx] : []
    } set: { newValue in
      let idx = min(max(selectedCabinet, 0), max(cabinetChecklists.count - 1, 0))
      if cabinetChecklists.indices.contains(idx) {
        cabinetChecklists[idx] = newValue
      }
    }
  }

  private func cabinetCompletion(_ index: Int) -> Int {
    guard cabinetChecklists.indices.contains(index) else { return 0 }
    let checklist = ChecklistTemplate.items(for: board.cabinetCount)
    let total = max(checklist.map(\.weight).reduce(0, +), 1)
    let done = checklist.filter { cabinetChecklists[index].contains($0.id) }.map(\.weight).reduce(0, +)
    return Int((Double(done) / Double(total) * 100).rounded())
  }

  private func normalizeLocalCabinets() {
    let n = board.cabinetCountValue
    if cabinetChecklists.count < n {
      cabinetChecklists.append(contentsOf: Array(repeating: Set<String>(), count: n - cabinetChecklists.count))
    } else if cabinetChecklists.count > n {
      cabinetChecklists = Array(cabinetChecklists.prefix(n))
    }
    selectedCabinet = min(max(selectedCabinet, 0), max(n - 1, 0))
  }

  @ViewBuilder
  private var cabinetChecklistSection: some View {
    let count = board.cabinetCountValue
    VStack(alignment: .leading, spacing: 10) {
      if count > 1 {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
              CabinetTab(
                theme: theme,
                number: index + 1,
                percent: cabinetCompletion(index),
                selected: index == selectedCabinet
              ) {
                withAnimation(.easeOut(duration: 0.16)) { selectedCabinet = index }
              }
            }
          }
          .padding(.vertical, 2)
        }
      }
      ChecklistProgressSection(
        theme: theme,
        title: count > 1 ? "Cabinet \(selectedCabinet + 1) Progress" : "Completion Progress",
        items: ChecklistTemplate.items(for: board.cabinetCount),
        checkedItems: cabinetBinding
      )
      .onChange(of: cabinetChecklists) { _ in
        scheduleBoardSync()
      }
    }
  }

  private var visibleComponentTypes: [String] {
    let types = Set(componentTypes).union(addedComponentsByType.keys)
    return types.isEmpty ? board.componentTypes : Array(types).sorted()
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        VStack(alignment: .leading, spacing: 4) {
          Text(board.name)
            .font(.largeTitle.bold())
          Text(board.number)
            .font(.headline)
            .foregroundStyle(.secondary)
        }

        BoardCoverPhotoSection(theme: theme, selectedImage: $board.coverImage)

        BoardPropertiesOverview(theme: theme, board: displayBoard, manufacturers: manufacturers) {
          finishRecordOpen = true
        }

        cabinetChecklistSection
          .onChange(of: board.cabinetCount) { _ in
            normalizeLocalCabinets()
          }
        PersonalChecklistSection(theme: theme, items: $personalChecklistItems)
          .onChange(of: personalChecklistItems) { _ in
            scheduleBoardSync()
          }
        SchemeAttachmentSection(theme: theme, attachments: $board.schemeAttachments)
        PhotoPickerSection(theme: theme, title: "Board Photos", photoTokens: $board.photoTokens, coverImage: $board.coverImage)
        componentsSection

      }
      .padding(18)
    }
    .background(theme.background.ignoresSafeArea())
    .overlay(alignment: .top) {
      TopScrollBlur(theme: theme)
    }
    .navigationTitle(board.name)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Done") { onDone() }
          .fontWeight(.bold)
      }
    }
    .sheet(isPresented: $finishRecordOpen) {
      // The manager app opens BoardEditSheet here. A worker gets the finish
      // record instead — see BoardProgressSheet.swift.
      BoardProgressSheet(theme: theme, board: $board)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
    .fullScreenCover(isPresented: $catalogOpen) {
      NavigationStack {
        ScrollView {
          ComponentCatalogView(theme: theme, groups: ComponentGroup.samples, manufacturers: manufacturers, onAddComponent: { component in
            if !componentTypes.contains(component.type) {
              componentTypes.append(component.type)
            }
            var components = addedComponentsByType[component.type] ?? []
            if !components.contains(where: { $0.id == component.id }) {
              components.append(component)
              addedComponentsByType[component.type] = components
            }
            scheduleBoardSync()
          })
            .padding(18)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("Add Components")
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button("Done") {
              catalogOpen = false
            }
            .fontWeight(.bold)
          }
        }
      }
    }
    .sheet(item: Binding(
      get: { selectedComponentType.map(ComponentTypeSelection.init(type:)) },
      set: { selectedComponentType = $0?.type }
    )) { selection in
      ComponentTypeCatalogSheet(
        theme: theme,
        type: selection.type,
        components: components(for: selection.type),
        manufacturers: manufacturers
      )
    }
    .onAppear {
      loadLocalBoardIfNeeded()
    }
    .onDisappear {
      flushBoardSync()
    }
  }

  private var componentsSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Components")
          .font(.headline)
        Spacer()
        Button {
          catalogOpen = true
        } label: {
          Label("Add", systemImage: "plus")
            .font(.caption.bold())
        }
        .buttonStyle(.borderedProminent)
        .tint(theme.primary)
      }

      if visibleComponentTypes.isEmpty {
        EmptyStateCard(theme: theme, title: "No components yet", subtitle: "Add MCBs, contactors, VFDs, PSUs, busbars and more from the catalog.")
      } else {
        ForEach(visibleComponentTypes, id: \.self) { type in
          GlassCard(theme: theme) {
            HStack {
              Image(systemName: "shippingbox.fill")
                .foregroundStyle(theme.primary)
              VStack(alignment: .leading, spacing: 3) {
                Text(type)
                  .font(.headline)
                Text(componentCountText(for: type))
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              HStack(spacing: 8) {
                DeleteIconButton(theme: theme) {
                  componentTypes.removeAll { $0 == type }
                  addedComponentsByType.removeValue(forKey: type)
                  scheduleBoardSync()
                }
                Button {
                  selectedComponentType = type
                } label: {
                  Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
              }
            }
          }
        }
      }
    }
  }

  private func components(for type: String) -> [PanelComponent] {
    if let components = addedComponentsByType[type], !components.isEmpty {
      return components
    }
    return ComponentGroup.samples
      .flatMap(\.items)
      .filter { $0.type.localizedCaseInsensitiveCompare(type) == .orderedSame }
  }

  private func componentCountText(for type: String) -> String {
    let count = addedComponentsByType[type]?.count ?? (board.componentTypes.contains(type) ? 1 : 0)
    return "\(count) catalog item\(count == 1 ? "" : "s")"
  }

  private func loadLocalBoardIfNeeded() {
    guard !localBoardLoaded else { return }
    localBoardLoaded = true
    componentTypes = board.componentTypes
    cabinetChecklists = board.normalizedCabinetChecklists
    selectedCabinet = min(max(selectedCabinet, 0), max(board.cabinetCountValue - 1, 0))
    personalChecklistItems = board.personalChecklistItems
  }

  private func scheduleBoardSync() {
    pendingBoardSyncWorkItem?.cancel()
    let workItem = DispatchWorkItem {
      flushBoardSync()
    }
    pendingBoardSyncWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.65, execute: workItem)
  }

  private func flushBoardSync() {
    pendingBoardSyncWorkItem?.cancel()
    pendingBoardSyncWorkItem = nil
    board.componentTypes = componentTypes
    board.cabinetChecklists = cabinetChecklists
    board.personalChecklistItems = personalChecklistItems
  }
}

struct ComponentTypeSelection: Identifiable {
  let type: String
  var id: String { type }
}

struct ComponentTypeCatalogSheet: View {
  let theme: PanelTheme
  let type: String
  let components: [PanelComponent]
  let manufacturers: [ManufacturerItem]
  @Environment(\.dismiss) private var dismiss
  /// Component id -> image-store token. Tokens, not images, so opening the
  /// catalog does not decode every component photo at once.
  @State private var componentImages: [String: String] = [:]
  @State private var selectedComponent: PanelComponent?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          if components.isEmpty {
            EmptyStateCard(theme: theme, title: "No \(type) items yet", subtitle: "Add exact \(type) items from the equipment catalog.")
          }

          ForEach(components) { component in
            let image = storedThumbnail(for: component)
            ComponentRow(
              theme: theme,
              component: component,
              manufacturer: manufacturer(for: component.manufacturer),
              storedImage: image,
              isAdded: true,
              hasPhoto: image != nil
            ) {
            } togglePhoto: {
            } savePhoto: { image in
              componentImages[component.imageStorageID] = ImageStore.shared.store(image)
              persistComponentImages()
            } showDetails: {
              selectedComponent = component
            }
          }
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle(type)
      .onAppear {
        if componentImages.isEmpty {
          componentImages = ComponentImageStore.load()
        }
      }
      .sheet(item: $selectedComponent) { component in
        ComponentDetailSheet(
          theme: theme,
          component: component,
          manufacturer: manufacturer(for: component.manufacturer),
          image: storedImage(for: component),
          onSaveImage: { image in
            componentImages[component.imageStorageID] = ImageStore.shared.store(image)
            persistComponentImages()
          },
          onRemoveImage: {
            for id in component.imageLookupIDs {
              if let token = componentImages.removeValue(forKey: id) {
                ImageStore.shared.delete(token)
              }
            }
            persistComponentImages()
          }
        )
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
      }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
    }
  }

  private func manufacturer(for name: String) -> ManufacturerItem? {
    manufacturers.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
  }

  private func storedImage(for component: PanelComponent) -> UIImage? {
    component.imageLookupIDs
      .lazy
      .compactMap { ImageStore.shared.image(for: componentImages[$0]) }
      .first
  }

  /// Row-sized variant, so scrolling the catalog does not decode full-size
  /// component photos.
  private func storedThumbnail(for component: PanelComponent) -> UIImage? {
    component.imageLookupIDs
      .lazy
      .compactMap { ImageStore.shared.thumbnail(for: componentImages[$0]) }
      .first
  }

  private func persistComponentImages() {
    ComponentImageStore.save(componentImages)
  }
}

struct BoardCoverPhotoSection: View {
  let theme: PanelTheme
  @State private var selectedItem: PhotosPickerItem?
  @State private var displayMode = "Fill"
  @State private var previewImage: ImagePreviewItem?
  @State private var editorImage: ImagePreviewItem?
  @Binding var selectedImage: UIImage?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if selectedImage == nil {
        PhotosPicker(selection: $selectedItem, matching: .images) {
          CoverPhotoView(
            theme: theme,
            image: selectedImage,
            displayMode: displayMode,
            title: "Add Board Picture",
            subtitle: "Tap to choose the board cover photo"
          )
        }
        .buttonStyle(.plain)
      } else {
        CoverPhotoView(
          theme: theme,
          image: selectedImage,
          displayMode: displayMode,
          title: "Board Picture Added",
          subtitle: "View, adjust or replace below"
        )
        .onTapGesture {
          if let selectedImage {
            previewImage = ImagePreviewItem(image: selectedImage)
          }
        }
      }

      if selectedImage != nil {
        Picker("Photo view", selection: $displayMode) {
          ForEach(["Fill", "Fit"], id: \.self) { Text($0) }
        }
        .pickerStyle(.segmented)

        HStack(spacing: 14) {
          Button {
            if let selectedImage {
              previewImage = ImagePreviewItem(image: selectedImage)
            }
          } label: {
            Label("View", systemImage: "photo.fill")
              .font(.caption.bold())
          }
          .buttonStyle(.plain)

          Button {
            if let selectedImage {
              editorImage = ImagePreviewItem(image: selectedImage)
            }
          } label: {
            Label("Adjust", systemImage: "crop")
              .font(.caption.bold())
          }
          .buttonStyle(.plain)

          PhotosPicker(selection: $selectedItem, matching: .images) {
            Label("Replace", systemImage: "arrow.triangle.2.circlepath.camera")
              .font(.caption.bold())
          }
          .buttonStyle(.plain)
        }
        .foregroundStyle(theme.primary)

        Button {
          selectedImage = nil
        } label: {
          Label("Remove Board Picture", systemImage: "xmark.circle.fill")
            .font(.caption.bold())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(hex: 0xD66A6A))
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
      }
    }
  }
}

struct ProjectCoverPhotoSection: View {
  let theme: PanelTheme
  @State private var selectedItem: PhotosPickerItem?
  @State private var displayMode = "Fill"
  @State private var previewImage: ImagePreviewItem?
  @State private var editorImage: ImagePreviewItem?
  @Binding var selectedImage: UIImage?
  var onImageChange: () -> Void = {}

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if selectedImage == nil {
        PhotosPicker(selection: $selectedItem, matching: .images) {
          CoverPhotoView(
            theme: theme,
            image: selectedImage,
            displayMode: displayMode,
            title: "Add Project Picture",
            subtitle: "Tap to choose the project cover photo"
          )
        }
        .buttonStyle(.plain)
      } else {
        CoverPhotoView(
          theme: theme,
          image: selectedImage,
          displayMode: displayMode,
          title: "Project Picture Added",
          subtitle: "View, adjust or replace below"
        )
        .onTapGesture {
          if let selectedImage {
            previewImage = ImagePreviewItem(image: selectedImage)
          }
        }
      }

      if selectedImage != nil {
        Picker("Photo view", selection: $displayMode) {
          ForEach(["Fill", "Fit"], id: \.self) { Text($0) }
        }
        .pickerStyle(.segmented)

        HStack(spacing: 14) {
          Button {
            if let selectedImage {
              previewImage = ImagePreviewItem(image: selectedImage)
            }
          } label: {
            Label("View", systemImage: "photo.fill")
              .font(.caption.bold())
          }
          .buttonStyle(.plain)

          Button {
            if let selectedImage {
              editorImage = ImagePreviewItem(image: selectedImage)
            }
          } label: {
            Label("Adjust", systemImage: "crop")
              .font(.caption.bold())
          }
          .buttonStyle(.plain)

          PhotosPicker(selection: $selectedItem, matching: .images) {
            Label("Replace", systemImage: "arrow.triangle.2.circlepath.camera")
              .font(.caption.bold())
          }
          .buttonStyle(.plain)
        }
        .foregroundStyle(theme.primary)

        Button {
          selectedImage = nil
          onImageChange()
        } label: {
          Label("Remove Project Picture", systemImage: "xmark.circle.fill")
            .font(.caption.bold())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(hex: 0xD66A6A))
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
        onImageChange()
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
        onImageChange()
      }
    }
  }
}

struct CoverPhotoView: View {
  let theme: PanelTheme
  let image: UIImage?
  var displayMode = "Fill"
  let title: String
  let subtitle: String

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(image == nil ? theme.surface.opacity(0.78) : theme.primary.opacity(0.18))

      if let image {
        Group {
          if displayMode == "Fit" {
            Image(uiImage: image)
              .resizable()
              .scaledToFit()
          } else {
            Image(uiImage: image)
              .resizable()
              .scaledToFill()
          }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .clipped()

        Label(displayMode, systemImage: displayMode == "Fit" ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
          .font(.caption.bold())
          .padding(.horizontal, 10)
          .padding(.vertical, 7)
          .background(.black.opacity(0.48))
          .clipShape(Capsule())
          .padding(10)
      } else {
        VStack(spacing: 8) {
          Image(systemName: "camera.fill")
            .font(.title2)
          Text(title)
            .font(.headline)
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .frame(height: 150)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
  }
}

struct CoverPhotoEditorSheet: View {
  let theme: PanelTheme
  let image: UIImage
  let onApply: (UIImage) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var zoom = 1.0
  @State private var horizontalOffset = 0.0
  @State private var verticalOffset = 0.0

  var body: some View {
    NavigationStack {
      VStack(spacing: 18) {
        Text("Adjust Cover")
          .font(.title2.bold())
          .frame(maxWidth: .infinity, alignment: .leading)

        ZStack {
          RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(theme.surface.opacity(0.84))
          Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .scaleEffect(zoom)
            .offset(x: horizontalOffset * 90, y: verticalOffset * 55)
            .frame(maxWidth: .infinity)
            .frame(height: 190)
            .clipped()
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(theme.primary.opacity(0.24), lineWidth: 1)
        )

        VStack(spacing: 14) {
          sliderRow(title: "Zoom", value: $zoom, range: 1...2.6, systemImage: "plus.magnifyingglass")
          sliderRow(title: "Left / Right", value: $horizontalOffset, range: -1...1, systemImage: "arrow.left.and.right")
          sliderRow(title: "Up / Down", value: $verticalOffset, range: -1...1, systemImage: "arrow.up.and.down")
        }

        Button {
          onApply(renderAdjustedImage())
          dismiss()
        } label: {
          Label("Use This Crop", systemImage: "checkmark.circle.fill")
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
        }
        .background(theme.primary)
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .buttonStyle(PanelPressButtonStyle())

        Spacer()
      }
      .padding(18)
      .background(theme.background.ignoresSafeArea())
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Cancel") { dismiss() }
        }
      }
    }
  }

  private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, systemImage: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(title, systemImage: systemImage)
        .font(.caption.bold())
        .foregroundStyle(.secondary)
      Slider(value: value, in: range)
        .tint(theme.primary)
    }
  }

  private func renderAdjustedImage() -> UIImage {
    let canvasSize = CGSize(width: 1200, height: 675)
    let imageSize = image.size
    let baseScale = max(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)
    let drawSize = CGSize(width: imageSize.width * baseScale * zoom, height: imageSize.height * baseScale * zoom)
    let origin = CGPoint(
      x: (canvasSize.width - drawSize.width) / 2 + horizontalOffset * canvasSize.width * 0.18,
      y: (canvasSize.height - drawSize.height) / 2 + verticalOffset * canvasSize.height * 0.18
    )

    let renderer = UIGraphicsImageRenderer(size: canvasSize)
    return renderer.image { _ in
      UIColor.black.setFill()
      UIBezierPath(rect: CGRect(origin: .zero, size: canvasSize)).fill()
      image.draw(in: CGRect(origin: origin, size: drawSize))
    }
  }
}

/// A selectable cabinet chip shown above the per-cabinet checklist on a board.
struct CabinetTab: View {
  let theme: PanelTheme
  let number: Int
  let percent: Int
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Text("\(number)")
          .font(.system(size: 14, weight: .heavy))
        Text("\(percent)%")
          .font(.system(size: 12, weight: .semibold))
          .opacity(0.75)
      }
      .foregroundStyle(selected ? Color.white : theme.primary)
      .lineLimit(1)
      .padding(.horizontal, 13)
      .frame(height: 34)
      .background(selected ? theme.primary : theme.primary.opacity(0.12))
      .clipShape(Capsule())
    }
    .buttonStyle(PanelPressButtonStyle())
  }
}

enum ChecklistTemplate {
  static let singleCabinet = [
    ChecklistItem(title: "Cable holders", weight: 5),
    ChecklistItem(title: "DIN rails", weight: 5),
    ChecklistItem(title: "Components", weight: 5),
    ChecklistItem(title: "Wiring", weight: 30),
    ChecklistItem(title: "N + PE bars", weight: 20),
    ChecklistItem(title: "Mask busbars", weight: 5),
    ChecklistItem(title: "Ground door", weight: 10),
    ChecklistItem(title: "Naming", weight: 10),
    ChecklistItem(title: "Tray ears and cylinder", weight: 5),
    ChecklistItem(title: "Scheme holder", weight: 5)
  ]

  static let multiCabinet = [
    ChecklistItem(title: "Building - Busbars", weight: 10),
    ChecklistItem(title: "Building - Components", weight: 10),
    ChecklistItem(title: "Building - DIN and cable holders", weight: 10),
    ChecklistItem(title: "Wiring", weight: 30),
    ChecklistItem(title: "Naming and finishing", weight: 10),
    ChecklistItem(title: "Stickers", weight: 5),
    ChecklistItem(title: "Scheme holder", weight: 5),
    ChecklistItem(title: "N + PE bars", weight: 20),
  ]

  static func items(for cabinetCount: String) -> [ChecklistItem] {
    (Int(cabinetCount) ?? 1) > 1 ? multiCabinet : singleCabinet
  }
}

struct ChecklistItem: Identifiable, Hashable {
  let title: String
  let weight: Int

  var id: String { title }
}

struct ChecklistProgressSection: View {
  let theme: PanelTheme
  let title: String
  let items: [ChecklistItem]
  @Binding var checkedItems: Set<String>

  private var sortedItems: [ChecklistItem] {
    items
  }

  private var totalWeight: Int {
    max(items.map(\.weight).reduce(0, +), 1)
  }

  private var completedWeight: Int {
    items
      .filter { checkedItems.contains($0.id) }
      .map(\.weight)
      .reduce(0, +)
  }

  private var completion: Int {
    Int((Double(completedWeight) / Double(totalWeight) * 100).rounded())
  }

  private var progress: CGFloat {
    min(max(CGFloat(completion) / 100, 0), 1)
  }

  private var progressColor: Color {
    let value = min(max(Double(completion) / 100, 0), 1)
    return Color(red: 1.0 - value * 0.78, green: 0.22 + value * 0.66, blue: 0.20 + value * 0.08)
  }

  var body: some View {
    GlassCard(theme: theme) {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Label(title, systemImage: "checklist.checked")
            .font(.headline)
          Spacer()
          Text("\(completion)%")
            .font(.system(size: 18, weight: .black))
            .foregroundStyle(progressColor)
            .contentTransition(.numericText())
            .animation(.easeOut(duration: 0.22), value: completion)
        }

        GeometryReader { proxy in
          ZStack(alignment: .leading) {
            Capsule()
              .fill(theme.background.opacity(0.72))
            Capsule()
              .fill(
                LinearGradient(
                  colors: [progressColor.opacity(0.72), progressColor],
                  startPoint: .leading,
                  endPoint: .trailing
                )
              )
              .frame(width: max(proxy.size.width * progress, progress > 0 ? 14 : 0))
              .shadow(color: progressColor.opacity(0.32), radius: 8, y: 2)
              .animation(.easeOut(duration: 0.22), value: progress)
              .animation(.easeOut(duration: 0.22), value: completion)
          }
        }
        .frame(height: 10)

        VStack(spacing: 8) {
          ForEach(sortedItems) { item in
            let isChecked = checkedItems.contains(item.id)
            Button {
              if isChecked {
                checkedItems.remove(item.id)
              } else {
                checkedItems.insert(item.id)
              }
            } label: {
              HStack {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                  .foregroundStyle(isChecked ? progressColor : .secondary)
                  .scaleEffect(isChecked ? 1.06 : 1)
                  .animation(.easeOut(duration: 0.14), value: isChecked)
                Text(item.title)
                  .foregroundStyle(.primary)
                Spacer()
              }
              .padding(12)
              .background(theme.surface.opacity(0.78))
              .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
              .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }
}

struct PersonalChecklistSection: View {
  let theme: PanelTheme
  @Binding var items: [PersonalChecklistItem]
  @State private var newItemTitle = ""

  private var canAdd: Bool {
    !newItemTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Personal Checklist")
          .font(.headline)
        Spacer()
        Text("\(items.filter(\.isDone).count)/\(items.count)")
          .font(.caption.bold())
          .foregroundStyle(.secondary)
      }

      GlassCard(theme: theme) {
        HStack(spacing: 10) {
          TextField("Add reminder item", text: $newItemTitle)
            .textInputAutocapitalization(.sentences)
            .submitLabel(.done)
            .onSubmit(addItem)
          Button {
            addItem()
          } label: {
            Image(systemName: "plus.circle.fill")
              .font(.title3)
              .foregroundStyle(canAdd ? theme.primary : .secondary)
          }
          .buttonStyle(.plain)
          .disabled(!canAdd)
        }
      }

      if items.isEmpty {
        EmptyStateCard(theme: theme, title: "Nothing to remember yet", subtitle: "Add your own reminders for this board.")
      } else {
        VStack(spacing: 8) {
          ForEach($items) { $item in
            HStack(spacing: 10) {
              Button {
                item.isDone.toggle()
              } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                  .foregroundStyle(item.isDone ? theme.primary : .secondary)
                  .font(.system(size: 18, weight: .semibold))
              }
              .buttonStyle(.plain)

              Text(item.title)
                .foregroundStyle(item.isDone ? .secondary : .primary)
                .strikethrough(item.isDone, color: .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

              DeleteIconButton(theme: theme) {
                items.removeAll { $0.id == item.id }
              }
            }
            .padding(12)
            .background(theme.surface.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          }
        }
      }
    }
  }

  private func addItem() {
    let trimmedTitle = newItemTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedTitle.isEmpty else { return }
    items.append(PersonalChecklistItem(title: trimmedTitle))
    newItemTitle = ""
  }
}

struct SchemeAttachmentSection: View {
  let theme: PanelTheme
  var title = "Schemes"
  @Binding var attachments: [SchemeAttachment]
  @State private var selectedPhotos: [PhotosPickerItem] = []
  @State private var pdfImporterOpen = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(title)
          .font(.headline)
        Spacer()
        HStack(spacing: 8) {
          PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 20, matching: .images) {
            Image(systemName: "photo.on.rectangle")
              .font(.system(size: 15, weight: .bold))
              .frame(width: 34, height: 34)
              .background(theme.primary.opacity(0.14))
              .clipShape(Circle())
          }
          .buttonStyle(.plain)

          Button {
            pdfImporterOpen = true
          } label: {
            Image(systemName: "doc.badge.plus")
              .font(.system(size: 15, weight: .bold))
              .frame(width: 34, height: 34)
              .background(theme.primary.opacity(0.14))
              .clipShape(Circle())
          }
          .buttonStyle(.plain)
        }
        .foregroundStyle(theme.primary)
      }

      if attachments.isEmpty {
        EmptyStateCard(theme: theme, title: "No schemes yet", subtitle: "Add a PDF or choose photos. Photos are saved here as scheme files.")
      } else {
        VStack(spacing: 8) {
          ForEach(attachments) { attachment in
            SchemeAttachmentRow(theme: theme, attachment: attachment) {
              attachments.removeAll { $0.id == attachment.id }
            }
          }
        }
      }
    }
    .onChange(of: selectedPhotos) { items in
      loadSchemePhotos(items)
    }
    .fileImporter(
      isPresented: $pdfImporterOpen,
      allowedContentTypes: [.pdf],
      allowsMultipleSelection: true
    ) { result in
      if case .success(let urls) = result {
        let newItems = urls.map { url in
          let savedURL = Self.persistPDF(url)
          return SchemeAttachment(kind: .pdf, name: url.lastPathComponent, image: nil, url: savedURL ?? url)
        }
        attachments.append(contentsOf: newItems)
      }
    }
  }

  private static func persistPDF(_ url: URL) -> URL? {
    let didAccess = url.startAccessingSecurityScopedResource()
    defer {
      if didAccess {
        url.stopAccessingSecurityScopedResource()
      }
    }
    guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
    let folder = documents.appendingPathComponent("PanelVault Schemes", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let destination = folder.appendingPathComponent(url.lastPathComponent)
    if FileManager.default.fileExists(atPath: destination.path) {
      try? FileManager.default.removeItem(at: destination)
    }
    do {
      try FileManager.default.copyItem(at: url, to: destination)
      return destination
    } catch {
      return nil
    }
  }

  private func loadSchemePhotos(_ items: [PhotosPickerItem]) {
    Task {
      var newItems: [SchemeAttachment] = []
      for (index, item) in items.enumerated() {
        if let data = try? await item.loadTransferable(type: Data.self),
           let imported = await ImageStore.imported(from: data) {
          newItems.append(
            SchemeAttachment(
              kind: .photo,
              name: "Scheme photo \(attachments.count + index + 1).jpg",
              imageToken: imported.token,
              url: nil
            )
          )
        }
      }
      await MainActor.run {
        attachments.append(contentsOf: newItems)
        selectedPhotos = []
      }
    }
  }
}

struct SchemeAttachmentRow: View {
  let theme: PanelTheme
  let attachment: SchemeAttachment
  let onDelete: () -> Void
  @Environment(\.openURL) private var openURL

  var body: some View {
    GlassCard(theme: theme) {
      HStack(spacing: 12) {
        ZStack {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(attachment.kind == .pdf ? Color(hex: 0xFF4E5F).opacity(0.18) : theme.primary.opacity(0.18))
          if let image = attachment.thumbnail {
            Image(uiImage: image)
              .resizable()
              .scaledToFill()
              .frame(width: 44, height: 54)
              .clipped()
          } else {
            Image(systemName: "doc.richtext.fill")
              .font(.system(size: 22, weight: .bold))
              .foregroundStyle(Color(hex: 0xFF4E5F))
          }
        }
        .frame(width: 44, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

        VStack(alignment: .leading, spacing: 4) {
          Text(attachment.name)
            .font(.headline)
            .lineLimit(1)
          Text(attachment.kind == .pdf ? "PDF scheme" : "Photo scheme file")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        if let url = attachment.url {
          Button {
            let didAccess = url.startAccessingSecurityScopedResource()
            openURL(url)
            if didAccess {
              DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                url.stopAccessingSecurityScopedResource()
              }
            }
          } label: {
            Image(systemName: "arrow.up.forward.app.fill")
              .foregroundStyle(theme.primary)
              .frame(width: 32, height: 32)
          }
          .buttonStyle(.plain)
        }
        DeleteIconButton(theme: theme, action: onDelete)
      }
    }
  }
}

struct PhotoPickerSection: View {
  let theme: PanelTheme
  let title: String

  /// Image-store tokens rather than decoded images. The grid draws thumbnails
  /// and only decodes a full-size photo when one is actually opened, so a board
  /// or project can hold as many photos as the disk allows.
  @Binding var photoTokens: [String]
  @Binding var coverImage: UIImage?
  @State private var selectedItems: [PhotosPickerItem] = []
  @State private var previewImage: ImagePreviewItem?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(title)
          .font(.headline)
        Spacer()
        PhotosPicker(selection: $selectedItems, maxSelectionCount: 30, matching: .images) {
          Label("Add Photos", systemImage: "camera.fill")
            .font(.caption.bold())
        }
        .buttonStyle(.borderedProminent)
        .tint(theme.primary)
      }

      if photoTokens.isEmpty {
        EmptyStateCard(theme: theme, title: "No photos yet", subtitle: "Tap Add Photos to choose pictures from your phone.")
      } else {
        Text(photoTokens.count == 1 ? "1 photo" : "\(photoTokens.count) photos")
          .font(.caption)
          .foregroundStyle(.secondary)

        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
          ForEach(photoTokens, id: \.self) { (token: String) in
            ZStack(alignment: .topTrailing) {
              GeometryReader { proxy in
                Button {
                  if let full = ImageStore.shared.image(for: token) {
                    previewImage = ImagePreviewItem(image: full)
                  }
                } label: {
                  if let thumbnail = ImageStore.shared.thumbnail(for: token) {
                    Image(uiImage: thumbnail)
                      .resizable()
                      .scaledToFill()
                      .frame(width: proxy.size.width, height: proxy.size.width)
                      .clipped()
                  } else {
                    Rectangle()
                      .fill(theme.surface)
                      .frame(width: proxy.size.width, height: proxy.size.width)
                  }
                }
                .buttonStyle(.plain)
              }
              Button {
                photoTokens.removeAll { $0 == token }
              } label: {
                Image(systemName: "xmark.circle.fill")
                  .font(.system(size: 18, weight: .bold))
                  .foregroundStyle(.white, Color(hex: 0xD66A6A))
                  .padding(5)
              }
              .buttonStyle(.plain)
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          }
        }
      }
    }
    .onChange(of: selectedItems) { items in
      loadImages(from: items)
    }
    .sheet(item: $previewImage) { item in
      ImagePreviewSheet(image: item.image)
    }
  }

  private func loadImages(from items: [PhotosPickerItem]) {
    Task {
      var tokens: [String] = []
      var firstImage: UIImage?

      for item in items {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let imported = await ImageStore.imported(from: data) else { continue }
        if firstImage == nil { firstImage = imported.image }
        tokens.append(imported.token)
      }

      await MainActor.run {
        if coverImage == nil {
          coverImage = firstImage
        }
        // Guard against duplicate ids in the grid if the same file comes back
        // with a token already in the list.
        photoTokens.append(contentsOf: tokens.filter { !photoTokens.contains($0) })
        selectedItems = []
      }
    }
  }
}

struct BoardAttachPickerSheet: View {
  let theme: PanelTheme
  let projectName: String
  let projectCustomer: String
  @Binding var boards: [BoardDraft]
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      BoardAttachPickerContent(theme: theme, projectName: projectName, projectCustomer: projectCustomer, boards: $boards, headerTitle: "Attach Boards", headerSubtitle: "Only boards for this customer can be attached here. Change a board customer from the board itself.")
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("Attach Boards")
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button("Done") { dismiss() }
              .fontWeight(.bold)
          }
        }
    }
  }
}

struct BoardAttachPickerContent: View {
  let theme: PanelTheme
  let projectName: String
  let projectCustomer: String
  @Binding var boards: [BoardDraft]
  let headerTitle: String
  let headerSubtitle: String

  private var attachableBoardIDs: [String] {
    let trimmedCustomer = projectCustomer.trimmingCharacters(in: .whitespacesAndNewlines)
    return boards
      .filter { board in
        if board.project == projectName { return true }
        let isLoose = board.project == "No Project" || board.project.isEmpty
        guard isLoose else { return false }
        guard !trimmedCustomer.isEmpty else { return true }
        return board.customer.localizedCaseInsensitiveCompare(trimmedCustomer) == .orderedSame
      }
      .map(\.id)
  }

  private var inProgressBoardIDs: [String] {
    boards
      .filter { attachableBoardIDs.contains($0.id) && !$0.isCompleted }
      .sorted(by: activeBoardPrioritySort)
      .map(\.id)
  }

  private var finishedBoardIDs: [String] {
    boards
      .filter { attachableBoardIDs.contains($0.id) && $0.isCompleted }
      .sorted { $0.name < $1.name }
      .map(\.id)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        GlassCard(theme: theme) {
          VStack(alignment: .leading, spacing: 6) {
            Label(headerTitle, systemImage: "rectangle.stack.badge.plus")
              .font(.headline)
              .foregroundStyle(theme.primary)
            Text(projectName)
              .font(.title2.bold())
              .lineLimit(1)
              .minimumScaleFactor(0.7)
            Text(headerSubtitle)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }

        boardSection(title: "In Progress Boards", ids: inProgressBoardIDs, empty: "No in-progress boards available.")
        boardSection(title: "Finished Boards", ids: finishedBoardIDs, empty: "No finished boards available.")
      }
      .padding(18)
    }
  }

  private func boardSection(title: String, ids: [String], empty: String) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(title)
          .font(.headline)
        Spacer()
        Text("\(ids.count)")
          .font(.caption.bold())
          .foregroundStyle(.secondary)
      }

      if ids.isEmpty {
        EmptyStateCard(theme: theme, title: empty, subtitle: "Create or finish boards and they will appear here.")
      }

      ForEach($boards.filter { ids.contains($0.wrappedValue.id) }) { $board in
        Button {
          withAnimation(.easeOut(duration: 0.16)) {
            board.project = board.project == projectName ? "No Project" : projectName
          }
        } label: {
          BoardAttachRow(theme: theme, board: board, selected: board.project == projectName)
        }
        .buttonStyle(PanelPressButtonStyle())
      }
    }
  }
}

struct BoardAttachRow: View {
  let theme: PanelTheme
  let board: BoardDraft
  let selected: Bool

  var body: some View {
    GlassCard(theme: theme) {
      HStack(spacing: 12) {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
          .font(.title3)
          .foregroundStyle(selected ? board.color : .secondary)
        VStack(alignment: .leading, spacing: 4) {
          Text(board.name)
            .font(.headline)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
          Text("\(board.number) • \(board.type) • \(board.customer)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        Spacer()
        StatusBadge(status: board.statusTitle)
      }
    }
    .background(board.color.opacity(selected ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(board.color.opacity(selected ? 0.34 : 0.16), lineWidth: 1)
    )
  }
}

struct ImagePreviewItem: Identifiable {
  let id = UUID()
  let image: UIImage
}

struct ImagePreviewSheet: View {
  let image: UIImage
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ZStack {
        Color.black.ignoresSafeArea()
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
          .padding()
      }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
            .fontWeight(.bold)
        }
      }
    }
  }
}
