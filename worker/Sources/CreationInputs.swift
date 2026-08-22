// Copied from the PanelVault app (ios/Runner/SceneDelegate.swift) by
// tools/split_worker.py. The worker app is a deliberate copy of PanelVault's
// design system and data model, with manager-only creation removed and the
// warehouse added. Edit here; do not re-run the splitter over hand edits.

import SwiftUI

struct CreationFormSection<Content: View>: View {
  let theme: PanelTheme
  let title: String
  let symbol: String
  var subtitle: String? = nil
  @ViewBuilder let content: Content

  var body: some View {
    GlassCard(theme: theme) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 10) {
          Image(systemName: symbol)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(theme.primary)
            .frame(width: 28, height: 28)
            .background(theme.primary.opacity(0.14))
            .clipShape(Circle())
          VStack(alignment: .leading, spacing: 2) {
            Text(title)
              .font(.system(size: 16, weight: .heavy))
            if let subtitle {
              Text(subtitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
          }
          Spacer(minLength: 0)
        }

        VStack(spacing: 8) {
          content
        }
      }
    }
  }
}

struct CreationTextInput: View {
  let theme: PanelTheme
  let title: String
  let placeholder: String
  let symbol: String
  @Binding var text: String
  var keyboardType: UIKeyboardType = .default
  var capitalization: TextInputAutocapitalization = .sentences

  var body: some View {
    CreationFieldShell(theme: theme, title: title, symbol: symbol) {
      TextField(placeholder, text: $text)
        .font(.system(size: 15, weight: .semibold))
        .multilineTextAlignment(.trailing)
        .textInputAutocapitalization(capitalization)
        .keyboardType(keyboardType)
        .autocorrectionDisabled(keyboardType != .default)
    }
  }
}

struct CreationMenuInput: View {
  let theme: PanelTheme
  let title: String
  let symbol: String
  let value: String
  let options: [String]
  @Binding var selection: String

  var body: some View {
    CreationFieldShell(theme: theme, title: title, symbol: symbol) {
      Menu {
        ForEach(options, id: \.self) { option in
          Button(option) {
            selection = option
          }
        }
      } label: {
        HStack(spacing: 6) {
          Text(value.isEmpty ? "Select" : value)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
          Image(systemName: "chevron.down")
            .font(.caption2.bold())
        }
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(theme.primary)
      }
    }
  }
}

struct CreationPickerInput: View {
  let theme: PanelTheme
  let title: String
  let symbol: String
  let value: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      CreationFieldShell(theme: theme, title: title, symbol: symbol) {
        HStack(spacing: 6) {
          Text(value.isEmpty ? "Choose" : value)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
          Image(systemName: "chevron.right")
            .font(.caption2.bold())
        }
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(theme.primary)
      }
    }
    .buttonStyle(PanelPressButtonStyle())
  }
}

struct ManufacturerPickerInput: View {
  let theme: PanelTheme
  let title: String
  let value: String
  let manufacturers: [ManufacturerItem]
  let action: () -> Void

  private var manufacturer: ManufacturerItem? {
    syncedManufacturer(named: value, in: manufacturers)
  }

  var body: some View {
    Button(action: action) {
      CreationFieldShell(theme: theme, title: title, symbol: "building.2.fill") {
        HStack(spacing: 7) {
          ManufacturerMarkView(manufacturer: manufacturer, fallbackName: value, size: 24)
          Text(value.isEmpty ? "Choose" : value)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
          Image(systemName: "chevron.right")
            .font(.caption2.bold())
        }
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(manufacturer?.color ?? theme.primary)
      }
    }
    .buttonStyle(PanelPressButtonStyle())
  }
}

struct CreationDateInput: View {
  let theme: PanelTheme
  let title: String
  let symbol: String
  @Binding var selection: Date
  let displayedComponents: DatePickerComponents

  var body: some View {
    CreationFieldShell(theme: theme, title: title, symbol: symbol) {
      DatePicker("", selection: $selection, displayedComponents: displayedComponents)
        .labelsHidden()
        .font(.system(size: 15, weight: .bold))
    }
  }
}

struct CreationToggleInput: View {
  let theme: PanelTheme
  let title: String
  let symbol: String
  @Binding var isOn: Bool

  var body: some View {
    CreationFieldShell(theme: theme, title: title, symbol: symbol) {
      Toggle("", isOn: $isOn)
        .labelsHidden()
        .tint(theme.primary)
    }
  }
}

struct CreationFieldShell<Accessory: View>: View {
  let theme: PanelTheme
  let title: String
  let symbol: String
  @ViewBuilder let accessory: Accessory

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: symbol)
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(theme.primary)
        .frame(width: 26, height: 26)
        .background(theme.primary.opacity(0.12))
        .clipShape(Circle())
      Text(title)
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .minimumScaleFactor(0.72)
      Spacer(minLength: 10)
      accessory
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 9)
    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
    .background(theme.surface.opacity(0.56))
    .clipShape(RoundedRectangle(cornerRadius: theme.radiusControl, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: theme.radiusControl, style: .continuous)
        .stroke(theme.cardBorder, lineWidth: 1)
    )
  }
}

struct CreationOptionPickerSheet: View {
  let theme: PanelTheme
  let title: String
  let symbol: String
  let options: [String]
  let selected: String
  let onSelect: (String) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""

  private var filteredOptions: [String] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return options }
    return options.filter { $0.localizedCaseInsensitiveContains(trimmed) }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          CreationPickerSearch(theme: theme, query: $query, placeholder: "Search \(title.lowercased())")

          LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(filteredOptions, id: \.self) { option in
              Button {
                onSelect(option)
                dismiss()
              } label: {
                CreationOptionCard(theme: theme, title: option, subtitle: option == selected ? "Selected" : nil, symbol: symbol, selected: option == selected)
              }
              .buttonStyle(PanelPressButtonStyle())
            }
          }

          if filteredOptions.isEmpty {
            EmptyStateCard(theme: theme, title: "No matches", subtitle: "Try a different search.")
          }
          BottomTabClearance(height: 40)
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle(title)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Close") { dismiss() }
        }
      }
    }
  }
}

struct ManufacturerCreationPickerSheet: View {
  let theme: PanelTheme
  let manufacturers: [ManufacturerItem]
  let selected: String
  let onSelect: (String) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""

  private var mergedManufacturers: [ManufacturerItem] {
    var seen: Set<String> = []
    return (manufacturers + ManufacturerItem.defaults).filter { manufacturer in
      let key = manufacturer.name.lowercased()
      guard !manufacturer.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !seen.contains(key) else { return false }
      seen.insert(key)
      return true
    }
    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  private var filteredManufacturers: [ManufacturerItem] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return mergedManufacturers }
    return mergedManufacturers.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          CreationPickerSearch(theme: theme, query: $query, placeholder: "Search manufacturers")

          LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(filteredManufacturers) { manufacturer in
              Button {
                onSelect(manufacturer.name)
                dismiss()
              } label: {
                GlassCard(theme: theme) {
                  VStack(alignment: .leading, spacing: 10) {
                    HStack {
                      ManufacturerMarkView(manufacturer: manufacturer, fallbackName: manufacturer.name, size: 42)
                      Spacer()
                      if selected.localizedCaseInsensitiveCompare(manufacturer.name) == .orderedSame {
                        Image(systemName: "checkmark.circle.fill")
                          .font(.system(size: 18, weight: .bold))
                          .foregroundStyle(manufacturer.color)
                      }
                    }

                    Text(manufacturer.name)
                      .font(.system(size: 15, weight: .heavy))
                      .lineLimit(2)
                      .minimumScaleFactor(0.72)

                    Text("Uses logo and color from Manufacturers")
                      .font(.caption2.weight(.semibold))
                      .foregroundStyle(.secondary)
                      .lineLimit(2)
                  }
                  .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
                }
                .overlay(
                  RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                      selected.localizedCaseInsensitiveCompare(manufacturer.name) == .orderedSame ? manufacturer.color : .white.opacity(0.07),
                      lineWidth: selected.localizedCaseInsensitiveCompare(manufacturer.name) == .orderedSame ? 1.4 : 1
                    )
                )
              }
              .buttonStyle(PanelPressButtonStyle())
            }
          }

          if filteredManufacturers.isEmpty {
            EmptyStateCard(theme: theme, title: "No manufacturers", subtitle: "Add it from More, then it will show here.")
          }
          BottomTabClearance(height: 40)
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Manufacturer")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Close") { dismiss() }
        }
      }
    }
  }
}

struct BoardTypeCreationPickerSheet: View {
  let theme: PanelTheme
  let boardTypes: [BoardType]
  let selected: String
  let onSelect: (String) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""

  private var filteredTypes: [BoardType] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return boardTypes }
    return boardTypes.filter {
      $0.name.localizedCaseInsensitiveContains(trimmed) ||
        $0.subtitle.localizedCaseInsensitiveContains(trimmed) ||
        ($0.localName?.localizedCaseInsensitiveContains(trimmed) ?? false)
    }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          CreationPickerSearch(theme: theme, query: $query, placeholder: "Search board types")

          LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(filteredTypes) { board in
              Button {
                onSelect(board.name)
                dismiss()
              } label: {
                GlassCard(theme: theme) {
                  VStack(alignment: .leading, spacing: 10) {
                    HStack {
                      BoardTypeIcon(board: board, size: 38)
                      Spacer()
                      if selected == board.name {
                        Image(systemName: "checkmark.circle.fill")
                          .font(.system(size: 18, weight: .bold))
                          .foregroundStyle(board.color)
                      }
                    }
                    Text(board.name)
                      .font(.system(size: 15, weight: .heavy))
                      .lineLimit(2)
                      .minimumScaleFactor(0.72)
                    Text(board.subtitle)
                      .font(.caption.weight(.semibold))
                      .foregroundStyle(.secondary)
                      .lineLimit(2)
                      .minimumScaleFactor(0.72)
                  }
                  .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
                }
                .overlay(
                  RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke((selected == board.name ? board.color : .white.opacity(0.07)), lineWidth: selected == board.name ? 1.4 : 1)
                )
              }
              .buttonStyle(PanelPressButtonStyle())
            }
          }

          if filteredTypes.isEmpty {
            EmptyStateCard(theme: theme, title: "No board types", subtitle: "Try a different search.")
          }
          BottomTabClearance(height: 40)
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Board Type")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Close") { dismiss() }
        }
      }
    }
  }
}

struct ProjectCreationPickerSheet: View {
  let theme: PanelTheme
  let projects: [ProjectItem]
  let selected: String
  let onSelect: (String) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""

  private var filteredProjects: [ProjectItem] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return projects }
    return projects.filter {
      $0.name.localizedCaseInsensitiveContains(trimmed) ||
        $0.customer.localizedCaseInsensitiveContains(trimmed) ||
        $0.detail.localizedCaseInsensitiveContains(trimmed)
    }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          CreationPickerSearch(theme: theme, query: $query, placeholder: "Search projects or customers")

          Button {
            onSelect("No Project")
            dismiss()
          } label: {
            CreationOptionCard(theme: theme, title: "No Project", subtitle: "Leave this board unattached", symbol: "tray", selected: selected == "No Project")
          }
          .buttonStyle(PanelPressButtonStyle())

          ForEach(filteredProjects) { project in
            Button {
              onSelect(project.name)
              dismiss()
            } label: {
              GlassCard(theme: theme) {
                HStack(spacing: 12) {
                  Image(systemName: "folder.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(project.color)
                    .frame(width: 42, height: 42)
                    .background(project.color.opacity(0.14))
                    .clipShape(Circle())
                  VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                      .font(.headline)
                      .lineLimit(1)
                      .minimumScaleFactor(0.7)
                    Text(project.customer.isEmpty ? "No customer" : project.customer)
                      .font(.caption.weight(.semibold))
                      .foregroundStyle(.secondary)
                      .lineLimit(1)
                  }
                  Spacer()
                  if selected == project.name {
                    Image(systemName: "checkmark.circle.fill")
                      .foregroundStyle(project.color)
                  }
                }
              }
            }
            .buttonStyle(PanelPressButtonStyle())
          }

          if filteredProjects.isEmpty && !query.isEmpty {
            EmptyStateCard(theme: theme, title: "No projects", subtitle: "Try another customer or project name.")
          }
          BottomTabClearance(height: 40)
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Project")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Close") { dismiss() }
        }
      }
    }
  }
}

struct CreationPickerSearch: View {
  let theme: PanelTheme
  @Binding var query: String
  let placeholder: String

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(theme.primary)
      TextField(placeholder, text: $query)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
      if !query.isEmpty {
        Button {
          query = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
      }
    }
    .font(.system(size: 15, weight: .semibold))
    .padding(13)
    .background(theme.surface.opacity(0.70))
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(.white.opacity(0.08), lineWidth: 1)
    )
  }
}

struct CreationOptionCard: View {
  let theme: PanelTheme
  let title: String
  var subtitle: String? = nil
  let symbol: String
  let selected: Bool

  var body: some View {
    GlassCard(theme: theme) {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Image(systemName: symbol)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(theme.primary)
            .frame(width: 38, height: 38)
            .background(theme.primary.opacity(0.14))
            .clipShape(Circle())
          Spacer()
          if selected {
            Image(systemName: "checkmark.circle.fill")
              .font(.system(size: 18, weight: .bold))
              .foregroundStyle(theme.primary)
          }
        }
        Text(title)
          .font(.system(size: 15, weight: .heavy))
          .lineLimit(2)
          .minimumScaleFactor(0.72)
        if let subtitle {
          Text(subtitle)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .minimumScaleFactor(0.72)
        }
      }
      .frame(maxWidth: .infinity, minHeight: subtitle == nil ? 96 : 112, alignment: .leading)
    }
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(selected ? theme.primary.opacity(0.75) : .white.opacity(0.07), lineWidth: selected ? 1.4 : 1)
    )
  }
}

struct SuggestionChips: View {
  let theme: PanelTheme
  let values: [String]
  let selectedValue: String
  let onSelect: (String) -> Void

  var body: some View {
    if !values.isEmpty {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(values, id: \.self) { value in
            Button {
              onSelect(value)
            } label: {
              Text(value)
                .font(.caption.bold())
                .lineLimit(1)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(selectedValue == value ? theme.primary : theme.primary.opacity(0.14))
                .foregroundStyle(selectedValue == value ? .white : theme.primary)
                .clipShape(Capsule())
            }
            .buttonStyle(PanelPressButtonStyle())
          }
        }
      }
    }
  }
}
