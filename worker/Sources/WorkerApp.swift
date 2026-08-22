// PanelVault Worker — the workshop-floor app.
//
// This is a copy of the PanelVault app's design system and data model with two
// deliberate differences:
//
//   * Nothing here creates or redefines a record. Projects, boards, customers,
//     manufacturers and board types are made in the manager app (ios/) or in
//     PanelVault Cloud. A worker changes a record's *state* — checklist
//     progress, photos, completion — never its definition.
//   * The centre tab is the warehouse instead of the "+" creation hub, so the
//     parts a worker actually handles are one tap away.
//
// The archive itself is still read from the same snapshot format the manager
// app writes, so a synchronized worker sees the same projects and boards.

import SwiftUI

@main
struct PanelVaultWorkerApp: App {
  @StateObject private var warehouse = WarehouseStore.shared

  var body: some Scene {
    WindowGroup {
      WorkerAppView()
        .environmentObject(warehouse)
    }
  }
}

enum WorkerTab: String, CaseIterable, Identifiable {
  case dashboard
  case projects
  case warehouse
  case search
  case more

  var id: String { rawValue }

  var iconName: String {
    switch self {
    case .dashboard: return "house"
    case .projects: return "folder"
    case .warehouse: return "shippingbox.fill"
    case .search: return "magnifyingglass"
    case .more: return "ellipsis"
    }
  }
}

struct WorkerAppView: View {
  @Environment(\.scenePhase) private var scenePhase
  @EnvironmentObject private var warehouse: WarehouseStore
  @State private var selectedTab: WorkerTab = .dashboard
  @State private var searchQuery = ""
  @State private var archiveQuery = ""
  @State private var archiveBoardTypeFilter = "All"
  @State private var archiveStatusFilter = "All"
  @State private var projects: [ProjectItem] = []
  @State private var createdBoards: [BoardDraft] = []
  @State private var boardTypes: [BoardType] = BoardType.samples
  @State private var contractorCompanies: [ContractorCompany] = []
  @State private var customers: [CustomerItem] = []
  @State private var manufacturers: [ManufacturerItem] = ManufacturerItem.defaults
  @State private var recentVisits: [RecentVisit] = []
  @State private var archiveMode: ArchiveMode = .projects
  @State private var pendingProjectOpenID: String?
  @AppStorage("panelvault.theme") private var selectedThemeID = PanelTheme.field.id
  @AppStorage("panelvault.interfaceSize") private var selectedInterfaceSizeID = InterfaceSize.large.id
  @AppStorage("panelvault.contractorMode") private var contractorMode = false
  @AppStorage("panelvault.activeCompany") private var activeCompanyID = ""
  @AppStorage("panelvault.profileName") private var profileName = ""
  @AppStorage("panelvault.profileCompany") private var profileCompany = ""
  @AppStorage("panelvault.profilePhone") private var profilePhone = ""
  @AppStorage("panelvault.profileImageToken") private var profileImageToken = ""
  @State private var loadedSnapshot = false
  @State private var pendingPersistWorkItem: DispatchWorkItem?

  private var selectedTheme: PanelTheme {
    // Field is the default for the worker app rather than Cupertino: it is the
    // high-contrast skin, and this app gets read on a workshop floor.
    PanelTheme.all.first { $0.id == selectedThemeID } ?? .field
  }

  private var activeCompany: Binding<ContractorCompany?> {
    Binding {
      contractorCompanies.first { $0.id == activeCompanyID }
    } set: { company in
      activeCompanyID = company?.id ?? ""
    }
  }

  var body: some View {
    ZStack(alignment: .bottom) {
      selectedTheme.background.ignoresSafeArea()
      selectedTabContent

      WorkerTabBar(theme: selectedTheme, selectedTab: $selectedTab)
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
    .ignoresSafeArea(.keyboard, edges: .bottom)
    .tint(selectedTheme.primary)
    .preferredColorScheme(selectedTheme.colorScheme)
    .onAppear {
      loadSnapshotIfNeeded()
    }
    .onChange(of: scenePhase) { phase in
      if phase == .active {
        // Stock a worker is about to consume must not be stale.
        Task { await warehouse.sync() }
      } else {
        persistSnapshot()
      }
    }
    .onChange(of: boardPersistenceSignature) { _ in
      applyCustomerColors()
      schedulePersistSnapshot()
    }
    .onChange(of: projectPersistenceSignature) { _ in
      applyCustomerColors()
      schedulePersistSnapshot()
    }
  }

  @ViewBuilder
  private var selectedTabContent: some View {
    switch selectedTab {
    case .dashboard:
      DashboardView(
        theme: selectedTheme,
        interfaceSize: InterfaceSize.option(for: selectedInterfaceSizeID),
        contractorMode: contractorMode,
        selectedTab: $selectedTab,
        archiveMode: $archiveMode,
        searchQuery: $searchQuery,
        archiveQuery: $archiveQuery,
        archiveBoardTypeFilter: $archiveBoardTypeFilter,
        archiveStatusFilter: $archiveStatusFilter,
        projects: $projects,
        boardCount: createdBoards.count,
        boards: $createdBoards,
        boardTypes: boardTypes,
        customers: customers,
        manufacturers: manufacturers,
        profileName: $profileName,
        profileCompany: $profileCompany,
        profilePhone: $profilePhone,
        profileImageToken: $profileImageToken,
        activeCompany: activeCompany,
        companies: $contractorCompanies,
        recentVisits: $recentVisits
      )
    case .projects:
      ProjectsView(
        theme: selectedTheme,
        projects: $projects,
        boards: $createdBoards,
        archiveMode: $archiveMode,
        archiveQuery: $archiveQuery,
        archiveBoardTypeFilter: $archiveBoardTypeFilter,
        archiveStatusFilter: $archiveStatusFilter,
        boardTypes: boardTypes,
        customers: customers,
        manufacturers: manufacturers,
        selectedTab: $selectedTab,
        pendingProjectOpenID: $pendingProjectOpenID,
        recentVisits: $recentVisits
      )
    case .warehouse:
      WarehouseTabView(theme: selectedTheme)
    case .search:
      SearchView(
        theme: selectedTheme,
        query: $searchQuery,
        projects: $projects,
        boards: $createdBoards,
        boardTypes: boardTypes,
        manufacturers: manufacturers,
        recentVisits: $recentVisits
      )
    case .more:
      MoreView(
        theme: selectedTheme,
        selectedThemeID: $selectedThemeID,
        selectedInterfaceSizeID: $selectedInterfaceSizeID,
        contractorMode: $contractorMode,
        projects: projects,
        boards: $createdBoards,
        customers: $customers,
        manufacturers: $manufacturers,
        boardTypes: $boardTypes,
        profileName: $profileName,
        profileCompany: $profileCompany,
        profilePhone: $profilePhone,
        profileImageToken: $profileImageToken,
        activeCompany: activeCompany,
        companies: $contractorCompanies
      )
    }
  }

  // MARK: - Archive snapshot
  //
  // Identical to the manager app's loader so both read the same file format.
  // The worker app never *creates* records, but it does write back the state
  // it changes (checklists, photos, completion), so it persists on the same
  // debounce.

  private func loadSnapshotIfNeeded() {
    guard !loadedSnapshot else { return }
    loadedSnapshot = true
    guard let raw = ArchiveStore.loadSnapshot(),
          let snapshot = PanelVaultSnapshot.decode(raw) else { return }
    projects = snapshot.projects.map(\.project)
    createdBoards = snapshot.boards.map(\.board)
    customers = snapshot.customers.map { record in
      var customer = record.customer
      if record.colorHex == nil {
        customer.colorHex = projects.first(where: {
          $0.customer.localizedCaseInsensitiveCompare(customer.name) == .orderedSame
        })?.color.archiveHex ?? createdBoards.first(where: {
          $0.customer.localizedCaseInsensitiveCompare(customer.name) == .orderedSame
        })?.color.archiveHex ?? 0x5E78FF
      }
      return customer
    }
    if let savedCompanies = snapshot.companies {
      contractorCompanies = savedCompanies.map(\.company)
    }
    if let savedManufacturers = snapshot.manufacturers {
      manufacturers = savedManufacturers.map(\.manufacturer)
    }
    applyCustomerColors()
    persistSnapshot()
    sweepOrphanImages()
  }

  /// Deletes image files nothing points at any more. Only ever called straight
  /// after a snapshot loaded successfully — running it on a failed load would
  /// hand it an empty token set and wipe every photo in the archive.
  private func sweepOrphanImages() {
    var tokens = Set<String>()
    for project in projects { tokens.formUnion(project.imageTokens) }
    for board in createdBoards { tokens.formUnion(board.imageTokens) }
    for manufacturer in manufacturers {
      if let token = manufacturer.imageToken { tokens.insert(token) }
    }
    tokens.formUnion(ComponentImageStore.load().values)
    if !profileImageToken.isEmpty { tokens.insert(profileImageToken) }

    ImageStore.shared.sweepOrphans(keeping: tokens)
  }

  private func applyCustomerColors() {
    for index in createdBoards.indices {
      guard !createdBoards[index].customer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
      guard let customer = customers.first(where: {
        $0.name.localizedCaseInsensitiveCompare(createdBoards[index].customer) == .orderedSame
      }) else { continue }
      if createdBoards[index].color.archiveHex != customer.colorHex {
        createdBoards[index].color = customer.color
      }
    }
    for index in projects.indices {
      guard !projects[index].customer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
      guard let customer = customers.first(where: {
        $0.name.localizedCaseInsensitiveCompare(projects[index].customer) == .orderedSame
      }) else { continue }
      if projects[index].color.archiveHex != customer.colorHex {
        projects[index].color = customer.color
      }
    }
  }

  private func persistSnapshot() {
    pendingPersistWorkItem?.cancel()
    pendingPersistWorkItem = nil
    ArchiveStore.saveSnapshot(
      PanelVaultSnapshot(
        projects: projects,
        boards: createdBoards,
        customers: customers,
        companies: contractorCompanies,
        manufacturers: manufacturers
      ).encoded()
    )
  }

  private func schedulePersistSnapshot() {
    guard loadedSnapshot else { return }
    pendingPersistWorkItem?.cancel()
    let workItem = DispatchWorkItem {
      persistSnapshot()
    }
    pendingPersistWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
  }

  private var projectPersistenceSignature: String {
    projects.map(\.persistenceSignature).joined(separator: "||")
  }

  private var boardPersistenceSignature: String {
    createdBoards.map(\.persistenceSignature).joined(separator: "||")
  }
}

struct WorkerTabBar: View {
  let theme: PanelTheme
  @Binding var selectedTab: WorkerTab

  var body: some View {
    HStack {
      HStack(spacing: 4) {
        ForEach(WorkerTab.allCases) { tab in
          Button {
            guard selectedTab != tab else { return }
            withAnimation(.easeOut(duration: 0.12)) {
              selectedTab = tab
            }
          } label: {
            ZStack {
              if selectedTab == tab {
                Capsule(style: .continuous)
                  .fill(
                    LinearGradient(
                      colors: [theme.primary.opacity(0.24), theme.secondary.opacity(0.14)],
                      startPoint: .topLeading,
                      endPoint: .bottomTrailing
                    )
                  )
                  .overlay(
                    Capsule(style: .continuous)
                      .stroke(theme.primary.opacity(0.24), lineWidth: 1)
                  )
              }

              Image(systemName: tab.iconName)
                .font(.system(size: tab == .warehouse ? 23 : 20, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(selectedTab == tab ? theme.primary.opacity(1) : theme.tabBarInactive)
                .scaleEffect(selectedTab == tab ? 1.03 : 1)
            }
            .frame(width: 62, height: 50)
            .contentShape(Rectangle())
          }
          .buttonStyle(TabBarButtonStyle())
          .frame(maxWidth: .infinity)
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .background(
        Capsule(style: .continuous)
          .fill(.ultraThinMaterial)
          .overlay(
            Capsule(style: .continuous)
              .fill(theme.tabBarTint.opacity(theme.colorScheme == .dark ? 0.68 : 0.55))
          )
          .overlay(
            Capsule(style: .continuous)
              .stroke(theme.cardBorder, lineWidth: 1)
          )
          .shadow(color: .black.opacity(theme.colorScheme == .dark ? 0.34 : 0.12), radius: 16, x: 0, y: 8)
      )
      .frame(maxWidth: 388)
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 12)
    .padding(.top, 4)
    .padding(.bottom, 0)
    .offset(y: 18)
  }
}
