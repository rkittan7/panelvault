// Copied from the PanelVault app (ios/Runner/SceneDelegate.swift) by
// tools/split_worker.py. The worker app is a deliberate copy of PanelVault's
// design system and data model, with manager-only creation removed and the
// warehouse added. Edit here; do not re-run the splitter over hand edits.

import SwiftUI
import PhotosUI

struct MoreView: View {
  let theme: PanelTheme
  @Binding var selectedThemeID: String
  @Binding var selectedInterfaceSizeID: String
  @Binding var contractorMode: Bool
  let projects: [ProjectItem]
  @Binding var boards: [BoardDraft]
  @Binding var customers: [CustomerItem]
  @Binding var manufacturers: [ManufacturerItem]
  @Binding var boardTypes: [BoardType]
  @Binding var profileName: String
  @Binding var profileCompany: String
  @Binding var profilePhone: String
  @Binding var profileImageToken: String
  @Binding var activeCompany: ContractorCompany?
  @Binding var companies: [ContractorCompany]
  @State private var componentCatalogOpen = false
  @State private var themePickerOpen = false
  @State private var displaySizeOpen = false
  @State private var profileOpen = false
  @State private var warehouseStockOpen = false
  // The worker app's warehouse is the full read/write store, not the manager
  // app's read-only stock mirror, so the Cloud row reports that session.
  @ObservedObject private var stockStore = WarehouseStore.shared

  private var selectedThemeOption: PanelTheme {
    PanelTheme.all.first { $0.id == selectedThemeID } ?? theme
  }

  private var selectedInterfaceSize: InterfaceSize {
    InterfaceSize.option(for: selectedInterfaceSizeID)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          GlassCard(theme: theme) {
            HStack(spacing: 14) {
              PanelVaultLogoMark(theme: theme, size: 30)
              VStack(alignment: .leading, spacing: 4) {
                Text("PanelVault")
                  .font(.system(size: 27, weight: .heavy))
                  .lineLimit(1)
              }
              Spacer(minLength: 12)
              Text("Zero clutter")
                .foregroundStyle(.secondary)
                .font(.system(size: 12, weight: .bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(theme.primary.opacity(0.12))
                .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }

          Toggle(isOn: $contractorMode) {
            HStack(spacing: 12) {
              Image(systemName: "person.2.fill")
                .foregroundStyle(theme.primary)
                .frame(width: 38, height: 38)
                .background(theme.primary.opacity(0.14))
                .clipShape(Circle())
              VStack(alignment: .leading, spacing: 4) {
                Text("Contractor Mode")
                  .font(.headline)
                Text("Switch between companies")
                  .foregroundStyle(.secondary)
                  .font(.caption)
                  .lineLimit(1)
              }
            }
          }
          .toggleStyle(PanelToggleStyle(theme: theme))
          .padding(12)
          .background(theme.surface.opacity(0.78))
          .clipShape(RoundedRectangle(cornerRadius: theme.radiusCard, style: .continuous))

          Button {
            profileOpen = true
          } label: {
            ProfileMoreRow(
              theme: theme,
              name: profileName,
              imageToken: profileImageToken,
              subtitle: profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Add your name, company and phone" : profileName
            )
          }
          .buttonStyle(PanelPressButtonStyle())

          Button {
            warehouseStockOpen = true
          } label: {
            MoreRow(
              theme: theme,
              symbol: "shippingbox.fill",
              title: "PanelVault Cloud",
              subtitle: stockStore.account.map { "\($0.companyName) • \(stockStore.syncPhase.title)" } ?? "Sign in to sync the warehouse"
            )
          }
          .buttonStyle(PanelPressButtonStyle())

          Button {
            themePickerOpen = true
          } label: {
            ThemePickerRow(theme: theme, selectedTheme: selectedThemeOption)
          }
          .buttonStyle(PanelPressButtonStyle())

          Button {
            displaySizeOpen = true
          } label: {
            MoreRow(theme: theme, symbol: "textformat.size", title: "Dashboard Size", subtitle: selectedInterfaceSize.name)
          }
          .buttonStyle(PanelPressButtonStyle())

          Text("Reference")
            .font(.title3.bold())

          Button {
            componentCatalogOpen = true
          } label: {
            MoreRow(theme: theme, symbol: "shippingbox", title: "Components", subtitle: "MCBs, MCCBs, contactors and more")
          }
          .buttonStyle(PanelPressButtonStyle())
          BottomTabClearance()
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("More")
      .sheet(isPresented: $themePickerOpen) {
        ThemePickerSheet(theme: theme, selectedThemeID: $selectedThemeID)
          .presentationDetents([.medium])
          .presentationDragIndicator(.visible)
      }
      .sheet(isPresented: $displaySizeOpen) {
        DisplaySizePickerSheet(theme: theme, selectedInterfaceSizeID: $selectedInterfaceSizeID)
          .presentationDetents([.medium])
          .presentationDragIndicator(.visible)
      }
      .fullScreenCover(isPresented: $componentCatalogOpen) {
        NavigationStack {
          ScrollView {
            ComponentCatalogView(theme: theme, groups: ComponentGroup.samples, manufacturers: manufacturers, boardStore: $boards)
              .padding(18)
          }
          .background(theme.background.ignoresSafeArea())
          .navigationTitle("Components")
          .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
              Button("Done") {
                componentCatalogOpen = false
              }
            }
          }
        }
      }
      .sheet(isPresented: $profileOpen) {
        ProfileEditorSheet(theme: theme, name: $profileName, company: $profileCompany, phone: $profilePhone, imageToken: $profileImageToken)
      }
      .sheet(isPresented: $warehouseStockOpen) {
        // Injected explicitly rather than relying on the sheet inheriting it:
        // an @EnvironmentObject that fails to propagate is a crash, not a
        // blank screen.
        AccountView(theme: theme)
          .environmentObject(WarehouseStore.shared)
          .presentationDetents([.large])
          .presentationDragIndicator(.visible)
      }
    }
  }

  private var uniqueCustomers: [String] {
    Array(Set(projects.map(\.customer).filter { !$0.isEmpty })).sorted()
  }
}

/// Circular profile picture. Shows the stored photo, or the person's initials,
/// or a person glyph when nothing has been set yet.
struct ProfileAvatarView: View {
  let theme: PanelTheme
  let name: String
  let imageToken: String
  var size: CGFloat = 40

  private var initials: String {
    let words = name
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .split(separator: " ")
      .prefix(2)
    let letters = words.compactMap { $0.first }.map(String.init).joined()
    return letters.uppercased()
  }

  private var image: UIImage? {
    guard !imageToken.isEmpty else { return nil }
    return ImageStore.shared.thumbnail(for: imageToken)
  }

  var body: some View {
    ZStack {
      if let image {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
      } else {
        theme.primary.opacity(0.16)
        if initials.isEmpty {
          Image(systemName: "person.fill")
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(theme.primary)
        } else {
          Text(initials)
            .font(.system(size: size * 0.4, weight: .bold))
            .foregroundStyle(theme.primary)
        }
      }
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
    .overlay(Circle().stroke(theme.cardBorder, lineWidth: 1))
  }
}

struct ProfileEditorSheet: View {
  let theme: PanelTheme
  @Binding var name: String
  @Binding var company: String
  @Binding var phone: String
  @Binding var imageToken: String
  @Environment(\.dismiss) private var dismiss
  @State private var pickerItem: PhotosPickerItem?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 14) {
          VStack(spacing: 12) {
            ProfileAvatarView(theme: theme, name: name, imageToken: imageToken, size: 92)
            PhotosPicker(selection: $pickerItem, matching: .images) {
              Text(imageToken.isEmpty ? "Add photo" : "Change photo")
                .font(.subheadline.bold())
                .foregroundStyle(theme.primary)
            }
            if !imageToken.isEmpty {
              Button(role: .destructive) {
                imageToken = ""
              } label: {
                Text("Remove photo").font(.caption)
              }
            }
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 6)

          CreationTextInput(theme: theme, title: "Full name", placeholder: "Your name", symbol: "person.fill", text: $name, capitalization: .words)
          CreationTextInput(theme: theme, title: "Company", placeholder: "Company", symbol: "building.2.fill", text: $company, capitalization: .words)
          CreationTextInput(theme: theme, title: "Phone", placeholder: "Phone", symbol: "phone.fill", text: $phone, keyboardType: .phonePad)

          BottomTabClearance()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Profile")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
            .fontWeight(.bold)
        }
      }
      .onChange(of: pickerItem) { item in
        guard let item else { return }
        Task {
          if let data = try? await item.loadTransferable(type: Data.self),
             let imported = await ImageStore.imported(from: data) {
            await MainActor.run { imageToken = imported.token }
          }
        }
      }
    }
  }
}

/// The Profile row in More. Same shape as [MoreRow], but its leading bubble is
/// the profile picture itself rather than a symbol.
struct ProfileMoreRow: View {
  let theme: PanelTheme
  let name: String
  let imageToken: String
  let subtitle: String

  var body: some View {
    HStack(spacing: 12) {
      ProfileAvatarView(theme: theme, name: name, imageToken: imageToken, size: 38)
      VStack(alignment: .leading, spacing: 4) {
        Text("Profile").font(.headline)
        Text(subtitle).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      Image(systemName: "chevron.right").foregroundStyle(.secondary)
    }
    .padding(12)
    .background(theme.surface.opacity(0.78))
    .clipShape(RoundedRectangle(cornerRadius: theme.radiusCard, style: .continuous))
  }
}

struct ThemeRow: View {
  let theme: PanelTheme
  let selected: Bool

  // Each row previews its own theme, so text must read against that theme's
  // surface rather than the app's current mode.
  private var ink: Color { theme.colorScheme == .dark ? .white : Color(hex: 0x141414) }
  private var subInk: Color { ink.opacity(0.62) }

  var body: some View {
    HStack(spacing: 12) {
      HStack(spacing: 0) {
        theme.background
        theme.primary
        theme.secondary
      }
      .frame(width: 46, height: 46)
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(theme.cardBorder, lineWidth: 1)
      )

      VStack(alignment: .leading, spacing: 4) {
        Text(theme.name)
          .font(.headline)
          .foregroundStyle(ink)
        Text(theme.description)
          .font(.caption)
          .foregroundStyle(subInk)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      Image(systemName: selected ? "checkmark.circle.fill" : "circle")
        .font(.system(size: 21))
        .foregroundStyle(selected ? theme.primary : subInk)
    }
    .padding(14)
    .background(theme.surface)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(selected ? theme.primary : theme.cardBorder, lineWidth: selected ? 2 : 1)
    )
  }
}

struct ThemePickerRow: View {
  let theme: PanelTheme
  let selectedTheme: PanelTheme

  var body: some View {
    HStack(spacing: 12) {
      HStack(spacing: 0) {
        selectedTheme.background
        selectedTheme.primary
        selectedTheme.secondary
      }
      .frame(width: 38, height: 38)
      .clipShape(Circle())

      VStack(alignment: .leading, spacing: 4) {
        Text("Theme").font(.headline)
        Text(selectedTheme.name).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      Image(systemName: "chevron.right").foregroundStyle(.secondary)
    }
    .padding(12)
    .background(theme.surface.opacity(0.78))
    .clipShape(RoundedRectangle(cornerRadius: theme.radiusCard, style: .continuous))
  }
}

struct ThemePickerSheet: View {
  let theme: PanelTheme
  @Binding var selectedThemeID: String
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 10) {
          ForEach(PanelTheme.all) { option in
            Button {
              selectedThemeID = option.id
              dismiss()
            } label: {
              ThemeRow(theme: option, selected: option.id == selectedThemeID)
            }
            .buttonStyle(.plain)
          }
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Theme")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
    }
  }
}

struct DisplaySizePickerSheet: View {
  let theme: PanelTheme
  @Binding var selectedInterfaceSizeID: String
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 10) {
          ForEach(InterfaceSize.all) { option in
            Button {
              selectedInterfaceSizeID = option.id
              dismiss()
            } label: {
              GlassCard(theme: theme) {
                HStack(spacing: 12) {
                  Image(systemName: option.id == "compact" ? "rectangle.compress.vertical" : option.id == "large" ? "rectangle.expand.vertical" : "rectangle.dashed")
                    .foregroundStyle(theme.primary)
                    .frame(width: 40, height: 40)
                    .background(theme.primary.opacity(0.14))
                    .clipShape(Circle())
                  VStack(alignment: .leading, spacing: 4) {
                    Text(option.name)
                      .font(.headline)
                    Text(option.subtitle)
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                  Spacer()
                  Image(systemName: option.id == selectedInterfaceSizeID ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(option.id == selectedInterfaceSizeID ? theme.primary : .secondary)
                }
              }
            }
            .buttonStyle(PanelPressButtonStyle())
          }
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Dashboard Size")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
    }
  }
}

struct CompanyRow: View {
  let theme: PanelTheme
  let title: String
  let subtitle: String
  let color: Color
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: "building.2")
          .foregroundStyle(color)
          .frame(width: 36, height: 36)
          .background(color.opacity(0.14))
          .clipShape(Circle())
        VStack(alignment: .leading, spacing: 3) {
          Text(title).font(.system(size: 16, weight: .bold))
          Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        Spacer()
        Image(systemName: selected ? "checkmark.circle.fill" : "chevron.right")
          .foregroundStyle(selected ? color : .secondary)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background(selected ? color.opacity(0.12) : .white.opacity(0.045))
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}
