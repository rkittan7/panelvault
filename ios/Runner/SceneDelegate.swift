import SwiftUI
import UIKit
import PhotosUI
import Security
import UniformTypeIdentifiers

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let windowScene = scene as? UIWindowScene else { return }

    let window = UIWindow(windowScene: windowScene)
    let hostingController = UIHostingController(rootView: PanelVaultAppView())
    hostingController.view.backgroundColor = UIColor(red: 0.04, green: 0.05, blue: 0.07, alpha: 1)
    window.rootViewController = hostingController
    window.backgroundColor = UIColor(red: 0.04, green: 0.05, blue: 0.07, alpha: 1)
    self.window = window
    window.makeKeyAndVisible()
  }
}

struct PanelVaultAppView: View {
  @Environment(\.scenePhase) private var scenePhase
  @State private var selectedTab: PanelTab = .dashboard
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
  @State private var newHubSelection: NewHubSelection?
  @State private var pendingProjectOpenID: String?
  @AppStorage("panelvault.theme") private var selectedThemeID = PanelTheme.cupertino.id
  @AppStorage("panelvault.interfaceSize") private var selectedInterfaceSizeID = InterfaceSize.standard.id
  @AppStorage("panelvault.standardSizeMigration") private var standardSizeMigration = false
  @AppStorage("panelvault.contractorMode") private var contractorMode = false
  @AppStorage("panelvault.activeCompany") private var activeCompanyID = ""
  @AppStorage("panelvault.profileName") private var profileName = ""
  @AppStorage("panelvault.profileCompany") private var profileCompany = ""
  @AppStorage("panelvault.profilePhone") private var profilePhone = ""
  @AppStorage("panelvault.profileImageToken") private var profileImageToken = ""
  @State private var loadedSnapshot = false
  @State private var pendingPersistWorkItem: DispatchWorkItem?
  @State private var cloudAccount = PanelCloudAccountKeychain.load()
  @State private var cloudWorkspaceVersion = 0
  @State private var cloudWorkspaceReady = false
  @State private var cloudWorkspaceDirty = false
  @State private var cloudSyncedSignature = ""
  @State private var applyingCloudWorkspace = false
  @State private var pendingCloudSyncWorkItem: DispatchWorkItem?

  private var selectedTheme: PanelTheme {
    PanelTheme.all.first { $0.id == selectedThemeID } ?? .cupertino
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

      PanelVaultTabBar(theme: selectedTheme, selectedTab: $selectedTab)
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
    .ignoresSafeArea(.keyboard, edges: .bottom)
    .tint(selectedTheme.primary)
    .preferredColorScheme(selectedTheme.colorScheme)
    .environment(\.panelCloudAccount, cloudAccount)
    .onAppear {
      if !standardSizeMigration {
        selectedInterfaceSizeID = InterfaceSize.standard.id
        standardSizeMigration = true
      }
      loadSnapshotIfNeeded()
    }
    .onChange(of: scenePhase) { phase in
      if phase != .active {
        persistSnapshot(synchronously: true)
      } else {
        Task { await pullCloudWorkspace() }
      }
    }
    .onChange(of: projectPersistenceSignature) { _ in
      applyCustomerColors()
      schedulePersistSnapshot()
      scheduleCloudWorkspacePush()
    }
    .onChange(of: boardPersistenceSignature) { _ in
      applyCustomerColors()
      schedulePersistSnapshot()
      scheduleCloudWorkspacePush()
    }
    .onChange(of: customerPersistenceSignature) { _ in
      applyCustomerColors()
      schedulePersistSnapshot()
    }
    .onChange(of: companyPersistenceSignature) { _ in
      schedulePersistSnapshot()
    }
    .onChange(of: manufacturerPersistenceSignature) { _ in
      schedulePersistSnapshot()
    }
    .onChange(of: boardTypePersistenceSignature) { _ in
      schedulePersistSnapshot()
    }
    .onChange(of: cloudAccount?.token) { _ in
      pendingCloudSyncWorkItem?.cancel()
      cloudWorkspaceReady = false
      cloudWorkspaceDirty = false
      cloudSyncedSignature = ""
    }
    .task(id: cloudAccount?.token) {
      guard cloudAccount != nil else { return }
      while !Task.isCancelled {
        await pullCloudWorkspace()
        try? await Task.sleep(nanoseconds: 20_000_000_000)
      }
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
        newHubSelection: $newHubSelection,
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
        newHubSelection: $newHubSelection,
        pendingProjectOpenID: $pendingProjectOpenID,
        recentVisits: $recentVisits
      )
    case .newBoard:
      NewHubView(
        theme: selectedTheme,
        projects: $projects,
        boards: $createdBoards,
        customers: customers,
        companies: contractorCompanies,
        manufacturers: manufacturers,
        boardTypes: boardTypes,
        selection: $newHubSelection,
        onCreateBoard: { board in
          createdBoards.insert(board, at: 0)
          let trimmedCustomer = board.customer.trimmingCharacters(in: .whitespacesAndNewlines)
          if !trimmedCustomer.isEmpty && !customers.contains(where: { $0.name.localizedCaseInsensitiveCompare(trimmedCustomer) == .orderedSame }) {
            customers.insert(CustomerItem(name: trimmedCustomer, colorHex: board.color.archiveHex), at: 0)
          }
          persistSnapshot()
        },
        onUpdateBoard: { updatedBoard in
          if let index = createdBoards.firstIndex(where: { $0.id == updatedBoard.id }) {
            createdBoards[index] = updatedBoard
            persistSnapshot()
          }
        },
        onCreateProject: { project in
          projects.insert(project, at: 0)
          let trimmedCustomer = project.customer.trimmingCharacters(in: .whitespacesAndNewlines)
          if !trimmedCustomer.isEmpty && !customers.contains(where: { $0.name.localizedCaseInsensitiveCompare(trimmedCustomer) == .orderedSame }) {
            customers.insert(CustomerItem(name: trimmedCustomer, colorHex: project.color.archiveHex), at: 0)
          }
          pendingProjectOpenID = project.id
          archiveMode = .projects
          archiveStatusFilter = "All"
          archiveBoardTypeFilter = "All"
          selectedTab = .projects
          newHubSelection = nil
          DispatchQueue.main.async {
            persistSnapshot()
          }
        }
      )
    case .search:
      SearchView(theme: selectedTheme, query: $searchQuery, projects: $projects, boards: $createdBoards, boardTypes: boardTypes, manufacturers: manufacturers, recentVisits: $recentVisits)
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
        companies: $contractorCompanies,
        cloudAccount: $cloudAccount
      )
    }
  }

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
    if let savedBoardTypes = snapshot.boardTypes {
      let custom = savedBoardTypes.map(\.boardType)
      let names = Set(custom.map { $0.name.lowercased() })
      boardTypes = custom + BoardType.samples.filter { !names.contains($0.name.lowercased()) }
    }
    applyCustomerColors()

    // Legacy snapshots stored base64; decoding above rewrote those as files, so
    // save once here to replace the old payload with tokens.
    persistSnapshot()
    sweepOrphanImages()
  }

  /// Deletes image files nothing points at any more.
  ///
  /// Deliberately only called straight after a snapshot loaded successfully —
  /// running it when loading failed would hand it an empty token set and wipe
  /// every photo in the archive.
  private func sweepOrphanImages() {
    var tokens = Set<String>()
    for project in projects { tokens.formUnion(project.imageTokens) }
    for board in createdBoards { tokens.formUnion(board.imageTokens) }
    for manufacturer in manufacturers {
      if let token = manufacturer.imageToken { tokens.insert(token) }
    }
    tokens.formUnion(ComponentImageStore.load().values)
    // The profile photo belongs to no project or board, so it has to be kept
    // explicitly or the sweep deletes it and the avatar goes blank on relaunch.
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

  private func persistSnapshot(synchronously: Bool = false) {
    pendingPersistWorkItem?.cancel()
    pendingPersistWorkItem = nil
    let encoded = PanelVaultSnapshot(projects: projects, boards: createdBoards, customers: customers, companies: contractorCompanies, manufacturers: manufacturers, boardTypes: boardTypes).encoded()
    if synchronously {
      ArchiveStore.saveSnapshotSynchronously(encoded)
    } else {
      ArchiveStore.saveSnapshot(encoded)
    }
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

  private var cloudWorkspaceSignature: String {
    "\(projectPersistenceSignature)##\(boardPersistenceSignature)"
  }

  private var cloudAccountCanAdminister: Bool {
    guard let role = cloudAccount?.role.lowercased() else { return false }
    return ["owner", "manager", "staff-manager"].contains(role)
  }

  private func scheduleCloudWorkspacePush() {
    guard loadedSnapshot, cloudWorkspaceReady, !applyingCloudWorkspace,
          cloudAccount != nil, cloudWorkspaceSignature != cloudSyncedSignature else { return }
    cloudWorkspaceDirty = true
    pendingCloudSyncWorkItem?.cancel()
    let workItem = DispatchWorkItem {
      Task { await pushCloudWorkspace() }
    }
    pendingCloudSyncWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
  }

  private func pullCloudWorkspace() async {
    guard loadedSnapshot, let account = cloudAccount,
          !cloudWorkspaceDirty, !applyingCloudWorkspace else { return }
    do {
      let remote = try await PanelCloudClient().downloadWorkspace(account: account)
      guard cloudAccount?.token == account.token else { return }

      // The first connection of an existing phone archive migrates it only into
      // an empty company. A populated company always wins, preventing records
      // from one account being copied into another after an account switch.
      if remote.projects.isEmpty, remote.boards.isEmpty,
         (!projects.isEmpty || !createdBoards.isEmpty), cloudAccountCanAdminister {
        let migrated = try await PanelCloudClient().uploadWorkspace(
          account: account,
          expectedVersion: remote.version,
          projects: projects,
          boards: createdBoards
        )
        applyCloudWorkspace(migrated)
      } else {
        applyCloudWorkspace(remote)
      }
    } catch {
      // Keep the phone fully usable offline. The task retries on foreground and
      // every polling interval, while local snapshot persistence continues.
    }
  }

  private func pushCloudWorkspace() async {
    guard let account = cloudAccount, cloudWorkspaceReady,
          cloudWorkspaceDirty, !applyingCloudWorkspace else { return }
    let localProjects = projects
    let localBoards = createdBoards
    let localSignature = cloudWorkspaceSignature
    do {
      let result: PanelCloudWorkspace
      if cloudAccountCanAdminister {
        do {
          result = try await PanelCloudClient().uploadWorkspace(
            account: account,
            expectedVersion: cloudWorkspaceVersion,
            projects: localProjects,
            boards: localBoards
          )
        } catch {
          // Optimistic versioning prevents a stale phone from overwriting a web
          // edit. Pull the new version and replay this local edit once.
          let latest = try await PanelCloudClient().downloadWorkspace(account: account)
          result = try await PanelCloudClient().uploadWorkspace(
            account: account,
            expectedVersion: latest.version,
            projects: localProjects,
            boards: localBoards
          )
        }
      } else {
        do {
          result = try await PanelCloudClient().uploadBoardProgress(
            account: account,
            expectedVersion: cloudWorkspaceVersion,
            boards: localBoards
          )
        } catch {
          let latest = try await PanelCloudClient().downloadWorkspace(account: account)
          result = try await PanelCloudClient().uploadBoardProgress(
            account: account,
            expectedVersion: latest.version,
            boards: localBoards
          )
        }
      }
      guard cloudAccount?.token == account.token else { return }
      if cloudWorkspaceSignature == localSignature {
        applyCloudWorkspace(result)
      } else {
        // A second tap landed while the first upload was in flight. Keep that
        // newer local state and send it against the version we just received.
        cloudWorkspaceVersion = result.version
        cloudWorkspaceDirty = true
        pendingCloudSyncWorkItem?.cancel()
        let workItem = DispatchWorkItem { Task { await pushCloudWorkspace() } }
        pendingCloudSyncWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
      }
    } catch {
      // Leave the dirty flag set; the next foreground/poll or local edit retries.
    }
  }

  private func applyCloudWorkspace(_ workspace: PanelCloudWorkspace) {
    let existingProjects = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
    let existingBoards = Dictionary(uniqueKeysWithValues: createdBoards.map { ($0.id, $0) })
    applyingCloudWorkspace = true
    projects = workspace.projects.map { $0.project(preserving: existingProjects[$0.id]) }
    createdBoards = workspace.boards.map { $0.board(preserving: existingBoards[$0.id]) }
    cloudWorkspaceVersion = workspace.version
    cloudWorkspaceReady = true
    cloudWorkspaceDirty = false
    cloudSyncedSignature = cloudWorkspaceSignature
    persistSnapshot()
    DispatchQueue.main.async {
      applyingCloudWorkspace = false
    }
  }

  private var projectPersistenceSignature: String {
    projects.map(\.persistenceSignature).joined(separator: "||")
  }

  private var boardPersistenceSignature: String {
    createdBoards.map(\.persistenceSignature).joined(separator: "||")
  }

  private var customerPersistenceSignature: String {
    customers.map(\.persistenceSignature).joined(separator: "||")
  }

  private var companyPersistenceSignature: String {
    contractorCompanies.map(\.persistenceSignature).joined(separator: "||")
  }

  private var manufacturerPersistenceSignature: String {
    manufacturers.map(\.persistenceSignature).joined(separator: "||")
  }

  private var boardTypePersistenceSignature: String {
    boardTypes.map { "\($0.id)|\($0.name)|\($0.subtitle)|\($0.emoji ?? "")" }.joined(separator: "||")
  }
}

enum PanelTab: String, CaseIterable, Identifiable {
  case dashboard
  case projects
  case newBoard
  case search
  case more

  var id: String { rawValue }

  var iconName: String {
    switch self {
    case .dashboard: return "house"
    case .projects: return "folder"
    case .newBoard: return "plus"
    case .search: return "magnifyingglass"
    case .more: return "ellipsis"
    }
  }
}

struct PanelVaultTabBar: View {
  let theme: PanelTheme
  @Binding var selectedTab: PanelTab

  var body: some View {
    HStack {
      HStack(spacing: 4) {
        ForEach(PanelTab.allCases) { tab in
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
                .font(.system(size: tab == .newBoard ? 23 : 20, weight: .semibold))
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

struct TabBarButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.94 : 1)
      .opacity(configuration.isPressed ? 0.86 : 1)
      .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
  }
}

struct BottomTabClearance: View {
  var height: CGFloat = 96

  var body: some View {
    Color.clear
      .frame(height: height)
      .allowsHitTesting(false)
  }
}

struct InterfaceSize: Identifiable, Equatable {
  let id: String
  let name: String
  let subtitle: String
  let dashboardSpacing: CGFloat
  let dashboardPadding: CGFloat
  let statHeight: CGFloat
  let titleSize: CGFloat
  let logoSize: CGFloat
  let rowScale: CGFloat
  let boardTypeColumns: Int
  let boardTypeIconSize: CGFloat
  let boardTypeTitleSize: CGFloat
  let boardTypeSubtitleSize: CGFloat

  static let compact = InterfaceSize(id: "compact", name: "Compact", subtitle: "More on screen", dashboardSpacing: 12, dashboardPadding: 10, statHeight: 78, titleSize: 20, logoSize: 26, rowScale: 0.94, boardTypeColumns: 3, boardTypeIconSize: 30, boardTypeTitleSize: 12, boardTypeSubtitleSize: 9)
  static let standard = InterfaceSize(id: "standard", name: "Standard", subtitle: "Balanced", dashboardSpacing: 22, dashboardPadding: 18, statHeight: 112, titleSize: 24, logoSize: 32, rowScale: 1, boardTypeColumns: 2, boardTypeIconSize: 38, boardTypeTitleSize: 15, boardTypeSubtitleSize: 11)
  static let large = InterfaceSize(id: "large", name: "Large", subtitle: "Easier to read", dashboardSpacing: 26, dashboardPadding: 20, statHeight: 122, titleSize: 26, logoSize: 36, rowScale: 1.04, boardTypeColumns: 2, boardTypeIconSize: 42, boardTypeTitleSize: 16, boardTypeSubtitleSize: 12)

  static let all = [compact, standard, large]

  static func option(for id: String) -> InterfaceSize {
    all.first { $0.id == id } ?? .standard
  }
}

enum DateDisplay {
  static let short: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
  }()

  static let due: DateFormatter = {
    let formatter = DateFormatter()
    formatter.setLocalizedDateFormatFromTemplate("d MMM")
    formatter.timeStyle = .none
    return formatter
  }()
}

private func dueDateComesFirst(_ left: Date?, _ right: Date?) -> Bool? {
  switch (left, right) {
  case let (left?, right?):
    guard abs(left.timeIntervalSince1970 - right.timeIntervalSince1970) > 1 else { return nil }
    return left < right
  case (_?, nil):
    return true
  case (nil, _?):
    return false
  default:
    return nil
  }
}

private func activeBoardPrioritySort(_ left: BoardDraft, _ right: BoardDraft) -> Bool {
  if let dueSort = dueDateComesFirst(left.dueDate, right.dueDate) { return dueSort }
  if left.completion != right.completion { return left.completion > right.completion }
  return left.name < right.name
}

private func boardPrioritySort(_ left: BoardDraft, _ right: BoardDraft) -> Bool {
  if let dueSort = dueDateComesFirst(left.dueDate, right.dueDate) { return dueSort }
  if left.isCompleted != right.isCompleted { return !left.isCompleted && right.isCompleted }
  if left.completion != right.completion { return left.completion > right.completion }
  return left.name < right.name
}

private func projectPrioritySort(_ left: ProjectItem, _ right: ProjectItem) -> Bool {
  if let dueSort = dueDateComesFirst(left.dueDate, right.dueDate) { return dueSort }
  return left.name < right.name
}

private func syncedManufacturer(named name: String, in manufacturers: [ManufacturerItem]) -> ManufacturerItem? {
  manufacturers.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame } ??
    ManufacturerItem.defaults.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
}

private func dueUrgencyColor(for date: Date) -> Color {
  let hours = date.timeIntervalSince(Date()) / 3600
  if hours <= 0 { return Color(hex: 0xFF453A) }
  let days = min(max(hours / 24, 0), 14)
  let urgency = 1 - (days / 14)
  let red = 0.20 + (urgency * 0.80)
  let green = 0.86 - (urgency * 0.58)
  let blue = 0.34 - (urgency * 0.18)
  return Color(red: red, green: green, blue: blue)
}

struct DashboardView: View {
  let theme: PanelTheme
  let interfaceSize: InterfaceSize
  let contractorMode: Bool
  @Binding var selectedTab: PanelTab
  @Binding var archiveMode: ArchiveMode
  @Binding var searchQuery: String
  @Binding var archiveQuery: String
  @Binding var archiveBoardTypeFilter: String
  @Binding var archiveStatusFilter: String
  @Binding var projects: [ProjectItem]
  let boardCount: Int
  @Binding var boards: [BoardDraft]
  let boardTypes: [BoardType]
  let customers: [CustomerItem]
  let manufacturers: [ManufacturerItem]
  @Binding var profileName: String
  @Binding var profileCompany: String
  @Binding var profilePhone: String
  @Binding var profileImageToken: String
  @Binding var newHubSelection: NewHubSelection?
  @Binding var activeCompany: ContractorCompany?
  @Binding var companies: [ContractorCompany]
  @Binding var recentVisits: [RecentVisit]
  @State private var profileOpen = false
  @State private var companySheetOpen = false
  @State private var dashboardSheet: DashboardSheet?
  @State private var selectedProject: ProjectItem?
  @State private var selectedBoardID: String?
  /// A project just created here, waiting for its form to close so its own
  /// page can be opened.
  @State private var pendingCreatedProject: ProjectItem?

  var title: String {
    guard contractorMode else { return "PanelVault" }
    return activeCompany?.name ?? "All Companies"
  }

  var subtitle: String {
    guard contractorMode else { return "" }
    return activeCompany == nil ? "Every company in PanelVault" : "Contractor workspace"
  }

  private var dashboardStats: [PanelStat] {
    [
      PanelStat(id: "projects", title: "Projects", value: "\(projects.count)", symbol: "folder.fill", color: theme.primary),
      PanelStat(id: "boards", title: "Boards", value: "\(boardCount)", symbol: "rectangle.3.group.fill", color: theme.secondary),
      PanelStat(id: "active-projects", title: "Active Projects", value: "\(activeProjectDashboardCount)", symbol: "clock.fill", color: theme.primary.opacity(0.82)),
      PanelStat(id: "active-boards", title: "Boards Active", value: "\(activeBoardDashboardCount)", symbol: "checklist", color: theme.secondary.opacity(0.9))
    ]
  }

  private var activeProjects: [ProjectItem] {
    projects.filter { ["In Progress", "Design"].contains(projectStatus($0)) }
      .sorted(by: projectPrioritySort)
      .prefix(3)
      .map { $0 }
  }

  private var activeBoards: [BoardDraft] {
    boards
      .filter { !$0.isCompleted }
      .sorted(by: activeBoardPrioritySort)
      .prefix(3)
      .map { $0 }
  }

  private var activeProjectDashboardCount: Int {
    projects.filter { ["In Progress", "Design"].contains(projectStatus($0)) }.count
  }

  private var activeBoardDashboardCount: Int {
    boards.filter { !$0.isCompleted }.count
  }

  private var greeting: String {
    let hour = Calendar.current.component(.hour, from: Date())
    let timeGreeting: String
    switch hour {
    case 5..<12:
      timeGreeting = "good morning"
    case 12..<18:
      timeGreeting = "good afternoon"
    case 18..<22:
      timeGreeting = "good evening"
    default:
      timeGreeting = "good night"
    }
    let trimmedName = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
    let firstName = trimmedName.split(separator: " ").first.map(String.init) ?? ""
    return firstName.isEmpty ? timeGreeting.capitalized : "Hey \(firstName), \(timeGreeting)!"
  }

  private var sortedBoardTypes: [BoardType] {
    Array(boardTypes
      .filter { boardCount(for: $0) > 0 }
      .sorted {
        let leftCount = boardCount(for: $0)
        let rightCount = boardCount(for: $1)
        if leftCount == rightCount { return $0.name < $1.name }
        return leftCount > rightCount
      }
      .prefix(6))
  }

  private var visibleRecentVisits: [RecentVisit] {
    recentVisits.filter { visit in
      switch visit.kind {
      case .project:
        return projects.contains { $0.id == visit.itemID }
      case .board:
        return boards.contains { $0.id == visit.itemID }
      }
    }
    .prefix(3)
    .map { $0 }
  }

  var body: some View {
    NavigationStack {
      ScrollView(showsIndicators: false) {
        VStack(spacing: interfaceSize.dashboardSpacing) {
          header
          statsGrid
          greetingHeader
          sectionHeader("Boards", symbol: "rectangle.3.group.fill", count: activeBoardDashboardCount, accent: theme.secondary) {
            archiveQuery = ""
            archiveBoardTypeFilter = "All"
            archiveStatusFilter = "In Progress"
            archiveMode = .boards
            selectedTab = .projects
          }
          activeBoardsList
          sectionHeader("Projects", symbol: "folder.fill", count: activeProjectDashboardCount) {
            archiveQuery = ""
            archiveBoardTypeFilter = "All"
            archiveStatusFilter = "In Progress"
            archiveMode = .projects
            selectedTab = .projects
          }
          activeProjectsList
          sectionHeader("Board Types", symbol: "square.grid.2x2.fill") {
            dashboardSheet = .boardTypes
          }
          boardTypesGrid
          quickSearch
          sectionHeader("Recents", symbol: "clock.arrow.circlepath") {
            archiveQuery = ""
            selectedTab = .search
          }
          recentsList
          BottomTabClearance()
        }
        .padding(.horizontal, interfaceSize.dashboardPadding)
        .padding(.top, 14)
        .padding(.bottom, 12)
      }
      .background(theme.background.ignoresSafeArea())
      .overlay(alignment: .top) {
        TopScrollBlur(theme: theme)
      }
      .sheet(isPresented: $companySheetOpen) {
        CompanySwitcherSheet(
          theme: theme,
          activeCompany: $activeCompany,
          companies: companies
        )
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
      }
      .sheet(item: $dashboardSheet) { sheet in
        switch sheet {
        case .boardTypes:
          BoardTypesSheet(theme: theme, boardTypes: boardTypes)
        case .recentProjects:
          ProjectsListSheet(theme: theme, projects: $projects, boards: $boards, boardTypes: boardTypes, manufacturers: manufacturers)
        case .stats:
          DashboardStatsSheet(theme: theme, projects: projects, boardCount: boardCount)
        case .companies:
          CompanyManagerSheet(
            theme: theme,
            companies: $companies,
            activeCompany: $activeCompany,
            projects: projects,
            boards: $boards,
            boardTypes: boardTypes,
            manufacturers: manufacturers
          )
        case .customers:
          SimpleListSheet(
            theme: theme,
            title: "Customers",
            rows: uniqueCustomers.map { SimpleListRow(symbol: "person.crop.circle", title: $0, subtitle: "", color: theme.primary) }
          )
        case .newProject:
          NewProjectSheet(theme: theme, boards: $boards, customers: customers, projectCustomers: uniqueCustomers, onDone: {
            dashboardSheet = nil
          }) { project in
            projects.insert(project, at: 0)
            pendingCreatedProject = project
          }
        }
      }
    }
    // Same reason as on the Projects tab: the new project's page can only be
    // presented once the form's own sheet has finished dismissing.
    .onChange(of: dashboardSheet) { sheet in
      guard sheet == nil, let project = pendingCreatedProject else { return }
      pendingCreatedProject = nil
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
        selectedProject = project
      }
    }
    .sheet(item: $selectedProject) { project in
          ProjectDetailSheet(theme: theme, project: project, boards: $boards, boardTypes: boardTypes, manufacturers: manufacturers) { board in
        remember(.board, id: board.id)
      } onUpdateProject: { updatedProject, previousName in
        if let index = projects.firstIndex(where: { $0.id == updatedProject.id }) {
          projects[index] = updatedProject
        }
        for index in boards.indices where boards[index].project == previousName {
          boards[index].project = updatedProject.name
        }
      } onDeleteProject: {
        deleteProject(project)
        selectedProject = nil
      }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
    .sheet(item: selectedBoardBinding) { boardID in
      if let index = boards.firstIndex(where: { $0.id == boardID.id }) {
        NavigationStack {
          CreatedBoardScreen(theme: theme, board: $boards[index], boardTypes: boardTypes, manufacturers: manufacturers, onDeleteBoard: {
            deleteBoard(id: boardID.id)
            selectedBoardID = nil
          }) {
            selectedBoardID = nil
          }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
      }
    }
  }

  private var uniqueCustomers: [String] {
    Array(Set(projects.map(\.customer).filter { !$0.isEmpty })).sorted()
  }

  private func linkedBoards(for project: ProjectItem) -> [BoardDraft] {
    boards.filter { $0.project == project.name }
  }

  private func projectStatus(_ project: ProjectItem) -> String {
    let linked = linkedBoards(for: project)
    guard !linked.isEmpty else { return project.status }
    return linked.allSatisfy(\.isCompleted) ? "Completed" : "In Progress"
  }

  private func boardCount(for boardType: BoardType) -> Int {
    boards.filter { $0.type == boardType.name }.count
  }

  private func remember(_ kind: RecentVisit.Kind, id: String) {
    recentVisits.removeAll { $0.kind == kind && $0.itemID == id }
    recentVisits.insert(RecentVisit(kind: kind, id: id), at: 0)
    recentVisits = Array(recentVisits.prefix(12))
  }

  private func deleteProject(_ project: ProjectItem) {
    projects.removeAll { $0.id == project.id }
    for index in boards.indices where boards[index].project == project.name {
      boards[index].project = "No Project"
    }
    recentVisits.removeAll { $0.kind == .project && $0.itemID == project.id }
    ImageStore.shared.delete(project.imageTokens)
  }

  private func deleteBoard(id: String) {
    let tokens = boards.first { $0.id == id }?.imageTokens ?? []
    boards.removeAll { $0.id == id }
    recentVisits.removeAll { $0.kind == .board && $0.itemID == id }
    ImageStore.shared.delete(tokens)
  }

  private var selectedBoardBinding: Binding<RecentBoardSelection?> {
    Binding {
      selectedBoardID.map(RecentBoardSelection.init(id:))
    } set: { selection in
      selectedBoardID = selection?.id
    }
  }

  var header: some View {
    HStack(spacing: 14) {
      if contractorMode {
        Button {
          companySheetOpen = true
        } label: {
          Image(systemName: "line.3.horizontal")
            .font(.system(size: 19, weight: .semibold))
            .frame(width: 38, height: 38)
            .background(theme.surface.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
      }

      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 10) {
          PanelVaultLogoMark(theme: theme, size: interfaceSize.logoSize)
          Text(title)
            .font(.system(size: interfaceSize.titleSize, weight: .heavy))
            .lineLimit(1)
        }

        if !subtitle.isEmpty {
          Text(subtitle)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }

      Spacer(minLength: 8)

      Button {
        profileOpen = true
      } label: {
        ProfileAvatarView(theme: theme, name: profileName, imageToken: profileImageToken, size: 48)
      }
      .buttonStyle(PanelPressButtonStyle())
      .accessibilityLabel("Profile")
    }
    .sheet(isPresented: $profileOpen) {
      ProfileEditorSheet(
        theme: theme,
        name: $profileName,
        company: $profileCompany,
        phone: $profilePhone,
        imageToken: $profileImageToken
      )
    }
  }

  var greetingHeader: some View {
    HStack {
      Text(greeting)
        .font(.system(size: 30, weight: .heavy))
        .foregroundStyle(.primary)
        .minimumScaleFactor(0.78)
      Spacer()
    }
    .padding(.top, 2)
  }

  var statsGrid: some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
      ForEach(dashboardStats) { stat in
        Button {
          if stat.id == "projects" {
            archiveQuery = ""
            archiveBoardTypeFilter = "All"
            archiveStatusFilter = "All"
            archiveMode = .projects
            selectedTab = .projects
          } else if stat.id == "boards" {
            archiveQuery = ""
            archiveBoardTypeFilter = "All"
            archiveStatusFilter = "All"
            archiveMode = .boards
            selectedTab = .projects
          } else if stat.id == "active-projects" {
            archiveQuery = ""
            archiveBoardTypeFilter = "All"
            archiveStatusFilter = "In Progress"
            archiveMode = .projects
            selectedTab = .projects
          } else if stat.id == "active-boards" {
            archiveQuery = ""
            archiveBoardTypeFilter = "All"
            archiveStatusFilter = "In Progress"
            archiveMode = .boards
            selectedTab = .projects
          } else {
            dashboardSheet = .stats
          }
        } label: {
          GlassCard(theme: theme) {
            VStack(spacing: 7) {
              Image(systemName: stat.symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(stat.color)
                .frame(width: 34, height: 34)
                .background(stat.color.opacity(0.14))
                .clipShape(Circle())
              Text(stat.value)
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(stat.color)
                .minimumScaleFactor(0.75)
                .frame(height: 26)
              Text(stat.title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .frame(height: interfaceSize.statHeight)
          }
        }
        .buttonStyle(.plain)
      }
    }
  }

  var boardTypesGrid: some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: interfaceSize.boardTypeColumns), spacing: 8) {
      if sortedBoardTypes.isEmpty {
        EmptyStateCard(theme: theme, title: "No board types yet", subtitle: "Create boards and their types will appear here by quantity.")
      }
      ForEach(sortedBoardTypes) { board in
        Button {
          archiveQuery = ""
          archiveBoardTypeFilter = board.name
          archiveStatusFilter = "All"
          archiveMode = .boards
          selectedTab = .projects
        } label: {
          GlassCard(theme: theme) {
            HStack(spacing: interfaceSize.boardTypeColumns == 3 ? 7 : 10) {
              BoardTypeIcon(board: board, size: interfaceSize.boardTypeIconSize)

              VStack(alignment: .leading, spacing: 3) {
                Text(board.name)
                  .font(.system(size: interfaceSize.boardTypeTitleSize, weight: .heavy))
                  .lineLimit(2)
                  .minimumScaleFactor(0.72)
                Text(board.subtitle)
                  .font(.system(size: interfaceSize.boardTypeSubtitleSize, weight: .semibold))
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
                  .minimumScaleFactor(0.65)
              }

              Spacer()
              Text("\(boardCount(for: board))")
                .font(.system(size: interfaceSize.boardTypeColumns == 3 ? 10 : 12, weight: .bold))
                .foregroundStyle(board.color)
                .padding(.horizontal, interfaceSize.boardTypeColumns == 3 ? 6 : 9)
                .padding(.vertical, interfaceSize.boardTypeColumns == 3 ? 4 : 5)
                .background(board.color.opacity(0.14))
                .clipShape(Capsule())
            }
          }
        }
        .buttonStyle(.plain)
      }
    }
  }

  var activeProjectsList: some View {
    VStack(spacing: 10) {
      if activeProjects.isEmpty {
        EmptyStateCard(theme: theme, title: "No active projects", subtitle: "Design and in-progress projects will show here.")
      }
      ForEach(Array(activeProjects.prefix(3).enumerated()), id: \.element.id) { _, project in
        Button {
          remember(.project, id: project.id)
          selectedProject = project
        } label: {
          ProjectDashboardRow(
            theme: theme,
            project: project,
            boardCount: linkedBoards(for: project).count,
            displayedStatus: projectStatus(project),
            glow: true
          )
        }
        .buttonStyle(.plain)
      }
    }
  }

  var activeBoardsList: some View {
    VStack(spacing: 10) {
      if activeBoards.isEmpty {
        EmptyStateCard(theme: theme, title: "No in-progress boards", subtitle: "Boards in active production stages will show here.")
      }
      ForEach(Array(activeBoards.prefix(3).enumerated()), id: \.element.id) { _, board in
        Button {
          remember(.board, id: board.id)
          selectedBoardID = board.id
        } label: {
          DashboardBoardProgressRow(theme: theme, board: board, boardTypes: boardTypes, manufacturers: manufacturers)
        }
        .buttonStyle(PanelPressButtonStyle())
      }
    }
  }

  var quickSearch: some View {
    GlassCard(theme: theme) {
      VStack(alignment: .leading, spacing: 14) {
        HStack(spacing: 10) {
          Image(systemName: "magnifyingglass")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(theme.primary)
            .frame(width: 30, height: 30)
            .background(theme.primary.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
          Text("Quick Search")
            .font(.system(size: 19, weight: .heavy))
          Spacer()
          Label("Filters", systemImage: "slider.horizontal.3")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(theme.primary)
        }

        Button {
          searchQuery = ""
          selectedTab = .search
        } label: {
          HStack {
            Image(systemName: "magnifyingglass")
              .foregroundStyle(.secondary)
            Text("Search 630A, ABB, project #...")
              .foregroundStyle(.secondary)
            Spacer()
            Image(systemName: "arrow.right.circle.fill")
              .foregroundStyle(theme.primary)
          }
          .font(.system(size: 15, weight: .semibold))
          .padding(14)
          .background(theme.surface.opacity(0.72))
          .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
      }
    }
  }

  var recentsList: some View {
    VStack(spacing: 14) {
      if visibleRecentVisits.isEmpty {
        EmptyStateCard(theme: theme, title: "No recents yet", subtitle: "Open a project or board and it will stay here.")
      }
      ForEach(visibleRecentVisits) { visit in
        Button {
          openRecent(visit)
        } label: {
          recentRow(for: visit)
        }
        .buttonStyle(.plain)
      }
    }
  }

  @ViewBuilder
  private func recentRow(for visit: RecentVisit) -> some View {
    switch visit.kind {
    case .project:
      if let project = projects.first(where: { $0.id == visit.itemID }) {
        DashboardProjectRecentRow(
          theme: theme,
          project: project,
          boardCount: linkedBoards(for: project).count,
          displayedStatus: projectStatus(project)
        )
      }
    case .board:
      if let board = boards.first(where: { $0.id == visit.itemID }) {
        DashboardBoardRecentRow(theme: theme, board: board, boardTypes: boardTypes, manufacturers: manufacturers)
      }
    }
  }

  private func openRecent(_ visit: RecentVisit) {
    remember(visit.kind, id: visit.itemID)
    switch visit.kind {
    case .project:
      selectedProject = projects.first { $0.id == visit.itemID }
    case .board:
      selectedBoardID = visit.itemID
    }
  }

  func sectionHeader(_ title: String, symbol: String, count: Int? = nil, accent: Color? = nil, action: @escaping () -> Void) -> some View {
    let tint = accent ?? theme.primary
    return HStack(spacing: 10) {
      Image(systemName: symbol)
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(tint)
        .frame(width: 30, height: 30)
        .background(tint.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
      Text(title)
        .font(.system(size: 22, weight: .heavy))
      if let count {
        Text(count > 3 ? "3+" : "\(count)")
          .font(.system(size: 12, weight: .heavy))
          .foregroundStyle(tint)
          .padding(.horizontal, 9)
          .padding(.vertical, 5)
          .background(tint.opacity(0.14))
          .clipShape(Capsule())
          .overlay(
            Capsule()
              .stroke(tint.opacity(0.18), lineWidth: 1)
          )
      }
      Spacer()
      Button(action: action) {
        Image(systemName: "arrow.right")
          .font(.system(size: 14, weight: .heavy))
          .foregroundStyle(tint)
          .frame(width: 34, height: 28)
          .background(tint.opacity(0.13))
          .clipShape(Capsule())
          .overlay(
            Capsule()
              .stroke(tint.opacity(0.18), lineWidth: 1)
          )
      }
      .buttonStyle(.plain)
    }
  }
}

enum DashboardSheet: String, Identifiable {
  case boardTypes
  case recentProjects
  case stats
  case companies
  case customers
  case newProject

  var id: String { rawValue }
}

struct ProjectsView: View {
  let theme: PanelTheme
  @Binding var projects: [ProjectItem]
  @Binding var boards: [BoardDraft]
  @Binding var archiveMode: ArchiveMode
  @Binding var archiveQuery: String
  @Binding var archiveBoardTypeFilter: String
  @Binding var archiveStatusFilter: String
  let boardTypes: [BoardType]
  let customers: [CustomerItem]
  let manufacturers: [ManufacturerItem]
  @Binding var selectedTab: PanelTab
  @Binding var newHubSelection: NewHubSelection?
  @Binding var pendingProjectOpenID: String?
  @Binding var recentVisits: [RecentVisit]
  @State private var newProjectOpen = false
  @State private var selectedProject: ProjectItem?
  @State private var selectedBoardID: String?

  private var statuses: [String] {
    archiveMode == .projects
      ? ["All", "In Progress", "Completed", "Design"]
      : ["All", "Design", "In Progress", "QA Ready", "QA Changes", "Finished"]
  }

  /// Projects carry the primary accent and boards the secondary one, matching
  /// the identity used on the dashboard so the color follows into this tab.
  private var modeAccent: Color {
    archiveMode == .projects ? theme.primary : theme.secondary
  }

  private var filteredProjects: [ProjectItem] {
    projects.filter { project in
      let statusMatches = archiveStatusFilter == "All" || projectStatus(project) == archiveStatusFilter
      return statusMatches && matchesArchive(projectArchiveText(project))
    }
    .sorted {
      let leftStatus = projectStatus($0)
      let rightStatus = projectStatus($1)
      if projectSortRank(leftStatus) != projectSortRank(rightStatus) {
        return projectSortRank(leftStatus) < projectSortRank(rightStatus)
      }
      if let dueSort = dueDateComesFirst($0.dueDate, $1.dueDate) { return dueSort }
      return $0.name < $1.name
    }
  }

  private var filteredBoardIDs: [String] {
    filteredBoardsForType.filter { board in
      let statusMatches = archiveStatusFilter == "All" || board.statusTitle == archiveStatusFilter
      return statusMatches && matchesArchive(board.searchText)
    }
    .sorted(by: boardPrioritySort)
    .map(\.id)
  }

  private var filteredBoardsForType: [BoardDraft] {
    boards.filter { board in
      archiveBoardTypeFilter == "All" || board.type == archiveBoardTypeFilter
    }
  }

  private var activeProjectCount: Int {
    projects.filter { projectStatus($0) == "In Progress" }.count
  }

  private var completedProjectCount: Int {
    projects.filter { projectStatus($0) == "Completed" }.count
  }

  private var activeBoardCount: Int {
    filteredBoardsForType.filter { !$0.isCompleted }.count
  }

  private var completedBoardCount: Int {
    filteredBoardsForType.filter(\.isCompleted).count
  }

  private var boardGroups: [String] {
    Array(Set(boards.filter { filteredBoardIDs.contains($0.id) }.map(\.group).filter { !$0.isEmpty }))
      .sorted {
        let leftPrefix = boardNumberPrefix($0)
        let rightPrefix = boardNumberPrefix($1)
        if leftPrefix != rightPrefix { return leftPrefix > rightPrefix }
        return $0 > $1
      }
  }

  private var uniqueCustomers: [String] {
    Array(Set(projects.map(\.customer).filter { !$0.isEmpty })).sorted()
  }

  private var ungroupedBoardIDs: [String] {
    filteredBoardIDs.filter { id in
      boards.first { $0.id == id }?.group.isEmpty == true
    }
  }

  private var inProgressFilteredBoardIDs: [String] {
    filteredBoardIDs.filter { id in
      boards.first { $0.id == id }?.isCompleted == false
    }
  }

  private var completedFilteredBoardIDs: [String] {
    filteredBoardIDs.filter { id in
      boards.first { $0.id == id }?.isCompleted == true
    }
  }

  private func boardIDs(in group: String) -> [String] {
    filteredBoardIDs.filter { id in
      boards.first { $0.id == id }?.group == group
    }
  }

  private func linkedBoards(for project: ProjectItem) -> [BoardDraft] {
    boards.filter { $0.project == project.name }
  }

  private func projectStatus(_ project: ProjectItem) -> String {
    let linked = linkedBoards(for: project)
    guard !linked.isEmpty else { return project.status }
    return linked.allSatisfy(\.isCompleted) ? "Completed" : "In Progress"
  }

  private func projectSortRank(_ status: String) -> Int {
    switch status {
    case "In Progress": return 0
    case "Design": return 1
    case "Completed": return 2
    default: return 3
    }
  }

  private func projectArchiveText(_ project: ProjectItem) -> String {
    let linked = linkedBoards(for: project)
    let boardText = linked.map(\.searchText).joined(separator: " ")
    return "\(project.searchText) \(projectStatus(project)) \(boardText)"
  }

  private func matchesArchive(_ text: String) -> Bool {
    let trimmedQuery = archiveQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedQuery.isEmpty || text.localizedCaseInsensitiveContains(trimmedQuery)
  }

  private func statusTitle(_ status: String) -> String {
    "\(status) \(statusCount(status))"
  }

  private func statusCount(_ status: String) -> Int {
    if status == "All" {
      return archiveMode == .projects ? projects.count : boards.count
    }
    if archiveMode == .projects {
      return projects.filter { projectStatus($0) == status }.count
    }
    return boards.filter { $0.statusTitle == status }.count
  }

  var body: some View {
    NavigationStack {
      ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: 20) {
          HStack(spacing: 12) {
            Image(systemName: archiveMode == .projects ? "folder" : "rectangle.3.group")
              .font(.system(size: 21, weight: .semibold))
              .foregroundStyle(modeAccent)
              .frame(width: 40, height: 40)
              .background(theme.surface.opacity(0.78))
              .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
              Text("Archive")
                .font(.system(size: 28, weight: .heavy))
              Text("Projects and boards")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            }
            Spacer()
          }

          Picker("Archive", selection: $archiveMode) {
            ForEach(ArchiveMode.allCases) { mode in
              Text(mode.title).tag(mode)
            }
          }
          .pickerStyle(.segmented)
          .tint(modeAccent)
          .animation(.easeOut(duration: 0.14), value: archiveMode)

          archiveSearchField

          if archiveMode == .boards {
            boardTypeFilterButton
          }

          LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            Button {
              archiveStatusFilter = "In Progress"
            } label: {
              ProjectMetricCard(theme: theme, title: archiveMode == .projects ? "Active" : "In Progress", value: "\(archiveMode == .projects ? activeProjectCount : activeBoardCount)", symbol: "clock.fill", color: Color(hex: 0x5E78FF))
            }
            .buttonStyle(.plain)

            Button {
              archiveStatusFilter = archiveMode == .projects ? "Completed" : "Finished"
            } label: {
              ProjectMetricCard(theme: theme, title: archiveMode == .projects ? "Completed" : "Finished", value: "\(archiveMode == .projects ? completedProjectCount : completedBoardCount)", symbol: "checkmark.circle.fill", color: Color(hex: 0x35E177))
            }
            .buttonStyle(.plain)

            Button {
              archiveMode = archiveMode == .projects ? .boards : .projects
              archiveStatusFilter = "All"
              archiveBoardTypeFilter = "All"
            } label: {
              ProjectMetricCard(theme: theme, title: archiveMode == .projects ? "Projects" : "Boards", value: "\(archiveMode == .projects ? projects.count : filteredBoardsForType.count)", symbol: archiveMode == .projects ? "folder.fill" : "rectangle.3.group.fill", color: modeAccent)
            }
            .buttonStyle(.plain)
          }

          HStack {
            Text("Status")
              .font(.headline)
            Spacer()
          }

          LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: statuses.count), spacing: 8) {
            ForEach(statuses, id: \.self) { status in
              SearchFilterChip(
                theme: theme,
                title: status,
                selected: archiveStatusFilter == status,
                fillsWidth: true
              ) {
                archiveStatusFilter = status
              }
            }
          }

          HStack {
            Button {
              archiveMode = archiveMode == .projects ? .boards : .projects
              archiveStatusFilter = "All"
              archiveBoardTypeFilter = "All"
            } label: {
              HStack(spacing: 9) {
                Text(archiveMode == .projects ? "Projects" : "Boards")
                  .font(.system(size: 22, weight: .heavy))
                Image(systemName: "arrow.left.arrow.right")
                  .font(.caption.bold())
                  .foregroundStyle(modeAccent)
              }
            }
            .buttonStyle(.plain)
            Spacer()
            if archiveMode == .projects {
            Button {
              // Its own page, presented here. This used to switch to the New
              // Board tab and rely on it rendering the project form, which put
              // people on the board hub when they asked for a project.
              newProjectOpen = true
            } label: {
              Label("New Project", systemImage: "plus")
                .font(.system(size: 13, weight: .bold))
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(modeAccent)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            }
          }

          VStack(spacing: archiveMode == .boards ? 16 : 10) {
            if archiveMode == .boards {
              if boards.isEmpty {
                EmptyStateCard(theme: theme, title: "No boards yet", subtitle: "Create a board from the New Board tab. Unattached boards will show here too.")
              } else if filteredBoardIDs.isEmpty {
                EmptyStateCard(theme: theme, title: "No boards here", subtitle: archiveQuery.isEmpty && archiveBoardTypeFilter == "All" ? "Switch the status filter to see another board stage." : "Clear the board filters or try another board type.")
              } else if archiveStatusFilter == "All" {
                groupedBoardSections
              } else {
                groupedBoardSections
              }
            } else {
            if filteredProjects.isEmpty {
              EmptyStateCard(theme: theme, title: projects.isEmpty ? "No projects yet" : "No projects here", subtitle: projects.isEmpty ? "Tap New Project to create your first project." : "Clear the Archive search or try another customer, board, or project name.")
            }
            ForEach(filteredProjects) { project in
              Button {
                remember(.project, id: project.id)
                selectedProject = project
              } label: {
                ProjectDashboardRow(
                  theme: theme,
                  project: project,
                  boardCount: linkedBoards(for: project).count,
                  displayedStatus: projectStatus(project)
                ) {
                  deleteProject(project)
                }
              }
              .buttonStyle(.plain)
            }
            }
          }
          .animation(.easeOut(duration: 0.14), value: archiveMode)
          .animation(.easeOut(duration: 0.14), value: archiveStatusFilter)
          BottomTabClearance()
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .overlay(alignment: .top) {
        TopScrollBlur(theme: theme)
      }
      .navigationTitle("")
      .navigationBarTitleDisplayMode(.inline)
      // Opening the created project has to wait for this sheet to be gone:
      // presenting the project page while this one is still up drops it.
      .sheet(isPresented: $newProjectOpen, onDismiss: {
        openPendingProject(pendingProjectOpenID)
      }) {
        NewProjectSheet(theme: theme, boards: $boards, customers: customers, projectCustomers: uniqueCustomers, onDone: {
          newProjectOpen = false
        }) { project in
          projects.insert(project, at: 0)
          pendingProjectOpenID = project.id
        }
          .presentationDetents([.large])
          .presentationDragIndicator(.visible)
      }
      .sheet(item: $selectedProject) { project in
        ProjectDetailSheet(theme: theme, project: project, boards: $boards, boardTypes: boardTypes, manufacturers: manufacturers) { board in
          remember(.board, id: board.id)
        } onUpdateProject: { updatedProject, previousName in
          if let index = projects.firstIndex(where: { $0.id == updatedProject.id }) {
            projects[index] = updatedProject
          }
          for index in boards.indices where boards[index].project == previousName {
            boards[index].project = updatedProject.name
          }
        } onDeleteProject: {
          deleteProject(project)
        }
          .presentationDetents([.large])
          .presentationDragIndicator(.visible)
      }
      .sheet(item: selectedBoardBinding) { boardSelection in
        NavigationStack {
          if let index = boards.firstIndex(where: { $0.id == boardSelection.id }) {
            CreatedBoardScreen(theme: theme, board: $boards[index], boardTypes: boardTypes, manufacturers: manufacturers, onDeleteBoard: {
              deleteBoard(boards[index])
              selectedBoardID = nil
            }) {
              selectedBoardID = nil
            }
          } else {
            EmptyStateCard(theme: theme, title: "Board no longer exists", subtitle: "It may have been deleted from Archive.")
              .padding(18)
              .background(theme.background.ignoresSafeArea())
          }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
      }
      .onChange(of: archiveMode) { _ in
        if !statuses.contains(archiveStatusFilter) {
          archiveStatusFilter = "All"
        }
        if archiveMode == .projects {
          archiveBoardTypeFilter = "All"
        }
      }
      .onChange(of: pendingProjectOpenID) { projectID in
        openPendingProject(projectID)
      }
      .onAppear {
        openPendingProject(pendingProjectOpenID)
      }
    }
  }

  private func openPendingProject(_ projectID: String?) {
    guard archiveMode == .projects,
          let projectID,
          let project = projects.first(where: { $0.id == projectID }) else { return }
    remember(.project, id: project.id)
    selectedProject = project
    pendingProjectOpenID = nil
  }

  private func deleteProject(_ project: ProjectItem) {
    projects.removeAll { $0.id == project.id }
    for index in boards.indices where boards[index].project == project.name {
      boards[index].project = "No Project"
    }
    ImageStore.shared.delete(project.imageTokens)
  }

  private func deleteBoard(_ board: BoardDraft) {
    boards.removeAll { $0.id == board.id }
    ImageStore.shared.delete(board.imageTokens)
  }

  private func remember(_ kind: RecentVisit.Kind, id: String) {
    recentVisits.removeAll { $0.kind == kind && $0.itemID == id }
    recentVisits.insert(RecentVisit(kind: kind, id: id), at: 0)
    recentVisits = Array(recentVisits.prefix(12))
  }

  private var archiveSearchField: some View {
    HStack(spacing: 10) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
      TextField(archiveMode == .projects ? "Search projects, customers, boards..." : "Search boards, type, ampere, project...", text: $archiveQuery)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
      if !archiveQuery.isEmpty {
        Button {
          archiveQuery = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
      }
    }
    .font(.system(size: 15, weight: .semibold))
    .padding(14)
    .background(theme.surface.opacity(0.78))
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(.white.opacity(0.07), lineWidth: 1)
    )
  }

  private var boardTypeFilterButton: some View {
    HStack(spacing: 10) {
      Menu {
        Button("All Board Types") {
          archiveBoardTypeFilter = "All"
        }
        ForEach(boardTypes) { type in
          Button(type.name) {
            archiveBoardTypeFilter = type.name
          }
        }
      } label: {
        HStack(spacing: 8) {
          Image(systemName: "slider.horizontal.3")
          Text(archiveBoardTypeFilter == "All" ? "All Board Types" : archiveBoardTypeFilter)
          Image(systemName: "chevron.down")
            .font(.caption.bold())
        }
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(archiveBoardTypeFilter == "All" ? .primary : theme.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background((archiveBoardTypeFilter == "All" ? theme.surface : theme.primary).opacity(archiveBoardTypeFilter == "All" ? 0.78 : 0.18))
        .clipShape(Capsule())
      }

      if archiveBoardTypeFilter != "All" {
        Button {
          archiveBoardTypeFilter = "All"
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
            .font(.system(size: 18, weight: .semibold))
        }
        .buttonStyle(.plain)
      }

      Spacer()
    }
  }

  private var groupedBoardSections: some View {
    VStack(alignment: .leading, spacing: 16) {
      if archiveStatusFilter == "All" {
        if !inProgressFilteredBoardIDs.isEmpty {
          BoardStageDivider(theme: theme, title: "In Progress", color: theme.primary)
          ForEach(activeBoardGroups, id: \.self) { group in
            boardGroupSection(title: group, ids: sortedInProgressBoardIDs(from: boardIDs(in: group)))
          }
          if !activeUngroupedBoardIDs.isEmpty {
            boardGroupSection(title: "Ungrouped", ids: activeUngroupedBoardIDs)
          }
        }
        if !completedFilteredBoardIDs.isEmpty {
          BoardStageDivider(theme: theme, title: "Finished", color: Color(hex: 0x35E177))
          ForEach(finishedBoardGroups, id: \.self) { group in
            boardGroupSection(title: group, ids: sortedFinishedBoardIDs(from: boardIDs(in: group)))
          }
          if !finishedUngroupedBoardIDs.isEmpty {
            boardGroupSection(title: "Ungrouped", ids: finishedUngroupedBoardIDs)
          }
        }
      } else {
        ForEach(boardGroups, id: \.self) { group in
          boardGroupSection(title: group, ids: boardIDs(in: group))
        }
        if !ungroupedBoardIDs.isEmpty {
          boardGroupSection(title: "Ungrouped", ids: ungroupedBoardIDs)
        }
      }
    }
  }

  private var activeBoardGroups: [String] {
    sortedGroups(for: inProgressFilteredBoardIDs)
  }

  private var finishedBoardGroups: [String] {
    sortedGroups(for: completedFilteredBoardIDs)
  }

  private var activeUngroupedBoardIDs: [String] {
    sortedInProgressBoardIDs(from: ungroupedBoardIDs)
  }

  private var finishedUngroupedBoardIDs: [String] {
    sortedFinishedBoardIDs(from: ungroupedBoardIDs)
  }

  private func sortedGroups(for ids: [String]) -> [String] {
    Array(Set(ids.compactMap { id in
      boards.first { $0.id == id }?.group
    }.filter { !$0.isEmpty }))
    .sorted {
      let leftPrefix = boardNumberPrefix($0)
      let rightPrefix = boardNumberPrefix($1)
      if leftPrefix != rightPrefix { return leftPrefix > rightPrefix }
      return $0 > $1
    }
  }

  private func boardGroupSection(title: String, ids: [String]) -> some View {
    let inProgressIDs = sortedInProgressBoardIDs(from: ids)
    let finishedIDs = sortedFinishedBoardIDs(from: ids)

    return VStack(alignment: .leading, spacing: 12) {
      ArchiveSectionDivider(theme: theme, title: title, prominent: true)
      if !inProgressIDs.isEmpty {
        boardRows(for: inProgressIDs)
      }
      if !inProgressIDs.isEmpty && !finishedIDs.isEmpty {
        Rectangle()
          .fill(
            LinearGradient(
              colors: [.clear, theme.primary.opacity(0.22), .clear],
              startPoint: .leading,
              endPoint: .trailing
            )
          )
          .frame(height: 1)
          .padding(.vertical, 2)
      }
      if !finishedIDs.isEmpty {
        boardRows(for: finishedIDs)
      }
    }
  }

  private func boardRows(for ids: [String]) -> some View {
    ForEach(ids, id: \.self) { boardID in
      if let index = boards.firstIndex(where: { $0.id == boardID }) {
        BoardGalleryRow(theme: theme, board: $boards[index], projects: projects, boardTypes: boardTypes, manufacturers: manufacturers) {
          remember(.board, id: boards[index].id)
          selectedBoardID = boards[index].id
        } onDelete: {
          deleteBoard(boards[index])
        }
      }
    }
  }

  private func sortedInProgressBoardIDs(from ids: [String]) -> [String] {
    ids
      .compactMap { id in boards.first { $0.id == id } }
      .filter { !$0.isCompleted }
      .sorted(by: activeBoardPrioritySort)
      .map(\.id)
  }

  private func sortedFinishedBoardIDs(from ids: [String]) -> [String] {
    ids
      .compactMap { id in boards.first { $0.id == id } }
      .filter(\.isCompleted)
      .sorted {
        let leftPrefix = boardNumberPrefix($0.number)
        let rightPrefix = boardNumberPrefix($1.number)
        if leftPrefix != rightPrefix { return leftPrefix > rightPrefix }
        if $0.number != $1.number { return $0.number > $1.number }
        return $0.name < $1.name
      }
      .map(\.id)
  }

  private func boardNumberPrefix(_ number: String) -> Int {
    let digits = number.prefix { $0.isNumber }.prefix(4)
    return Int(digits) ?? 0
  }

  private func boardStatusSection(title: String, ids: [String]) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      if !title.isEmpty {
        ArchiveSectionDivider(theme: theme, title: title, prominent: true)
      }
      ForEach(ids, id: \.self) { boardID in
        if let index = boards.firstIndex(where: { $0.id == boardID }) {
          BoardGalleryRow(theme: theme, board: $boards[index], projects: projects, boardTypes: boardTypes, manufacturers: manufacturers) {
            remember(.board, id: boards[index].id)
            selectedBoardID = boards[index].id
          } onDelete: {
            deleteBoard(boards[index])
          }
        }
      }
    }
  }

  private var selectedBoardBinding: Binding<RecentBoardSelection?> {
    Binding {
      selectedBoardID.map(RecentBoardSelection.init(id:))
    } set: { selection in
      selectedBoardID = selection?.id
    }
  }
}

struct ArchiveSectionDivider: View {
  let theme: PanelTheme
  let title: String
  var prominent = false

  var body: some View {
    HStack(spacing: 10) {
      Rectangle()
        .fill(.white.opacity(prominent ? 0.16 : 0.10))
        .frame(height: prominent ? 2 : 1)
      Text(title)
        .font(.system(size: prominent ? 24 : 12, weight: .heavy))
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .minimumScaleFactor(0.78)
      Rectangle()
        .fill(.white.opacity(prominent ? 0.16 : 0.10))
        .frame(height: prominent ? 2 : 1)
    }
    .padding(.vertical, prominent ? 8 : 4)
  }
}

struct BoardStageDivider: View {
  let theme: PanelTheme
  let title: String
  let color: Color

  var body: some View {
    HStack(spacing: 10) {
      Capsule()
        .fill(
          LinearGradient(
            colors: [color.opacity(0.26), color],
            startPoint: .leading,
            endPoint: .trailing
          )
        )
        .frame(height: 5)
      Text(title)
        .font(.system(size: 13, weight: .heavy))
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.14))
        .clipShape(Capsule())
    }
    .padding(.top, 2)
  }
}

enum ArchiveMode: String, CaseIterable, Identifiable {
  case projects
  case boards

  var id: String { rawValue }

  var title: String {
    switch self {
    case .projects: "Projects"
    case .boards: "Boards"
    }
  }
}

struct ProjectMetricCard: View {
  let theme: PanelTheme
  let title: String
  let value: String
  let symbol: String
  let color: Color

  var body: some View {
    GlassCard(theme: theme) {
      VStack(alignment: .leading, spacing: 8) {
        Image(systemName: symbol)
          .font(.system(size: 19, weight: .bold))
          .foregroundStyle(color)
        Text(value)
          .font(.system(size: 24, weight: .heavy))
          .foregroundStyle(color)
          .lineLimit(1)
          .minimumScaleFactor(0.65)
        Text(title)
          .font(.system(size: 11, weight: .bold))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.65)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(height: 86)
    }
  }
}

struct BoardGalleryRow: View {
  let theme: PanelTheme
  @Binding var board: BoardDraft
  let projects: [ProjectItem]
  let boardTypes: [BoardType]
  let manufacturers: [ManufacturerItem]
  var onOpen: () -> Void = {}
  let onDelete: () -> Void

  private var boardType: BoardType {
    boardTypes.first { $0.name == board.type } ?? .fallback
  }

  private var manufacturer: ManufacturerItem? {
    syncedManufacturer(named: board.manufacturer, in: manufacturers)
  }

  var body: some View {
    GlassCard(theme: theme) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 12) {
          BoardCardThumbnail(theme: theme, boardType: boardType, color: board.color, image: board.coverThumbnail, completed: board.isCompleted)

          VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
              Text(board.name)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
              if let dueDate = board.dueDate {
                DueDateBadge(date: dueDate, compact: true)
              }
            }
            Text(board.number)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .minimumScaleFactor(0.7)
            Text("Out \(DateDisplay.short.string(from: board.dateOut))")
              .font(.caption2.bold())
              .foregroundStyle(board.color)
            if let finishDate = board.finishDate {
              Text("Finished \(DateDisplay.short.string(from: finishDate))")
                .font(.caption2.bold())
                .foregroundStyle(Color(hex: 0x35E177))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
          }

          Spacer()

          VStack(alignment: .trailing, spacing: 6) {
            BoardProgressStatusBadge(board: board)
            DeleteIconButton(theme: theme, action: onDelete)
          }
        }

        HStack {
          Text("\(board.manufacturer) • \(board.displayType) • \(board.ampere) • \(board.cabinetCount) cabinets • \(board.buildFormat)" + (board.group.isEmpty ? "" : " • Group \(board.group)"))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
          Spacer()
        }

        Picker("Project", selection: $board.project) {
          Text("No Project").tag("No Project")
          ForEach(projects.map(\.name), id: \.self) { Text($0).tag($0) }
        }
        .pickerStyle(.menu)

        Button {
          onOpen()
        } label: {
          Label("Open Board", systemImage: "arrow.right.circle.fill")
            .font(.caption.bold())
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(board.color)
      }
    }
    .background(board.color.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(board.color.opacity(0.26), lineWidth: 1)
    )
    .shadow(color: board.color.opacity(0.10), radius: 14, y: 5)
  }
}

struct ProjectDashboardRow: View {
  let theme: PanelTheme
  let project: ProjectItem
  var boardCount: Int? = nil
  var displayedStatus: String? = nil
  var onDelete: (() -> Void)? = nil
  var glow = false

  private var detailText: String {
    let cleanedDetail = project.detail.replacingOccurrences(
      of: #"^\d+ boards?( • )?"#,
      with: "",
      options: .regularExpression
    )
    let boardText = boardCount.map { "\($0) board\($0 == 1 ? "" : "s")" }
    return [boardText, cleanedDetail.isEmpty ? nil : cleanedDetail]
      .compactMap { $0 }
      .joined(separator: " • ")
  }

  private var statusText: String {
    displayedStatus ?? project.status
  }

  var body: some View {
    GlassCard(theme: theme) {
      HStack(spacing: 12) {
        ZStack {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(project.color.gradient)
          if let image = project.coverThumbnail {
            Image(uiImage: image)
              .resizable()
              .scaledToFill()
              .frame(width: 48, height: 48)
              .clipped()
          } else {
            Image(systemName: "building.2.crop.circle.fill")
              .font(.title3)
              .foregroundStyle(.white)
          }
        }
        .frame(width: 58, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

        VStack(alignment: .leading, spacing: 5) {
          HStack(spacing: 6) {
            Text(project.name)
              .font(.system(size: 17, weight: .heavy))
              .lineLimit(1)
              .minimumScaleFactor(0.65)
            if let dueDate = project.dueDate {
              DueDateBadge(date: dueDate, compact: true)
            }
            StatusBadge(status: statusText)
              .scaleEffect(0.86)
          }
          Text(project.customer)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.primary.opacity(0.86))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
          Text(detailText)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }

        Spacer()

        HStack(spacing: 6) {
          if let onDelete {
            DeleteIconButton(theme: theme, action: onDelete)
          }
          Image(systemName: "chevron.right")
            .foregroundStyle(.secondary)
        }
      }
    }
    .background(project.color.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(project.color.opacity(0.28), lineWidth: 1)
    )
    .shadow(color: project.color.opacity(glow ? 0.28 : 0.14), radius: glow ? 22 : 15, x: 0, y: glow ? 9 : 5)
  }
}

struct DashboardProjectRecentRow: View {
  let theme: PanelTheme
  let project: ProjectItem
  let boardCount: Int
  let displayedStatus: String

  private var cleanedDetail: String {
    project.detail.replacingOccurrences(
      of: #"^\d+ boards?( • )?"#,
      with: "",
      options: .regularExpression
    )
  }

  var body: some View {
    GlassCard(theme: theme) {
      HStack(spacing: 12) {
        ZStack {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(project.color.gradient)
          if let image = project.coverThumbnail {
            Image(uiImage: image)
              .resizable()
              .scaledToFill()
              .frame(width: 48, height: 48)
              .clipped()
          } else {
            Image(systemName: "folder.fill")
              .font(.title3)
              .foregroundStyle(.white)
          }
        }
        .frame(width: 58, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

        VStack(alignment: .leading, spacing: 5) {
          HStack(spacing: 7) {
            RecentKindBadge(title: "Project", color: theme.primary)
            RecentStatusBadge(status: displayedStatus)
          }

          HStack(spacing: 6) {
            Text(project.name)
              .font(.system(size: 17, weight: .heavy))
              .lineLimit(1)
              .minimumScaleFactor(0.65)
            if let dueDate = project.dueDate {
              DueDateBadge(date: dueDate, compact: true)
            }
          }
          Text("\(project.customer) • \(boardCount) board\(boardCount == 1 ? "" : "s")")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
          if !cleanedDetail.isEmpty {
            Text(cleanedDetail)
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(.secondary.opacity(0.82))
              .lineLimit(1)
              .minimumScaleFactor(0.7)
          }
        }

        Spacer()
        Image(systemName: "chevron.right")
          .foregroundStyle(.secondary)
      }
    }
    .background(project.color.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(project.color.opacity(0.28), lineWidth: 1)
    )
  }
}

struct DashboardBoardProgressRow: View {
  let theme: PanelTheme
  let board: BoardDraft
  let boardTypes: [BoardType]
  let manufacturers: [ManufacturerItem]

  private var boardType: BoardType {
    boardTypes.first { $0.name == board.type } ?? .fallback
  }

  private var manufacturer: ManufacturerItem? {
    syncedManufacturer(named: board.manufacturer, in: manufacturers)
  }

  private var progress: CGFloat {
    min(max(CGFloat(board.completion) / 100, 0), 1)
  }

  private var progressColor: Color {
    let value = min(max(Double(board.completion) / 100, 0), 1)
    let red = 1.0 - (value * 0.78)
    let green = 0.22 + (value * 0.66)
    let blue = 0.20 + (value * 0.08)
    return Color(red: red, green: green, blue: blue)
  }

  private var glowOpacity: Double {
    0.10 + (Double(progress) * 0.42)
  }

  private var glowRadius: CGFloat {
    8 + (progress * 20)
  }

  var body: some View {
    GlassCard(theme: theme) {
      VStack(alignment: .leading, spacing: 9) {
        HStack(spacing: 12) {
          BoardCardThumbnail(theme: theme, boardType: boardType, color: board.color, image: board.coverThumbnail, completed: board.isCompleted)

          VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 6) {
            Text(board.name)
              .font(.system(size: 17, weight: .heavy))
              .lineLimit(1)
              .minimumScaleFactor(0.65)
            if let dueDate = board.dueDate {
              DueDateBadge(date: dueDate, compact: true)
            }
            Spacer(minLength: 5)
            Text("\(board.completion)%")
              .font(.system(size: 17, weight: .black))
              .foregroundStyle(progressColor)
              .monospacedDigit()
            Image(systemName: "chevron.right")
              .font(.system(size: 13, weight: .bold))
              .foregroundStyle(.secondary)
          }
          HStack(spacing: 5) {
            RecentBoardInfoChip(symbol: "number", text: board.number, color: board.color)
            RecentBoardInfoChip(symbol: "bolt.fill", text: board.ampere, color: theme.secondary)
            RecentManufacturerChip(manufacturer: manufacturer, fallbackName: board.manufacturer)
          }
          .fixedSize(horizontal: false, vertical: true)
          GeometryReader { proxy in
            ZStack(alignment: .leading) {
              Capsule()
                .fill(theme.surface.opacity(0.82))
              Capsule()
                .fill(
                  LinearGradient(
                    colors: [progressColor.opacity(0.70), progressColor],
                    startPoint: .leading,
                    endPoint: .trailing
                  )
                )
                .frame(width: max(proxy.size.width * progress, progress > 0 ? 12 : 0))
                .shadow(color: progressColor.opacity(0.28), radius: 5, y: 1)
                .animation(.easeInOut(duration: 0.38), value: board.completion)
            }
          }
          .frame(height: 7)
          }
        }
      }
      .frame(minHeight: 82)
    }
    .background(progressColor.opacity(0.06 + Double(progress) * 0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(progressColor.opacity(0.18 + Double(progress) * 0.18), lineWidth: 1)
    )
    .shadow(color: progressColor.opacity(glowOpacity), radius: glowRadius, y: 8)
    .shadow(color: progressColor.opacity(0.10 + Double(progress) * 0.14), radius: 5, y: 2)
  }
}

struct BoardCardThumbnail: View {
  let theme: PanelTheme
  let boardType: BoardType
  let color: Color
  let image: UIImage?
  let completed: Bool

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(
          LinearGradient(
            colors: [color.opacity(0.30), theme.surface.opacity(0.92)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )

      if let image {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
          .frame(width: 48, height: 48)
          .clipped()
      } else {
        BoardTypeIcon(board: boardType, size: 28, overrideColor: color)
      }
    }
      .frame(width: 48, height: 48)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay(alignment: .bottomTrailing) {
        if completed || image == nil {
          Image(systemName: completed ? "checkmark.circle.fill" : "camera.fill")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(completed ? Color(hex: 0x35E177) : color)
            .padding(5)
        }
      }
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(.white.opacity(0.08), lineWidth: 1)
      )
  }
}

struct BoardTypeIcon: View {
  let board: BoardType
  let size: CGFloat
  var overrideColor: Color? = nil

  private var iconColor: Color {
    overrideColor ?? board.color
  }

  var body: some View {
    ZStack {
      Circle()
        .fill(iconColor.opacity(0.16))
      if let emoji = board.emoji, !emoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Text(emoji)
          .font(.system(size: size * 0.48, weight: .bold))
          .lineLimit(1)
          .minimumScaleFactor(0.5)
      } else {
        Image(systemName: board.symbol)
          .font(.system(size: size * 0.48, weight: .bold))
          .foregroundStyle(iconColor)
      }
    }
    .frame(width: size, height: size)
  }
}

struct DashboardBoardRecentRow: View {
  let theme: PanelTheme
  let board: BoardDraft
  let boardTypes: [BoardType]
  let manufacturers: [ManufacturerItem]

  private var boardType: BoardType {
    boardTypes.first { $0.name == board.type } ?? .fallback
  }

  private var manufacturer: ManufacturerItem? {
    syncedManufacturer(named: board.manufacturer, in: manufacturers)
  }

  var body: some View {
    GlassCard(theme: theme) {
      VStack(alignment: .leading, spacing: 9) {
        HStack(spacing: 7) {
          RecentKindBadge(title: "Board", color: theme.secondary)
          RecentStatusBadge(status: board.statusTitle)
          Spacer(minLength: 10)
        }

        HStack(spacing: 12) {
          BoardCardThumbnail(theme: theme, boardType: boardType, color: board.color, image: board.coverThumbnail, completed: board.isCompleted)
          VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
              Text(board.name)
                .font(.system(size: 17, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
              Spacer(minLength: 5)
              Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
            }
            HStack(spacing: 5) {
              RecentBoardInfoChip(symbol: "number", text: board.number, color: board.color)
              RecentBoardInfoChip(symbol: "bolt.fill", text: board.ampere, color: theme.secondary)
              RecentManufacturerChip(manufacturer: manufacturer, fallbackName: board.manufacturer)
            }
            .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    }
    .background(board.color.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(board.color.opacity(0.24), lineWidth: 1)
    )
    .shadow(color: board.color.opacity(0.22), radius: 18, y: 7)
  }
}

struct RecentBoardTypeChip: View {
  let boardType: BoardType
  let color: Color

  var body: some View {
    HStack(spacing: 5) {
      BoardTypeIcon(board: boardType, size: 18, overrideColor: color)
      Text(boardType.name)
        .font(.system(size: 11, weight: .black))
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
    .foregroundStyle(color)
    .padding(.horizontal, 7)
    .padding(.vertical, 5)
    .background(color.opacity(0.13))
    .clipShape(Capsule())
    .overlay(Capsule().stroke(color.opacity(0.24), lineWidth: 1))
  }
}

struct RecentBoardInfoChip: View {
  let symbol: String
  let text: String
  let color: Color

  var body: some View {
    HStack(spacing: 5) {
      Image(systemName: symbol)
        .font(.system(size: 10, weight: .black))
      Text(text.isEmpty ? "-" : text)
        .font(.system(size: 11, weight: .black))
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
    .foregroundStyle(color)
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background(color.opacity(0.12))
    .clipShape(Capsule())
    .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 1))
  }
}

struct RecentManufacturerChip: View {
  let manufacturer: ManufacturerItem?
  let fallbackName: String

  private var color: Color {
    manufacturer?.color ?? Color(hex: 0xAEB4BC)
  }

  private var name: String {
    let trimmed = fallbackName.trimmingCharacters(in: .whitespacesAndNewlines)
    return manufacturer?.name ?? (trimmed.isEmpty ? "Manufacturer" : trimmed)
  }

  var body: some View {
    ManufacturerMarkView(manufacturer: manufacturer, fallbackName: name, size: 22)
    .padding(.horizontal, 5)
    .padding(.vertical, 3)
    .background(color.opacity(0.13))
    .clipShape(Capsule())
    .overlay(Capsule().stroke(color.opacity(0.24), lineWidth: 1))
    .accessibilityLabel(name)
  }
}

struct RecentKindBadge: View {
  let title: String
  let color: Color

  var body: some View {
    Text(title)
      .font(.system(size: 10, weight: .heavy))
      .foregroundStyle(color)
      .lineLimit(1)
      .padding(.horizontal, 9)
      .frame(height: 21)
      .background(color.opacity(0.16))
      .clipShape(Capsule())
  }
}

struct RecentStatusBadge: View {
  let status: String

  private var color: Color {
    switch status {
    case "Design":
      return Color(hex: 0xD85CFF)
    case "In Progress", "Active":
      return Color(hex: 0x2F8CFF)
    case "QA Ready":
      return Color(hex: 0x8B4DFF)
    case "QA Changes":
      return Color.red
    case "Completed", "Done", "Finished":
      return Color(hex: 0x35E177)
    default:
      return Color(hex: 0x8B4DFF)
    }
  }

  var body: some View {
    Text(status)
      .font(.system(size: 10, weight: .heavy))
      .foregroundStyle(color)
      .lineLimit(1)
      .padding(.horizontal, 9)
      .frame(height: 21)
      .background(color.opacity(0.18))
      .clipShape(Capsule())
  }
}

struct DeleteIconButton: View {
  let theme: PanelTheme
  let action: () -> Void
  @State private var confirmingDelete = false

  var body: some View {
    Menu {
      Button(role: .destructive) {
        confirmingDelete = true
      } label: {
        Label("Delete", systemImage: "trash")
      }
    } label: {
      Image(systemName: "ellipsis")
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(.secondary)
        .frame(width: 30, height: 30)
        .background(theme.surface.opacity(0.85))
        .clipShape(Circle())
    }
    .buttonStyle(.plain)
    .confirmationDialog("Delete this item?", isPresented: $confirmingDelete, titleVisibility: .visible) {
      Button("Delete", role: .destructive, action: action)
      Button("Cancel", role: .cancel) {}
    }
  }
}

struct DeleteRecordButton: View {
  let title: String
  let itemName: String
  let action: () -> Void
  @State private var confirmingDelete = false

  var body: some View {
    Button(role: .destructive) {
      confirmingDelete = true
    } label: {
      Label(title, systemImage: "trash.fill")
        .font(.system(size: 16, weight: .bold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .foregroundStyle(Color(hex: 0xFF6B6B))
        .background(Color(hex: 0xD94B4B).opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color(hex: 0xFF6B6B).opacity(0.32), lineWidth: 1)
        )
    }
    .buttonStyle(PanelPressButtonStyle())
    .confirmationDialog("Delete \(itemName)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
      Button(title, role: .destructive, action: action)
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This action cannot be undone.")
    }
  }
}

struct AccentChoice: Identifiable {
  let id: UInt32
  let name: String

  var color: Color {
    Color(hex: id)
  }
}

enum AccentPalette {
  static let choices = [
    AccentChoice(id: 0x5E78FF, name: "Blue"),
    AccentChoice(id: 0x64D2FF, name: "Sky"),
    AccentChoice(id: 0x35E177, name: "Green"),
    AccentChoice(id: 0x7FAE9A, name: "Sage"),
    AccentChoice(id: 0x00C7BE, name: "Teal"),
    AccentChoice(id: 0xD85CFF, name: "Violet"),
    AccentChoice(id: 0xBF5AF2, name: "Purple"),
    AccentChoice(id: 0xFF9F0A, name: "Amber"),
    AccentChoice(id: 0xFFD60A, name: "Gold"),
    AccentChoice(id: 0xFF4E5F, name: "Red"),
    AccentChoice(id: 0xFF6B35, name: "Orange"),
    AccentChoice(id: 0xAEB4BC, name: "Titanium")
  ]
}

struct ColorSwatchPicker: View {
  let title: String
  @Binding var selectedHex: UInt32
  @State private var customColor = Color(hex: 0x5E78FF)

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.caption.bold())
        .foregroundStyle(.secondary)

      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
        ForEach(AccentPalette.choices) { choice in
          Button {
            selectedHex = choice.id
          } label: {
            Circle()
              .fill(choice.color.gradient)
              .frame(width: 30, height: 30)
              .overlay {
                if selectedHex == choice.id {
                  Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.white)
                }
              }
              .overlay(
                Circle()
                  .stroke(selectedHex == choice.id ? .white.opacity(0.88) : .white.opacity(0.16), lineWidth: selectedHex == choice.id ? 2 : 1)
              )
              .accessibilityLabel(choice.name)
          }
          .buttonStyle(.plain)
        }
      }

      ColorPicker("Custom color", selection: $customColor, supportsOpacity: false)
        .font(.caption.bold())
        .onChange(of: customColor) { newColor in
          if let hex = Self.hexValue(from: newColor) {
            selectedHex = hex
          }
        }
    }
    .onAppear {
      customColor = Color(hex: selectedHex)
    }
  }

  private static func hexValue(from color: Color) -> UInt32? {
    let uiColor = UIColor(color)
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
    return (UInt32(red * 255) << 16) | (UInt32(green * 255) << 8) | UInt32(blue * 255)
  }
}

struct StatusBadge: View {
  let status: String

  private var color: Color {
    switch status {
    case "Design":
      return Color(hex: 0xD85CFF)
    case "In Progress", "Active":
      return Color(hex: 0x2F8CFF)
    case "QA Ready":
      return Color(hex: 0x8B4DFF)
    case "QA Changes":
      return Color.red
    case "Completed", "Done", "Finished":
      return Color(hex: 0x35E177)
    default:
      return Color(hex: 0x8B4DFF)
    }
  }

  var body: some View {
    Text(status)
      .font(.caption.bold())
      .foregroundStyle(color)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(color.opacity(0.22))
      .clipShape(Capsule())
      .shadow(color: color.opacity(0.34), radius: 10, y: 2)
  }
}

struct BoardProgressStatusBadge: View {
  let board: BoardDraft

  var body: some View {
    StatusBadge(status: board.statusTitle)
  }
}

struct PanelPressButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.992 : 1)
      .opacity(configuration.isPressed ? 0.97 : 1)
      .shadow(color: .black.opacity(configuration.isPressed ? 0.08 : 0.12), radius: configuration.isPressed ? 2 : 4, y: configuration.isPressed ? 1 : 2)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

struct PanelToggleStyle: ToggleStyle {
  let theme: PanelTheme

  func makeBody(configuration: Configuration) -> some View {
    Button {
      withAnimation(.easeOut(duration: 0.16)) {
        configuration.isOn.toggle()
      }
    } label: {
      HStack {
        configuration.label
        Spacer()
        ZStack(alignment: configuration.isOn ? .trailing : .leading) {
          Capsule()
            .fill(configuration.isOn ? theme.primary.opacity(0.95) : Color.primary.opacity(0.16))
            .frame(width: 50, height: 30)
          Circle()
            .fill(.white)
            .frame(width: 24, height: 24)
            .padding(3)
            .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(PanelPressButtonStyle())
  }
}

struct ProjectDetailSheet: View {
  let theme: PanelTheme
  let project: ProjectItem
  @Binding var boards: [BoardDraft]
  let boardTypes: [BoardType]
  let manufacturers: [ManufacturerItem]
  var onVisitBoard: (BoardDraft) -> Void = { _ in }
  var onUpdateProject: ((ProjectItem, String) -> Void)? = nil
  var onDeleteProject: (() -> Void)? = nil
  @Environment(\.dismiss) private var dismiss
  @State private var selectedBoard: BoardDraft?
  @State private var projectName: String
  @State private var lastSavedName: String
  @State private var customer: String
  @State private var detail: String
  @State private var projectColor: Color
  @State private var coverImage: UIImage?
  @State private var projectPhotoTokens: [String] = []
  @State private var projectSchemes: [SchemeAttachment]
  @State private var hasDueDate: Bool
  @State private var dueDate: Date
  @State private var editOpen = false
  @State private var attachBoardsOpen = false

  init(
    theme: PanelTheme,
    project: ProjectItem,
    boards: Binding<[BoardDraft]>,
    boardTypes: [BoardType],
    manufacturers: [ManufacturerItem],
    onVisitBoard: @escaping (BoardDraft) -> Void = { _ in },
    onUpdateProject: ((ProjectItem, String) -> Void)? = nil,
    onDeleteProject: (() -> Void)? = nil
  ) {
    self.theme = theme
    self.project = project
    self._boards = boards
    self.boardTypes = boardTypes
    self.manufacturers = manufacturers
    self.onVisitBoard = onVisitBoard
    self.onUpdateProject = onUpdateProject
    self.onDeleteProject = onDeleteProject
    _projectName = State(initialValue: project.name)
    _lastSavedName = State(initialValue: project.name)
    _customer = State(initialValue: project.customer)
    _detail = State(initialValue: project.detail)
    _projectColor = State(initialValue: project.color)
    _coverImage = State(initialValue: project.coverImage)
    _projectPhotoTokens = State(initialValue: project.photoTokens)
    _projectSchemes = State(initialValue: project.schemeAttachments)
    _hasDueDate = State(initialValue: project.dueDate != nil)
    _dueDate = State(initialValue: project.dueDate ?? Date())
  }

  private var linkedBoards: [BoardDraft] {
    boards
      .filter { $0.project == projectName }
      .sorted(by: boardPrioritySort)
  }

  private var projectDetailWithoutBoardCount: String {
    detail.replacingOccurrences(
      of: #"^\d+ boards?( • )?"#,
      with: "",
      options: .regularExpression
    )
  }

  private var projectStatus: String {
    guard !linkedBoards.isEmpty else { return project.status }
    return linkedBoards.allSatisfy(\.isCompleted) ? "Completed" : "In Progress"
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          ProjectCoverPhotoSection(theme: theme, selectedImage: $coverImage) {
            saveProjectChanges()
          }

          GlassCard(theme: theme) {
            VStack(alignment: .leading, spacing: 10) {
              Label("Project Properties", systemImage: "folder.fill")
                .font(.headline)
                .foregroundStyle(projectColor)

              VStack(alignment: .leading, spacing: 4) {
                Text(projectName)
                  .font(.title2.bold())
                  .lineLimit(2)
                  .minimumScaleFactor(0.72)
                Text(customer.isEmpty ? "No customer selected" : customer)
                  .font(.subheadline.weight(.semibold))
                  .foregroundStyle(.secondary)
                  .lineLimit(2)
                  .minimumScaleFactor(0.72)
              }

              ProjectPropertiesOverview(
                theme: theme,
                color: projectColor,
                boardCount: linkedBoards.count,
                status: projectStatus,
                customer: customer,
                detail: projectDetailWithoutBoardCount,
                dueDate: hasDueDate ? dueDate : nil
              )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }

          SchemeAttachmentSection(theme: theme, title: "Project PDFs & Schemes", attachments: $projectSchemes)
            .onChange(of: projectSchemes) { _ in
              saveProjectChanges()
            }

          HStack {
            Text("Boards")
              .font(.headline)
            Spacer()
            Button {
              attachBoardsOpen = true
            } label: {
              Label("Attach", systemImage: "plus.circle.fill")
                .font(.caption.bold())
            }
            .buttonStyle(.borderedProminent)
            .tint(projectColor)
          }

          if linkedBoards.isEmpty {
            EmptyStateCard(theme: theme, title: "No boards attached", subtitle: "Tap Attach to add boards to this project.")
          }

          ForEach(linkedBoards) { board in
            Button {
              onVisitBoard(board)
              selectedBoard = board
            } label: {
              GlassCard(theme: theme) {
                HStack {
                  let boardType = boardTypes.first { $0.name == board.type } ?? .fallback
                  BoardTypeIcon(board: boardType, size: 36, overrideColor: board.color)
                  VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                      Text(board.name).font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                      if let dueDate = board.dueDate {
                        DueDateBadge(date: dueDate, compact: true)
                      }
                    }
                    Text("\(board.number) • \(board.type) • Out \(DateDisplay.short.string(from: board.dateOut))").font(.caption).foregroundStyle(.secondary)
                      .lineLimit(1)
                      .minimumScaleFactor(0.7)
                  }
                  Spacer()
                  StatusBadge(status: board.statusTitle)
                  Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
              }
            }
            .buttonStyle(.plain)
          }

          PhotoPickerSection(theme: theme, title: "Project Photos", photoTokens: $projectPhotoTokens, coverImage: $coverImage)
            .onChange(of: projectPhotoTokens) { _ in
              saveProjectChanges()
            }
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .overlay(alignment: .top) {
        TopScrollBlur(theme: theme)
      }
      .navigationTitle(projectName)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Edit") {
            withAnimation(.easeInOut(duration: 0.24)) {
              editOpen = true
            }
          }
          .fontWeight(.bold)
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
      .sheet(item: $selectedBoard) { board in
        NavigationStack {
          if let index = boards.firstIndex(where: { $0.id == board.id }) {
            CreatedBoardScreen(theme: theme, board: $boards[index], boardTypes: boardTypes, manufacturers: manufacturers, onDeleteBoard: {
              boards.removeAll { $0.id == board.id }
              selectedBoard = nil
            }) {
              selectedBoard = nil
            }
          } else {
            EmptyStateCard(theme: theme, title: "Board no longer exists", subtitle: "It may have been deleted from Archive.")
              .padding(18)
              .background(theme.background.ignoresSafeArea())
          }
        }
      }
      .sheet(isPresented: $attachBoardsOpen) {
        BoardAttachPickerSheet(theme: theme, projectName: projectName, projectCustomer: customer, boards: $boards)
          .presentationDetents([.large])
          .presentationDragIndicator(.visible)
      }
      .sheet(isPresented: $editOpen) {
        ProjectEditSheet(
          theme: theme,
          projectName: $projectName,
          customer: $customer,
          detail: $detail,
          hasDueDate: $hasDueDate,
          dueDate: $dueDate,
          onSave: saveProjectChanges,
          onDelete: onDeleteProject.map { deleteProject in
            {
              deleteProject()
              dismiss()
            }
          }
        )
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
      }
    }
  }

  private func saveProjectChanges() {
    let trimmedName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else { return }
    let previousName = lastSavedName
    onUpdateProject?(
      ProjectItem(
        id: project.id,
        name: trimmedName,
        customer: customer.trimmingCharacters(in: .whitespacesAndNewlines),
        detail: detail.trimmingCharacters(in: .whitespacesAndNewlines),
        status: project.status,
        color: projectColor,
        dueDate: hasDueDate ? dueDate : nil,
        schemeAttachments: projectSchemes,
        coverToken: ImageStore.shared.store(coverImage),
        photoTokens: projectPhotoTokens
      ),
      previousName
    )
    lastSavedName = trimmedName
  }
}

struct ProjectPropertiesOverview: View {
  let theme: PanelTheme
  let color: Color
  let boardCount: Int
  let status: String
  let customer: String
  let detail: String
  let dueDate: Date?

  private var boardText: String {
    if boardCount == 0 { return "No boards attached" }
    return "\(boardCount) board\(boardCount == 1 ? "" : "s")"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
        ProjectPropertyPill(symbol: "person.crop.circle.fill", title: "Customer", value: customer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No customer" : customer, color: color)
        ProjectPropertyPill(symbol: "rectangle.3.group.fill", title: "Boards", value: boardText, color: color)
        ProjectPropertyPill(symbol: "checkmark.seal.fill", title: "Status", value: status, color: statusColor)
        if let dueDate {
          DueDatePropertyPill(date: dueDate)
        }
      }

      let cleanedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
      if !cleanedDetail.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          Text("Notes")
            .font(.caption.bold())
            .foregroundStyle(.secondary)
          Text(cleanedDetail)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(4)
            .minimumScaleFactor(0.72)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface.opacity(0.46))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      }
    }
  }

  private var statusColor: Color {
    switch status {
    case "Completed", "Finished":
      return Color(hex: 0x35E177)
    case "Design":
      return Color(hex: 0xFF4FD8)
    default:
      return Color(hex: 0x64D2FF)
    }
  }
}

struct ProjectPropertyPill: View {
  let symbol: String
  let title: String
  let value: String
  let color: Color

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: symbol)
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(color)
        .frame(width: 28, height: 28)
        .background(color.opacity(0.14))
        .clipShape(Circle())
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.caption2.bold())
          .foregroundStyle(.secondary)
        Text(value)
          .font(.caption.bold())
          .lineLimit(2)
          .minimumScaleFactor(0.7)
      }
      Spacer(minLength: 0)
    }
    .padding(10)
    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
    .background(color.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(color.opacity(0.13), lineWidth: 1)
    )
  }
}

struct ManufacturerInlineMark: View {
  let manufacturer: ManufacturerItem?
  let fallbackName: String

  private var name: String {
    manufacturer?.name ?? fallbackName
  }

  private var color: Color {
    manufacturer?.color ?? Color(hex: 0xAEB4BC)
  }

  var body: some View {
    HStack(spacing: 5) {
      ManufacturerMarkView(manufacturer: manufacturer, fallbackName: fallbackName, size: 18)
      Text(name)
        .font(.caption2.bold())
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
    .foregroundStyle(color)
    .padding(.horizontal, 7)
    .padding(.vertical, 4)
    .background(color.opacity(0.13))
    .clipShape(Capsule())
    .overlay(
      Capsule()
        .stroke(color.opacity(0.22), lineWidth: 1)
    )
  }
}

struct ManufacturerPropertyPill: View {
  let manufacturer: ManufacturerItem?
  let fallbackName: String

  private var name: String {
    manufacturer?.name ?? fallbackName
  }

  private var color: Color {
    manufacturer?.color ?? Color(hex: 0xAEB4BC)
  }

  var body: some View {
    HStack(spacing: 8) {
      ManufacturerMarkView(manufacturer: manufacturer, fallbackName: fallbackName, size: 30)
      VStack(alignment: .leading, spacing: 2) {
        Text("Manufacturer")
          .font(.caption2.bold())
          .foregroundStyle(.secondary)
        Text(name)
          .font(.caption.bold())
          .lineLimit(2)
          .minimumScaleFactor(0.7)
      }
      Spacer(minLength: 0)
    }
    .padding(10)
    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
    .background(color.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(color.opacity(0.13), lineWidth: 1)
    )
  }
}

struct DueDateBadge: View {
  let date: Date
  var compact = false

  private var color: Color {
    dueUrgencyColor(for: date)
  }

  var body: some View {
    HStack(spacing: 5) {
      Image(systemName: "clock.badge.exclamationmark.fill")
        .font(.system(size: compact ? 9 : 11, weight: .black))
      Text(DateDisplay.due.string(from: date))
        .font(.system(size: compact ? 10 : 12, weight: .black))
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
    .foregroundStyle(color)
    .padding(.horizontal, compact ? 8 : 10)
    .padding(.vertical, compact ? 4 : 6)
    .background(color.opacity(0.16))
    .clipShape(Capsule())
    .overlay(
      Capsule()
        .stroke(color.opacity(0.34), lineWidth: 1)
    )
    .shadow(color: color.opacity(0.22), radius: compact ? 4 : 7, y: 1)
    .fixedSize(horizontal: true, vertical: false)
    .layoutPriority(2)
  }
}

struct DueDatePropertyPill: View {
  let date: Date

  private var color: Color {
    dueUrgencyColor(for: date)
  }

  var body: some View {
    ProjectPropertyPill(
      symbol: "clock.badge.exclamationmark.fill",
      title: "Due",
      value: DateDisplay.due.string(from: date),
      color: color
    )
    .shadow(color: color.opacity(0.24), radius: 10, y: 2)
  }
}

struct AddablePropertyPill: View {
  let title: String
  let value: String
  let isEmpty: Bool
  let isEnabled: Bool
  let action: () -> Void

  private var color: Color {
    if !isEnabled && isEmpty { return Color.gray.opacity(0.46) }
    return isEmpty ? Color(hex: 0x64D2FF) : Color(hex: 0x64D2FF)
  }

  var body: some View {
    Button(action: action) {
      ProjectPropertyPill(
        symbol: isEmpty ? "plus" : "timer",
        title: title,
        value: isEmpty ? (isEnabled ? "Add time" : "Complete checklist first") : value,
        color: color
      )
    }
    .buttonStyle(PanelPressButtonStyle())
    .disabled(!isEnabled && isEmpty)
    .opacity(!isEnabled && isEmpty ? 0.68 : 1)
  }
}

struct FinishStatusPropertyPill: View {
  let board: BoardDraft
  let action: () -> Void

  private var value: String {
    let finishDate = board.finishDate.map { DateDisplay.short.string(from: $0) }
    let finishTime = board.finishTimeHours.trimmingCharacters(in: .whitespacesAndNewlines)

    if !board.isCompleted {
      return "Complete checklist first"
    }
    if let finishDate, !finishTime.isEmpty {
      return "\(finishDate) • \(finishTime) h"
    }
    if let finishDate {
      return "\(finishDate) • Add time"
    }
    return finishTime.isEmpty ? "Add finish time" : "\(finishTime) h"
  }

  private var color: Color {
    board.isCompleted ? Color(hex: 0x35E177) : Color.gray.opacity(0.46)
  }

  var body: some View {
    Button(action: action) {
      ProjectPropertyPill(
        symbol: board.isCompleted ? "checkmark.circle.fill" : "lock.fill",
        title: "Finished",
        value: value,
        color: color
      )
    }
    .buttonStyle(PanelPressButtonStyle())
    .disabled(!board.isCompleted)
    .opacity(board.isCompleted ? 1 : 0.68)
  }
}

struct BoardPropertiesOverview: View {
  let theme: PanelTheme
  let board: BoardDraft
  let manufacturers: [ManufacturerItem]
  let onEditFinishTime: () -> Void

  private var manufacturer: ManufacturerItem? {
    syncedManufacturer(named: board.manufacturer, in: manufacturers)
  }

  var body: some View {
    GlassCard(theme: theme) {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Label("Board Properties", systemImage: "rectangle.3.group.fill")
            .font(.headline)
          Spacer()
          BoardProgressStatusBadge(board: board)
        }

        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
          ProjectPropertyPill(symbol: "person.crop.circle.fill", title: "Customer", value: board.customer.isEmpty ? "No customer" : board.customer, color: board.color)
          if !board.company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ProjectPropertyPill(symbol: "building.2.fill", title: "Company", value: board.company, color: board.color)
          }
          ProjectPropertyPill(symbol: "folder.fill", title: "Project", value: board.project.isEmpty ? "No Project" : board.project, color: board.color)
          ProjectPropertyPill(symbol: "hammer.fill", title: "Builder", value: board.assignedName.isEmpty ? "Unassigned" : board.assignedName, color: board.color)
          ProjectPropertyPill(symbol: "checkmark.shield.fill", title: "QA Reviewer", value: board.qaAssignedName.isEmpty ? "Unassigned" : board.qaAssignedName, color: theme.secondary)
          ProjectPropertyPill(symbol: "square.grid.2x2.fill", title: "Type", value: board.type, color: board.color)
          if BoardSubtypeCatalog.isVisible(board.subtype) {
            ProjectPropertyPill(symbol: "rectangle.grid.1x2.fill", title: "Subtype", value: board.subtype, color: board.color)
          }
          ManufacturerPropertyPill(manufacturer: manufacturer, fallbackName: board.manufacturer)
          ProjectPropertyPill(symbol: "bolt.fill", title: "Ampere", value: board.ampere, color: board.color)
          ProjectPropertyPill(symbol: "rectangle.split.3x1.fill", title: "Cabinets", value: "\(board.cabinetCount) • \(board.buildFormat)", color: board.color)
          ProjectPropertyPill(symbol: "calendar", title: "Out Date", value: DateDisplay.short.string(from: board.dateOut), color: board.color)
          if let dueDate = board.dueDate {
            DueDatePropertyPill(date: dueDate)
          }
          FinishStatusPropertyPill(board: board, action: onEditFinishTime)
          ProjectPropertyPill(symbol: "bolt.shield.fill", title: "Breaker Type", value: board.mainBreakerType, color: board.color)
          ProjectPropertyPill(symbol: "tag.fill", title: "Breaker", value: board.mainBreakerLabel.isEmpty ? board.mainBreakerModel : board.mainBreakerLabel, color: board.color)
          if !board.group.isEmpty {
            ProjectPropertyPill(symbol: "rectangle.stack.fill", title: "Group", value: board.group, color: board.color)
          }
        }
      }
    }
  }
}

struct ProjectEditSheet: View {
  let theme: PanelTheme
  @Binding var projectName: String
  @Binding var customer: String
  @Binding var detail: String
  @Binding var hasDueDate: Bool
  @Binding var dueDate: Date
  let onSave: () -> Void
  var onDelete: (() -> Void)? = nil
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          CreationFormSection(theme: theme, title: "Project Details", symbol: "folder.fill", subtitle: "Identity and customer") {
            CreationTextInput(theme: theme, title: "Project name", placeholder: "Project name", symbol: "folder.fill", text: $projectName, capitalization: .words)
            CreationTextInput(theme: theme, title: "Customer", placeholder: "Customer", symbol: "person.crop.circle.fill", text: $customer, capitalization: .words)
            CreationTextInput(theme: theme, title: "Project detail", placeholder: "Site or notes", symbol: "mappin.and.ellipse", text: $detail, capitalization: .words)
          }

          CreationFormSection(theme: theme, title: "Schedule", symbol: "calendar.badge.clock") {
            CreationToggleInput(theme: theme, title: "Expected finish date", symbol: "clock.badge.exclamationmark.fill", isOn: $hasDueDate)
            if hasDueDate {
              CreationDateInput(theme: theme, title: "Due", symbol: "calendar.badge.clock", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
            }
          }

          if let onDelete {
            DeleteRecordButton(title: "Delete Project", itemName: projectName, action: onDelete)
              .padding(.top, 8)
          }
          BottomTabClearance(height: 72)
        }
        .padding(18)
      }
      .scrollDismissesKeyboard(.interactively)
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Edit Project")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") {
            onSave()
            dismiss()
          }
          .fontWeight(.bold)
        }
      }
      .onDisappear {
        onSave()
      }
    }
  }
}

struct BoardTypesSheet: View {
  let theme: PanelTheme
  let boardTypes: [BoardType]
  @Environment(\.dismiss) private var dismiss
  @State private var selectedBoardType: BoardType?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 10) {
          ForEach(boardTypes) { board in
            Button {
              selectedBoardType = board
            } label: {
              GlassCard(theme: theme) {
                HStack(spacing: 12) {
                  BoardTypeIcon(board: board, size: 42)
                  VStack(alignment: .leading, spacing: 4) {
                    Text(board.name)
                      .font(.headline)
                      .lineLimit(2)
                      .minimumScaleFactor(0.75)
                    Text([board.localName, board.subtitle].compactMap { $0 }.joined(separator: " • "))
                      .font(.caption)
                      .foregroundStyle(.secondary)
                      .lineLimit(2)
                      .minimumScaleFactor(0.75)
                  }
                  Spacer()
                  Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
              }
            }
            .buttonStyle(.plain)
          }
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Board Types")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
      .sheet(item: $selectedBoardType) { board in
        BoardTypeDetailSheet(theme: theme, board: board)
      }
    }
  }
}

struct BoardTypeDetailSheet: View {
  let theme: PanelTheme
  let board: BoardType
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          HStack(spacing: 14) {
            BoardTypeIcon(board: board, size: 70)
            VStack(alignment: .leading, spacing: 5) {
              Text(board.name)
                .font(.largeTitle.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.72)
              if let localName = board.localName {
                Text(localName)
                  .font(.headline)
                  .foregroundStyle(board.color)
              }
              Text(board.subtitle)
                .foregroundStyle(.secondary)
            }
          }

          BoardReferenceSection(theme: theme, title: "Description", symbol: "text.alignleft", color: board.color) {
            Text(board.overview ?? "\(board.name) is a custom board type. Add notes, photos and schemes to each board record to document how this category is used in your projects.")
              .font(.body)
              .foregroundStyle(.primary.opacity(0.9))
              .fixedSize(horizontal: false, vertical: true)
          }

          BoardReferenceSection(theme: theme, title: "Typical Uses", symbol: "building.2.fill", color: board.color) {
            BoardBulletList(items: board.typicalUses.isEmpty ? ["Project-specific use", "Custom distribution or control category"] : board.typicalUses)
          }

          BoardReferenceSection(theme: theme, title: "Common Equipment", symbol: "shippingbox.fill", color: board.color) {
            BoardBulletList(items: board.typicalComponents.isEmpty ? ["Main switch or breaker", "Protection devices", "Terminals", "Labels and documentation"] : board.typicalComponents)
          }

          BoardReferenceSection(theme: theme, title: "Checks Before Build", symbol: "checklist.checked", color: board.color) {
            BoardBulletList(items: board.designChecks.isEmpty ? ["Rated current", "Short-circuit rating", "IP rating", "Cable entry space", "Labeling"] : board.designChecks)
          }

          if !board.notes.isEmpty {
            BoardReferenceSection(theme: theme, title: "Israel Notes", symbol: "mappin.and.ellipse", color: board.color) {
              BoardBulletList(items: board.notes)
            }
          }

          BoardReferenceSection(theme: theme, title: "Default Units", symbol: "ruler.fill", color: board.color) {
            BoardBulletList(items: ["Current: A", "Fault level: kA", "Cable and copper dimensions: mm, cm, m", "Motor and PV power: kW / kVAr where relevant"])
          }
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle(board.name)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
    }
  }
}

struct BoardReferenceSection<Content: View>: View {
  let theme: PanelTheme
  let title: String
  let symbol: String
  let color: Color
  @ViewBuilder let content: Content

  var body: some View {
    GlassCard(theme: theme) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 8) {
          Image(systemName: symbol)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(color)
          Text(title)
            .font(.headline)
        }
        content
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

struct BoardBulletList: View {
  let items: [String]

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      ForEach(items, id: \.self) { item in
        HStack(alignment: .top, spacing: 8) {
          Circle()
            .fill(.secondary)
            .frame(width: 5, height: 5)
            .padding(.top, 7)
          Text(item)
            .font(.subheadline)
            .foregroundStyle(.primary.opacity(0.9))
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }
}

struct ProjectsListSheet: View {
  let theme: PanelTheme
  @Binding var projects: [ProjectItem]
  @Binding var boards: [BoardDraft]
  let boardTypes: [BoardType]
  let manufacturers: [ManufacturerItem]
  @Environment(\.dismiss) private var dismiss
  @State private var selectedProject: ProjectItem?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 10) {
          if projects.isEmpty {
            EmptyStateCard(theme: theme, title: "No projects yet", subtitle: "Create your first project from the Projects tab.")
          }
          ForEach(projects) { project in
            Button {
              selectedProject = project
            } label: {
              ProjectDashboardRow(theme: theme, project: project)
            }
            .buttonStyle(.plain)
          }
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Recent Projects")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
      .sheet(item: $selectedProject) { project in
        ProjectDetailSheet(theme: theme, project: project, boards: $boards, boardTypes: boardTypes, manufacturers: manufacturers) { _ in
        } onUpdateProject: { updatedProject, previousName in
          if let index = projects.firstIndex(where: { $0.id == updatedProject.id }) {
            projects[index] = updatedProject
          }
          for index in boards.indices where boards[index].project == previousName {
            boards[index].project = updatedProject.name
          }
        } onDeleteProject: {
          projects.removeAll { $0.id == project.id }
          for index in boards.indices where boards[index].project == project.name {
            boards[index].project = "No Project"
          }
          selectedProject = nil
        }
      }
    }
  }
}

struct DashboardStatsSheet: View {
  let theme: PanelTheme
  let projects: [ProjectItem]
  let boardCount: Int
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      VStack(spacing: 12) {
        ProjectMetricCard(theme: theme, title: "Projects", value: "\(projects.count)", symbol: "folder.fill", color: theme.primary)
        ProjectMetricCard(theme: theme, title: "Boards", value: "\(boardCount)", symbol: "rectangle.3.group.fill", color: Color(hex: 0xAEB4BC))
        ProjectMetricCard(theme: theme, title: "Customers", value: "\(Set(projects.map(\.customer)).count)", symbol: "person.2.fill", color: Color(hex: 0x7D8791))
        Spacer()
      }
      .padding(18)
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Statistics")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
    }
  }
}

struct ViewAllInlineButton: View {
  let theme: PanelTheme
  let title: String
  let action: () -> Void

  var body: some View {
    HStack {
      Spacer()
      Button(action: action) {
        HStack(spacing: 7) {
          Text(title)
          Image(systemName: "arrow.up.right")
            .font(.system(size: 11, weight: .black))
        }
        .font(.system(size: 13, weight: .heavy))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(
          LinearGradient(
            colors: [theme.primary.opacity(0.92), theme.secondary.opacity(0.82)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
      }
        .clipShape(Capsule())
        .overlay(
          Capsule()
            .stroke(.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: theme.primary.opacity(0.24), radius: 12, y: 4)
      .buttonStyle(PanelPressButtonStyle())
      Spacer()
    }
    .padding(.top, 2)
  }
}

struct EmptyStateCard: View {
  let theme: PanelTheme
  let title: String
  let subtitle: String

  var body: some View {
    GlassCard(theme: theme) {
      VStack(spacing: 8) {
        Image(systemName: "tray")
          .font(.title2)
          .foregroundStyle(.secondary)
        Text(title)
          .font(.headline)
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 8)
    }
  }
}

enum NewHubSelection {
  case project
  case board
}

struct NewHubView: View {
  let theme: PanelTheme
  @Binding var projects: [ProjectItem]
  @Binding var boards: [BoardDraft]
  let customers: [CustomerItem]
  let companies: [ContractorCompany]
  let manufacturers: [ManufacturerItem]
  let boardTypes: [BoardType]
  @Binding var selection: NewHubSelection?
  let onCreateBoard: (BoardDraft) -> Void
  let onUpdateBoard: (BoardDraft) -> Void
  let onCreateProject: (ProjectItem) -> Void

  private var projectCustomers: [String] {
    Array(Set(projects.map(\.customer).filter { !$0.isEmpty })).sorted()
  }

  var body: some View {
    Group {
      switch selection {
      case .board:
        NewBoardView(
          theme: theme,
          projects: projects,
          customers: customers,
          companies: companies,
          manufacturers: manufacturers,
          boardTypes: boardTypes,
          onCreate: onCreateBoard,
          onUpdate: onUpdateBoard,
          onBackToHub: {
            withAnimation(.easeOut(duration: 0.16)) {
              selection = nil
            }
          }
        )
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
      case .project:
        NewProjectSheet(theme: theme, boards: $boards, customers: customers, projectCustomers: projectCustomers, onDone: {
          selection = nil
        }) { project in
          onCreateProject(project)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
      case nil:
        NavigationStack {
          ScrollView {
            VStack(alignment: .leading, spacing: 16) {
              Text("New")
                .font(.largeTitle.bold())
              Text("Create a project or start a board.")
                .foregroundStyle(.secondary)

              Button {
                selection = .project
              } label: {
                NewBoardModeCard(
                  theme: theme,
                  symbol: "folder.badge.plus",
                  title: "New Project",
                  subtitle: "Create the customer/project container first, then attach boards.",
                  color: Color(hex: 0x35E177)
                )
              }
              .buttonStyle(PanelPressButtonStyle())

              Button {
                selection = .board
              } label: {
                NewBoardModeCard(
                  theme: theme,
                  symbol: "rectangle.3.group.fill",
                  title: "New Board",
                  subtitle: "Scan a scheme with AI or enter the board manually.",
                  color: Color(hex: 0x5E78FF)
                )
              }
              .buttonStyle(PanelPressButtonStyle())
              BottomTabClearance()
            }
            .padding(18)
          }
          .background(theme.background.ignoresSafeArea())
        }
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
      }
    }
    .animation(.easeOut(duration: 0.16), value: selection)
  }
}

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

enum NewBoardPickerSheet: String, Identifiable {
  case boardType
  case subtype
  case manufacturer
  case project

  var id: String { rawValue }
}

struct NewBoardView: View {
  let theme: PanelTheme
  let projects: [ProjectItem]
  let customers: [CustomerItem]
  let companies: [ContractorCompany]
  let manufacturers: [ManufacturerItem]
  let boardTypes: [BoardType]
  let onCreate: (BoardDraft) -> Void
  let onUpdate: (BoardDraft) -> Void
  var onBackToHub: (() -> Void)? = nil
  @State private var boardNumber = ""
  @State private var boardGroup = ""
  @State private var boardName = ""
  @State private var customerName = ""
  @State private var companyName = ""
  @State private var project = "No Project"
  @State private var boardType = BoardType.samples.first?.name ?? "MDB"
  @State private var boardSubtype = BoardSubtypeCatalog.defaultSubtype
  @State private var boardManufacturer = ManufacturerItem.defaults.first?.name ?? "Generic"
  @State private var cabinetCount = "1"
  @State private var buildFormat = "Panels"
  @State private var boardDate = Date()
  @State private var hasDueDate = false
  @State private var boardDueDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
  @State private var hasFinishDate = false
  @State private var boardFinishDate = Date()
  @State private var mainBreakerType = "Main Breaker"
  @State private var mainBreakerModel = ManufacturerItem.defaults.first?.name ?? "ABB"
  @State private var mainBreakerAmpere = "630A"
  @State private var createdBoard: BoardDraft?
  @State private var mainBreakerOpen = false
  @State private var createdMessage = false
  @State private var entryMode: NewBoardEntryMode?
  @State private var pendingSchemeAttachments: [SchemeAttachment] = []
  /// What the AI read off the scheme, kept so the draft can show its source
  /// and so the matched parts can be put on the board once it is created.
  @State private var schemeReading: BoardSchemeReading?
  @State private var pickerSheet: NewBoardPickerSheet?

  private var canCreate: Bool {
    !boardNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !boardName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !customerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var recentCustomers: [String] {
    Array(Set(projects.map(\.customer) + customers.map(\.name))).filter { !$0.isEmpty }.sorted()
  }

  private var matchingRecentCustomers: [String] {
    let query = customerName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return recentCustomers }
    return recentCustomers.filter { $0.localizedCaseInsensitiveContains(query) }
  }

  private var companyNames: [String] {
    Array(Set(companies.map(\.name).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })).sorted()
  }

  private var matchingCompanyNames: [String] {
    let query = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return companyNames }
    return companyNames.filter { $0.localizedCaseInsensitiveContains(query) }
  }

  private var subtypeOptions: [String] {
    BoardSubtypeCatalog.options(for: boardType)
  }

  private var manufacturerNames: [String] {
    let names = manufacturers.map(\.name) + ManufacturerItem.defaults.map(\.name)
    return Array(Set(names.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })).sorted()
  }

  private var suggestedGroup: String {
    guard let dashIndex = boardNumber.lastIndex(of: "-") else { return "" }
    return String(boardNumber[..<dashIndex])
  }

  private var assignedCustomerColor: Color {
    if let customer = customers.first(where: {
      $0.name.localizedCaseInsensitiveCompare(customerName) == .orderedSame
    }) {
      return customer.color
    }
    if let selectedProject = projects.first(where: { $0.name == project }) {
      return selectedProject.color
    }
    return theme.primary
  }

  var body: some View {
    NavigationStack {
      if let createdBoard {
        CreatedBoardScreen(
          theme: theme,
          board: Binding(
            get: { createdBoard },
            set: {
              self.createdBoard = $0
              onUpdate($0)
            }
          ),
          boardTypes: boardTypes,
          manufacturers: manufacturers,
          showsCreationFlow: true
        ) {
          self.createdBoard = nil
          entryMode = nil
          pendingSchemeAttachments = []
          schemeReading = nil
        }
      } else if entryMode == nil {
        // The scheme comes first. The drawing is what the board is, so it is
        // read before the form rather than being one card inside it.
        NewBoardSchemeIntakeView(theme: theme, back: onBackToHub) { reading in
          if let reading { apply(reading) }
          withAnimation(.easeOut(duration: 0.16)) {
            entryMode = reading == nil ? .manual : .aiScan
          }
        } onAttach: { attachment in
          pendingSchemeAttachments.append(attachment)
        }
      } else {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          if let schemeReading {
            SchemeReadingReviewCard(
              theme: theme,
              reading: schemeReading,
              rescan: {
                withAnimation(.easeOut(duration: 0.16)) {
                  self.schemeReading = nil
                  entryMode = nil
                }
              }
            )
          }

          CreationFormSection(theme: theme, title: "Progress", symbol: "point.3.connected.trianglepath.dotted") {
          NewBoardStepIndicator(theme: theme, currentStep: 1)
              .frame(height: 72)
          }

          if createdMessage {
            Label("Board draft created", systemImage: "checkmark.circle.fill")
              .font(.callout.bold())
              .foregroundStyle(Color(hex: 0x7FAE9A))
              .padding(12)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(Color(hex: 0x7FAE9A).opacity(0.12))
              .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
          }

          CreationFormSection(theme: theme, title: "Board Identity", symbol: "rectangle.3.group.fill", subtitle: "Number, name and type") {
            CreationTextInput(theme: theme, title: "Board number", placeholder: "3918.24-1", symbol: "number", text: $boardNumber, keyboardType: .numbersAndPunctuation, capitalization: .characters)
            CreationTextInput(theme: theme, title: "Board group", placeholder: suggestedGroup.isEmpty ? "Optional group" : suggestedGroup, symbol: "rectangle.stack.fill", text: $boardGroup, keyboardType: .numbersAndPunctuation, capitalization: .characters)
          if !suggestedGroup.isEmpty && boardGroup != suggestedGroup {
              Button {
                boardGroup = suggestedGroup
              } label: {
                Label("Use group \(suggestedGroup)", systemImage: "wand.and.stars")
                  .font(.caption.bold())
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
              .buttonStyle(.plain)
              .foregroundStyle(theme.primary)
            }
            CreationTextInput(theme: theme, title: "Board name", placeholder: "Main LV Board", symbol: "textformat", text: $boardName, capitalization: .words)
            CreationPickerInput(theme: theme, title: "Board type", symbol: "square.grid.2x2.fill", value: boardType) {
              pickerSheet = .boardType
            }
            CreationPickerInput(theme: theme, title: "Subtype", symbol: "rectangle.grid.1x2.fill", value: boardSubtype) {
              pickerSheet = .subtype
            }
            ManufacturerPickerInput(theme: theme, title: "Board manufacturer", value: boardManufacturer, manufacturers: manufacturers) {
              pickerSheet = .manufacturer
            }
            HStack(spacing: 10) {
              CreationMenuInput(theme: theme, title: "Cabinets", symbol: "cabinet.fill", value: cabinetCount, options: (1...12).map(String.init), selection: $cabinetCount)
              CreationMenuInput(theme: theme, title: "Build", symbol: "rectangle.split.2x1.fill", value: buildFormat, options: ["Panels", "Plate"], selection: $buildFormat)
            }
            CreationDateInput(theme: theme, title: "Out date", symbol: "calendar", selection: $boardDate, displayedComponents: .date)
            CreationToggleInput(theme: theme, title: "Add due date/time", symbol: "clock.badge.exclamationmark.fill", isOn: $hasDueDate)
            if hasDueDate {
              CreationDateInput(theme: theme, title: "Due", symbol: "clock.fill", selection: $boardDueDate, displayedComponents: [.date, .hourAndMinute])
            }
            CreationToggleInput(theme: theme, title: "Add finished date", symbol: "flag.checkered", isOn: $hasFinishDate)
            if hasFinishDate {
              CreationDateInput(theme: theme, title: "Finished date", symbol: "checkmark.seal.fill", selection: $boardFinishDate, displayedComponents: .date)
            }
          }

          CreationFormSection(theme: theme, title: "Project & Customer", symbol: "folder.badge.person.crop") {
            CreationPickerInput(theme: theme, title: "Project", symbol: "folder.fill", value: project) {
              pickerSheet = .project
            }
            if project == "No Project" {
              CreationTextInput(theme: theme, title: "Customer name", placeholder: "Search or type customer", symbol: "person.crop.circle.fill", text: $customerName, capitalization: .words)
            } else {
              InfoLine(title: "Customer", value: customerName.isEmpty ? "From selected project" : customerName)
                .padding(12)
                .background(theme.surface.opacity(0.56))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            SuggestionChips(theme: theme, values: matchingRecentCustomers, selectedValue: customerName) { customerName = $0 }
          }

          CreationFormSection(theme: theme, title: "Company", symbol: "building.2.crop.circle") {
            CreationTextInput(theme: theme, title: "Company you are doing it for", placeholder: "Optional company", symbol: "building.2.fill", text: $companyName, capitalization: .words)
            SuggestionChips(theme: theme, values: matchingCompanyNames, selectedValue: companyName) { companyName = $0 }
          }
          BottomTabClearance(height: 118)
            }
      }
      .padding(18)
      .scrollDismissesKeyboard(.interactively)
      .background(theme.background.ignoresSafeArea())
      .ignoresSafeArea(.keyboard, edges: .bottom)
      .navigationTitle("New Board")
      .sheet(item: $pickerSheet) { sheet in
        switch sheet {
        case .boardType:
          BoardTypeCreationPickerSheet(theme: theme, boardTypes: boardTypes, selected: boardType) { selected in
            boardType = selected
            if !BoardSubtypeCatalog.options(for: selected).contains(boardSubtype) {
              boardSubtype = BoardSubtypeCatalog.defaultSubtype
            }
          }
        case .subtype:
          CreationOptionPickerSheet(theme: theme, title: "Subtype", symbol: "rectangle.grid.1x2.fill", options: subtypeOptions, selected: boardSubtype) {
            boardSubtype = $0
          }
        case .manufacturer:
          ManufacturerCreationPickerSheet(theme: theme, manufacturers: manufacturers, selected: boardManufacturer) {
            boardManufacturer = $0
          }
        case .project:
          ProjectCreationPickerSheet(theme: theme, projects: projects, selected: project) { selected in
            project = selected
            if let selectedProject = projects.first(where: { $0.name == selected }) {
              customerName = selectedProject.customer
            } else if selected == "No Project" {
              customerName = ""
            }
          }
        }
      }
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Back") {
            if entryMode == nil {
              onBackToHub?()
            } else {
              // Back from the draft returns to the scheme step, not out of
              // board creation entirely.
              entryMode = nil
              pendingSchemeAttachments = []
              schemeReading = nil
            }
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Next") {
            mainBreakerOpen = true
          }
          .disabled(!canCreate)
          .fontWeight(.bold)
        }
      }
      .navigationDestination(isPresented: $mainBreakerOpen) {
        MainBreakerStepView(
          theme: theme,
          actionColor: assignedCustomerColor,
          mainBreakerType: $mainBreakerType,
          mainBreakerModel: $mainBreakerModel,
          mainBreakerAmpere: $mainBreakerAmpere,
          manufacturerNames: manufacturerNames,
          manufacturers: manufacturers
        ) {
              let normalizedAmpere = mainBreakerAmpere.uppercased().hasSuffix("A") ? mainBreakerAmpere : "\(mainBreakerAmpere)A"
              let board = BoardDraft(
                id: "board-\(UUID().uuidString)",
                number: boardNumber,
                group: boardGroup,
                name: boardName,
                customer: customerName,
                company: companyName.trimmingCharacters(in: .whitespacesAndNewlines),
                project: project,
                type: boardType,
                subtype: boardSubtype,
                manufacturer: boardManufacturer,
                ampere: normalizedAmpere,
                cabinetCount: cabinetCount,
                buildFormat: buildFormat,
                dateOut: boardDate,
                dueDate: hasDueDate ? boardDueDate : nil,
                finishDate: hasFinishDate ? boardFinishDate : nil,
                mainBreakerType: mainBreakerType,
                mainBreakerModel: mainBreakerModel.trimmingCharacters(in: .whitespacesAndNewlines),
                mainBreakerAmpere: normalizedAmpere,
                componentTypes: inferredComponentTypes(),
                color: assignedCustomerColor,
                schemeAttachments: pendingSchemeAttachments
              )
              onCreate(board)
              mainBreakerOpen = false
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                createdBoard = board
              }
              boardNumber = ""
              boardGroup = ""
              boardName = ""
              customerName = ""
              companyName = ""
              project = "No Project"
              boardType = boardTypes.first?.name ?? "MDB"
              boardSubtype = BoardSubtypeCatalog.defaultSubtype
              boardManufacturer = manufacturerNames.first ?? "Generic"
              cabinetCount = "1"
              buildFormat = "Panels"
              boardDate = Date()
              hasDueDate = false
              boardDueDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
              hasFinishDate = false
              boardFinishDate = Date()
              mainBreakerType = "Main Breaker"
              mainBreakerModel = manufacturerNames.first ?? "ABB"
              mainBreakerAmpere = "630A"
              pendingSchemeAttachments = []
              schemeReading = nil
              createdMessage = true
          }
      }
      .onChange(of: boardNumber) { _ in
        if boardGroup.isEmpty {
          boardGroup = suggestedGroup
        }
        createdMessage = false
      }
      .onChange(of: boardName) { _ in
        createdMessage = false
      }
      .onChange(of: customerName) { _ in
        createdMessage = false
      }
      .onChange(of: companyName) { _ in
        createdMessage = false
      }
      .onChange(of: boardType) { _ in
        if !subtypeOptions.contains(boardSubtype) {
          boardSubtype = subtypeOptions.first ?? BoardSubtypeCatalog.defaultSubtype
        }
        createdMessage = false
      }
      .onChange(of: project) { newProject in
        if let selectedProject = projects.first(where: { $0.name == newProject }) {
          customerName = selectedProject.customer
        } else if newProject == "No Project" {
          customerName = ""
        }
      }
      }
    }
    .animation(.easeOut(duration: 0.16), value: entryMode)
    .animation(.easeOut(duration: 0.16), value: createdBoard?.id)
  }

  /// The component types the scheme actually listed.
  ///
  /// Only types behind a part the catalog matched — an unplaced line is not
  /// evidence the board has that type of device on it, and this list drives
  /// what the workshop is told to build.
  private func inferredComponentTypes() -> [String] {
    guard let schemeReading else { return [] }
    var seen: Set<String> = []
    return schemeReading.components
      .map(\.type)
      .filter { !$0.isEmpty && seen.insert($0).inserted }
      .sorted()
  }

  /// Fill the draft from what the AI read off the scheme.
  ///
  /// Only empty fields are written, and only from values the drawing actually
  /// carried — a field the reading left blank stays as the form's default
  /// rather than being overwritten with an empty string. The reading is a
  /// starting point for review, not an authority.
  private func apply(_ reading: BoardSchemeReading) {
    schemeReading = reading
    let board = reading.board

    if boardNumber.isEmpty {
      boardNumber = board.number.isEmpty
        ? PanelVaultSchemeReader.boardNumber(
            fromFileName: pendingSchemeAttachments.first?.name ?? "")
        : board.number
    }
    if boardGroup.isEmpty {
      boardGroup = projectGroup(from: boardNumber)
    }
    if boardName.isEmpty, !board.name.isEmpty {
      boardName = board.name
    }

    // Prefer an existing project over the free text on the drawing, so a board
    // lands in the project it belongs to instead of creating a near-duplicate.
    if let match = matchingProject(name: board.project, customer: board.customer) {
      project = match.name
      customerName = match.customer
    } else if customerName.isEmpty, !board.customer.isEmpty {
      customerName = board.customer
    }

    if !board.type.isEmpty,
       let matched = boardTypes.first(where: { $0.name.localizedCaseInsensitiveContains(board.type) })
        ?? BoardType.samples.first(where: { $0.name.localizedCaseInsensitiveContains(board.type) }) {
      boardType = matched.name
    }
    if !board.manufacturer.isEmpty,
       let matched = manufacturerNames.first(where: {
         $0.localizedCaseInsensitiveContains(board.manufacturer)
           || board.manufacturer.localizedCaseInsensitiveContains($0)
       }) {
      boardManufacturer = matched
    }
    if !board.mainBreakerModel.isEmpty {
      mainBreakerModel = manufacturerNames.first {
        board.mainBreakerModel.localizedCaseInsensitiveContains($0)
      } ?? board.mainBreakerModel
    }
    if !board.mainBreakerAmpere.isEmpty {
      mainBreakerAmpere = board.mainBreakerAmpere
    }
    if !board.mainBreakerType.isEmpty {
      mainBreakerType = board.mainBreakerType
    }
    if board.cabinetCount > 0 {
      cabinetCount = "\(board.cabinetCount)"
    }
  }

  private func matchingProject(name: String, customer: String) -> ProjectItem? {
    if !name.isEmpty,
       let hit = projects.first(where: {
         $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
       }) { return hit }
    if !customer.isEmpty {
      return projects.first { $0.customer.localizedCaseInsensitiveCompare(customer) == .orderedSame }
    }
    return nil
  }

  private func projectGroup(from boardNumber: String) -> String {
    guard let dashIndex = boardNumber.lastIndex(of: "-") else { return "" }
    return String(boardNumber[..<dashIndex])
  }
}

enum NewBoardEntryMode {
  case aiScan
  case manual
}

/// Reads a board scheme, through PanelVault Cloud when it is reachable.
///
/// The reading happens on the server because that is where the Gemini key
/// lives — shipping an API key inside an app that goes on a workshop iPhone
/// would hand it to anyone who unpacks the binary.
///
/// With no company signed in, or with the server unreachable, the caller is
/// told plainly and falls back to the manual form. Nothing is invented here:
/// an offline guess dressed up as a reading is worse than an empty form.
enum PanelVaultSchemeReader {
  enum ReaderError: LocalizedError {
    case notSignedIn

    var errorDescription: String? {
      switch self {
      case .notSignedIn:
        return "Sign in to PanelVault Cloud from More to read schemes with AI. You can still enter the board manually."
      }
    }
  }

  static func read(fileName: String, mimeType: String, data: Data) async throws -> BoardSchemeReading {
    guard let account = PanelCloudKeychain.load() else { throw ReaderError.notSignedIn }
    return try await PanelCloudClient().readBoardScheme(
      fileName: fileName,
      mimeType: mimeType,
      data: data,
      account: account
    )
  }

  /// The board number as printed in a drawing's file name, when it is there.
  /// `3918.24-1 MDB.pdf` is the shape every scheme in this shop is named.
  static func boardNumber(fromFileName name: String) -> String {
    let source = name
      .replacingOccurrences(of: "_", with: "-")
      .replacingOccurrences(of: "/", with: "-")
    if let match = source.range(of: #"\d{4}\.\d{2}-\d+"#, options: .regularExpression) {
      return String(source[match]).uppercased()
    }
    return ""
  }
}

/// The first thing New Board shows: read the AutoCAD scheme.
///
/// The drawing is what the board actually is, so it comes before the form
/// rather than being one card buried at the top of it. Nothing is typed until
/// the reading is back, and the form that follows is a review of it.
///
/// Entering manually stays one tap away — a scheme is not always ready, and a
/// flow that could only start from a PDF would be worse than the form.
struct NewBoardSchemeIntakeView: View {
  let theme: PanelTheme
  var back: (() -> Void)? = nil
  /// Returns the reading, or nil when the manager chose to type it in.
  let onFinish: (BoardSchemeReading?) -> Void
  /// Keeps the picked drawing on the board as a scheme attachment.
  let onAttach: (SchemeAttachment) -> Void

  enum Stage: Equatable {
    case waiting
    case reading(String)
    case failed(String)
    case done(String)
  }

  @State private var stage: Stage = .waiting
  @State private var importerOpen = false
  @State private var reading: BoardSchemeReading?
  @State private var readTask: Task<Void, Never>?

  private var isReading: Bool {
    if case .reading = stage { return true }
    return false
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          VStack(alignment: .leading, spacing: 8) {
            Text("Scan the Scheme")
              .font(.largeTitle.bold())
            Text("Attach the AutoCAD PDF. PanelVault reads the board details and the component schedule off the drawing, then hands you the draft to check.")
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }

          switch stage {
          case .waiting:
            waitingCard
          case .reading(let name):
            readingCard(name)
          case .failed(let message):
            failureCard(message)
          case .done(let name):
            if let reading {
              SchemeReadingSummaryCard(theme: theme, fileName: name, reading: reading)
              Button {
                onFinish(reading)
              } label: {
                Label("Review the draft", systemImage: "arrow.right.circle.fill")
                  .font(.headline)
                  .frame(maxWidth: .infinity)
                  .padding(.vertical, 14)
                  .background(theme.primary)
                  .foregroundStyle(.white)
                  .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
              }
              .buttonStyle(PanelPressButtonStyle())

              Button("Scan a different file") {
                reading = nil
                stage = .waiting
              }
              .font(.subheadline.weight(.semibold))
              .frame(maxWidth: .infinity)
            }
          }

          if !isReading {
            Button {
              onFinish(nil)
            } label: {
              Label("Enter the board manually instead", systemImage: "square.and.pencil")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
          }

          BottomTabClearance()
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("New Board")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Back") {
            readTask?.cancel()
            back?()
          }
        }
      }
    }
    .fileImporter(isPresented: $importerOpen, allowedContentTypes: [.pdf, .image]) { result in
      guard case .success(let url) = result else { return }
      read(url)
    }
    .onDisappear { readTask?.cancel() }
  }

  private var waitingCard: some View {
    Button {
      importerOpen = true
    } label: {
      VStack(spacing: 12) {
        Image(systemName: "doc.viewfinder.fill")
          .font(.system(size: 40, weight: .semibold))
          .foregroundStyle(theme.primary)
        Text("Choose the scheme PDF")
          .font(.headline)
        Text("PDF from AutoCAD, or a photo of the printed drawing")
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 40)
      .background(theme.primary.opacity(0.08))
      .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 20, style: .continuous)
          .strokeBorder(theme.primary.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
      )
    }
    .buttonStyle(PanelPressButtonStyle())
  }

  private func readingCard(_ name: String) -> some View {
    GlassCard(theme: theme) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 12) {
          ProgressView().tint(theme.primary)
          VStack(alignment: .leading, spacing: 3) {
            Text("Reading the scheme")
              .font(.headline)
            Text(name)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .truncationMode(.middle)
          }
          Spacer()
        }
        Text("A full multi-page scheme can take a minute. Keep this screen open.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Button("Cancel") {
          readTask?.cancel()
          stage = .waiting
        }
        .font(.subheadline.weight(.semibold))
      }
    }
  }

  private func failureCard(_ message: String) -> some View {
    GlassCard(theme: theme) {
      VStack(alignment: .leading, spacing: 12) {
        Label("Could not read that scheme", systemImage: "exclamationmark.triangle.fill")
          .font(.headline)
          .foregroundStyle(Color(hex: 0xFF9F0A))
        Text(message)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Button {
          importerOpen = true
        } label: {
          Label("Choose a file again", systemImage: "arrow.clockwise")
            .font(.subheadline.bold())
        }
      }
    }
  }

  private func read(_ url: URL) {
    // A file handed over by the document picker is outside the sandbox until
    // its security scope is opened, and the scope has to be closed again even
    // when reading throws.
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }

    guard let data = try? Data(contentsOf: url) else {
      stage = .failed("That file could not be opened. Try exporting it from AutoCAD again.")
      return
    }
    let name = url.lastPathComponent
    let isPDF = url.pathExtension.lowercased() == "pdf"

    // Keep the drawing with the board however the reading goes: the workshop
    // needs the scheme whether or not the AI could parse it.
    if isPDF, let saved = SchemeAttachmentSection.persistPDF(url) {
      onAttach(SchemeAttachment(kind: .pdf, name: name, image: nil, url: saved))
    } else if !isPDF, let image = UIImage(data: data) {
      onAttach(SchemeAttachment(kind: .photo, name: name, image: image))
    }

    stage = .reading(name)
    readTask?.cancel()
    readTask = Task {
      do {
        let result = try await PanelVaultSchemeReader.read(
          fileName: name,
          mimeType: isPDF ? "application/pdf" : "image/jpeg",
          data: data
        )
        if Task.isCancelled { return }
        await MainActor.run {
          reading = result
          stage = .done(name)
        }
      } catch {
        if Task.isCancelled { return }
        await MainActor.run {
          stage = .failed(error.localizedDescription)
        }
      }
    }
  }
}

/// Sits above the pre-filled draft, so it is never unclear which fields a
/// person typed and which came off the drawing.
struct SchemeReadingReviewCard: View {
  let theme: PanelTheme
  let reading: BoardSchemeReading
  let rescan: () -> Void
  @State private var partsOpen = false

  var body: some View {
    GlassCard(theme: theme) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 10) {
          Image(systemName: "sparkles")
            .foregroundStyle(theme.primary)
          VStack(alignment: .leading, spacing: 2) {
            Text("Filled from the scheme")
              .font(.headline)
            Text("Check every field against the drawing before creating.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
        }

        HStack(spacing: 8) {
          if !reading.components.isEmpty {
            EquipmentPill(text: "\(reading.componentCount) parts", color: Color(hex: 0x35E177))
          }
          if !reading.unmatched.isEmpty {
            EquipmentPill(text: "\(reading.unmatched.count) unplaced", color: Color(hex: 0xFF9F0A))
          }
        }

        if !reading.components.isEmpty || !reading.unmatched.isEmpty {
          Button {
            withAnimation(.easeOut(duration: 0.16)) { partsOpen.toggle() }
          } label: {
            Label(
              partsOpen ? "Hide the schedule" : "Show the schedule it read",
              systemImage: partsOpen ? "chevron.up" : "chevron.down"
            )
            .font(.caption.bold())
          }

          if partsOpen {
            VStack(alignment: .leading, spacing: 6) {
              ForEach(reading.components) { component in
                scheduleLine(
                  quantity: component.quantity,
                  text: component.displayName,
                  reference: component.reference,
                  color: Color(hex: 0x35E177)
                )
              }
              ForEach(reading.unmatched) { line in
                scheduleLine(
                  quantity: line.quantity,
                  text: line.description.isEmpty ? line.type : line.description,
                  reference: line.reference,
                  color: Color(hex: 0xFF9F0A)
                )
              }
            }
            .padding(.top, 2)

            if !reading.unmatched.isEmpty {
              Text("Amber lines are not on the board. The catalog had no confident match, so they are left for you to place rather than guessed at.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }

        Button(action: rescan) {
          Label("Scan a different scheme", systemImage: "arrow.clockwise")
            .font(.caption.bold())
        }
      }
    }
  }

  private func scheduleLine(quantity: Int, text: String, reference: String, color: Color) -> some View {
    HStack(spacing: 8) {
      Text("\(quantity)×")
        .font(.caption2.weight(.black))
        .foregroundStyle(color)
        .frame(width: 30, alignment: .leading)
      Text(text)
        .font(.caption)
        .lineLimit(1)
      if !reference.isEmpty {
        Text(reference)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
  }
}

/// What the reading found, before anyone commits to it.
struct SchemeReadingSummaryCard: View {
  let theme: PanelTheme
  let fileName: String
  let reading: BoardSchemeReading

  var body: some View {
    GlassCard(theme: theme) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 10) {
          Image(systemName: "checkmark.seal.fill")
            .foregroundStyle(Color(hex: 0x35E177))
          VStack(alignment: .leading, spacing: 2) {
            Text("Scheme read")
              .font(.headline)
            Text(fileName)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .truncationMode(.middle)
          }
          Spacer()
        }

        if reading.isEmpty {
          Text("Nothing could be read off this drawing. You can still enter the board by hand — the file stays attached to it.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        } else {
          VStack(alignment: .leading, spacing: 7) {
            readingLine("number", reading.board.number)
            readingLine("board", reading.board.name)
            readingLine("type", reading.board.type)
            readingLine("customer", reading.board.customer)
            readingLine("main breaker", [
              reading.board.mainBreakerModel,
              reading.board.mainBreakerAmpere,
            ].filter { !$0.isEmpty }.joined(separator: " "))
          }

          HStack(spacing: 8) {
            if !reading.components.isEmpty {
              EquipmentPill(
                text: "\(reading.componentCount) parts matched",
                color: Color(hex: 0x35E177)
              )
            }
            if !reading.unmatched.isEmpty {
              EquipmentPill(
                text: "\(reading.unmatched.count) need a look",
                color: Color(hex: 0xFF9F0A)
              )
            }
          }

          if !reading.unmatched.isEmpty {
            Text("Lines the catalog had no confident match for are listed on the draft. They are not added to the board — place them yourself so nothing is guessed.")
              .font(.caption2)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }

          if !reading.board.notes.isEmpty {
            Text(reading.board.notes)
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
              .padding(10)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(theme.primary.opacity(0.08))
              .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          }
        }

        Text("Everything below is a draft. Check it against the drawing before you create the board.")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  @ViewBuilder
  private func readingLine(_ label: String, _ value: String) -> some View {
    if !value.isEmpty {
      HStack(alignment: .top, spacing: 8) {
        Text(label)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
          .frame(width: 92, alignment: .leading)
        Text(value)
          .font(.caption.bold())
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
      }
    }
  }
}

struct NewBoardModeCard: View {
  let theme: PanelTheme
  let symbol: String
  let title: String
  let subtitle: String
  let color: Color

  var body: some View {
    GlassCard(theme: theme) {
      HStack(spacing: 14) {
        Image(systemName: symbol)
          .font(.system(size: 24, weight: .heavy))
          .foregroundStyle(color)
          .frame(width: 54, height: 54)
          .background(color.opacity(0.16))
          .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        VStack(alignment: .leading, spacing: 5) {
          Text(title)
            .font(.title3.bold())
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer()
        Image(systemName: "chevron.right")
          .foregroundStyle(.secondary)
      }
    }
  }
}

struct MainBreakerStepView: View {
  let theme: PanelTheme
  let actionColor: Color
  @Binding var mainBreakerType: String
  @Binding var mainBreakerModel: String
  @Binding var mainBreakerAmpere: String
  let manufacturerNames: [String]
  let manufacturers: [ManufacturerItem]
  let create: () -> Void
  @State private var pickerSheet: MainBreakerPickerSheet?

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          CreationFormSection(theme: theme, title: "Progress", symbol: "point.3.connected.trianglepath.dotted") {
          NewBoardStepIndicator(theme: theme, currentStep: 2)
              .frame(height: 72)
          }

          CreationFormSection(theme: theme, title: "Main Breaker", symbol: "bolt.shield.fill", subtitle: "Choose the breaker details") {
            CreationMenuInput(theme: theme, title: "Breaker type", symbol: "bolt.fill", value: mainBreakerType, options: ["MCB", "RCBO", "MCCB", "ACB", "Switch Disconnector", "Fuse Switch"], selection: $mainBreakerType)
            ManufacturerPickerInput(theme: theme, title: "Manufacturer", value: mainBreakerModel, manufacturers: manufacturers) {
              pickerSheet = .manufacturer
            }
            CreationPickerInput(theme: theme, title: "Ampere", symbol: "gauge.with.dots.needle.67percent", value: mainBreakerAmpere) {
              pickerSheet = .ampere
            }
          }
          BottomTabClearance(height: 24)
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())

      Button(action: create) {
        HStack {
          Image(systemName: "checkmark.circle.fill")
          Text("Create Board")
        }
        .font(.system(size: 17, weight: .bold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
      }
      .background(actionColor)
      .foregroundStyle(.white)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .shadow(color: actionColor.opacity(0.24), radius: 14, y: 6)
      .padding(.horizontal, 18)
      .padding(.top, 10)
      .padding(.bottom, 108)
    }
    .background(theme.background.ignoresSafeArea())
    .navigationTitle("Main Breaker")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(item: $pickerSheet) { sheet in
      switch sheet {
      case .manufacturer:
        ManufacturerCreationPickerSheet(theme: theme, manufacturers: manufacturers, selected: mainBreakerModel) {
          mainBreakerModel = $0
        }
      case .ampere:
        CreationOptionPickerSheet(theme: theme, title: "Ampere", symbol: "gauge.with.dots.needle.67percent", options: AmpereRating.all, selected: mainBreakerAmpere) {
          mainBreakerAmpere = $0
        }
      }
    }
  }
}

enum MainBreakerPickerSheet: String, Identifiable {
  case manufacturer
  case ampere

  var id: String { rawValue }
}

struct NewBoardStepIndicator: View {
  let theme: PanelTheme
  let currentStep: Int

  private let steps = [
    (number: 1, title: "Board", symbol: "rectangle.3.group.fill"),
    (number: 2, title: "Breaker", symbol: "bolt.shield.fill"),
    (number: 3, title: "Finish", symbol: "checkmark.circle.fill")
  ]

  var body: some View {
    GeometryReader { proxy in
      let sideInset: CGFloat = 34
      let availableWidth = max(proxy.size.width - sideInset * 2, 1)
      let gap = availableWidth / CGFloat(max(steps.count - 1, 1))

      ZStack(alignment: .topLeading) {
        ForEach(0..<(steps.count - 1), id: \.self) { index in
          Capsule()
            .fill(index + 1 < currentStep ? theme.primary : theme.surface.opacity(0.82))
            .frame(width: max(gap - 42, 1), height: 4)
            .offset(x: sideInset + CGFloat(index) * gap + 21, y: 17)
        }

        ForEach(Array(steps.enumerated()), id: \.element.number) { index, step in
          VStack(spacing: 7) {
            ZStack {
              Circle()
                .fill(step.number <= currentStep ? theme.primary : theme.surface.opacity(0.92))
                .frame(width: 34, height: 34)
              Text("\(step.number)")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(step.number <= currentStep ? .white : .secondary)
            }
            Text(step.title)
              .font(.system(size: 11, weight: .heavy))
              .foregroundStyle(step.number <= currentStep ? .primary : .secondary)
              .lineLimit(1)
              .minimumScaleFactor(0.75)
          }
          .frame(width: 68)
          .offset(x: sideInset + CGFloat(index) * gap - 34, y: 0)
        }
      }
    }
    .frame(height: 58)
    .padding(.vertical, 8)
    .animation(.easeOut(duration: 0.16), value: currentStep)
  }
}

struct BoardProductionStageTracker: View {
  let theme: PanelTheme
  let board: BoardDraft
  let onSelect: (String) -> Void

  private func color(for stage: BoardProductionStage) -> Color {
    switch stage.state {
    case "done": return Color(hex: 0x35E177)
    case "attention": return Color.red
    case "current", "ready": return theme.primary
    default: return .secondary
    }
  }

  var body: some View {
    GlassCard(theme: theme) {
      VStack(alignment: .leading, spacing: 13) {
        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text("Production Workflow")
              .font(.caption.weight(.bold))
              .foregroundStyle(.secondary)
              .textCase(.uppercase)
            Text(board.currentProductionStage.title)
              .font(.title3.bold())
          }
          Spacer()
          StatusBadge(status: board.statusTitle)
        }

        ScrollView(.horizontal, showsIndicators: false) {
          let stages = board.productionStages
          HStack(alignment: .top, spacing: 0) {
            ForEach(stages.indices, id: \.self) { index in
              let stage = stages[index]
              let stageColor = color(for: stage)
              VStack(spacing: 8) {
                HStack(spacing: 0) {
                  Capsule()
                    .fill(index > 0 && stages[index - 1].state == "done" ? Color(hex: 0x35E177).opacity(0.72) : theme.surface)
                    .frame(width: 27, height: 3)
                    .opacity(index == 0 ? 0 : 1)
                  ZStack {
                    if ["current", "ready", "attention"].contains(stage.state) {
                      Circle()
                        .stroke(stageColor.opacity(0.18), lineWidth: 6)
                        .frame(width: 38, height: 38)
                    }
                  Circle()
                      .fill(stage.state == "upcoming" ? theme.surface : stageColor)
                      .frame(width: 30, height: 30)
                      .overlay(Circle().stroke(stageColor.opacity(stage.state == "upcoming" ? 0.28 : 0.8), lineWidth: 1))
                    if stage.state == "done" {
                      Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.white)
                    } else {
                      Text("\(index + 1)")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(stage.state == "upcoming" ? Color.secondary : Color.white)
                    }
                  }
                  Capsule()
                    .fill(stage.state == "done" ? Color(hex: 0x35E177).opacity(0.72) : theme.surface)
                    .frame(width: 27, height: 3)
                    .opacity(index == stages.count - 1 ? 0 : 1)
                }
                Text(stage.title)
                  .font(.system(size: 10, weight: .heavy))
                  .foregroundStyle(["current", "ready", "attention"].contains(stage.state) ? stageColor : Color.primary)
                  .multilineTextAlignment(.center)
                  .lineLimit(2)
                  .frame(width: 84)
                if ["mechanical", "components", "wiring", "finishing"].contains(stage.id) {
                  Text("\(stage.progress)%")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
              }
              .frame(width: 84, alignment: .top)
              .contentShape(Rectangle())
              .onTapGesture {
                guard stage.id != "complete", stage.id != board.currentProductionStage.id else { return }
                onSelect(stage.id)
              }
              .accessibilityAddTraits(stage.id == board.currentProductionStage.id ? .isSelected : .isButton)
              .accessibilityHint(stage.id == "complete" ? "Unlocked by QA approval" : "Sets the board stage")
            }
          }
          .padding(.horizontal, 4)
          .padding(.vertical, 8)
        }
      }
    }
    .animation(.easeInOut(duration: 0.38), value: board.currentProductionStage.id)
  }
}

struct CreatedBoardScreen: View {
  let theme: PanelTheme
  @Binding var board: BoardDraft
  var boardTypes: [BoardType] = BoardType.samples
  var manufacturers: [ManufacturerItem] = ManufacturerItem.defaults
  var showsCreationFlow = false
  var onDeleteBoard: (() -> Void)? = nil
  let createAnother: () -> Void
  @State private var catalogOpen = false
  @State private var componentTypes: [String] = []
  @State private var addedComponentsByType: [String: [PanelComponent]] = [:]
  @State private var cabinetChecklists: [Set<String>] = []
  @State private var selectedCabinet: Int = 0
  @State private var personalChecklistItems: [PersonalChecklistItem] = []
  @State private var localBoardLoaded = false
  @State private var pendingBoardSyncWorkItem: DispatchWorkItem?
  @State private var selectedComponentType: String?
  @State private var editOpen = false
  @Environment(\.panelCloudAccount) private var cloudAccount
  @State private var qaNote = ""
  @State private var qaSubmitting = false
  @State private var qaError = ""
  @State private var stageSubmitting = false

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
        if showsCreationFlow {
          NewBoardStepIndicator(theme: theme, currentStep: 3)
        }

        VStack(alignment: .leading, spacing: 4) {
          Text(board.name)
            .font(.largeTitle.bold())
          Text(board.number)
            .font(.headline)
            .foregroundStyle(.secondary)
        }

        BoardCoverPhotoSection(theme: theme, selectedImage: $board.coverImage)

        BoardPropertiesOverview(theme: theme, board: displayBoard, manufacturers: manufacturers) {
          editOpen = true
        }

        BoardProductionStageTracker(theme: theme, board: displayBoard) { stageID in
          Task { await submitStage(stageID) }
        }
        .allowsHitTesting(!stageSubmitting)
        qaReviewSection

        componentsSection
        SchemeAttachmentSection(theme: theme, attachments: $board.schemeAttachments)
        PhotoPickerSection(theme: theme, title: "Board Photos", photoTokens: $board.photoTokens, coverImage: $board.coverImage)
        PersonalChecklistSection(theme: theme, items: $personalChecklistItems)
          .onChange(of: personalChecklistItems) { _ in
            scheduleBoardSync()
          }

        if showsCreationFlow {
          Button(action: createAnother) {
            HStack(spacing: 12) {
              Image(systemName: "plus.circle.fill")
                .font(.system(size: 26, weight: .bold))
              VStack(alignment: .leading, spacing: 3) {
                Text("Create Another Board")
                  .font(.system(size: 17, weight: .heavy))
                Text("Start a clean board draft")
                  .font(.caption)
                  .foregroundStyle(.white.opacity(0.78))
              }
              Spacer()
              Image(systemName: "arrow.right")
                .font(.system(size: 15, weight: .heavy))
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
              LinearGradient(
                colors: [theme.primary, theme.secondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: theme.primary.opacity(0.24), radius: 16, y: 8)
          }
          .buttonStyle(.plain)
        }
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
      ToolbarItem(placement: .topBarLeading) {
        if showsCreationFlow {
          Button("Done") {
            createAnother()
          }
          .fontWeight(.bold)
        }
      }
      ToolbarItem(placement: .topBarTrailing) {
        Button("Edit") {
          withAnimation(.easeInOut(duration: 0.24)) {
            editOpen = true
          }
        }
        .fontWeight(.bold)
      }
    }
    .sheet(isPresented: $editOpen) {
      BoardEditSheet(theme: theme, board: $board, boardTypes: boardTypes, manufacturers: manufacturers, onDelete: onDeleteBoard)
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

  private var canReviewQA: Bool {
    guard let account = cloudAccount,
          ["owner", "manager", "staff-manager", "qa"].contains(account.role.lowercased()),
          displayBoard.completion >= 100,
          displayBoard.qaStatus != "approved" else { return false }
    if ["owner", "manager", "staff-manager"].contains(account.role.lowercased()) { return true }
    return displayBoard.qaAssignedTo == account.userID
  }

  @ViewBuilder
  private var qaReviewSection: some View {
    GlassCard(theme: theme) {
      VStack(alignment: .leading, spacing: 11) {
        HStack {
          Label("Quality Assurance", systemImage: "checkmark.shield.fill")
            .font(.headline)
          Spacer()
          Text(displayBoard.qaAssignedName.isEmpty ? "Unassigned" : displayBoard.qaAssignedName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }

        if displayBoard.qaStatus == "approved" {
          Label("QA approved — Complete is unlocked", systemImage: "checkmark.seal.fill")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color(hex: 0x35E177))
        } else if displayBoard.qaStatus == "changes_requested" {
          Label("Corrections requested — returned to Finishing", systemImage: "arrow.uturn.backward.circle.fill")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.red)
          if !displayBoard.qaNote.isEmpty {
            Text(displayBoard.qaNote)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        } else if displayBoard.completion >= 100 {
          Label("Production is finished and ready for QA", systemImage: "bell.badge.fill")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(theme.primary)
        } else {
          Text("Complete the Finishing stage before QA can approve this board.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        if canReviewQA {
          TextField("QA note or requested correction", text: $qaNote, axis: .vertical)
            .lineLimit(2...5)
            .textFieldStyle(.roundedBorder)
          if !qaError.isEmpty {
            Text(qaError)
              .font(.caption)
              .foregroundStyle(.red)
          }
          HStack {
            Button("Request Corrections", role: .destructive) {
              Task { await submitQA(action: "request_changes") }
            }
            .buttonStyle(.bordered)
            Spacer()
            Button {
              Task { await submitQA(action: "approve") }
            } label: {
              Label("Approve QA", systemImage: "checkmark.shield.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.primary)
          }
          .disabled(qaSubmitting)
        }
      }
    }
  }

  @MainActor
  private func submitStage(_ stageID: String) async {
    guard stageID != "complete", stageID != board.productionStage else { return }
    stageSubmitting = true
    qaError = ""
    if let account = cloudAccount {
      do {
        let remote = try await PanelCloudClient().submitStage(account: account, boardID: board.id, stageID: stageID)
        board = remote.board(preserving: board)
      } catch {
        qaError = error.localizedDescription
      }
    } else {
      board.productionStage = stageID
      board.qaStatus = stageID == "qa" ? "ready" : "pending"
      board.qaApprovedAt = nil
      if stageID != "qa" { board.qaReadyAt = nil }
    }
    stageSubmitting = false
  }

  @MainActor
  private func submitQA(action: String) async {
    guard let account = cloudAccount else { return }
    qaSubmitting = true
    qaError = ""
    do {
      let remote = try await PanelCloudClient().submitQA(
        account: account,
        boardID: board.id,
        action: action,
        note: qaNote
      )
      let synced = remote.board(preserving: board)
      board.qaAssignedTo = synced.qaAssignedTo
      board.qaAssignedName = synced.qaAssignedName
      board.qaStatus = synced.qaStatus
      board.qaNote = synced.qaNote
      board.qaReadyAt = synced.qaReadyAt
      board.qaApprovedAt = synced.qaApprovedAt
      board.productionStage = synced.productionStage
      qaNote = synced.qaNote
    } catch {
      qaError = error.localizedDescription
    }
    qaSubmitting = false
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
    qaNote = board.qaNote
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

struct BoardEditSheet: View {
  let theme: PanelTheme
  @Binding var board: BoardDraft
  let boardTypes: [BoardType]
  let manufacturers: [ManufacturerItem]
  var onDelete: (() -> Void)? = nil
  @Environment(\.dismiss) private var dismiss
  @State private var pickerSheet: BoardEditPickerSheet?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          CreationFormSection(theme: theme, title: "Board Details", symbol: "rectangle.3.group.fill", subtitle: "Identity and customer") {
            CreationTextInput(theme: theme, title: "Board name", placeholder: "Board name", symbol: "textformat", text: $board.name, capitalization: .words)
            CreationTextInput(theme: theme, title: "Board number", placeholder: "3918.24-1", symbol: "number", text: $board.number, keyboardType: .numbersAndPunctuation, capitalization: .characters)
            CreationTextInput(theme: theme, title: "Customer", placeholder: "Customer", symbol: "person.crop.circle.fill", text: $board.customer, capitalization: .words)
            CreationTextInput(theme: theme, title: "Company", placeholder: "Company", symbol: "building.2.fill", text: $board.company, capitalization: .words)
          }

          CreationFormSection(theme: theme, title: "Board Setup", symbol: "slider.horizontal.3") {
            CreationPickerInput(theme: theme, title: "Board type", symbol: "square.grid.2x2.fill", value: board.type) {
              pickerSheet = .boardType
            }
            CreationPickerInput(theme: theme, title: "Subtype", symbol: "rectangle.grid.1x2.fill", value: board.subtype) {
              pickerSheet = .subtype
            }
            ManufacturerPickerInput(theme: theme, title: "Manufacturer", value: board.manufacturer, manufacturers: manufacturers) {
              pickerSheet = .manufacturer
            }
            HStack(spacing: 10) {
              CreationMenuInput(theme: theme, title: "Cabinets", symbol: "cabinet.fill", value: board.cabinetCount, options: (1...12).map(String.init), selection: $board.cabinetCount)
              CreationMenuInput(theme: theme, title: "Build", symbol: "rectangle.split.2x1.fill", value: board.buildFormat, options: ["Panels", "Plate"], selection: $board.buildFormat)
            }
            CreationDateInput(theme: theme, title: "Out date", symbol: "calendar", selection: $board.dateOut, displayedComponents: .date)
            CreationToggleInput(theme: theme, title: "Has due date/time", symbol: "clock.badge.exclamationmark.fill", isOn: dueDateEnabled)
            if board.dueDate != nil {
              CreationDateInput(theme: theme, title: "Due", symbol: "clock.fill", selection: dueDateBinding, displayedComponents: [.date, .hourAndMinute])
            }
            CreationToggleInput(theme: theme, title: "Has finished date", symbol: "flag.checkered", isOn: finishDateEnabled)
            if board.finishDate != nil {
              CreationDateInput(theme: theme, title: "Finished date", symbol: "checkmark.seal.fill", selection: finishDateBinding, displayedComponents: .date)
            }
            CreationTextInput(theme: theme, title: "Finish time", placeholder: "Hours", symbol: "timer", text: $board.finishTimeHours, keyboardType: .decimalPad)
          }

          CreationFormSection(theme: theme, title: "Main Breaker", symbol: "bolt.shield.fill") {
            CreationMenuInput(theme: theme, title: "Main breaker", symbol: "bolt.fill", value: board.mainBreakerType, options: ["MCB", "RCBO", "MCCB", "ACB", "Switch Disconnector", "Fuse Switch"], selection: $board.mainBreakerType)
            ManufacturerPickerInput(theme: theme, title: "Model or family", value: board.mainBreakerModel, manufacturers: manufacturers) {
              pickerSheet = .mainBreakerManufacturer
            }
            CreationMenuInput(theme: theme, title: "Ampere", symbol: "gauge.with.dots.needle.67percent", value: board.mainBreakerAmpere, options: AmpereRating.all, selection: ampereBinding)
          }

          if let onDelete {
            DeleteRecordButton(title: "Delete Board", itemName: board.name) {
              onDelete()
              dismiss()
            }
            .padding(.top, 8)
          }
          BottomTabClearance(height: 84)
        }
        .padding(18)
      }
      .scrollDismissesKeyboard(.interactively)
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Edit Board")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
            .fontWeight(.bold)
        }
      }
      .sheet(item: $pickerSheet) { sheet in
        switch sheet {
        case .boardType:
          BoardTypeCreationPickerSheet(theme: theme, boardTypes: mergedBoardTypes, selected: board.type) { selected in
            boardTypeBinding.wrappedValue = selected
          }
        case .subtype:
          CreationOptionPickerSheet(theme: theme, title: "Subtype", symbol: "rectangle.grid.1x2.fill", options: BoardSubtypeCatalog.options(for: board.type), selected: board.subtype) {
            subtypeBinding.wrappedValue = $0
          }
        case .manufacturer:
          ManufacturerCreationPickerSheet(theme: theme, manufacturers: manufacturers, selected: board.manufacturer) {
            board.manufacturer = $0
          }
        case .mainBreakerManufacturer:
          ManufacturerCreationPickerSheet(theme: theme, manufacturers: manufacturers, selected: board.mainBreakerModel) {
            board.mainBreakerModel = $0
          }
        }
      }
    }
  }

  private var ampereBinding: Binding<String> {
    Binding {
      board.mainBreakerAmpere
    } set: { value in
      board.mainBreakerAmpere = value
      board.ampere = value.uppercased().hasSuffix("A") ? value : "\(value)A"
    }
  }

  private var manufacturerBinding: Binding<String> {
    Binding {
      manufacturerNames.contains(board.manufacturer) ? board.manufacturer : board.manufacturer
    } set: { value in
      board.manufacturer = value
    }
  }

  private var manufacturerNames: [String] {
    let names = manufacturers.map(\.name) + ManufacturerItem.defaults.map(\.name) + EquipmentCompany.all + [board.manufacturer, board.mainBreakerModel]
    return Array(Set(names.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })).sorted()
  }

  private var boardTypeNames: [String] {
    let names = boardTypes.map(\.name) + BoardType.samples.map(\.name) + [board.type]
    return Array(Set(names.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })).sorted()
  }

  private var mergedBoardTypes: [BoardType] {
    var seen: Set<String> = []
    return (boardTypes + BoardType.samples).filter { seen.insert($0.name.lowercased()).inserted }
  }

  private var boardTypeBinding: Binding<String> {
    Binding {
      board.type
    } set: { value in
      board.type = value
      if !BoardSubtypeCatalog.options(for: value).contains(board.subtype) {
        board.subtype = BoardSubtypeCatalog.defaultSubtype
      }
    }
  }

  private var subtypeBinding: Binding<String> {
    Binding {
      let options = BoardSubtypeCatalog.options(for: board.type)
      return options.contains(board.subtype) ? board.subtype : BoardSubtypeCatalog.defaultSubtype
    } set: { value in
      board.subtype = value
    }
  }

  private var finishDateEnabled: Binding<Bool> {
    Binding {
      board.finishDate != nil
    } set: { enabled in
      board.finishDate = enabled ? (board.finishDate ?? Date()) : nil
    }
  }

  private var finishDateBinding: Binding<Date> {
    Binding {
      board.finishDate ?? Date()
    } set: { value in
      board.finishDate = value
    }
  }

  private var dueDateEnabled: Binding<Bool> {
    Binding {
      board.dueDate != nil
    } set: { enabled in
      board.dueDate = enabled ? (board.dueDate ?? Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()) : nil
    }
  }

  private var dueDateBinding: Binding<Date> {
    Binding {
      board.dueDate ?? Date()
    } set: { value in
      board.dueDate = value
    }
  }
}

enum BoardEditPickerSheet: String, Identifiable {
  case boardType
  case subtype
  case manufacturer
  case mainBreakerManufacturer

  var id: String { rawValue }
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

  private func persistComponentImages() {
    ComponentImageStore.save(componentImages)
  }
}

struct InfoLine: View {
  let title: String
  let value: String

  var body: some View {
    HStack {
      Text(title)
        .foregroundStyle(.secondary)
      Spacer()
      Text(value)
        .fontWeight(.semibold)
        .multilineTextAlignment(.trailing)
    }
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

  /// Internal rather than private: the scheme intake screen saves the drawing
  /// it just read through the same path, so both end up in one folder.
  static func persistPDF(_ url: URL) -> URL? {
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

struct NewProjectSheet: View {
  let theme: PanelTheme
  @Binding var boards: [BoardDraft]
  let customers: [CustomerItem]
  let projectCustomers: [String]
  var onDone: (() -> Void)? = nil
  let onCreate: (ProjectItem) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var projectName = ""
  @State private var customer = ""
  @State private var site = ""
  @State private var hasDueDate = false
  @State private var dueDate = Date()

  private var canCreate: Bool {
    !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !customer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var knownCustomers: [String] {
    Array(Set(customers.map(\.name) + projectCustomers))
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .sorted()
  }

  private var matchingKnownCustomers: [String] {
    let query = customer.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return knownCustomers }
    return knownCustomers.filter { $0.localizedCaseInsensitiveContains(query) }
  }

  private var assignedCustomerColor: Color {
    customers.first {
      $0.name.localizedCaseInsensitiveCompare(customer) == .orderedSame
    }?.color ?? theme.primary
  }

  var body: some View {
    NavigationStack {
      ScrollView {
          VStack(alignment: .leading, spacing: 14) {
            CreationFormSection(theme: theme, title: "Project Details", symbol: "folder.fill", subtitle: "Create the container first") {
              CreationTextInput(theme: theme, title: "Project name", placeholder: "Azrieli Office Tower", symbol: "folder.fill", text: $projectName, capitalization: .words)
              CreationTextInput(theme: theme, title: "Customer", placeholder: "Search or type customer", symbol: "person.crop.circle.fill", text: $customer, capitalization: .words)
              SuggestionChips(theme: theme, values: matchingKnownCustomers, selectedValue: customer) { customer = $0 }
              CreationTextInput(theme: theme, title: "Site or building", placeholder: "Optional location", symbol: "mappin.and.ellipse", text: $site, capitalization: .words)
            }

            CreationFormSection(theme: theme, title: "Schedule", symbol: "calendar.badge.clock") {
              CreationToggleInput(theme: theme, title: "Add expected finish date", symbol: "clock.badge.exclamationmark.fill", isOn: $hasDueDate)
              if hasDueDate {
                CreationDateInput(theme: theme, title: "Expected finish", symbol: "calendar.badge.clock", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
              }
            }
            BottomTabClearance(height: 118)
          }
          .padding(18)
        }
        .scrollDismissesKeyboard(.interactively)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("New Project")
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button("Cancel") {
              onDone?()
              dismiss()
            }
          }

          ToolbarItem(placement: .topBarTrailing) {
            Button("Create") {
              let project = ProjectItem(
                id: "project-\(UUID().uuidString)",
                name: projectName,
                customer: customer,
                detail: site.isEmpty ? "0 boards" : "0 boards • \(site)",
                status: "Design",
                color: assignedCustomerColor,
                dueDate: hasDueDate ? dueDate : nil
              )
              // Hand the project over and get out of the way. The caller opens
              // the project's own page, which is where boards, schemes and
              // photos are added — the same place it is managed from later,
              // rather than a one-off picker that only appears at creation.
              onCreate(project)
              onDone?()
              dismiss()
            }
            .disabled(!canCreate)
            .fontWeight(.bold)
          }
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

struct SearchView: View {
  let theme: PanelTheme
  @Binding var query: String
  @Binding var projects: [ProjectItem]
  @Binding var boards: [BoardDraft]
  let boardTypes: [BoardType]
  let manufacturers: [ManufacturerItem]
  @Binding var recentVisits: [RecentVisit]
  @State private var scope: SearchScope = .all
  @State private var activeFilters: Set<String> = []
  @State private var filtersExpanded = false
  @State private var selectedProject: ProjectItem?
  @State private var selectedBoard: BoardDraft?

  private var filteredProjects: [ProjectItem] {
    guard scope.includesProjects else { return [] }
    return projects.filter { project in
      matches(projectSearchText(project))
    }
    .sorted {
      let leftStatus = projectStatus($0)
      let rightStatus = projectStatus($1)
      if leftStatus != rightStatus {
        return projectSearchRank(leftStatus) < projectSearchRank(rightStatus)
      }
      if let dueSort = dueDateComesFirst($0.dueDate, $1.dueDate) { return dueSort }
      return $0.name < $1.name
    }
  }

  private var filteredBoards: [BoardDraft] {
    guard scope.includesBoards else { return [] }
    return boards.filter { board in
      matches(boardSearchText(board))
    }
    .sorted(by: boardPrioritySort)
  }

  private var filteredGroups: [ComponentGroup] {
    guard scope.includesComponents else { return [] }
    return ComponentGroup.samples.compactMap { group in
      let items = group.items.filter { item in
        matches("\(group.name) \(item.searchText)")
      }
      return items.isEmpty ? nil : ComponentGroup(id: group.id, name: group.name, items: items)
    }
  }

  private var hasResults: Bool {
    !filteredProjects.isEmpty || !filteredBoards.isEmpty || !filteredGroups.isEmpty
  }

  private var filterSections: [SearchFilterSection] {
    [
      SearchFilterSection(title: "Ampere", symbol: "bolt.fill", options: AmpereRating.all),
      SearchFilterSection(title: "Main Breaker", symbol: "bolt.shield.fill", options: ["MCB", "RCBO", "MCCB", "ACB", "Switch Disconnector", "Fuse Switch", "XT1", "XT2", "XT3", "XT4", "XT5", "XT6", "XT7", "XT7 M", "NSX", "S203"]),
      SearchFilterSection(title: "Brand", symbol: "tag.fill", options: ["ABB", "Schneider", "Siemens", "Eaton"]),
      SearchFilterSection(title: "Build Format", symbol: "square.grid.2x2.fill", options: ["Panels", "Plate"]),
      SearchFilterSection(title: "Component Type", symbol: "shippingbox.fill", options: EquipmentTypeCatalog.all),
      SearchFilterSection(title: "Board Type", symbol: "rectangle.3.group.fill", options: boardTypes.map(\.name)),
      SearchFilterSection(title: "Project", symbol: "folder.fill", options: projects.map(\.name)),
      SearchFilterSection(title: "Customer", symbol: "person.crop.circle.fill", options: Array(Set((projects.map(\.customer) + boards.map(\.customer)).filter { !$0.isEmpty })).sorted())
    ]
  }

  private var visibleFilterSections: [SearchFilterSection] {
    filtersExpanded ? filterSections : Array(filterSections.prefix(3))
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
              .font(.system(size: 21, weight: .semibold))
              .foregroundStyle(theme.primary)
              .frame(width: 40, height: 40)
              .background(theme.surface.opacity(0.78))
              .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
              Text("Search")
                .font(.system(size: 28, weight: .heavy))
              Text("Boards, projects and components")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            }
            Spacer()
          }

          HStack {
            Image(systemName: "magnifyingglass")
              .font(.headline)
              .foregroundStyle(.secondary)
            TextField("Search board, main breaker, project, component...", text: $query)
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
          .padding(14)
          .background(theme.surface.opacity(0.78))
          .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

          searchFilters

          Picker("Search scope", selection: $scope) {
            ForEach(SearchScope.allCases) { option in
              Text(option.title).tag(option)
            }
          }
          .pickerStyle(.segmented)

          if hasResults {
            if !filteredProjects.isEmpty {
              Text("Projects")
                .font(.headline)
              ForEach(filteredProjects) { project in
                Button {
                  remember(.project, id: project.id)
                  selectedProject = project
                } label: {
                  ProjectSearchRow(
                    theme: theme,
                    project: project,
                    boardCount: linkedBoards(for: project).count,
                    displayedStatus: projectStatus(project)
                  )
                }
                .buttonStyle(.plain)
              }
            }

            if !filteredBoards.isEmpty {
              Text("Boards")
                .font(.headline)
              ForEach(filteredBoards) { board in
                Button {
                  remember(.board, id: board.id)
                  selectedBoard = board
                } label: {
                  BoardSearchRow(theme: theme, board: board, boardTypes: boardTypes, manufacturers: manufacturers)
                }
                .buttonStyle(.plain)
              }
            }

            if !filteredGroups.isEmpty {
              ComponentCatalogView(theme: theme, groups: filteredGroups, manufacturers: manufacturers, boardStore: $boards)
            }
          } else {
            VStack(spacing: 10) {
              Image(systemName: "magnifyingglass")
                .font(.system(size: 38, weight: .semibold))
              Text("No Matches")
                .font(.headline)
              Text("Try a board type, main breaker model, ABB family, rating or project name.")
                .font(.caption)
                .multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 34)
          }
          BottomTabClearance()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.36), value: filtersExpanded)
      }
      .background(theme.background.ignoresSafeArea())
      .overlay(alignment: .top) {
        TopScrollBlur(theme: theme)
      }
      .navigationTitle("")
      .navigationBarTitleDisplayMode(.inline)
      .sheet(item: $selectedProject) { project in
        ProjectDetailSheet(theme: theme, project: project, boards: $boards, boardTypes: boardTypes, manufacturers: manufacturers) { board in
          remember(.board, id: board.id)
        } onUpdateProject: { updatedProject, previousName in
          if let index = projects.firstIndex(where: { $0.id == updatedProject.id }) {
            projects[index] = updatedProject
          }
          for index in boards.indices where boards[index].project == previousName {
            boards[index].project = updatedProject.name
          }
        } onDeleteProject: {
          projects.removeAll { $0.id == project.id }
          for index in boards.indices where boards[index].project == project.name {
            boards[index].project = "No Project"
          }
          recentVisits.removeAll { $0.kind == .project && $0.itemID == project.id }
          selectedProject = nil
        }
          .presentationDetents([.large])
          .presentationDragIndicator(.visible)
      }
      .sheet(item: $selectedBoard) { board in
        if let index = boards.firstIndex(where: { $0.id == board.id }) {
          CreatedBoardScreen(theme: theme, board: $boards[index], boardTypes: boardTypes, manufacturers: manufacturers, onDeleteBoard: {
            boards.removeAll { $0.id == board.id }
            recentVisits.removeAll { $0.kind == .board && $0.itemID == board.id }
            selectedBoard = nil
          }) {
            selectedBoard = nil
          }
        } else {
          EmptyStateCard(theme: theme, title: "Board no longer exists", subtitle: "It may have been deleted from Archive.")
            .padding(18)
            .background(theme.background.ignoresSafeArea())
        }
      }
      .onChange(of: query) { newValue in
        if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && filtersExpanded {
          withAnimation(.easeInOut(duration: 0.24)) {
            filtersExpanded = false
          }
        }
      }
    }
  }

  private var searchFilters: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Filters")
          .font(.headline)
        Spacer()
        Button {
          if !activeFilters.isEmpty {
            activeFilters.removeAll()
          }
        } label: {
          Text("Clear")
            .font(.caption.bold())
            .foregroundStyle(activeFilters.isEmpty ? .secondary.opacity(0.55) : Color(hex: 0xD66A6A))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(activeFilters.isEmpty ? .clear : Color(hex: 0xD66A6A).opacity(0.14))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(activeFilters.isEmpty)
      }

      ForEach(Array(filterSections.prefix(3))) { section in
        searchFilterSection(section)
      }

      if filtersExpanded {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(Array(filterSections.dropFirst(3))) { section in
            searchFilterSection(section)
          }
        }
        .padding(.top, 2)
        .clipped()
        .transition(.asymmetric(
          insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
          removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
        ))
      }

      if filterSections.count > 3 {
        moreFiltersButton
      }
    }
    .padding(14)
    .background(theme.surface.opacity(0.58))
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .frame(maxWidth: .infinity, alignment: .leading)
    .animation(.easeInOut(duration: 0.36), value: filtersExpanded)
  }

  private var moreFiltersButton: some View {
    Button {
      withAnimation(.easeInOut(duration: 0.36)) {
        filtersExpanded.toggle()
      }
    } label: {
      HStack(spacing: 8) {
        Image(systemName: "chevron.down")
          .font(.system(size: 11, weight: .heavy))
          .rotationEffect(.degrees(filtersExpanded ? 180 : 0))
        Text(filtersExpanded ? "Show Less" : "More Filters")
        Spacer()
        Text(filtersExpanded ? "\(filterSections.count) filters" : "+\(filterSections.count - 3)")
          .foregroundStyle(.secondary)
      }
      .font(.caption.bold())
      .foregroundStyle(theme.primary)
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background(theme.primary.opacity(0.10))
      .overlay(
        RoundedRectangle(cornerRadius: 13, style: .continuous)
          .stroke(theme.primary.opacity(0.16), lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
      .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
    .buttonStyle(TabBarButtonStyle())
  }

  private func searchFilterSection(_ section: SearchFilterSection) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(section.title, systemImage: section.symbol)
        .font(.caption.bold())
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(section.options, id: \.self) { option in
            SearchFilterChip(
              theme: theme,
              title: option,
              selected: activeFilters.contains(option)
            ) {
              if activeFilters.contains(option) {
                activeFilters.remove(option)
              } else {
                activeFilters.insert(option)
              }
            }
          }
        }
      }
    }
  }

  private func remember(_ kind: RecentVisit.Kind, id: String) {
    recentVisits.removeAll { $0.kind == kind && $0.itemID == id }
    recentVisits.insert(RecentVisit(kind: kind, id: id), at: 0)
    recentVisits = Array(recentVisits.prefix(12))
  }

  private func matches(_ text: String) -> Bool {
    let queryMatches = query.isEmpty || text.localizedCaseInsensitiveContains(query)
    return queryMatches && groupedFiltersMatch(text)
  }

  private func groupedFiltersMatch(_ text: String) -> Bool {
    filterSections.allSatisfy { section in
      let selectedOptions = section.options.filter { activeFilters.contains($0) }
      guard !selectedOptions.isEmpty else { return true }
      return selectedOptions.contains { option in
        text.localizedCaseInsensitiveContains(option)
      }
    }
  }

  private func linkedBoards(for project: ProjectItem) -> [BoardDraft] {
    boards.filter { $0.project == project.name }
  }

  private func linkedProject(for board: BoardDraft) -> ProjectItem? {
    projects.first { $0.name == board.project }
  }

  private func projectSearchText(_ project: ProjectItem) -> String {
    "\(project.searchText) \(linkedBoards(for: project).map(\.searchText).joined(separator: " "))"
  }

  private func boardSearchText(_ board: BoardDraft) -> String {
    guard let project = linkedProject(for: board) else { return board.searchText }
    return "\(board.searchText) \(project.searchText) \(project.customer) \(project.name)"
  }

  private func projectStatus(_ project: ProjectItem) -> String {
    let linked = linkedBoards(for: project)
    guard !linked.isEmpty else { return project.status }
    return linked.allSatisfy(\.isCompleted) ? "Completed" : "In Progress"
  }

  private func projectSearchRank(_ status: String) -> Int {
    switch status {
    case "In Progress": return 0
    case "Design": return 1
    case "Completed": return 2
    default: return 3
    }
  }
}

struct SearchFilterSection: Identifiable {
  var id: String { title }
  let title: String
  let symbol: String
  let options: [String]
}

struct SearchFilterChip: View {
  let theme: PanelTheme
  let title: String
  let selected: Bool
  var fillsWidth = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        if selected {
          Image(systemName: "checkmark")
            .font(.system(size: 11, weight: .heavy))
        }
        Text(title)
          .font(.system(size: 13, weight: .bold))
          .lineLimit(1)
          .minimumScaleFactor(0.55)
      }
      .frame(maxWidth: fillsWidth ? .infinity : nil)
      .foregroundStyle(selected ? .white : .primary)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(selected ? theme.primary : theme.surface.opacity(0.9))
      .clipShape(Capsule())
      .overlay(
        Capsule()
          .stroke(selected ? .clear : .white.opacity(0.08), lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
  }
}

enum SearchScope: String, CaseIterable, Identifiable {
  case all
  case projects
  case boards
  case components

  var id: String { rawValue }

  var title: String {
    switch self {
    case .all: "All"
    case .projects: "Projects"
    case .boards: "Boards"
    case .components: "Parts"
    }
  }

  var includesProjects: Bool {
    self == .all || self == .projects
  }

  var includesBoards: Bool {
    self == .all || self == .boards
  }

  var includesComponents: Bool {
    self == .all || self == .components
  }
}

struct ProjectSearchRow: View {
  let theme: PanelTheme
  let project: ProjectItem
  let boardCount: Int
  let displayedStatus: String

  private var detailText: String {
    let cleanedDetail = project.detail.replacingOccurrences(
      of: #"^\d+ boards?( • )?"#,
      with: "",
      options: .regularExpression
    )
    return [
      "\(boardCount) board\(boardCount == 1 ? "" : "s")",
      cleanedDetail.isEmpty ? nil : cleanedDetail
    ]
      .compactMap { $0 }
      .joined(separator: " • ")
  }

  var body: some View {
    GlassCard(theme: theme) {
      HStack(spacing: 12) {
        ZStack {
          Circle()
            .fill(project.color.opacity(0.14))
          if let image = project.coverThumbnail {
            Image(uiImage: image)
              .resizable()
              .scaledToFill()
              .frame(width: 42, height: 42)
              .clipShape(Circle())
          } else {
            Image(systemName: "rectangle.3.group.fill")
              .foregroundStyle(project.color)
          }
        }
        .frame(width: 42, height: 42)

        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 6) {
            Text(project.name)
              .font(.system(size: 16, weight: .bold))
              .lineLimit(1)
              .minimumScaleFactor(0.65)
            if let dueDate = project.dueDate {
              DueDateBadge(date: dueDate, compact: true)
            }
          }
          Text(detailText)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }

        Spacer()

        StatusBadge(status: displayedStatus)
      }
      .frame(minHeight: 58)
    }
  }
}

struct BoardSearchRow: View {
  let theme: PanelTheme
  let board: BoardDraft
  let boardTypes: [BoardType]
  let manufacturers: [ManufacturerItem]

  private var boardType: BoardType {
    boardTypes.first { $0.name == board.type } ?? .fallback
  }

  private var manufacturer: ManufacturerItem? {
    syncedManufacturer(named: board.manufacturer, in: manufacturers)
  }

  var body: some View {
    GlassCard(theme: theme) {
      HStack(spacing: 12) {
        BoardCardThumbnail(theme: theme, boardType: boardType, color: board.color, image: board.coverThumbnail, completed: board.isCompleted)

        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 6) {
            Text(board.name)
              .font(.system(size: 16, weight: .bold))
              .lineLimit(1)
              .minimumScaleFactor(0.65)
            if let dueDate = board.dueDate {
              DueDateBadge(date: dueDate, compact: true)
            }
          }
          Text("\(board.number) • \(board.displayType) • \(board.manufacturer)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
          if let finishDate = board.finishDate {
            Text("Finished \(DateDisplay.short.string(from: finishDate))")
              .font(.caption2.bold())
              .foregroundStyle(Color(hex: 0x35E177))
              .lineLimit(1)
              .minimumScaleFactor(0.7)
          }
        }

        Spacer()

        Text(board.project == "No Project" ? "Unattached" : board.project)
          .font(.caption.bold())
          .foregroundStyle(board.project == "No Project" ? .secondary : theme.primary)
          .lineLimit(1)
          .minimumScaleFactor(0.7)

        Image(systemName: "chevron.right")
          .foregroundStyle(.secondary)
          .font(.caption.bold())
      }
      .frame(minHeight: 58)
    }
    .background(board.color.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(board.color.opacity(0.22), lineWidth: 1)
    )
  }
}

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
  @Binding var cloudAccount: PanelCloudAccount?
  @State private var componentCatalogOpen = false
  @State private var moreSheet: MoreSheet?
  @State private var themePickerOpen = false
  @State private var displaySizeOpen = false
  @State private var profileOpen = false
  @State private var warehouseStockOpen = false
  @ObservedObject private var stockStore = WarehouseStockStore.shared
  @State private var cloudAccountOpen = false

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

          Button {
            cloudAccountOpen = true
          } label: {
            MoreRow(
              theme: theme,
              symbol: cloudAccount == nil ? "person.crop.circle.badge.plus" : "checkmark.icloud.fill",
              title: "PanelVault Cloud",
              subtitle: cloudAccount.map { "\($0.companyName) • \($0.role.capitalized)" } ?? "Sign in, create a company or join an invite"
            )
          }
          .buttonStyle(PanelPressButtonStyle())

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
              title: "Warehouse Stock",
              subtitle: stockStore.account.map { "\($0.companyName) • live stock" } ?? "Connect to PanelVault Cloud"
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

          Text("Archive")
            .font(.title3.bold())

          Button {
            moreSheet = .companies
          } label: {
            MoreRow(theme: theme, symbol: "building.2", title: "All Companies", subtitle: "Contractors, manufacturers and factories")
          }
          .buttonStyle(PanelPressButtonStyle())

          Button {
            moreSheet = .customers
          } label: {
            MoreRow(theme: theme, symbol: "person.2", title: "Customers", subtitle: "Add and manage customer names")
          }
          .buttonStyle(PanelPressButtonStyle())

          Button {
            moreSheet = .manufacturers
          } label: {
            MoreRow(theme: theme, symbol: "tag.fill", title: "Manufacturers", subtitle: "Edit brands, logos and custom makers")
          }
          .buttonStyle(PanelPressButtonStyle())

          Button {
            moreSheet = .boardTypes
          } label: {
            MoreRow(theme: theme, symbol: "rectangle.3.group", title: "Board Types", subtitle: "MDB, MCC, ATS and custom categories")
          }
          .buttonStyle(PanelPressButtonStyle())

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
      .sheet(item: $moreSheet) { sheet in
        switch sheet {
        case .companies:
          CompanyManagerSheet(
            theme: theme,
            companies: $companies,
            activeCompany: $activeCompany,
            projects: projects,
            boards: $boards,
            boardTypes: boardTypes,
            manufacturers: manufacturers
          )
        case .customers:
          CustomerManagerSheet(
            theme: theme,
            customers: $customers,
            projectCustomers: uniqueCustomers,
            projects: projects,
            boards: $boards,
            boardTypes: boardTypes,
            manufacturers: manufacturers
          )
        case .manufacturers:
          ManufacturerManagerSheet(theme: theme, manufacturers: $manufacturers)
        case .boardTypes:
          BoardTypeManagerSheet(theme: theme, boardTypes: $boardTypes)
        }
      }
      .sheet(isPresented: $profileOpen) {
        ProfileEditorSheet(theme: theme, name: $profileName, company: $profileCompany, phone: $profilePhone, imageToken: $profileImageToken)
      }
      .sheet(isPresented: $warehouseStockOpen) {
        WarehouseStockSheet(theme: theme)
          .presentationDetents([.large])
          .presentationDragIndicator(.visible)
      }
      .sheet(isPresented: $cloudAccountOpen) {
        PanelCloudAccountView(theme: theme, account: $cloudAccount)
      }
    }
  }

  private var uniqueCustomers: [String] {
    Array(Set(projects.map(\.customer).filter { !$0.isEmpty })).sorted()
  }
}

enum MoreSheet: String, Identifiable {
  case companies
  case customers
  case manufacturers
  case boardTypes

  var id: String { rawValue }
}

struct PanelCloudAccount: Codable, Equatable {
  let baseURL: String
  let token: String
  let expiresAt: String
  let companyCode: String
  let companyName: String
  let userID: String
  let userName: String
  let role: String
}

private struct PanelCloudAccountEnvironmentKey: EnvironmentKey {
  static let defaultValue: PanelCloudAccount? = nil
}

extension EnvironmentValues {
  var panelCloudAccount: PanelCloudAccount? {
    get { self[PanelCloudAccountEnvironmentKey.self] }
    set { self[PanelCloudAccountEnvironmentKey.self] = newValue }
  }
}

private struct PanelCloudAccountResponse: Decodable {
  struct Company: Decodable { let code: String; let name: String }
  struct User: Decodable { let id: String; let name: String; let role: String }

  let token: String
  let expiresAt: String
  let company: Company
  let user: User
}

private struct PanelCloudErrorResponse: Decodable { let error: String }

private enum PanelCloudError: LocalizedError {
  case invalidServer
  case invalidInvite
  case invalidResponse
  case server(String)

  var errorDescription: String? {
    switch self {
    case .invalidServer:
      return "Enter a valid HTTPS PanelVault website address."
    case .invalidInvite:
      return "Paste the worker invite link, or enter both company and invite codes."
    case .invalidResponse:
      return "PanelVault Cloud returned an invalid response."
    case .server(let message):
      return message
    }
  }
}

private struct PanelCloudInvite {
  let companyCode: String
  let inviteCode: String

  static func parse(companyCode rawCompany: String, invite rawInvite: String) throws -> PanelCloudInvite {
    let company = rawCompany.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    let text = rawInvite.trimmingCharacters(in: .whitespacesAndNewlines)
    if let url = URL(string: text), let fragment = url.fragment {
      let parts = fragment.split(separator: "/").map(String.init)
      if parts.count >= 3, parts[0].lowercased() == "join" {
        return PanelCloudInvite(companyCode: parts[1].uppercased(), inviteCode: parts[2].uppercased())
      }
    }
    guard !company.isEmpty, !text.isEmpty else { throw PanelCloudError.invalidInvite }
    return PanelCloudInvite(companyCode: company, inviteCode: text.uppercased())
  }
}

private enum PanelCloudDate {
  static func decode(_ value: String?) -> Date? {
    guard let value else { return nil }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: value) { return date }
    return ISO8601DateFormatter().date(from: value)
  }

  static func encode(_ value: Date?) -> String? {
    guard let value else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: value)
  }
}

private func panelCloudColor(_ value: String?) -> UInt32 {
  guard let value else { return 0x5E78FF }
  let clean = value.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
  return UInt32(clean, radix: 16) ?? 0x5E78FF
}

private struct PanelCloudWorkspace: Codable {
  let version: Int
  let projects: [PanelCloudProject]
  let boards: [PanelCloudBoard]
}

private struct PanelCloudWorkspaceUpload: Encodable {
  let expectedVersion: Int
  let projects: [PanelCloudProject]
  let boards: [PanelCloudBoard]
}

private struct PanelCloudBoardProgressUpload: Encodable {
  let expectedVersion: Int
  let boards: [PanelCloudBoardProgress]
}

private struct PanelCloudBoardProgress: Encodable {
  let id: String
  let productionStage: String
  let cabinetChecklists: [[String]]
  let personalChecklistItems: [PanelCloudPersonalChecklistItem]

  init(board: BoardDraft) {
    id = board.id
    productionStage = board.productionStage
    cabinetChecklists = board.normalizedCabinetChecklists.map { Array($0).sorted() }
    personalChecklistItems = board.personalChecklistItems.map(PanelCloudPersonalChecklistItem.init(item:))
  }
}

private struct PanelCloudProject: Codable {
  let id: String
  let name: String
  let customer: String
  let site: String?
  let detail: String
  let status: String
  let colorHex: String?
  let dueDate: String?
  let createdAt: String?

  init(project: ProjectItem) {
    id = project.id
    name = project.name
    customer = project.customer
    site = nil
    detail = project.detail
    status = project.status
    colorHex = String(format: "#%06X", project.color.archiveHex)
    dueDate = PanelCloudDate.encode(project.dueDate)
    createdAt = nil
  }

  func project(preserving existing: ProjectItem?) -> ProjectItem {
    ProjectItem(
      id: id,
      name: name,
      customer: customer,
      detail: detail,
      status: status,
      color: Color(hex: panelCloudColor(colorHex)),
      dueDate: PanelCloudDate.decode(dueDate),
      schemeAttachments: existing?.schemeAttachments ?? [],
      coverToken: existing?.coverToken,
      photoTokens: existing?.photoTokens ?? []
    )
  }
}

private struct PanelCloudPersonalChecklistItem: Codable {
  let id: String
  let title: String
  let isDone: Bool

  init(item: PersonalChecklistItem) {
    id = item.id
    title = item.title
    isDone = item.isDone
  }
}

private struct PanelCloudBoard: Codable {
  let id: String
  let number: String
  let group: String?
  let name: String
  let customer: String
  let company: String?
  let project: String
  let type: String
  let subtype: String?
  let manufacturer: String?
  let ampere: String?
  let cabinetCount: String
  let buildFormat: String?
  let dateOut: String?
  let dueDate: String?
  let finishDate: String?
  let finishTimeHours: String?
  let mainBreakerType: String?
  let mainBreakerModel: String?
  let mainBreakerAmpere: String?
  let componentTypes: [String]?
  let colorHex: String?
  let assignedTo: String?
  let assignedName: String?
  let qaAssignedTo: String?
  let qaAssignedName: String?
  let qaStatus: String?
  let qaNote: String?
  let qaReadyAt: String?
  let qaApprovedAt: String?
  let productionStage: String?
  let cabinetChecklists: [[String]]?
  let personalChecklistItems: [PanelCloudPersonalChecklistItem]?
  let createdAt: String?

  init(board: BoardDraft) {
    id = board.id
    number = board.number
    group = board.group
    name = board.name
    customer = board.customer
    company = board.company
    project = board.project
    type = board.type
    subtype = board.subtype
    manufacturer = board.manufacturer
    ampere = board.ampere
    cabinetCount = board.cabinetCount
    buildFormat = board.buildFormat
    dateOut = PanelCloudDate.encode(board.dateOut)
    dueDate = PanelCloudDate.encode(board.dueDate)
    finishDate = PanelCloudDate.encode(board.finishDate)
    finishTimeHours = board.finishTimeHours
    mainBreakerType = board.mainBreakerType
    mainBreakerModel = board.mainBreakerModel
    mainBreakerAmpere = board.mainBreakerAmpere
    componentTypes = board.componentTypes
    colorHex = String(format: "#%06X", board.color.archiveHex)
    assignedTo = board.assignedTo
    assignedName = board.assignedName
    qaAssignedTo = board.qaAssignedTo
    qaAssignedName = board.qaAssignedName
    qaStatus = board.qaStatus
    qaNote = board.qaNote
    qaReadyAt = PanelCloudDate.encode(board.qaReadyAt)
    qaApprovedAt = PanelCloudDate.encode(board.qaApprovedAt)
    productionStage = board.productionStage
    cabinetChecklists = board.normalizedCabinetChecklists.map { Array($0).sorted() }
    personalChecklistItems = board.personalChecklistItems.map(PanelCloudPersonalChecklistItem.init(item:))
    createdAt = nil
  }

  func board(preserving existing: BoardDraft?) -> BoardDraft {
    BoardDraft(
      id: id,
      number: number,
      group: group ?? "",
      name: name,
      customer: customer,
      company: company ?? "",
      project: project,
      type: type,
      subtype: subtype ?? BoardSubtypeCatalog.defaultSubtype,
      manufacturer: manufacturer ?? "Generic",
      ampere: ampere ?? mainBreakerAmpere ?? "630A",
      cabinetCount: cabinetCount,
      buildFormat: buildFormat ?? "Panels",
      dateOut: PanelCloudDate.decode(dateOut) ?? Date(),
      dueDate: PanelCloudDate.decode(dueDate),
      finishDate: PanelCloudDate.decode(finishDate),
      finishTimeHours: finishTimeHours ?? "",
      mainBreakerType: mainBreakerType ?? "Main Breaker",
      mainBreakerModel: mainBreakerModel ?? "",
      mainBreakerAmpere: mainBreakerAmpere ?? ampere ?? "630A",
      componentTypes: componentTypes ?? [],
      color: Color(hex: panelCloudColor(colorHex)),
      coverToken: existing?.coverToken,
      photoTokens: existing?.photoTokens ?? [],
      schemeAttachments: existing?.schemeAttachments ?? [],
      completedChecklistItems: [],
      personalChecklistItems: (personalChecklistItems ?? []).map {
        PersonalChecklistItem(id: $0.id, title: $0.title, isDone: $0.isDone)
      },
      cabinetChecklists: (cabinetChecklists ?? []).map(Set.init),
      assignedTo: assignedTo,
      assignedName: assignedName ?? "",
      qaAssignedTo: qaAssignedTo,
      qaAssignedName: qaAssignedName ?? "",
      qaStatus: qaStatus ?? "pending",
      qaNote: qaNote ?? "",
      qaReadyAt: PanelCloudDate.decode(qaReadyAt),
      qaApprovedAt: PanelCloudDate.decode(qaApprovedAt),
      productionStage: productionStage ?? (qaStatus == "approved" ? "complete" : "design")
    )
  }
}

private struct PanelCloudQARequest: Encodable {
  let boardID: String
  let action: String
  let note: String
}

private struct PanelCloudQAResponse: Decodable {
  let board: PanelCloudBoard
}

private struct PanelCloudStageRequest: Encodable {
  let boardID: String
  let stageID: String
}

private struct PanelCloudClient {
  func signIn(baseURL: String, companyCode: String, name: String, password: String) async throws -> PanelCloudAccount {
    try await accountRequest(
      baseURL: baseURL,
      path: "/api/mobile/login",
      body: ["companyCode": companyCode, "name": name, "password": password]
    )
  }

  func createCompany(baseURL: String, companyName: String, name: String, password: String) async throws -> PanelCloudAccount {
    try await accountRequest(
      baseURL: baseURL,
      path: "/api/mobile/company",
      body: ["companyName": companyName, "name": name, "password": password]
    )
  }

  func joinCompany(
    baseURL: String,
    companyCode: String,
    inviteCode: String,
    name: String,
    password: String
  ) async throws -> PanelCloudAccount {
    let invite = try PanelCloudInvite.parse(companyCode: companyCode, invite: inviteCode)
    return try await accountRequest(
      baseURL: baseURL,
      path: "/api/mobile/join",
      body: [
        "companyCode": invite.companyCode,
        "inviteCode": invite.inviteCode,
        "name": name,
        "password": password,
      ]
    )
  }

  func downloadWorkspace(account: PanelCloudAccount) async throws -> PanelCloudWorkspace {
    try await authenticatedRequest(account: account, path: "/api/sync/workspace", method: "GET", body: nil)
  }

  func uploadWorkspace(
    account: PanelCloudAccount,
    expectedVersion: Int,
    projects: [ProjectItem],
    boards: [BoardDraft]
  ) async throws -> PanelCloudWorkspace {
    let payload = PanelCloudWorkspaceUpload(
      expectedVersion: expectedVersion,
      projects: projects.map(PanelCloudProject.init(project:)),
      boards: boards.map(PanelCloudBoard.init(board:))
    )
    return try await authenticatedRequest(
      account: account,
      path: "/api/sync/workspace",
      method: "POST",
      body: try JSONEncoder().encode(payload)
    )
  }

  func uploadBoardProgress(
    account: PanelCloudAccount,
    expectedVersion: Int,
    boards: [BoardDraft]
  ) async throws -> PanelCloudWorkspace {
    let assignedBoards = boards.filter { $0.assignedTo == account.userID }
    let payload = PanelCloudBoardProgressUpload(
      expectedVersion: expectedVersion,
      boards: assignedBoards.map(PanelCloudBoardProgress.init(board:))
    )
    return try await authenticatedRequest(
      account: account,
      path: "/api/sync/board-progress",
      method: "POST",
      body: try JSONEncoder().encode(payload)
    )
  }

  func submitQA(account: PanelCloudAccount, boardID: String, action: String, note: String) async throws -> PanelCloudBoard {
    let payload = PanelCloudQARequest(boardID: boardID, action: action, note: note)
    let response: PanelCloudQAResponse = try await authenticatedRequest(
      account: account,
      path: "/api/board-qa",
      method: "POST",
      body: try JSONEncoder().encode(payload)
    )
    return response.board
  }

  func submitStage(account: PanelCloudAccount, boardID: String, stageID: String) async throws -> PanelCloudBoard {
    let payload = PanelCloudStageRequest(boardID: boardID, stageID: stageID)
    let response: PanelCloudQAResponse = try await authenticatedRequest(
      account: account,
      path: "/api/board-stage",
      method: "POST",
      body: try JSONEncoder().encode(payload)
    )
    return response.board
  }

  private func accountRequest(baseURL: String, path: String, body: [String: String]) async throws -> PanelCloudAccount {
    let base = try normalizedBaseURL(baseURL)
    guard let url = URL(string: path, relativeTo: base) else { throw PanelCloudError.invalidServer }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 30
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(body)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw PanelCloudError.invalidResponse }
    guard 200..<300 ~= http.statusCode else {
      let detail = (try? JSONDecoder().decode(PanelCloudErrorResponse.self, from: data).error)
        ?? "PanelVault Cloud request failed (\(http.statusCode))."
      throw PanelCloudError.server(detail)
    }
    guard let result = try? JSONDecoder().decode(PanelCloudAccountResponse.self, from: data) else {
      throw PanelCloudError.invalidResponse
    }
    return PanelCloudAccount(
      baseURL: base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
      token: result.token,
      expiresAt: result.expiresAt,
      companyCode: result.company.code,
      companyName: result.company.name,
      userID: result.user.id,
      userName: result.user.name,
      role: result.user.role
    )
  }

  private func authenticatedRequest<Result: Decodable>(
    account: PanelCloudAccount,
    path: String,
    method: String,
    body: Data?
  ) async throws -> Result {
    let base = try normalizedBaseURL(account.baseURL)
    guard let url = URL(string: path, relativeTo: base) else { throw PanelCloudError.invalidServer }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = 30
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("Bearer \(account.token)", forHTTPHeaderField: "Authorization")
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = body
    }
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw PanelCloudError.invalidResponse }
    guard 200..<300 ~= http.statusCode else {
      let detail = (try? JSONDecoder().decode(PanelCloudErrorResponse.self, from: data).error)
        ?? "PanelVault Cloud request failed (\(http.statusCode))."
      throw PanelCloudError.server(detail)
    }
    guard let result = try? JSONDecoder().decode(Result.self, from: data) else {
      throw PanelCloudError.invalidResponse
    }
    return result
  }

  private func normalizedBaseURL(_ value: String) throws -> URL {
    var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if !text.contains("://") { text = "https://\(text)" }
    guard let url = URL(string: text),
          ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
          let host = url.host else { throw PanelCloudError.invalidServer }
    if url.scheme?.lowercased() == "http", !Self.isPrivateDevelopmentHost(host) {
      throw PanelCloudError.invalidServer
    }
    return url
  }

  private static func isPrivateDevelopmentHost(_ rawHost: String) -> Bool {
    let host = rawHost.lowercased()
    if host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".local") {
      return true
    }
    let octets = host.split(separator: ".").compactMap { Int($0) }
    guard octets.count == 4 else { return false }
    if octets[0] == 10 || (octets[0] == 192 && octets[1] == 168) { return true }
    return octets[0] == 172 && (16...31).contains(octets[1])
  }
}

enum PanelCloudAccountKeychain {
  private static let service = "com.panelvault.main.cloud"
  private static let account = "active-account"

  static func load() -> PanelCloudAccount? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
          let data = result as? Data else { return nil }
    return try? JSONDecoder().decode(PanelCloudAccount.self, from: data)
  }

  @discardableResult
  static func save(_ value: PanelCloudAccount?) -> Bool {
    let base: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    SecItemDelete(base as CFDictionary)
    guard let value else { return true }
    guard let data = try? JSONEncoder().encode(value) else { return false }
    var insert = base
    insert[kSecValueData as String] = data
    insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
  }
}

struct PanelCloudAccountView: View {
  private enum Mode: String, CaseIterable, Identifiable {
    case signIn = "Sign In"
    case create = "Create"
    case join = "Join"
    var id: String { rawValue }
  }

  let theme: PanelTheme
  @Binding var account: PanelCloudAccount?
  @Environment(\.dismiss) private var dismiss
  @State private var mode: Mode = .signIn
  @State private var server = UserDefaults.standard.string(forKey: "panelvault.cloudServer") ?? ""
  @State private var companyCode = ""
  @State private var companyName = ""
  @State private var inviteCode = ""
  @State private var name = ""
  @State private var password = ""
  @State private var isConnecting = false
  @State private var message = ""

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          if let account { connectedView(account) } else { accountForm }
        }
        .padding(18)
      }
      .scrollDismissesKeyboard(.interactively)
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("PanelVault Cloud")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
      }
    }
    .tint(theme.primary)
    .preferredColorScheme(theme.colorScheme)
  }

  private var accountForm: some View {
    VStack(alignment: .leading, spacing: 16) {
      GlassCard(theme: theme) {
        Label {
          VStack(alignment: .leading, spacing: 3) {
            Text("One account everywhere").font(.headline.bold())
            Text("Use the same company and worker accounts as the website.")
              .font(.subheadline).foregroundStyle(.secondary)
          }
        } icon: {
          Image(systemName: "person.2.badge.gearshape.fill")
            .font(.title2).foregroundStyle(theme.secondary)
        }
      }

      Picker("Account action", selection: $mode) {
        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
      }
      .pickerStyle(.segmented)

      VStack(spacing: 1) {
        field("Website address", text: $server, symbol: "network")
          .textInputAutocapitalization(.never).keyboardType(.URL).autocorrectionDisabled()
        switch mode {
        case .signIn:
          field("Company code", text: $companyCode, symbol: "building.2.fill")
            .textInputAutocapitalization(.characters).autocorrectionDisabled()
        case .create:
          field("Company name", text: $companyName, symbol: "building.2.crop.circle.fill")
            .textContentType(.organizationName)
        case .join:
          field("Company code (optional with full link)", text: $companyCode, symbol: "building.2.fill")
            .textInputAutocapitalization(.characters).autocorrectionDisabled()
          field("Paste worker invite link or code", text: $inviteCode, symbol: "link")
            .textInputAutocapitalization(.never).autocorrectionDisabled()
        }
        field("Your name", text: $name, symbol: "person.fill").textContentType(.username)
        secureField("Password", text: $password, symbol: "lock.fill").textContentType(.password)
      }
      .clipShape(RoundedRectangle(cornerRadius: theme.radiusCard, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: theme.radiusCard, style: .continuous).stroke(theme.cardBorder))

      if !message.isEmpty {
        Label(message, systemImage: "exclamationmark.circle.fill")
          .font(.footnote.bold()).foregroundStyle(theme.danger)
      }

      Button(action: submit) {
        HStack(spacing: 9) {
          if isConnecting { ProgressView().tint(.white) }
          Text(isConnecting ? "Connecting" : submitTitle)
          if !isConnecting { Image(systemName: "arrow.right") }
        }
        .font(.headline.bold()).frame(maxWidth: .infinity).frame(height: 50)
      }
      .buttonStyle(.borderedProminent)
      .disabled(!canSubmit || isConnecting)
    }
  }

  private func connectedView(_ account: PanelCloudAccount) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      GlassCard(theme: theme) {
        HStack(spacing: 14) {
          Image(systemName: "checkmark.icloud.fill")
            .font(.system(size: 28, weight: .semibold)).foregroundStyle(theme.success)
            .frame(width: 50, height: 50).background(theme.success.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
          VStack(alignment: .leading, spacing: 4) {
            Text(account.companyName).font(.title3.bold())
            Text("\(account.userName)  •  \(account.role.capitalized)")
              .font(.subheadline).foregroundStyle(.secondary)
          }
        }
      }
      GlassCard(theme: theme) {
        VStack(spacing: 12) {
          detailRow("Company code", account.companyCode)
          Divider()
          detailRow("Website", account.baseURL)
        }
      }
      Text("This account is shared with the website and Warehouse app. The login token is stored in this iPhone's Keychain.")
        .font(.footnote).foregroundStyle(.secondary)
      Button(role: .destructive) {
        PanelCloudAccountKeychain.save(nil)
        self.account = nil
      } label: {
        Text("Disconnect This iPhone").font(.headline.bold()).frame(maxWidth: .infinity).frame(height: 46)
      }
      .buttonStyle(.bordered)
    }
  }

  private func field(_ prompt: String, text: Binding<String>, symbol: String) -> some View {
    HStack(spacing: 12) {
      Image(systemName: symbol).foregroundStyle(theme.secondary).frame(width: 22)
      TextField(prompt, text: text)
    }
    .padding(.horizontal, 15).frame(height: 54).background(theme.surface)
  }

  private func secureField(_ prompt: String, text: Binding<String>, symbol: String) -> some View {
    HStack(spacing: 12) {
      Image(systemName: symbol).foregroundStyle(theme.secondary).frame(width: 22)
      SecureField(prompt, text: text)
    }
    .padding(.horizontal, 15).frame(height: 54).background(theme.surface)
  }

  private func detailRow(_ label: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(label).foregroundStyle(.secondary)
      Spacer()
      Text(value).fontWeight(.semibold).multilineTextAlignment(.trailing)
    }
  }

  private var canSubmit: Bool {
    let common = !server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && password.count >= 6
    switch mode {
    case .signIn: return common && !companyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    case .create: return common && !companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    case .join: return common && !inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }

  private var submitTitle: String {
    switch mode {
    case .signIn: return "Sign In"
    case .create: return "Create Company"
    case .join: return "Join Company"
    }
  }

  private func submit() {
    message = ""
    isConnecting = true
    let address = server.trimmingCharacters(in: .whitespacesAndNewlines)
    UserDefaults.standard.set(address, forKey: "panelvault.cloudServer")
    Task {
      do {
        let client = PanelCloudClient()
        let result: PanelCloudAccount
        switch mode {
        case .signIn:
          result = try await client.signIn(
            baseURL: address,
            companyCode: companyCode.trimmingCharacters(in: .whitespacesAndNewlines),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
          )
        case .create:
          result = try await client.createCompany(
            baseURL: address,
            companyName: companyName.trimmingCharacters(in: .whitespacesAndNewlines),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
          )
        case .join:
          result = try await client.joinCompany(
            baseURL: address,
            companyCode: companyCode.trimmingCharacters(in: .whitespacesAndNewlines),
            inviteCode: inviteCode.trimmingCharacters(in: .whitespacesAndNewlines),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
          )
        }
        guard PanelCloudAccountKeychain.save(result) else {
          throw PanelCloudError.server("The account connected, but its secure login could not be saved on this iPhone.")
        }
        account = result
        password = ""
      } catch {
        message = error.localizedDescription
      }
      isConnecting = false
    }
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

struct SimpleListRow: Identifiable {
  let id = UUID()
  let symbol: String
  let title: String
  let subtitle: String
  let color: Color
}

struct SimpleListSheet: View {
  let theme: PanelTheme
  let title: String
  let rows: [SimpleListRow]
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 10) {
          if rows.isEmpty {
            EmptyStateCard(theme: theme, title: "Nothing here yet", subtitle: "Create a project or board and this list will fill in.")
          }
          ForEach(rows) { row in
            GlassCard(theme: theme) {
              HStack(spacing: 12) {
                Image(systemName: row.symbol)
                  .foregroundStyle(row.color)
                  .frame(width: 40, height: 40)
                  .background(row.color.opacity(0.14))
                .clipShape(Circle())
                VStack(alignment: .leading, spacing: 4) {
                  Text(row.title).font(.headline)
                  if !row.subtitle.isEmpty {
                    Text(row.subtitle).font(.caption).foregroundStyle(.secondary)
                  }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
              }
            }
          }
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle(title)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
    }
  }
}

struct CustomerManagerSheet: View {
  let theme: PanelTheme
  @Binding var customers: [CustomerItem]
  let projectCustomers: [String]
  let projects: [ProjectItem]
  @Binding var boards: [BoardDraft]
  let boardTypes: [BoardType]
  let manufacturers: [ManufacturerItem]
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var customerKind = "Company"
  @State private var contactName = ""
  @State private var phone = ""
  @State private var note = ""
  @State private var selectedColorHex: UInt32 = 0x5E78FF
  @State private var selectedCustomer: CustomerItem?

  private var allCustomers: [CustomerItem] {
    let existingNames = Set(customers.map { $0.name.lowercased() })
    let inferred = projectCustomers
      .filter { !existingNames.contains($0.lowercased()) }
      .map { customerName in
        let projectColor = projects.first {
          $0.customer.localizedCaseInsensitiveCompare(customerName) == .orderedSame
        }?.color.archiveHex ?? 0x5E78FF
        return CustomerItem(id: "project-customer-\(customerName)", name: customerName, kind: "Company", contactName: "", phone: "", note: "From projects", colorHex: projectColor)
      }
    return customers + inferred
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          GlassCard(theme: theme) {
            VStack(alignment: .leading, spacing: 12) {
              TextField("Customer name", text: $name)
                .textInputAutocapitalization(.words)
              Picker("Type", selection: $customerKind) {
                ForEach(["Company", "Person"], id: \.self) { Text($0) }
              }
              if customerKind == "Company" {
                TextField("Contact person", text: $contactName)
                  .textInputAutocapitalization(.words)
              }
              TextField("Phone", text: $phone)
                .keyboardType(.phonePad)
              TextField("Note", text: $note)
              ColorSwatchPicker(title: "Customer color", selectedHex: $selectedColorHex)
              Button {
                addCustomer()
              } label: {
                Label("Add Customer", systemImage: "plus")
                  .frame(maxWidth: .infinity)
              }
              .buttonStyle(.borderedProminent)
              .tint(theme.primary)
              .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
          }

          if allCustomers.isEmpty {
            EmptyStateCard(theme: theme, title: "No customers yet", subtitle: "Add customer names here and they will appear as suggestions.")
          } else {
            ForEach(allCustomers) { customer in
              CustomerManagerRow(
                theme: theme,
                customer: customer,
                summary: customerSummary(customer.name),
                canDelete: customers.contains(where: { $0.id == customer.id }),
                open: {
                  openCustomer(customer)
                },
                delete: {
                  customers.removeAll { $0.id == customer.id }
                }
              )
            }
          }
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Customers")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
    }
    .sheet(item: $selectedCustomer) { customer in
      if let customerBinding = binding(for: customer.id) {
        CustomerArchiveDetailSheet(
          theme: theme,
          title: customer.name,
          subtitle: customer.profileSummary,
          symbol: customer.kind == "Person" ? "person.fill" : "building.2.fill",
          color: customer.color,
          projects: projects.filter { $0.customer.localizedCaseInsensitiveCompare(customer.name) == .orderedSame },
          boardIDs: boards.filter { $0.customer.localizedCaseInsensitiveCompare(customer.name) == .orderedSame }.map(\.id),
          boards: $boards,
          boardTypes: boardTypes,
          manufacturers: manufacturers,
          editableCustomer: customerBinding
        )
      }
    }
  }

  private func openCustomer(_ customer: CustomerItem) {
    if customers.contains(where: { $0.id == customer.id }) {
      selectedCustomer = customer
      return
    }

    let savedCustomer = CustomerItem(
      name: customer.name,
      kind: customer.kind,
      contactName: customer.contactName,
      phone: customer.phone,
      note: customer.note,
      contacts: customer.contacts,
      colorHex: customer.colorHex
    )
    customers.insert(savedCustomer, at: 0)
    selectedCustomer = savedCustomer
  }

  private func binding(for customerID: String) -> Binding<CustomerItem>? {
    guard customers.contains(where: { $0.id == customerID }) else { return nil }
    return Binding {
      customers.first(where: { $0.id == customerID }) ?? CustomerItem(id: customerID, name: "Customer")
    } set: { updatedCustomer in
      guard let index = customers.firstIndex(where: { $0.id == customerID }) else { return }
      customers[index] = updatedCustomer
    }
  }

  private func addCustomer() {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else { return }
    customers.removeAll { $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame }
    customers.insert(CustomerItem(name: trimmedName, kind: customerKind, contactName: contactName.trimmingCharacters(in: .whitespacesAndNewlines), phone: phone.trimmingCharacters(in: .whitespacesAndNewlines), note: note.trimmingCharacters(in: .whitespacesAndNewlines), colorHex: selectedColorHex), at: 0)
    name = ""
    customerKind = "Company"
    contactName = ""
    phone = ""
    note = ""
    selectedColorHex = 0x5E78FF
  }

  private func customerSummary(_ customerName: String) -> String {
    let projectCount = projects.filter { $0.customer.localizedCaseInsensitiveCompare(customerName) == .orderedSame }.count
    let boardCount = boards.filter { $0.customer.localizedCaseInsensitiveCompare(customerName) == .orderedSame }.count
    return "\(projectCount) project\(projectCount == 1 ? "" : "s") • \(boardCount) board\(boardCount == 1 ? "" : "s")"
  }
}

struct CustomerManagerRow: View {
  let theme: PanelTheme
  let customer: CustomerItem
  let summary: String
  let canDelete: Bool
  let open: () -> Void
  let delete: () -> Void

  var body: some View {
    GlassCard(theme: theme) {
      HStack(spacing: 12) {
        Button(action: open) {
          HStack(spacing: 12) {
            CompanyColorLogo(color: customer.color, symbol: customer.kind == "Person" ? "person.fill" : "building.2.fill")
            VStack(alignment: .leading, spacing: 4) {
              Text(customer.name)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
              Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
              if !customer.phone.isEmpty {
                Label([customer.contactName.isEmpty ? nil : customer.contactName, customer.phone].compactMap { $0 }.joined(separator: " • "), systemImage: "phone.fill")
                  .font(.caption)
                  .foregroundStyle(customer.color)
                  .lineLimit(1)
                  .minimumScaleFactor(0.72)
              }
              if customer.kind == "Company", !customer.contacts.isEmpty {
                Label("\(customer.contacts.count) contact\(customer.contacts.count == 1 ? "" : "s")", systemImage: "person.2.fill")
                  .font(.caption)
                  .foregroundStyle(customer.color.opacity(0.86))
              }
              if !customer.note.isEmpty {
                Text(customer.note)
                  .font(.caption)
                  .foregroundStyle(.secondary.opacity(0.78))
                  .lineLimit(2)
                  .minimumScaleFactor(0.72)
              }
            }
            Spacer(minLength: 8)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if canDelete {
          Menu {
            Button(role: .destructive, action: delete) {
              Label("Delete Customer", systemImage: "trash")
            }
          } label: {
            Image(systemName: "ellipsis")
              .font(.system(size: 17, weight: .heavy))
              .foregroundStyle(.secondary)
              .frame(width: 34, height: 34)
              .background(theme.surface.opacity(0.72))
              .clipShape(Circle())
          }
          .buttonStyle(.plain)
        } else {
          Image(systemName: "chevron.right")
            .foregroundStyle(.secondary)
            .frame(width: 34, height: 34)
        }
      }
    }
    .frame(maxWidth: .infinity)
  }
}

struct CustomerArchiveDetailSheet: View {
  let theme: PanelTheme
  let title: String
  let subtitle: String
  let symbol: String
  let color: Color
  let projects: [ProjectItem]
  let boardIDs: [String]
  @Binding var boards: [BoardDraft]
  let boardTypes: [BoardType]
  let manufacturers: [ManufacturerItem]
  var editableCustomer: Binding<CustomerItem>? = nil
  @Environment(\.dismiss) private var dismiss
  @State private var selectedBoardID: String?
  @State private var editOpen = false

  private var visibleBoards: [BoardDraft] {
    boards.filter { boardIDs.contains($0.id) }
  }

  private var displayCustomer: CustomerItem? {
    editableCustomer?.wrappedValue
  }

  private var displayTitle: String {
    displayCustomer?.name ?? title
  }

  private var displaySubtitle: String {
    displayCustomer?.profileSummary ?? subtitle
  }

  private var displayColor: Color {
    displayCustomer?.color ?? color
  }

  private var displaySymbol: String {
    guard let displayCustomer else { return symbol }
    return displayCustomer.kind == "Person" ? "person.fill" : "building.2.fill"
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          HStack(spacing: 14) {
            CompanyColorLogo(color: displayColor, symbol: displaySymbol)
            VStack(alignment: .leading, spacing: 4) {
              Text(displayTitle)
                .font(.largeTitle.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
              Text("\(projects.count) project\(projects.count == 1 ? "" : "s") • \(visibleBoards.count) board\(visibleBoards.count == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
              if !displaySubtitle.isEmpty {
                Text(displaySubtitle)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }

          Text("Projects")
            .font(.headline)
          if projects.isEmpty {
            EmptyStateCard(theme: theme, title: "No projects", subtitle: "Projects for this name will show here.")
          } else {
            ForEach(projects) { project in
              ProjectDashboardRow(theme: theme, project: project)
            }
          }

          Text("Boards")
            .font(.headline)
          if visibleBoards.isEmpty {
            EmptyStateCard(theme: theme, title: "No boards", subtitle: "Boards for this name will show here.")
          } else {
            ForEach(visibleBoards) { board in
              Button {
                selectedBoardID = board.id
              } label: {
                DashboardBoardRecentRow(theme: theme, board: board, boardTypes: boardTypes, manufacturers: manufacturers)
              }
              .buttonStyle(.plain)
            }
          }
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle(displayTitle)
      .toolbar {
        if editableCustomer != nil {
          ToolbarItem(placement: .topBarLeading) {
            Button("Edit") { editOpen = true }
              .fontWeight(.bold)
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
      .sheet(isPresented: $editOpen) {
        if let editableCustomer {
          CustomerEditSheet(theme: theme, customer: editableCustomer)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
      }
      .sheet(item: Binding(
        get: { selectedBoardID.map(BoardIDSelection.init(id:)) },
        set: { selectedBoardID = $0?.id }
      )) { selection in
        if let index = boards.firstIndex(where: { $0.id == selection.id }) {
          CreatedBoardScreen(theme: theme, board: $boards[index], boardTypes: boardTypes, manufacturers: manufacturers) {
            selectedBoardID = nil
          }
        }
      }
    }
  }
}

struct CustomerEditSheet: View {
  let theme: PanelTheme
  @Binding var customer: CustomerItem
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          CreationFormSection(theme: theme, title: "Customer Profile", symbol: customer.kind == "Person" ? "person.fill" : "building.2.fill") {
            CreationFieldShell(theme: theme, title: "Customer type", symbol: "person.2.fill") {
              Picker("Customer type", selection: $customer.kind) {
                Text("Person").tag("Person")
                Text("Company").tag("Company")
              }
              .pickerStyle(.segmented)
              .frame(maxWidth: 190)
            }
            CreationTextInput(theme: theme, title: "Phone", placeholder: "Phone number", symbol: "phone.fill", text: $customer.phone, keyboardType: .phonePad)
            if customer.kind == "Company" {
              CreationTextInput(theme: theme, title: "Primary contact", placeholder: "Contact person", symbol: "person.crop.circle.fill", text: $customer.contactName, capitalization: .words)
            }
            CreationTextInput(theme: theme, title: "Note", placeholder: "Optional note", symbol: "note.text", text: $customer.note, capitalization: .sentences)
            ColorSwatchPicker(title: "Customer color", selectedHex: $customer.colorHex)
          }

          if customer.kind == "Company" {
            CreationFormSection(theme: theme, title: "Company People", symbol: "person.2.fill", subtitle: "People you can contact at this company") {
              if customer.contacts.isEmpty {
                Text("No contact people yet")
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.secondary)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .padding(.vertical, 4)
              }

              ForEach($customer.contacts) { $contact in
                CustomerContactEditorRow(theme: theme, contact: $contact) {
                  customer.contacts.removeAll { $0.id == contact.id }
                }
              }

              Button {
                withAnimation(.easeOut(duration: 0.18)) {
                  customer.contacts.append(CustomerContact())
                }
              } label: {
                Label("Add Contact Person", systemImage: "person.badge.plus")
                  .font(.system(size: 14, weight: .bold))
                  .frame(maxWidth: .infinity)
                  .padding(.vertical, 11)
              }
              .buttonStyle(.borderedProminent)
              .tint(theme.primary)
            }
          }

          BottomTabClearance(height: 56)
        }
        .padding(18)
      }
      .scrollDismissesKeyboard(.interactively)
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Edit \(customer.name)")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
            .fontWeight(.bold)
        }
      }
    }
  }
}

struct CustomerContactEditorRow: View {
  let theme: PanelTheme
  @Binding var contact: CustomerContact
  let onDelete: () -> Void

  var body: some View {
    VStack(spacing: 9) {
      HStack(spacing: 8) {
        Image(systemName: "person.crop.circle.fill")
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(theme.primary)
        TextField("Full name", text: $contact.name)
          .textInputAutocapitalization(.words)
        Button(role: .destructive, action: onDelete) {
          Image(systemName: "trash")
            .font(.system(size: 13, weight: .bold))
            .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
      }
      HStack(spacing: 9) {
        TextField("Role, e.g. site manager", text: $contact.role)
          .textInputAutocapitalization(.words)
        TextField("Phone", text: $contact.phone)
          .keyboardType(.phonePad)
      }
      .font(.system(size: 13, weight: .semibold))
    }
    .padding(12)
    .background(theme.background.opacity(0.44))
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.07), lineWidth: 1))
  }
}

struct BoardIDSelection: Identifiable {
  let id: String
}

struct ManufacturerManagerSheet: View {
  let theme: PanelTheme
  @Binding var manufacturers: [ManufacturerItem]
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var selectedColorHex: UInt32 = 0x5E78FF
  @State private var selectedManufacturerID: String?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          GlassCard(theme: theme) {
            VStack(alignment: .leading, spacing: 12) {
              TextField("Manufacturer name", text: $name)
                .textInputAutocapitalization(.words)
              ColorSwatchPicker(title: "Logo color", selectedHex: $selectedColorHex)
              Button {
                addManufacturer()
              } label: {
                Label("Add Manufacturer", systemImage: "plus")
                  .frame(maxWidth: .infinity)
              }
              .buttonStyle(.borderedProminent)
              .tint(theme.primary)
              .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
          }

          ForEach($manufacturers) { $manufacturer in
            ManufacturerEditorRow(theme: theme, manufacturer: $manufacturer) {
              manufacturers.removeAll { $0.id == manufacturer.id }
            } showDetails: {
              selectedManufacturerID = manufacturer.id
            }
          }
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Manufacturers")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
      .sheet(item: selectedManufacturerBinding) { selection in
        if let manufacturer = manufacturers.first(where: { $0.id == selection.id }) {
          ManufacturerDetailSheet(theme: theme, manufacturer: manufacturer)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
      }
    }
  }

  private var selectedManufacturerBinding: Binding<ManufacturerSelection?> {
    Binding {
      selectedManufacturerID.map(ManufacturerSelection.init(id:))
    } set: { selection in
      selectedManufacturerID = selection?.id
    }
  }

  private func addManufacturer() {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else { return }
    manufacturers.removeAll { $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame }
    manufacturers.insert(ManufacturerItem(name: trimmedName, colorHex: selectedColorHex), at: 0)
    name = ""
    selectedColorHex = 0x5E78FF
  }
}

struct ManufacturerEditorRow: View {
  let theme: PanelTheme
  @Binding var manufacturer: ManufacturerItem
  let delete: () -> Void
  let showDetails: () -> Void
  @State private var selectedItem: PhotosPickerItem?

  var body: some View {
    GlassCard(theme: theme) {
      HStack(spacing: 12) {
        PhotosPicker(selection: $selectedItem, matching: .images) {
          ManufacturerLogoView(manufacturer: manufacturer)
        }
        .buttonStyle(.plain)
        .onChange(of: selectedItem) { item in
          loadImage(from: item)
        }

        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 7) {
            Image(systemName: "tag.fill")
              .font(.caption.bold())
              .foregroundStyle(manufacturer.color)
            TextField("Manufacturer", text: $manufacturer.name)
              .font(.headline)
              .lineLimit(1)
              .minimumScaleFactor(0.7)
          }
          Menu {
            ForEach(AccentPalette.choices) { choice in
              Button(choice.name) {
                manufacturer.colorHex = choice.id
              }
            }
          } label: {
            HStack(spacing: 6) {
              Circle()
                .fill(manufacturer.color)
                .frame(width: 12, height: 12)
              Text("Color")
                .font(.caption.bold())
              Image(systemName: "chevron.down")
                .font(.caption2.bold())
            }
            .foregroundStyle(.secondary)
          }
          if manufacturer.imageToken != nil {
            Button(role: .destructive) {
              removeLogo()
            } label: {
              Label("Remove Logo", systemImage: "trash")
                .font(.caption.bold())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(hex: 0xD66A6A))
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Button(action: showDetails) {
          Image(systemName: "info.circle.fill")
            .font(.title3)
            .foregroundStyle(theme.primary)
            .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)

        DeleteIconButton(theme: theme, action: delete)
      }
      .frame(maxWidth: .infinity)
    }
  }

  private func loadImage(from item: PhotosPickerItem?) {
    Task {
      guard item == selectedItem else { return }
      guard let data = try? await item?.loadTransferable(type: Data.self),
            let image = (await ImageStore.imported(from: data))?.image else { return }
      await MainActor.run {
        if item == selectedItem {
          manufacturer.image = image
        }
      }
    }
  }

  private func removeLogo() {
    selectedItem = nil
    ImageStore.shared.delete(manufacturer.imageToken)
    manufacturer.imageToken = nil
  }
}

struct ManufacturerSelection: Identifiable {
  let id: String
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

struct ComponentSummaryCard: View {
  let theme: PanelTheme
  let component: PanelComponent
  let color: Color

  var body: some View {
    GlassCard(theme: theme) {
      HStack(spacing: 12) {
        Image(systemName: ComponentIcon.symbol(for: component.type))
          .foregroundStyle(color)
          .frame(width: 40, height: 40)
          .background(color.opacity(0.14))
          .clipShape(Circle())
        VStack(alignment: .leading, spacing: 4) {
          Text(component.displayName)
            .font(.headline)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
          Text(component.detailLine)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        Spacer()
      }
    }
  }
}

enum ComponentIcon {
  /// Order matters: the most specific match has to win first. "Power Analyzer"
  /// contains "power" and would otherwise draw the PSU plug, and a soft starter
  /// would otherwise share the VFD speedometer.
  static func symbol(for type: String) -> String {
    let lowered = type.lowercased()

    // Drives and motor control.
    if lowered.contains("vfd") || lowered.contains("drive") { return "speedometer" }
    if lowered.contains("soft starter") { return "chart.line.uptrend.xyaxis" }
    if lowered.contains("motor starter") { return "gearshape.fill" }
    if lowered.contains("mpcb") || lowered.contains("motor protection") { return "gearshape.2.fill" }
    if lowered.contains("overload") { return "thermometer.medium" }

    // Control power.
    if lowered.contains("ups") { return "battery.100percent.bolt" }
    if lowered.contains("psu") || lowered.contains("power supply") { return "powerplug.fill" }
    if lowered.contains("current transformer") { return "smallcircle.filled.circle.fill" }
    if lowered.contains("transformer") { return "square.stack.3d.up.fill" }

    // Protection and switching.
    if lowered.contains("rcbo") || lowered.contains("rccb") || lowered.contains("rcd") { return "waveform.path.ecg" }
    if lowered.contains("afdd") { return "flame.fill" }
    if lowered.contains("mcb") || lowered.contains("mccb") || lowered.contains("acb") || lowered.contains("breaker") { return "bolt.shield.fill" }
    if lowered.contains("spd") || lowered.contains("surge") { return "bolt.trianglebadge.exclamationmark.fill" }
    if lowered.contains("fuse") { return "bolt.horizontal.fill" }
    if lowered.contains("contactor") { return "switch.2" }
    if lowered.contains("ats controller") { return "arrow.left.arrow.right.circle.fill" }
    if lowered.contains("changeover") { return "arrow.left.arrow.right" }
    if lowered.contains("isolator") { return "power" }
    if lowered.contains("interlock") { return "lock.fill" }
    if lowered.contains("emergency stop") { return "exclamationmark.octagon.fill" }

    // Measurement, control and I/O.
    if lowered.contains("analyzer") { return "chart.xyaxis.line" }
    if lowered.contains("rcm") { return "magnifyingglass.circle.fill" }
    if lowered.contains("test block") { return "cable.connector" }
    if lowered.contains("meter") { return "gauge.with.dots.needle.67percent" }
    if lowered.contains("plc") { return "cpu.fill" }
    if lowered.contains("hmi") { return "display" }
    if lowered.contains("timer") { return "timer" }
    if lowered.contains("safety") { return "shield.lefthalf.filled" }
    if lowered.contains("monitoring") { return "waveform.path.ecg.rectangle.fill" }
    if lowered.contains("relay") { return "rectangle.connected.to.line.below" }
    if lowered.contains("button") || lowered.contains("selector") { return "button.programmable" }
    if lowered.contains("indicator") || lowered.contains("light") { return "lightbulb.fill" }

    // Power factor and quality.
    if lowered.contains("pfc") { return "slider.horizontal.3" }
    if lowered.contains("capacitor") { return "bolt.circle.fill" }
    if lowered.contains("reactor") { return "wave.3.right" }
    if lowered.contains("harmonic") || lowered.contains("filter") { return "waveform.path" }

    // Terminals, wiring and bars.
    if lowered.contains("distribution block") { return "arrow.triangle.branch" }
    if lowered.contains("terminal") { return "point.3.connected.trianglepath.dotted" }
    if lowered.contains("ferrule") { return "capsule.fill" }
    if lowered.contains("lug") { return "link" }
    if lowered.contains("marker") { return "tag.fill" }
    if lowered.contains("bonding") { return "point.bottomleft.forward.to.point.topright.scurvepath" }
    if lowered.contains("busbar") || lowered.contains("bar") { return "rectangle.grid.1x2.fill" }
    if lowered.contains("din rail") || lowered.contains("trunking") { return "rectangle.split.3x1.fill" }
    if lowered.contains("gland") { return "circle.circle.fill" }

    // Enclosure and climate.
    if lowered.contains("enclosure") { return "cabinet.fill" }
    if lowered.contains("cooling") { return "snowflake" }
    if lowered.contains("fan") { return "fan.fill" }
    if lowered.contains("heater") { return "thermometer.sun.fill" }
    if lowered.contains("hygrostat") { return "humidity.fill" }
    if lowered.contains("thermostat") { return "thermometer.medium" }
    if lowered.contains("socket") { return "poweroutlet.type.b.fill" }

    return "shippingbox.fill"
  }

  static func description(for component: PanelComponent) -> String {
    // Catalog parts carry their own text; fall back to the per-type blurb for
    // components the user created.
    let specific = component.about.trimmingCharacters(in: .whitespacesAndNewlines)
    if !specific.isEmpty { return specific }

    let type = component.type.lowercased()
    if type.contains("mcb") && !type.contains("mccb") {
      return "Miniature circuit breaker used for final circuit protection. Choose poles, curve and ampere rating to match the connected circuit."
    }
    if type.contains("mccb") {
      return "Molded case circuit breaker for higher-current feeders, main breakers and distribution protection. Check frame size, trip unit and breaking capacity."
    }
    if type.contains("rcbo") {
      return "Combined overcurrent and residual-current protection, commonly used when a circuit needs both MCB and RCD protection in one device."
    }
    if type.contains("contactor") {
      return "Electrically operated switching device for motors, lighting banks and controlled loads. Confirm AC duty, coil voltage and auxiliary contacts."
    }
    if type.contains("vfd") {
      return "Variable frequency drive for speed control of motors. Check kW rating, supply voltage, ventilation and EMC requirements."
    }
    if type.contains("soft starter") {
      return "Ramps a motor up and down to limit inrush current and mechanical shock. Check motor kW, start duty cycle, whether a bypass is built in, and whether an isolator and overload are still needed upstream."
    }
    if type.contains("mpcb") {
      return "Manual motor starter combining short-circuit and adjustable overload protection in one device. Set the current dial to the motor full-load amps and check the breaking capacity for the fault level."
    }
    if type.contains("overload") {
      return "Protects a motor from sustained overcurrent. Match the setting range to motor full-load amps, confirm the trip class against start-up time, and check it pairs with the chosen contactor."
    }
    if type.contains("dc-ups") || (type.contains("ups") && !type.contains("psu")) {
      return "Keeps 24VDC control power alive through dips and outages. Check hold-up time at the actual load, battery or capacitor type, and where the alarm contact is wired."
    }
    if type.contains("psu") {
      return "Power supply for control circuits, sensors, PLCs and relays. Check output voltage, current and spare capacity."
    }
    if type.contains("busbar") {
      return "Copper or distribution bar used to carry current between sections or devices. Check current rating, spacing, supports and insulation."
    }
    return "Catalog component used inside the board. Confirm manufacturer data, model, rating, poles/phase and project-specific installation notes."
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

struct ManufacturerLogoView: View {
  let manufacturer: ManufacturerItem

  /// A logo the user set on this device, else the one bundled for this brand.
  private var logo: UIImage? {
    manufacturer.thumbnail
      ?? CatalogImageLibrary.manufacturerThumbnail(name: manufacturer.name)
  }

  var body: some View {
    Group {
      if let image = logo {
        TransparentImageBubble(
          image: image,
          width: 54,
          height: 54,
          glowColor: manufacturer.color
        )
      } else {
        ZStack {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(manufacturer.color.gradient)
          Text(manufacturer.initials)
            .font(.system(size: 13, weight: .black))
            .foregroundStyle(.white)
        }
        .frame(width: 54, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      }
    }
    .frame(width: 54, height: 54)
  }
}

struct ManufacturerMarkView: View {
  let manufacturer: ManufacturerItem?
  let fallbackName: String
  let size: CGFloat

  private var color: Color {
    manufacturer?.color ?? Color(hex: 0xAEB4BC)
  }

  private var initials: String {
    if let manufacturer { return manufacturer.initials }
    let parts = fallbackName.split(separator: " ")
    let letters = parts.prefix(2).compactMap(\.first)
    return letters.isEmpty ? String(fallbackName.prefix(2)).uppercased() : String(letters).uppercased()
  }

  /// The brand's own logo where the mark is used for a known manufacturer, and
  /// the bundled catalog logo otherwise — including for the plain-name case,
  /// where a board records a brand nobody has added as a manufacturer yet.
  private var logo: UIImage? {
    manufacturer?.thumbnail
      ?? CatalogImageLibrary.manufacturerThumbnail(name: manufacturer?.name ?? fallbackName)
  }

  var body: some View {
    Group {
      if let image = logo {
        TransparentImageBubble(
          image: image,
          width: size,
          height: size,
          cornerRadius: max(size * 0.22, 5),
          glowColor: color
        )
      } else {
        ZStack {
          RoundedRectangle(cornerRadius: max(size * 0.22, 5), style: .continuous)
            .fill(color.opacity(0.18))
          Text(initials)
            .font(.system(size: max(size * 0.34, 7), weight: .black))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
        }
        .frame(width: size, height: size)
      }
    }
    .frame(width: size, height: size)
  }
}

struct BoardTypeManagerSheet: View {
  let theme: PanelTheme
  @Binding var boardTypes: [BoardType]
  @Environment(\.dismiss) private var dismiss
  @State private var newTypeIcon = "⚡"
  @State private var newTypeName = ""
  @State private var newTypeDescription = ""
  @State private var selectedBoardType: BoardType?

  private var canAdd: Bool {
    !newTypeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          GlassCard(theme: theme) {
            VStack(alignment: .leading, spacing: 10) {
              TextField("Icon or emoji", text: $newTypeIcon)
              TextField("Board type name", text: $newTypeName)
              TextField("Description", text: $newTypeDescription)
              Button {
                let trimmedName = newTypeName.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedDescription = newTypeDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                let newType = BoardType(
                  id: "custom-\(UUID().uuidString)",
                  name: trimmedName,
                  subtitle: trimmedDescription.isEmpty ? "Custom board type" : trimmedDescription,
                  symbol: "rectangle.3.group.fill",
                  color: theme.primary,
                  emoji: newTypeIcon
                )
                boardTypes.removeAll { $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame }
                boardTypes.insert(newType, at: 0)
                newTypeIcon = "⚡"
                newTypeName = ""
                newTypeDescription = ""
              } label: {
                Label("Add Board Type", systemImage: "plus")
                  .frame(maxWidth: .infinity)
              }
              .buttonStyle(.borderedProminent)
              .tint(theme.primary)
              .disabled(!canAdd)
            }
          }

          Text("Available Types")
            .font(.headline)

          ForEach(boardTypes) { board in
            HStack(spacing: 8) {
              Button {
                selectedBoardType = board
              } label: {
                SimpleBoardTypeRow(theme: theme, icon: board.emoji, name: board.name, subtitle: board.subtitle, color: board.color)
              }
              .buttonStyle(.plain)
              if board.id.hasPrefix("custom-") {
                DeleteIconButton(theme: theme) {
                  boardTypes.removeAll { $0.id == board.id }
                }
              }
            }
          }
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Board Types")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
    }
    .sheet(item: $selectedBoardType) { board in
      BoardTypeDetailSheet(theme: theme, board: board)
    }
  }
}

struct SimpleBoardTypeRow: View {
  let theme: PanelTheme
  let icon: String?
  let name: String
  let subtitle: String
  let color: Color

  var body: some View {
    GlassCard(theme: theme) {
      HStack {
        if let icon {
          Text(icon)
            .font(.title3)
            .frame(width: 38, height: 38)
            .background(color.opacity(0.14))
            .clipShape(Circle())
        } else {
          Image(systemName: "rectangle.3.group")
            .foregroundStyle(color)
            .frame(width: 38, height: 38)
            .background(color.opacity(0.14))
            .clipShape(Circle())
        }
        VStack(alignment: .leading, spacing: 4) {
          Text(name).font(.headline)
          Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

struct CompanySwitcherSheet: View {
  let theme: PanelTheme
  @Binding var activeCompany: ContractorCompany?
  let companies: [ContractorCompany]
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Companies")
        .font(.title2.bold())
      Text("Choose which contractor workspace is active.")
        .foregroundStyle(.secondary)

      CompanyRow(
        theme: theme,
        title: "All Companies",
        subtitle: "Show every company and project together",
        color: theme.primary,
        selected: activeCompany == nil
      ) {
        activeCompany = nil
        dismiss()
      }

      if companies.isEmpty {
        EmptyStateCard(theme: theme, title: "No companies yet", subtitle: "Add companies from More, then switch between them here.")
      }

      ForEach(companies) { company in
        CompanyRow(
          theme: theme,
          title: company.name,
          subtitle: "\(company.role) • \(company.projectCount)",
          color: company.color,
          selected: activeCompany?.id == company.id
        ) {
          activeCompany = company
          dismiss()
        }
      }
    }
    .padding(18)
    .background(theme.surface.ignoresSafeArea())
  }
}

struct CompanyManagerSheet: View {
  let theme: PanelTheme
  @Binding var companies: [ContractorCompany]
  @Binding var activeCompany: ContractorCompany?
  let projects: [ProjectItem]
  @Binding var boards: [BoardDraft]
  let boardTypes: [BoardType]
  let manufacturers: [ManufacturerItem]
  @Environment(\.dismiss) private var dismiss
  @State private var companyName = ""
  @State private var companyRole = ""
  @State private var selectedColorHex: UInt32 = 0x5E78FF
  @State private var selectedCompany: ContractorCompany?

  private var canAdd: Bool {
    !companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          GlassCard(theme: theme) {
            VStack(alignment: .leading, spacing: 12) {
              TextField("Company name", text: $companyName)
                .textInputAutocapitalization(.words)
              TextField("Type or role", text: $companyRole)
                .textInputAutocapitalization(.words)
              ColorSwatchPicker(title: "Company color", selectedHex: $selectedColorHex)
              Button {
                addCompany()
              } label: {
                Label("Add Company", systemImage: "plus")
                  .frame(maxWidth: .infinity)
              }
              .buttonStyle(.borderedProminent)
              .tint(theme.primary)
              .disabled(!canAdd)
            }
          }

          Text("Companies")
            .font(.headline)

          if companies.isEmpty {
            EmptyStateCard(theme: theme, title: "No companies yet", subtitle: "Add factories, contractors or manufacturers you work with.")
          } else {
            ForEach(companies) { company in
              HStack(spacing: 8) {
                Button {
                  selectedCompany = company
                } label: {
                  GlassCard(theme: theme) {
                    HStack(spacing: 12) {
                      CompanyColorLogo(color: company.color, symbol: "building.2.fill")
                      VStack(alignment: .leading, spacing: 4) {
                        Text(company.name)
                          .font(.headline)
                        Text(company.role)
                          .font(.caption)
                          .foregroundStyle(.secondary)
                        Text(companySummary(company.name))
                          .font(.caption)
                          .foregroundStyle(.secondary.opacity(0.78))
                          .lineLimit(1)
                          .minimumScaleFactor(0.7)
                      }
                      Spacer()
                      Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                    }
                  }
                  .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                      .stroke(company.color.opacity(0.24), lineWidth: 1)
                  )
                }
                .buttonStyle(.plain)

                Button {
                  activeCompany = company
                } label: {
                  Image(systemName: activeCompany?.id == company.id ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(activeCompany?.id == company.id ? company.color : .secondary)
                }
                .buttonStyle(.plain)
                DeleteIconButton(theme: theme) {
                  if activeCompany?.id == company.id {
                    activeCompany = nil
                  }
                  companies.removeAll { $0.id == company.id }
                }
              }
            }
          }
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Companies")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
    }
    .sheet(item: $selectedCompany) { company in
      CustomerArchiveDetailSheet(
        theme: theme,
        title: company.name,
        subtitle: company.role,
        symbol: "building.2.fill",
        color: company.color,
        projects: projects.filter { $0.customer.localizedCaseInsensitiveCompare(company.name) == .orderedSame },
        boardIDs: boards.filter { $0.company.localizedCaseInsensitiveCompare(company.name) == .orderedSame }.map(\.id),
        boards: $boards,
        boardTypes: boardTypes,
        manufacturers: manufacturers
      )
    }
  }

  private func addCompany() {
    let trimmedName = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedRole = companyRole.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else { return }
    let company = ContractorCompany(
      id: "company-\(UUID().uuidString)",
      name: trimmedName,
      role: trimmedRole.isEmpty ? "Company" : trimmedRole,
      projectCount: "0 projects",
      color: Color(hex: selectedColorHex)
    )
    companies.insert(company, at: 0)
    companyName = ""
    companyRole = ""
    selectedColorHex = 0x5E78FF
  }

  private func companySummary(_ companyName: String) -> String {
    let projectCount = projects.filter { $0.customer.localizedCaseInsensitiveCompare(companyName) == .orderedSame }.count
    let boardCount = boards.filter { $0.company.localizedCaseInsensitiveCompare(companyName) == .orderedSame }.count
    return "\(projectCount) project\(projectCount == 1 ? "" : "s") • \(boardCount) board\(boardCount == 1 ? "" : "s")"
  }
}

struct CompanyColorLogo: View {
  let color: Color
  let symbol: String

  var body: some View {
    RoundedRectangle(cornerRadius: 12, style: .continuous)
      .fill(color.gradient)
      .frame(width: 44, height: 44)
      .overlay(
        Image(systemName: symbol)
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(.white)
      )
  }
}

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
  @State private var addComponentOpen = false
  @State private var componentToConfigure: PanelComponent?
  @State private var componentToDescribe: PanelComponent?
  @State private var componentToAssign: PanelComponent?
  @ObservedObject private var stockStore = WarehouseStockStore.shared

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
      },
      deleteComponent: group.id == "custom-components" ? {
        customComponents.removeAll { $0.id == item.id }
        addedComponentIDs.remove(item.id)
        photoComponentIDs.remove(item.id)
      } : nil
    )
  }

  /// The drill-in page for one category, listing every part under it.
  @ViewBuilder
  private func categoryDetail(_ group: ComponentGroup) -> some View {
    let live = visibleGroups.first { $0.id == group.id } ?? group
    ScrollView {
      VStack(alignment: .leading, spacing: 8) {
        ForEach(live.items) { item in
          componentRow(for: item, in: live)
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
          Text("Add manufacturer parts by type, amp rating, poles and model.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button {
          addComponentOpen = true
        } label: {
          Label("Add", systemImage: "plus")
            .font(.caption.bold())
        }
        .buttonStyle(.borderedProminent)
        .tint(theme.primary)
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
    .sheet(isPresented: $addComponentOpen) {
      AddComponentSheet(theme: theme, manufacturerNames: manufacturers.map(\.name)) { component in
        customComponents.insert(component, at: 0)
        handleAddedComponent(component, sourceID: component.id)
      }
      .presentationDetents([.large])
      .presentationDragIndicator(.visible)
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
  var deleteComponent: (() -> Void)? = nil
  @State private var selectedPhotoItem: PhotosPickerItem?
  @ObservedObject private var stockStore = WarehouseStockStore.shared

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
        if let deleteComponent {
          DeleteIconButton(theme: theme, action: deleteComponent)
        }
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

struct PickerLikeRow: View {
  let title: String
  let value: String
  let color: Color

  var body: some View {
    HStack {
      Text(title)
        .foregroundStyle(.primary)
      Spacer()
      Text(value)
        .fontWeight(.bold)
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
      Image(systemName: "chevron.down")
        .font(.caption.bold())
        .foregroundStyle(.secondary)
    }
  }
}

struct AddComponentSheet: View {
  let theme: PanelTheme
  let manufacturerNames: [String]
  let onAdd: (PanelComponent) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var manufacturer = "ABB"
  @State private var type = "MCB"
  @State private var customManufacturer = ""
  @State private var customType = ""
  @State private var model = ""
  @State private var rating = "63A"
  @State private var poles = "3P"
  @State private var curve = "C Curve"
  @State private var serialNumber = ""

  private var canAdd: Bool {
    !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !rating.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !resolvedManufacturer.isEmpty &&
      !resolvedType.isEmpty
  }

  private var resolvedManufacturer: String {
    manufacturer == "Other" ? customManufacturer.trimmingCharacters(in: .whitespacesAndNewlines) : manufacturer
  }

  private var resolvedType: String {
    type == "Other" ? customType.trimmingCharacters(in: .whitespacesAndNewlines) : type
  }

  private var isMCBType: Bool {
    resolvedType.localizedCaseInsensitiveCompare("MCB") == .orderedSame
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          Text("Company")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.secondary)

          CreationMenuInput(theme: theme, title: "Manufacturer", symbol: "building.2.fill", value: manufacturer, options: Array(Set(manufacturerNames)).sorted() + ["Other"], selection: $manufacturer)
          if manufacturer == "Other" {
            CreationTextInput(theme: theme, title: "Manufacturer name", placeholder: "Name", symbol: "pencil", text: $customManufacturer, capitalization: .words)
          }
          CreationMenuInput(theme: theme, title: "Equipment Type", symbol: "shippingbox.fill", value: type, options: EquipmentTypeCatalog.all + ["Other"], selection: $type)
          if type == "Other" {
            CreationTextInput(theme: theme, title: "Equipment type", placeholder: "Type", symbol: "pencil", text: $customType, capitalization: .words)
          }

          Text("Specification")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(.top, 4)

          CreationTextInput(theme: theme, title: "Model", placeholder: "Model", symbol: "tag.fill", text: $model, capitalization: .characters)
          CreationTextInput(theme: theme, title: "Serial number", placeholder: "Optional", symbol: "number", text: $serialNumber, capitalization: .characters)
          CreationTextInput(theme: theme, title: "Ampere / rating", placeholder: "Rating", symbol: "bolt.fill", text: $rating, keyboardType: .numberPad)
          CreationMenuInput(theme: theme, title: "Poles", symbol: "square.grid.2x2.fill", value: poles, options: PoleRating.all, selection: $poles)
          if isMCBType {
            CreationTextInput(theme: theme, title: "Curve", placeholder: "B/C/D", symbol: "waveform.path.ecg", text: $curve, capitalization: .characters)
          }

          BottomTabClearance()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Add Component")
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Add") {
            onAdd(
              PanelComponent(
                id: "custom-\(UUID().uuidString)",
                manufacturer: resolvedManufacturer,
                type: resolvedType,
                model: model,
                rating: normalizedRating,
                poles: poles,
                curve: isMCBType ? curve : "",
                serialNumber: serialNumber.trimmingCharacters(in: .whitespacesAndNewlines)
              )
            )
            dismiss()
          }
          .disabled(!canAdd)
          .fontWeight(.bold)
        }
      }
    }
  }

  private var normalizedRating: String {
    let trimmed = rating.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.rangeOfCharacter(from: .letters) == nil &&
        (isMCBType || resolvedType.localizedCaseInsensitiveContains("MCCB") || resolvedType.localizedCaseInsensitiveContains("Contactor")) {
      return "\(trimmed)A"
    }
    return trimmed
  }
}

struct GlassCard<Content: View>: View {
  let theme: PanelTheme
  @ViewBuilder let content: Content

  var body: some View {
    content
      .padding(14)
      .background(theme.surface.opacity(0.78))
      .clipShape(RoundedRectangle(cornerRadius: theme.radiusCard, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: theme.radiusCard, style: .continuous)
          .stroke(theme.cardBorder, lineWidth: 1)
      )
  }
}

struct TopScrollBlur: View {
  let theme: PanelTheme

  var body: some View {
    Rectangle()
      .fill(
        LinearGradient(
          stops: [
            .init(color: theme.background.opacity(0.98), location: 0),
            .init(color: theme.background.opacity(0.82), location: 0.34),
            .init(color: theme.background.opacity(0.36), location: 0.72),
            .init(color: .clear, location: 1)
          ],
          startPoint: .top,
          endPoint: .bottom
        )
      )
      .frame(height: 58)
      .ignoresSafeArea(edges: .top)
      .allowsHitTesting(false)
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

struct PanelVaultLogoMark: View {
  let theme: PanelTheme
  let size: CGFloat

  var body: some View {
    Image(systemName: "bolt")
      .font(.system(size: size, weight: .regular))
      .foregroundStyle(theme.primary)
      .frame(width: size, height: size)
      .shadow(color: theme.primary.opacity(0.9), radius: size * 0.32)
      .shadow(color: theme.primary.opacity(0.55), radius: size * 0.7)
  }
}

struct ABBLogo: View {
  var body: some View {
    Text("ABB")
      .font(.system(size: 13, weight: .black))
      .foregroundStyle(.red)
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .background(.white)
      .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
  }
}

struct EquipmentBrandBadge: View {
  let name: String
  var image: UIImage? = nil

  /// The caller's logo, or the one bundled in `assets/catalog` for this brand.
  /// Resolved here rather than at each call site so every badge in the app
  /// picks up a newly added logo without another edit.
  private var resolvedImage: UIImage? {
    image ?? CatalogImageLibrary.manufacturerThumbnail(name: name)
  }

  var body: some View {
    Group {
      if let image = resolvedImage {
        TransparentImageBubble(
          image: image,
          width: 50,
          height: 50,
          cornerRadius: 12,
          glowColor: brandGlowColor
        )
      } else {
        ZStack {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.white)
          Text(name)
            .font(.system(size: 11, weight: .black))
            .foregroundStyle(brandColor)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .padding(.horizontal, 5)
        }
        .frame(width: 50, height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
    }
    .frame(width: 50, height: resolvedImage == nil ? 28 : 50)
  }

  private var brandGlowColor: Color {
    switch name {
    case "ABB": Color.red
    case "Schneider": Color(hex: 0x5F9F79)
    case "Siemens": Color(hex: 0x4F9AA8)
    default: Color(hex: 0x7FA6C9)
    }
  }

  private var brandColor: Color {
    switch name {
    case "ABB": Color.red
    case "Schneider": Color(hex: 0x5F9F79)
    case "Siemens": Color(hex: 0x4F9AA8)
    default: Color.black
    }
  }
}

struct TransparentImageBubble: View {
  let image: UIImage
  let width: CGFloat
  let height: CGFloat
  var cornerRadius: CGFloat = 12
  let glowColor: Color

  var body: some View {
    Image(uiImage: image)
      .resizable()
      .scaledToFit()
      .padding(3)
      .frame(width: width, height: height)
      .shadow(color: glowColor.opacity(0.34), radius: 9, x: 0, y: 0)
      .shadow(color: glowColor.opacity(0.18), radius: 18, x: 0, y: 0)
      .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }
}

struct EquipmentPill: View {
  let text: String
  let color: Color

  var body: some View {
    Text(text)
      .font(.system(size: 10, weight: .bold))
      .foregroundStyle(color)
      .lineLimit(1)
      .minimumScaleFactor(0.8)
      .padding(.horizontal, 7)
      .padding(.vertical, 4)
      .background(color.opacity(0.12))
      .clipShape(Capsule())
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

struct MoreRow: View {
  let theme: PanelTheme
  let symbol: String
  let title: String
  let subtitle: String

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: symbol)
        .foregroundStyle(theme.primary)
        .frame(width: 38, height: 38)
        .background(theme.primary.opacity(0.14))
        .clipShape(Circle())
      VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.headline)
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

struct PanelTheme: Identifiable, Equatable {
  let id: String
  let name: String
  let description: String
  let background: Color
  let surface: Color
  let primary: Color
  let secondary: Color

  // MARK: Design tokens
  // These default to the dark control-room language so every existing theme
  // keeps its current look with no call-site changes. Light skins such as
  // Cupertino override them to change the whole feel — not just the accent.
  var colorScheme: ColorScheme = .dark
  var radiusCard: CGFloat = 16
  var radiusControl: CGFloat = 12
  var radiusPill: CGFloat = 8
  var cardBorder: Color = Color.white.opacity(0.07)
  var elevatedSurface: Color = Color.white.opacity(0.06)
  // Semantic status colors, tuned per skin so pills stay legible on the ground.
  var success: Color = Color(hex: 0x35E177)
  var info: Color = Color(hex: 0x64D2FF)
  var designAccent: Color = Color(hex: 0xFF4FD8)
  var danger: Color = Color(hex: 0xFF6B6B)
  // Floating tab-bar material. Dark skins use a black glass pill; light skins
  // opt into a light one so it doesn't read as a hole in the layout.
  var tabBarTint: Color = Color.black
  var tabBarInactive: Color = Color.white.opacity(0.78)

  // Synthwave. Purple-black ground, hot magenta controls, cyan support, and a
  // neon-tinted card edge instead of the usual hairline.
  static let neonNights = PanelTheme(
    id: "neon-nights",
    name: "Neon Nights",
    description: "Synthwave purple-black with hot magenta and cyan",
    background: Color(hex: 0x0B0313),
    surface: Color(hex: 0x1A0B2E),
    primary: Color(hex: 0xFF2E97),
    secondary: Color(hex: 0x00E5FF),
    colorScheme: .dark,
    radiusCard: 18,
    radiusControl: 14,
    radiusPill: 10,
    cardBorder: Color(hex: 0xFF2E97).opacity(0.20),
    elevatedSurface: Color.white.opacity(0.06),
    success: Color(hex: 0x3DFFA8),
    info: Color(hex: 0x00E5FF),
    designAccent: Color(hex: 0xFF2E97),
    danger: Color(hex: 0xFF4D6D),
    tabBarTint: Color(hex: 0x12061F),
    tabBarInactive: Color(hex: 0x9B7FB8)
  )

  // Eighties Miami. Deep teal-navy with hot pink and aqua, soft fat corners.
  static let miami = PanelTheme(
    id: "miami",
    name: "Miami",
    description: "Eighties teal and hot pink with soft fat corners",
    background: Color(hex: 0x071A26),
    surface: Color(hex: 0x0E2C3D),
    primary: Color(hex: 0xFF4FA3),
    secondary: Color(hex: 0x2EE6C5),
    colorScheme: .dark,
    radiusCard: 22,
    radiusControl: 18,
    radiusPill: 12,
    cardBorder: Color(hex: 0x2EE6C5).opacity(0.18),
    elevatedSurface: Color.white.opacity(0.06),
    success: Color(hex: 0x2EE6C5),
    info: Color(hex: 0x4FC3F7),
    designAccent: Color(hex: 0xFF4FA3),
    danger: Color(hex: 0xFF6B6B),
    tabBarTint: Color(hex: 0x05141D),
    tabBarInactive: Color(hex: 0x7FA6B8)
  )

  // Electric lime on deep violet. The loudest pairing in the set.
  static let ultraviolet = PanelTheme(
    id: "ultraviolet",
    name: "Ultraviolet",
    description: "Deep violet with electric lime controls",
    background: Color(hex: 0x0A0618),
    surface: Color(hex: 0x171030),
    primary: Color(hex: 0xB4FF39),
    secondary: Color(hex: 0xA855F7),
    colorScheme: .dark,
    radiusCard: 16,
    radiusControl: 12,
    radiusPill: 8,
    cardBorder: Color(hex: 0xB4FF39).opacity(0.16),
    elevatedSurface: Color.white.opacity(0.06),
    success: Color(hex: 0xB4FF39),
    info: Color(hex: 0xA855F7),
    designAccent: Color(hex: 0xC77DFF),
    danger: Color(hex: 0xFF5C7C),
    tabBarTint: Color(hex: 0x080412),
    tabBarInactive: Color(hex: 0x8B7FA8)
  )

  // Molten. Near-black brown ground with vivid orange and yellow.
  static let solarFlare = PanelTheme(
    id: "solar-flare",
    name: "Solar Flare",
    description: "Molten orange and yellow on scorched black",
    background: Color(hex: 0x140A02),
    surface: Color(hex: 0x241203),
    primary: Color(hex: 0xFF7A18),
    secondary: Color(hex: 0xFFD028),
    colorScheme: .dark,
    radiusCard: 10,
    radiusControl: 8,
    radiusPill: 6,
    cardBorder: Color(hex: 0xFF7A18).opacity(0.20),
    elevatedSurface: Color.white.opacity(0.06),
    success: Color(hex: 0x7FD858),
    info: Color(hex: 0xFFD028),
    designAccent: Color(hex: 0xFF7A18),
    danger: Color(hex: 0xFF4530),
    tabBarTint: Color(hex: 0x0E0701),
    tabBarInactive: Color(hex: 0xB08A63)
  )

  // CRT terminal. Pure black, phosphor green, amber support, hard corners.
  static let terminal = PanelTheme(
    id: "terminal",
    name: "Terminal",
    description: "Phosphor green and amber on pure black",
    background: Color(hex: 0x000000),
    surface: Color(hex: 0x0A140A),
    primary: Color(hex: 0x33FF66),
    secondary: Color(hex: 0xFFB000),
    colorScheme: .dark,
    radiusCard: 16,
    radiusControl: 12,
    radiusPill: 8,
    cardBorder: Color(hex: 0x33FF66).opacity(0.24),
    elevatedSurface: Color(hex: 0x33FF66).opacity(0.06),
    success: Color(hex: 0x33FF66),
    info: Color(hex: 0x00E5FF),
    designAccent: Color(hex: 0xFFB000),
    danger: Color(hex: 0xFF3B30),
    tabBarTint: Color(hex: 0x000000),
    tabBarInactive: Color(hex: 0x4E7A57)
  )

  // The light funky option. Candy pink ground, magenta and purple, very round.
  static let bubblegum = PanelTheme(
    id: "bubblegum",
    name: "Bubblegum",
    description: "Candy pink and purple, extra round and playful",
    background: Color(hex: 0xFFF0F6),
    surface: Color(hex: 0xFFFFFF),
    primary: Color(hex: 0xE5399B),
    secondary: Color(hex: 0x7C4DFF),
    colorScheme: .light,
    radiusCard: 22,
    radiusControl: 18,
    radiusPill: 14,
    cardBorder: Color(hex: 0xE5399B).opacity(0.16),
    elevatedSurface: Color.black.opacity(0.03),
    success: Color(hex: 0x00B37E),
    info: Color(hex: 0x7C4DFF),
    designAccent: Color(hex: 0xE5399B),
    danger: Color(hex: 0xF43F5E),
    tabBarTint: Color.white,
    tabBarInactive: Color(hex: 0xB08AA0)
  )

  // Apple-native light skin. Light system grays, iOS blue, tighter rounding,
  // and a light frosted tab bar. Reads like a first-party iOS app.
  static let cupertino = PanelTheme(
    id: "cupertino",
    name: "Cupertino",
    description: "Apple-native light theme with system grays and iOS blue",
    background: Color(hex: 0xF2F2F7),
    surface: Color(hex: 0xFFFFFF),
    primary: Color(hex: 0x007AFF),
    secondary: Color(hex: 0x5AC8FA),
    colorScheme: .light,
    radiusCard: 14,
    radiusControl: 10,
    radiusPill: 7,
    cardBorder: Color.black.opacity(0.06),
    elevatedSurface: Color.black.opacity(0.03),
    success: Color(hex: 0x34C759),
    info: Color(hex: 0x007AFF),
    designAccent: Color(hex: 0xFF9500),
    danger: Color(hex: 0xFF3B30),
    tabBarTint: Color.white,
    tabBarInactive: Color(hex: 0x8A8A8E)
  )

  // Draftsman skin. A cool "spec sheet" identity: paper-gray ground, white
  // cards, ink-teal accent. Reads like an electrical single-line diagram.
  static let blueprint = PanelTheme(
    id: "blueprint",
    name: "Blueprint",
    description: "Technical spec-sheet look with paper ground and ink teal",
    background: Color(hex: 0xE9EDF1),
    surface: Color(hex: 0xFFFFFF),
    primary: Color(hex: 0x0F6D7E),
    secondary: Color(hex: 0x1B4D8F),
    colorScheme: .light,
    radiusCard: 14,
    radiusControl: 11,
    radiusPill: 8,
    cardBorder: Color(hex: 0x16222E).opacity(0.16),
    elevatedSurface: Color.black.opacity(0.03),
    success: Color(hex: 0x2F7D32),
    info: Color(hex: 0x0F6D7E),
    designAccent: Color(hex: 0x9A5B00),
    danger: Color(hex: 0xC0392B),
    tabBarTint: Color.white,
    tabBarInactive: Color(hex: 0x5A6B78)
  )

  // Rugged workshop skin. Dark slate with a safety-amber accent — high
  // contrast, warm, built to be read fast on site.
  static let field = PanelTheme(
    id: "field",
    name: "Field",
    description: "Rugged dark slate with a safety-amber accent",
    background: Color(hex: 0x16181C),
    surface: Color(hex: 0x202429),
    primary: Color(hex: 0xFFB020),
    secondary: Color(hex: 0xFF6A3D),
    colorScheme: .dark,
    radiusCard: 8,
    radiusControl: 7,
    radiusPill: 4,
    cardBorder: Color.white.opacity(0.09),
    elevatedSurface: Color.white.opacity(0.06),
    success: Color(hex: 0x5FD08A),
    info: Color(hex: 0x4EA3FF),
    designAccent: Color(hex: 0xFFB020),
    danger: Color(hex: 0xFF6B6B),
    tabBarTint: Color(hex: 0x101215),
    tabBarInactive: Color(hex: 0x9AA0A6)
  )

  static let all = [cupertino, neonNights, miami, ultraviolet, solarFlare, terminal, bubblegum, blueprint, field]
}

struct ContractorCompany: Identifiable, Equatable {
  let id: String
  let name: String
  let role: String
  let projectCount: String
  let color: Color

  var persistenceSignature: String {
    "\(id)|\(name)|\(role)|\(projectCount)|\(color.archiveHex)"
  }

  static let samples: [ContractorCompany] = []
}

struct CustomerContact: Identifiable, Equatable {
  let id: String
  var name: String
  var role: String
  var phone: String

  init(id: String = "customer-contact-\(UUID().uuidString)", name: String = "", role: String = "", phone: String = "") {
    self.id = id
    self.name = name
    self.role = role
    self.phone = phone
  }

  var persistenceSignature: String {
    "\(id)|\(name)|\(role)|\(phone)"
  }
}

struct CustomerItem: Identifiable, Equatable {
  let id: String
  var name: String
  var kind: String
  var contactName: String
  var phone: String
  var note: String
  var contacts: [CustomerContact]
  var colorHex: UInt32

  init(id: String = "customer-\(UUID().uuidString)", name: String, kind: String = "Company", contactName: String = "", phone: String = "", note: String = "", contacts: [CustomerContact] = [], colorHex: UInt32 = 0x5E78FF) {
    self.id = id
    self.name = name
    self.kind = kind
    self.contactName = contactName
    self.phone = phone
    self.note = note
    self.contacts = contacts
    self.colorHex = colorHex
  }

  var color: Color { Color(hex: colorHex) }

  var profileSummary: String {
    let contactsSummary = contacts.isEmpty ? nil : "\(contacts.count) contact\(contacts.count == 1 ? "" : "s")"
    return [kind, contactName.isEmpty ? nil : contactName, phone.isEmpty ? nil : phone, contactsSummary, note.isEmpty ? nil : note]
      .compactMap { $0 }
      .joined(separator: " • ")
  }

  var persistenceSignature: String {
    "\(id)|\(name)|\(kind)|\(contactName)|\(phone)|\(note)|\(contacts.map(\.persistenceSignature).joined(separator: ";"))|\(colorHex)"
  }
}

struct RecentVisit: Identifiable, Equatable {
  enum Kind: String {
    case project
    case board
  }

  let kind: Kind
  let itemID: String

  init(kind: Kind, id: String) {
    self.kind = kind
    self.itemID = id
  }

  var identifier: String {
    "\(kind.rawValue)-\(itemID)"
  }
}

extension RecentVisit {
  var id: String { identifier }
}

struct RecentBoardSelection: Identifiable {
  let id: String
}

struct SchemeAttachment: Identifiable, Equatable {
  enum Kind: Equatable {
    case pdf
    case photo
  }

  let id: String
  let kind: Kind
  var name: String
  var url: URL?

  /// Filename in the image store rather than the image itself, so a scheme can
  /// be listed without decoding its drawing.
  var imageToken: String?

  var image: UIImage? {
    get { ImageStore.shared.image(for: imageToken) }
    set { imageToken = ImageStore.shared.store(newValue) }
  }

  var thumbnail: UIImage? {
    ImageStore.shared.thumbnail(for: imageToken)
  }

  static func == (lhs: SchemeAttachment, rhs: SchemeAttachment) -> Bool {
    lhs.id == rhs.id &&
      lhs.kind == rhs.kind &&
      lhs.name == rhs.name &&
      lhs.url == rhs.url &&
      lhs.imageToken == rhs.imageToken
  }

  init(id: String = "scheme-\(UUID().uuidString)", kind: Kind, name: String, image: UIImage?, url: URL? = nil) {
    self.id = id
    self.kind = kind
    self.name = name
    self.url = url
    self.imageToken = ImageStore.shared.store(image)
  }

  init(id: String = "scheme-\(UUID().uuidString)", kind: Kind, name: String, imageToken: String?, url: URL? = nil) {
    self.id = id
    self.kind = kind
    self.name = name
    self.url = url
    self.imageToken = imageToken
  }

  var persistenceSignature: String {
    [
      id,
      kind == .pdf ? "pdf" : "photo",
      name,
      url?.absoluteString ?? "",
      ImageStore.shared.signature(for: imageToken)
    ].joined(separator: "|")
  }
}

struct ManufacturerItem: Identifiable {
  let id: String
  var name: String
  var colorHex: UInt32

  /// Brand logo, stored on disk like every other image in the archive.
  var imageToken: String? = nil

  var image: UIImage? {
    get { ImageStore.shared.image(for: imageToken) }
    set { imageToken = ImageStore.shared.store(newValue) }
  }

  var thumbnail: UIImage? {
    ImageStore.shared.thumbnail(for: imageToken)
  }

  init(id: String = "manufacturer-\(UUID().uuidString)", name: String, colorHex: UInt32 = 0x5E78FF, image: UIImage? = nil) {
    self.id = id
    self.name = name
    self.colorHex = colorHex
    self.imageToken = ImageStore.shared.store(image)
  }

  init(id: String = "manufacturer-\(UUID().uuidString)", name: String, colorHex: UInt32 = 0x5E78FF, imageToken: String?) {
    self.id = id
    self.name = name
    self.colorHex = colorHex
    self.imageToken = imageToken
  }

  var color: Color {
    Color(hex: colorHex)
  }

  var initials: String {
    let parts = name.split(separator: " ")
    let letters = parts.prefix(2).compactMap(\.first)
    return letters.isEmpty ? String(name.prefix(2)).uppercased() : String(letters).uppercased()
  }

  var persistenceSignature: String {
    let imageSignature = ImageStore.shared.signature(for: imageToken)
    return "\(id)|\(name)|\(colorHex)|\(imageSignature)"
  }

  static let defaults = [
    ManufacturerItem(id: "rittal", name: "Rittal", colorHex: 0x5E78FF),
    ManufacturerItem(id: "abb", name: "ABB", colorHex: 0xFF3B30),
    ManufacturerItem(id: "yakir", name: "Yakir", colorHex: 0x35E177),
    ManufacturerItem(id: "tamhash", name: "Tamhash", colorHex: 0xFF9F0A),
    ManufacturerItem(id: "hager", name: "HAGER", colorHex: 0x64D2FF),
    ManufacturerItem(id: "delta", name: "Delta", colorHex: 0x0A84FF),
    ManufacturerItem(id: "schneider", name: "Schneider", colorHex: 0x35E177),
    ManufacturerItem(id: "siemens", name: "Siemens", colorHex: 0x18D4E8),
    ManufacturerItem(id: "eaton", name: "Eaton", colorHex: 0x5E78FF),
    ManufacturerItem(id: "legrand", name: "Legrand", colorHex: 0xD85CFF),
    ManufacturerItem(id: "mean-well", name: "Mean Well", colorHex: 0xFFD60A),
    ManufacturerItem(id: "phoenix", name: "Phoenix", colorHex: 0xFF9F0A),
    ManufacturerItem(id: "danfoss", name: "Danfoss", colorHex: 0xE2231A),
    ManufacturerItem(id: "socomec", name: "Socomec", colorHex: 0x00A0DF),
    ManufacturerItem(id: "generic", name: "Generic", colorHex: 0xAEB4BC)
  ]
}

struct PanelStat: Identifiable {
  let id: String
  let title: String
  let value: String
  let symbol: String
  let color: Color

  static let samples = [
    PanelStat(id: "projects", title: "Projects", value: "214", symbol: "folder.fill", color: Color(hex: 0x7FAE9A)),
    PanelStat(id: "photos", title: "Photos", value: "8426", symbol: "photo.fill", color: Color(hex: 0x7FA6C9)),
    PanelStat(id: "companies", title: "Companies", value: "19", symbol: "building.2.fill", color: Color(hex: 0xAEB4BC)),
    PanelStat(id: "customers", title: "Customers", value: "67", symbol: "person.2.fill", color: Color(hex: 0xA895C8))
  ]
}

struct BoardType: Identifiable {
  let id: String
  let name: String
  let subtitle: String
  let symbol: String
  let color: Color
  var emoji: String? = nil
  var localName: String? = nil
  var overview: String? = nil
  var typicalUses: [String] = []
  var typicalComponents: [String] = []
  var designChecks: [String] = []
  var notes: [String] = []

  static let fallback = BoardType(
    id: "board",
    name: "Board",
    subtitle: "Distribution board",
    symbol: "rectangle.3.group.fill",
    color: Color(hex: 0x5E78FF),
    overview: "A general low-voltage electrical assembly used to distribute, protect, control, meter or switch electrical circuits.",
    typicalUses: ["General project documentation", "Custom boards that do not fit a standard category"],
    typicalComponents: ["Main isolator or breaker", "MCBs/MCCBs", "Busbars", "Terminals", "N and PE bars"],
    designChecks: ["Rated current", "Short-circuit rating", "IP rating", "Cable entries", "Clear labeling"]
  )

  static let samples = [
    BoardType(id: "main-lv", name: "Main LV Board", subtitle: "Main low-voltage intake", symbol: "bolt.fill", color: Color(hex: 0x0A84FF), localName: "לוח ראשי", overview: "The main low-voltage switchboard for a building, floor group, factory area or service. It receives the main supply and distributes power downstream to sub boards, mechanical loads and specialist panels.", typicalUses: ["Commercial and industrial main supply", "Building incoming service", "Factory main distribution"], typicalComponents: ["Main ACB/MCCB or switch disconnector", "Metering and CTs", "Busbars", "Surge protection", "Outgoing MCCBs"], designChecks: ["Incoming supply and service size", "Icu/Ics short-circuit rating", "Form of separation", "Ventilation and heat rise", "Clear source and outgoing labels"], notes: ["Often called לוח ראשי in Israel.", "Commonly documented against IEC 61439 low-voltage assembly concepts."]),
    BoardType(id: "mdb", name: "MDB", subtitle: "Main Distribution", symbol: "bolt.square.fill", color: Color(hex: 0x5E78FF), localName: "לוח חלוקה ראשי", overview: "A main distribution board that splits a major feeder into multiple outgoing feeders. It may be the main LV board or a major distribution board below the main intake.", typicalUses: ["Office towers", "Malls", "Hospitals", "Large public buildings"], typicalComponents: ["Main MCCB/ACB", "Outgoing MCCBs", "Busbar system", "Power meter", "SPD"], designChecks: ["Load diversity", "Phase balance", "Cable termination space", "Future spare ways", "Selective protection coordination"]),
    BoardType(id: "sub-distribution", name: "Sub Distribution", subtitle: "Sub boards", symbol: "point.3.connected.trianglepath.dotted", color: Color(hex: 0x18D4E8), localName: "לוח משנה", overview: "A downstream distribution board fed from a main board or MDB. It supplies a zone, floor, tenant, machine area or service room.", typicalUses: ["Floor boards", "Tenant boards", "Mechanical-room sub boards", "Area distribution"], typicalComponents: ["Incoming isolator/MCCB", "MCBs/RCBOs", "RCD/RCCB protection", "N and PE bars", "DIN rails"], designChecks: ["Feeder rating", "Voltage drop", "Fault loop/short-circuit level", "RCD requirements", "Circuit labeling"]),
    BoardType(id: "mcc", name: "MCC", subtitle: "Motor Control Center", symbol: "gearshape.fill", color: Color(hex: 0x35E177), localName: "לוח מנועים / MCC", overview: "A board dedicated to motor feeders and motor control. It centralizes motor protection, switching, control and automation interfaces.", typicalUses: ["Pumps", "Fans", "Conveyors", "Industrial machines", "HVAC plant"], typicalComponents: ["MCCBs/MCBs", "Contactors", "Overload relays", "VFDs or soft starters", "Control transformers", "PLC/IO terminals"], designChecks: ["Motor kW and starting method", "AC-3 contactor rating", "Overload setting range", "Control voltage", "Ventilation for drives"]),
    BoardType(id: "cabinet-collection", name: "Cabinet Collection", subtitle: "Multi-cabinet assembly", symbol: "rectangle.3.group.bubble.left.fill", color: Color(hex: 0x8EA2FF), localName: "מערך ארונות", overview: "A cabinet collection is a board record used when one electrical board is physically built from several connected cabinets or bays. It keeps the cabinets grouped under one board number while still allowing build progress and photos to be tracked together.", typicalUses: ["Multi-cabinet MDBs", "Large MCC lineups", "Sectioned distribution boards", "Panel rows with shared busbars"], typicalComponents: ["Shared busbar system", "Inter-cabinet wiring", "Main breaker section", "Outgoing feeder sections", "N and PE bars"], designChecks: ["Cabinet order", "Busbar continuity", "Inter-cabinet links", "Transport split points", "Consistent labels across cabinets"]),
    BoardType(id: "ats", name: "ATS", subtitle: "Automatic Transfer Switch", symbol: "arrow.left.arrow.right", color: Color(hex: 0x8B4DFF), localName: "לוח החלפה / ATS", overview: "A transfer board that switches loads between normal utility supply and an alternate source such as generator or UPS. It may be automatic or manual depending on project needs.", typicalUses: ["Generator-backed buildings", "Critical loads", "Fire/safety services", "Data and telecom rooms"], typicalComponents: ["Motorized changeover switch or contactors", "Controller", "Source voltage sensing", "Mechanical/electrical interlocking", "Bypass or manual mode"], designChecks: ["Source interlocking", "Neutral switching method", "Generator start signal", "Transfer delay settings", "Load priority"]),
    BoardType(id: "metering", name: "Metering Board", subtitle: "Meters and CTs", symbol: "gauge.with.dots.needle.67percent", color: Color(hex: 0x64D2FF), localName: "לוח מונים", overview: "A board or section used for energy metering, tenant metering, CT wiring and monitoring equipment.", typicalUses: ["Tenant billing", "Energy monitoring", "Utility/customer metering sections"], typicalComponents: ["Energy meters", "CTs", "Test blocks", "Voltage fuses", "Communication modules"], designChecks: ["CT ratio and class", "Sealable compartments", "Meter access", "Phase order", "Communication wiring"]),
    BoardType(id: "capacitor", name: "Capacitor Bank", subtitle: "Power factor correction", symbol: "waveform.path.ecg.rectangle.fill", color: Color(hex: 0xFFD60A), localName: "לוח קבלים", overview: "A power-factor correction board that switches capacitor stages to improve power factor and reduce reactive energy penalties.", typicalUses: ["Factories", "Large commercial buildings", "Motor-heavy installations"], typicalComponents: ["PFC controller", "Capacitor contactors", "Capacitor stages", "HRC fuses/MCCBs", "Detuned reactors when needed"], designChecks: ["kVAr sizing", "Harmonic environment", "Ventilation", "Discharge resistors", "Stage protection"]),
    BoardType(id: "control", name: "Control Board", subtitle: "Controls and automation", symbol: "switch.2", color: Color(hex: 0xD85CFF), localName: "לוח פיקוד", overview: "A control panel focused on command, indication, automation and interlocking rather than heavy power distribution.", typicalUses: ["Machine control", "Pump control", "HVAC control", "Process automation"], typicalComponents: ["PLC or controller", "Relays", "Timers", "Power supplies", "Terminals", "Selector switches and lamps"], designChecks: ["Control voltage", "Input/output list", "Fail-safe logic", "Cable numbering", "Door controls and indicators"]),
    BoardType(id: "lighting", name: "Lighting", subtitle: "Lighting boards", symbol: "lightbulb.fill", color: Color(hex: 0xFFD60A), localName: "לוח תאורה", overview: "A distribution board dedicated to lighting circuits, lighting control and sometimes emergency lighting groups.", typicalUses: ["Office floors", "Public areas", "Exterior lighting", "Emergency lighting circuits"], typicalComponents: ["MCBs/RCBOs", "Contactors", "Astronomical clock or timer", "Lighting controllers", "RCD protection"], designChecks: ["Circuit grouping", "Emergency/normal separation", "Control schedule", "RCD selectivity", "Clear room/area labels"]),
    BoardType(id: "power", name: "Power", subtitle: "Power boards", symbol: "powerplug.fill", color: Color(hex: 0xFF4E5F), localName: "לוח כח", overview: "A board feeding socket circuits, small power, dedicated equipment outlets and general power loads.", typicalUses: ["Workstations", "Kitchen equipment", "Workshop outlets", "Mechanical service outlets"], typicalComponents: ["MCBs/RCBOs", "RCDs", "Socket circuit terminals", "Main isolator", "N and PE bars"], designChecks: ["Load per circuit", "RCD protection", "Dedicated equipment circuits", "Socket labeling", "Spare capacity"]),
    BoardType(id: "apartment", name: "Apartment", subtitle: "Residential boards", symbol: "house.fill", color: Color(hex: 0x35C7D7), localName: "לוח דירתי", overview: "A residential distribution board serving an apartment or small dwelling, usually with final circuits for lighting, sockets, HVAC and appliances.", typicalUses: ["Apartments", "Small homes", "Residential units"], typicalComponents: ["Main switch", "RCD/RCCB", "MCBs/RCBOs", "Surge protection", "N and PE bars"], designChecks: ["Circuit count", "RCD arrangement", "Main rating", "Future spaces", "Clear room/appliance labels"]),
    BoardType(id: "generator", name: "Generator Board", subtitle: "Generator distribution", symbol: "fuelpump.fill", color: Color(hex: 0xFF9F0A), localName: "לוח גנרטור", overview: "A board associated with generator output, protection, synchronization or distribution to emergency/backup loads.", typicalUses: ["Backup supply", "Emergency power rooms", "Generator packages"], typicalComponents: ["Generator MCCB/ACB", "Controller terminals", "Meters", "Protection relays", "Outgoing breakers"], designChecks: ["Generator rating", "Earthing/neutral method", "ATS interface", "Short-circuit contribution", "Load shedding"]),
    BoardType(id: "ups", name: "UPS Board", subtitle: "Critical power", symbol: "battery.100percent.bolt", color: Color(hex: 0x34C759), localName: "לוח UPS", overview: "A board feeding or distributing uninterruptible power supply circuits for critical equipment.", typicalUses: ["Server rooms", "Security systems", "Medical/critical equipment", "Control systems"], typicalComponents: ["UPS input/output breakers", "Maintenance bypass", "Critical load MCBs", "Meters", "Warning labels"], designChecks: ["Bypass arrangement", "Load criticality", "Neutral continuity", "Battery room/interface", "Segregation from normal power"]),
    BoardType(id: "pv", name: "PV Solar", subtitle: "Solar AC/DC board", symbol: "sun.max.fill", color: Color(hex: 0xFFCC00), localName: "לוח סולארי", overview: "A photovoltaic board for inverter AC output, DC string combining, protection or solar system isolation.", typicalUses: ["Rooftop PV", "Commercial solar systems", "Inverter rooms"], typicalComponents: ["DC isolators", "String fuses", "SPD DC/AC", "AC breakers", "Inverter feeders"], designChecks: ["DC voltage rating", "Polarity", "SPD type", "Inverter AC rating", "Warning labels and isolation"]),
    BoardType(id: "ev", name: "EV Charging", subtitle: "Charging infrastructure", symbol: "ev.charger.fill", color: Color(hex: 0x00C7BE), localName: "לוח טעינה לרכב חשמלי", overview: "A board dedicated to electric vehicle charging circuits and load management equipment.", typicalUses: ["Parking lots", "Residential charging rooms", "Commercial EV chargers"], typicalComponents: ["MCCBs/MCBs", "RCD type A/B or RDC-DD coordination", "Meters", "Load management controller", "Surge protection"], designChecks: ["Charger rating", "Diversity/load management", "RCD type", "Cable route length", "Metering and access"]),
    BoardType(id: "temporary-site", name: "Site Temporary", subtitle: "Construction site power", symbol: "hammer.fill", color: Color(hex: 0xAEB4BC), localName: "לוח זמני לאתר", overview: "A temporary distribution board for construction sites or temporary works, often ruggedized and protected for outdoor/site conditions.", typicalUses: ["Construction sites", "Temporary events", "Site cabins", "Temporary tools"], typicalComponents: ["Main breaker/RCD", "Socket outlets", "Outgoing MCBs", "Enclosure with high IP rating", "Earthing terminals"], designChecks: ["Outdoor/IP protection", "RCD protection", "Mechanical protection", "Temporary earthing", "Inspection labeling"]),
    BoardType(id: "fire-pump", name: "Fire Pump", subtitle: "Life-safety motor board", symbol: "flame.fill", color: Color(hex: 0xFF453A), localName: "לוח משאבות כיבוי", overview: "A specialized control and power board for fire pumps and related life-safety equipment.", typicalUses: ["Fire pump rooms", "Sprinkler systems", "Emergency water systems"], typicalComponents: ["Main isolator/breaker", "Pump contactors or soft starter", "Controller", "Alarms", "Pressure switch terminals"], designChecks: ["Life-safety supply requirements", "Alarm outputs", "Manual/auto operation", "Motor starting current", "Clear emergency labeling"]),
    BoardType(id: "hvac", name: "HVAC", subtitle: "Mechanical services", symbol: "fan.fill", color: Color(hex: 0x5AC8FA), localName: "לוח מיזוג / אוורור", overview: "A board serving chillers, AHUs, fans, dampers and mechanical ventilation/control loads.", typicalUses: ["Air handling units", "Ventilation fans", "Chillers", "Mechanical plant rooms"], typicalComponents: ["MCCBs/MCBs", "Contactors", "VFDs", "Overloads", "Control relays", "BMS terminals"], designChecks: ["Motor and drive heat", "BMS interface", "Local/remote control", "Maintenance isolators", "Fault indication"]),
    BoardType(id: "elv-bms", name: "ELV / BMS", subtitle: "Low-current systems", symbol: "network", color: Color(hex: 0xAF52DE), localName: "לוח תקשורת / בקרה", overview: "A low-current or building-management panel for control, communications and monitoring equipment. It is usually separate from power distribution.", typicalUses: ["BMS panels", "Security interfaces", "Communication cabinets", "Monitoring systems"], typicalComponents: ["Power supplies", "Network switches", "Controllers", "Relays", "Terminal blocks"], designChecks: ["Separation from power circuits", "24VDC load sizing", "Network labeling", "Backup supply", "Cable management"]),
    BoardType(id: "pcc", name: "PCC", subtitle: "Power control center", symbol: "slider.horizontal.3", color: Color(hex: 0x30D158), localName: "לוח כח ראשי / PCC", overview: "A power control center is a heavy-duty low-voltage assembly used for main feeders, large loads and plant-level power distribution. It often sits close to transformers, generators or major mechanical loads.", typicalUses: ["Industrial plant rooms", "Large mechanical services", "Transformer outgoing distribution"], typicalComponents: ["ACBs/MCCBs", "Busbar system", "Metering", "Protection relays", "Outgoing feeders"], designChecks: ["Short-circuit level", "Form of separation", "Thermal rise", "Access and maintenance clearance", "Feeder selectivity"]),
    BoardType(id: "synchronizing", name: "Synchronizing", subtitle: "Generator sync board", symbol: "arrow.triangle.2.circlepath", color: Color(hex: 0x64D2FF), localName: "לוח סנכרון", overview: "A synchronizing board controls and protects parallel operation of generators or generator-to-grid arrangements. It monitors voltage, frequency, phase angle and load sharing before closing breakers.", typicalUses: ["Multiple generator sets", "Generator-grid parallel operation", "Critical facilities"], typicalComponents: ["Sync controller", "ACB/MCCB control", "Protection relays", "Meters", "Load sharing modules"], designChecks: ["Phase sequence", "Voltage and frequency windows", "Breaker interlocks", "Load sharing setup", "Protection coordination"]),
    BoardType(id: "bypass", name: "Bypass Board", subtitle: "Maintenance bypass", symbol: "arrow.uturn.right.circle.fill", color: Color(hex: 0xFF9F0A), localName: "לוח מעקף", overview: "A bypass board allows critical loads to remain supplied while UPS, ATS or other equipment is isolated for service. It must make the switching path clear and hard to operate incorrectly.", typicalUses: ["UPS maintenance", "ATS maintenance", "Critical service isolation"], typicalComponents: ["Bypass switch", "Interlocked isolators", "Indication lamps", "Warning labels", "Meters"], designChecks: ["Mechanical/electrical interlocks", "Clear operating sequence", "Neutral arrangement", "Load transfer path", "Warning labels"]),
    BoardType(id: "transformer", name: "Transformer Board", subtitle: "Transformer feeder", symbol: "square.stack.3d.up.fill", color: Color(hex: 0xBF5AF2), localName: "לוח שנאי", overview: "A transformer board handles incoming or outgoing protection and distribution around a transformer. It may include LV main protection, metering and temperature/alarm interfaces.", typicalUses: ["Transformer rooms", "Industrial substations", "Building LV rooms"], typicalComponents: ["Main ACB/MCCB", "Meters", "Protection relay inputs", "Temperature alarm terminals", "Busbars"], designChecks: ["Transformer kVA", "Inrush and protection settings", "Earthing system", "Ventilation", "Cable termination space"]),
    BoardType(id: "pump", name: "Pump Board", subtitle: "Water and process pumps", symbol: "drop.fill", color: Color(hex: 0x0A84FF), localName: "לוח משאבות", overview: "A pump board controls one or more water, sewage or process pumps. It may include direct-on-line starters, star-delta, soft starters or drives depending on pump size.", typicalUses: ["Booster pumps", "Sewage pumps", "Process pumps", "Irrigation systems"], typicalComponents: ["Contactors", "Overload relays", "VFDs or soft starters", "Float/pressure inputs", "Run/fault indication"], designChecks: ["Pump kW", "Duty/standby logic", "Sensor inputs", "Manual/auto control", "Alarm output"]),
    BoardType(id: "elevator", name: "Elevator", subtitle: "Lift supply board", symbol: "arrow.up.arrow.down.square.fill", color: Color(hex: 0x5E78FF), localName: "לוח מעלית", overview: "An elevator board supplies lift controllers and associated services. It often needs clear isolation, dedicated feeds and coordination with emergency or generator-backed supply.", typicalUses: ["Passenger lifts", "Service lifts", "Lift machine rooms"], typicalComponents: ["Main isolator/MCCB", "Auxiliary MCBs", "SPD", "Meters", "Emergency supply interface"], designChecks: ["Dedicated supply", "Rescue/emergency power", "Isolation access", "Labeling", "Manufacturer requirements"]),
    BoardType(id: "outdoor-lighting", name: "Outdoor Lighting", subtitle: "Street and facade lighting", symbol: "lightbulb.2.fill", color: Color(hex: 0xFFD60A), localName: "לוח תאורת חוץ", overview: "An outdoor lighting board feeds street, parking, facade or landscape lighting. It usually combines protection with automatic schedules and weather-ready enclosure choices.", typicalUses: ["Parking lots", "Street lighting", "Facade lighting", "Landscape lighting"], typicalComponents: ["MCBs/RCBOs", "Contactors", "Astronomical clock", "SPD", "Photocell inputs"], designChecks: ["IP rating", "Earthing", "Cable lengths", "Control schedule", "Surge exposure"]),
    BoardType(id: "pdu", name: "PDU", subtitle: "Data center distribution", symbol: "server.rack", color: Color(hex: 0x32D74B), localName: "לוח PDU", overview: "A power distribution unit board distributes critical power to server racks, telecom equipment or data cabinets. It often emphasizes metering, redundancy and clean circuit identification.", typicalUses: ["Server rooms", "Data centers", "Telecom spaces"], typicalComponents: ["Input MCCB", "Metering", "Branch MCBs", "RCD/RCM where required", "Monitoring modules"], designChecks: ["A/B feed separation", "Load monitoring", "Circuit labeling", "Neutral loading", "Thermal management"]),
    BoardType(id: "harmonic-filter", name: "Harmonic Filter", subtitle: "Power quality", symbol: "waveform.path", color: Color(hex: 0xFF375F), localName: "לוח סינון הרמוניות", overview: "A harmonic filter board reduces harmonic distortion caused by drives, UPS systems and non-linear loads. It may be passive or active depending on the installation.", typicalUses: ["Drive-heavy plants", "UPS rooms", "Large commercial buildings", "Power quality correction"], typicalComponents: ["Active filter module", "Detuned reactors", "Capacitors", "MCCB/fuses", "Controller"], designChecks: ["Measured THD", "Load profile", "Ventilation", "Protection sizing", "Power quality target"]),
    BoardType(id: "fire-alarm", name: "Fire Alarm", subtitle: "Life-safety controls", symbol: "bell.and.waves.left.and.right.fill", color: Color(hex: 0xFF453A), localName: "לוח גילוי אש", overview: "A fire alarm or life-safety interface panel organizes control power, relays and monitored circuits around fire detection and emergency systems. It should remain clearly separated from ordinary power distribution.", typicalUses: ["Fire alarm interfaces", "Smoke control interfaces", "Emergency command panels"], typicalComponents: ["Power supplies", "Relays", "Monitoring modules", "Terminal blocks", "Battery/interface wiring"], designChecks: ["Life-safety labeling", "Circuit supervision", "Backup supply", "Cable separation", "Alarm/fault outputs"]),
    BoardType(id: "earthing", name: "Earthing", subtitle: "Grounding and bonding", symbol: "point.bottomleft.forward.to.point.topright.scurvepath", color: Color(hex: 0x8E8E93), localName: "לוח הארקה", overview: "An earthing or bonding board centralizes grounding bars, test links and bonding connections for an installation. It is often simple physically but very important for safety and documentation.", typicalUses: ["Main earthing terminals", "Lightning protection bonds", "Telecom bonding", "Industrial equipotential bonding"], typicalComponents: ["Copper earth bar", "Test links", "Labels", "Bonding terminals", "Surge protection bonds"], designChecks: ["Conductor sizes", "Continuity", "Labeling", "Test accessibility", "Separation from live parts"])
  ]
}

struct ProjectItem: Identifiable {
  let id: String
  let name: String
  let customer: String
  let detail: String
  let status: String
  var color: Color
  var dueDate: Date? = nil
  var schemeAttachments: [SchemeAttachment] = []

  /// Photos are held as image-store tokens, not as decoded UIImages, so a
  /// project with a thousand photos costs the same to keep in memory as one
  /// with none. The accessors below resolve them on demand.
  var coverToken: String? = nil
  var photoTokens: [String] = []

  var coverImage: UIImage? {
    get { ImageStore.shared.image(for: coverToken) }
    set { coverToken = ImageStore.shared.store(newValue) }
  }

  /// Cheap enough for list rows — prefer this over [coverImage] in scrolling
  /// views, which would decode the full-size original per row.
  var coverThumbnail: UIImage? {
    ImageStore.shared.thumbnail(for: coverToken)
  }

  var photoCount: Int { photoTokens.count }

  /// Every token this project owns, for orphan cleanup.
  var imageTokens: [String] {
    ([coverToken] + photoTokens + schemeAttachments.map(\.imageToken)).compactMap { $0 }
  }

  var searchText: String {
    "\(name) \(customer) \(detail) \(status) \(dueDate.map { DateDisplay.due.string(from: $0) } ?? "") \(schemeAttachments.map(\.name).joined(separator: " "))"
  }

  var persistenceSignature: String {
    let coverSignature = ImageStore.shared.signature(for: coverToken)
    let photoSignature = photoTokens.joined(separator: "|")
    let schemeSignature = schemeAttachments.map(\.persistenceSignature).joined(separator: "|")
    return [
      id, name, customer, detail, status, "\(color.archiveHex)",
      coverSignature, photoSignature,
      "\(dueDate?.timeIntervalSince1970 ?? 0)",
      schemeSignature
    ].joined(separator: "||")
  }

  static let samples: [ProjectItem] = []
}

struct ComponentGroup: Identifiable {
  let id: String
  let name: String
  let items: [PanelComponent]

  static let samples = [
    ComponentGroup(id: "mcbs", name: "MCBs", items: [
      PanelComponent(id: "abb-s201-1p", manufacturer: "ABB", type: "MCB", model: "S201", rating: "Set A", poles: "1P", curve: "B/C/D Curve", about: "Single-pole miniature circuit breaker for one final circuit, protecting against overload and short circuit. Pick the curve for the load: B for resistive and lighting, C for general mixed loads, D for high-inrush motors and transformers."),
      PanelComponent(id: "abb-s202-2p", manufacturer: "ABB", type: "MCB", model: "S202", rating: "Set A", poles: "2P", curve: "B/C/D Curve", about: "Two-pole MCB that breaks line and neutral together, common on single-phase circuits where full isolation is required for maintenance."),
      PanelComponent(id: "abb-s203-3p", manufacturer: "ABB", type: "MCB", model: "S203", rating: "Set A", poles: "3P", curve: "B/C/D Curve", about: "Three-pole MCB for three-phase loads. All three poles trip together so a fault on one phase cannot leave a motor running single-phased."),
      PanelComponent(id: "abb-s204-4p", manufacturer: "ABB", type: "MCB", model: "S204", rating: "Set A", poles: "4P", curve: "B/C/D Curve", about: "Four-pole MCB breaking three phases plus neutral, used where the neutral must be isolated, such as on generator or changeover circuits."),
      PanelComponent(id: "abb-sn201-1pn", manufacturer: "ABB", type: "MCB", model: "SN201", rating: "Set A", poles: "1P+N", curve: "B/C Curve", about: "One pole plus switched neutral in a single module width, the usual choice for apartment and lighting boards where DIN space is tight."),
      PanelComponent(id: "abb-s300-p", manufacturer: "ABB", type: "MCB", model: "S300 P", rating: "Set A", poles: "1P-4P", curve: "Industrial", about: "Industrial-grade MCB with a higher breaking capacity than domestic ranges. Specify where the prospective short-circuit current at the board exceeds what a standard 6kA device can clear."),
      PanelComponent(id: "abb-su200", manufacturer: "ABB", type: "MCB", model: "SU200", rating: "Set A", poles: "1P-4P", curve: "UL/CSA", about: "MCB built to UL and CSA ratings for panels destined for North American markets or for machinery exported there."),
      PanelComponent(id: "schneider-ic60n", manufacturer: "Schneider", type: "MCB", model: "Acti9 iC60N", rating: "Set A", poles: "1P-4P", curve: "B/C/D", about: "Standard Acti9 MCB at 6kA breaking capacity, suitable for most commercial final circuits. Pairs with Vigi add-on blocks if earth-leakage protection is needed later."),
      PanelComponent(id: "schneider-ic60h", manufacturer: "Schneider", type: "MCB", model: "Acti9 iC60H", rating: "Set A", poles: "1P-4P", curve: "B/C/D", about: "Higher breaking capacity version of the iC60 for boards closer to the transformer where fault levels are greater."),
      PanelComponent(id: "siemens-5sy", manufacturer: "Siemens", type: "MCB", model: "SENTRON 5SY", rating: "Set A", poles: "1P-4P", curve: "B/C/D", about: "General purpose SENTRON MCB for final circuit protection across lighting, socket and small power circuits."),
      PanelComponent(id: "siemens-5sl", manufacturer: "Siemens", type: "MCB", model: "SENTRON 5SL", rating: "Set A", poles: "1P-4P", curve: "B/C/D", about: "Compact economy MCB for high-volume repeat circuits in residential and light commercial boards."),
      PanelComponent(id: "eaton-faz", manufacturer: "Eaton", type: "MCB", model: "FAZ", rating: "Set A", poles: "1P-4P", curve: "B/C/D", about: "Eaton MCB range with a wide curve and rating selection, frequently specified in machine-building and OEM panels.")
    ]),
    ComponentGroup(id: "rcbo", name: "RCBOs & RCDs", items: [
      PanelComponent(id: "abb-ds201-1pn", manufacturer: "ABB", type: "RCBO", model: "DS201", rating: "Set A", poles: "1P+N", curve: "B/C Curve + RCD", about: "Combined MCB and residual current device in one module: overload, short-circuit and earth-leakage protection for a single circuit. Common at 30mA for socket outlets requiring additional protection."),
      PanelComponent(id: "abb-ds202-2p", manufacturer: "ABB", type: "RCBO", model: "DS202", rating: "Set A", poles: "2P", curve: "B/C Curve + RCD", about: "Two-pole RCBO providing overcurrent and earth-leakage protection while isolating both line and neutral."),
      PanelComponent(id: "abb-ds203-3p", manufacturer: "ABB", type: "RCBO", model: "DS203", rating: "Set A", poles: "3P", curve: "B/C Curve + RCD", about: "Three-pole RCBO for three-phase circuits needing residual current protection without a separate upstream RCCB."),
      PanelComponent(id: "abb-ds204-4p", manufacturer: "ABB", type: "RCBO", model: "DS204", rating: "Set A", poles: "4P", curve: "B/C Curve + RCD", about: "Four-pole RCBO covering three phases and neutral. Used where individual circuit discrimination matters more than a single shared RCCB."),
      PanelComponent(id: "abb-ds200", manufacturer: "ABB", type: "RCBO", model: "DS200", rating: "up to 63A", poles: "1P+N/3P+N", curve: "30-300mA, 10kA", about: "Higher breaking capacity RCBO range for boards with elevated fault levels where a standard 6kA device would be inadequate."),
      PanelComponent(id: "schneider-acti9-rcbo", manufacturer: "Schneider", type: "RCBO", model: "Acti9 iDPN Vigi", rating: "Set A", poles: "1P+N", curve: "B/C + RCD", about: "Acti9 RCBO in one module width, giving each circuit its own earth-leakage protection so a single fault does not trip an entire board section."),
      PanelComponent(id: "generic-rccb", manufacturer: "Generic", type: "RCD/RCCB", model: "Residual Current Device", rating: "Set A", poles: "2P/4P", curve: "30-300mA", about: "Residual current circuit breaker detecting earth leakage but offering no overload protection, so it always sits behind or above separate overcurrent devices. Choose the type by load: AC for simple resistive, A where electronics are present, B where drives or DC components can produce smooth residual currents."),
      PanelComponent(id: "abb-f200", manufacturer: "ABB", type: "RCD/RCCB", model: "F200", rating: "25-125A", poles: "2P/4P", curve: "30-500mA, Type AC/A", about: "Residual current circuit breaker protecting a group of circuits against earth leakage. At 30mA it provides additional protection against electric shock; at 300mA it is normally used for fire protection on a whole section."),
      PanelComponent(id: "schneider-iid", manufacturer: "Schneider", type: "RCD/RCCB", model: "Acti9 iID", rating: "25-100A", poles: "2P/4P", curve: "30-300mA, Type AC/A/B", about: "Acti9 residual current device available in Type A and Type B. Type B is required where variable speed drives can produce smooth DC residual current that would blind a Type AC device."),
      PanelComponent(id: "siemens-5sv", manufacturer: "Siemens", type: "RCD/RCCB", model: "SENTRON 5SV", rating: "25-125A", poles: "2P/4P", curve: "30-300mA", about: "SENTRON RCCB for group earth-leakage protection. Consider splitting circuits across several RCCBs so one nuisance trip does not take out an entire board.")
    ]),
    ComponentGroup(id: "mccbs", name: "MCCBs & ACBs", items: [
      PanelComponent(id: "abb-tmax-xt1", manufacturer: "ABB", type: "MCCB", model: "SACE Tmax XT1", rating: "Set A - max 160A", poles: "3P/4P", curve: "Basic - thermal-magnetic", about: "Compact moulded case breaker for feeders up to 160A with a fixed thermal-magnetic trip. Suits outgoing ways on small distribution boards."),
      PanelComponent(id: "abb-tmax-xt2", manufacturer: "ABB", type: "MCCB", model: "SACE Tmax XT2", rating: "Set A - max 160A", poles: "3P/4P", curve: "Heavy duty - TM/Ekip Dip/Touch", about: "160A frame with a choice of thermal-magnetic or Ekip electronic trip units, giving adjustable settings for selectivity against downstream devices."),
      PanelComponent(id: "abb-tmax-xt3", manufacturer: "ABB", type: "MCCB", model: "SACE Tmax XT3", rating: "Set A - max 250A", poles: "3P/4P", curve: "Basic - thermal-magnetic", about: "250A frame thermal-magnetic breaker for mid-size feeders and sub-board supplies."),
      PanelComponent(id: "abb-tmax-xt4", manufacturer: "ABB", type: "MCCB", model: "SACE Tmax XT4", rating: "Set A - max 250A", poles: "3P/4P", curve: "Heavy duty - TM/Ekip Dip/Touch", about: "250A frame with electronic trip options, used where adjustable overload and instantaneous settings are needed to coordinate with upstream protection."),
      PanelComponent(id: "abb-tmax-xt5", manufacturer: "ABB", type: "MCCB", model: "SACE Tmax XT5", rating: "Set A - max 630A", poles: "3P/4P", curve: "Heavy duty - TM/Ekip Dip/Touch", about: "400 to 630A frame for major feeders, transformer outgoings and sub-main distribution."),
      PanelComponent(id: "abb-tmax-xt6", manufacturer: "ABB", type: "MCCB", model: "SACE Tmax XT6", rating: "Set A - max 1000A", poles: "3P/4P", curve: "Basic - thermal-magnetic/Ekip Dip", about: "630 to 800A frame typically used as a main incomer on medium boards or feeding large mechanical plant."),
      PanelComponent(id: "abb-tmax-xt7", manufacturer: "ABB", type: "MCCB", model: "SACE Tmax XT7", rating: "Set A - max 1600A", poles: "3P/4P", curve: "Heavy duty - Ekip Dip/Touch", about: "1000 to 1600A frame for main incoming protection on large distribution boards where an air circuit breaker is not required."),
      PanelComponent(id: "abb-tmax-xt7m", manufacturer: "ABB", type: "MCCB", model: "SACE Tmax XT7 M", rating: "Set A - max 1600A", poles: "3P/4P", curve: "Motorized - Ekip Dip/Touch", about: "Motorised version of the XT7 for remote or automatic operation, used in transfer schemes and where remote tripping is part of the control philosophy."),
      PanelComponent(id: "schneider-nsx", manufacturer: "Schneider", type: "MCCB", model: "Compact NSX", rating: "16-630A", poles: "3P/4P", curve: "TM/Micrologic", about: "Compact NSX moulded case breaker with interchangeable TM or Micrologic trip units. The electronic units add metering and adjustable protection curves."),
      PanelComponent(id: "schneider-nsj", manufacturer: "Schneider", type: "MCCB", model: "EasyPact CVS/NSX", rating: "16-630A", poles: "3P/4P", curve: "Thermal Magnetic", about: "Cost-focused moulded case breaker for standard distribution feeders where adjustable electronic protection is not required."),
      PanelComponent(id: "siemens-3va1", manufacturer: "Siemens", type: "MCCB", model: "SENTRON 3VA1", rating: "16-160A", poles: "3P/4P", curve: "Thermal Magnetic", about: "SENTRON moulded case breaker with thermal-magnetic trip for general distribution feeders."),
      PanelComponent(id: "siemens-3va2", manufacturer: "Siemens", type: "MCCB", model: "SENTRON 3VA2", rating: "25-630A", poles: "3P/4P", curve: "ETU", about: "SENTRON breaker with electronic trip units and optional communications, suited to boards where energy data and selectivity are both required."),
      PanelComponent(id: "eaton-nzm", manufacturer: "Eaton", type: "MCCB", model: "NZM", rating: "20-1600A", poles: "3P/4P", curve: "Electronic/TM", about: "Eaton moulded case breaker range covering a wide band of frame sizes, common as both incomer and outgoing protection in industrial boards."),
      PanelComponent(id: "eaton-bzmx", manufacturer: "Eaton", type: "MCCB", model: "BZMX", rating: "15-250A", poles: "3P/4P", curve: "Thermal Magnetic", about: "Compact moulded case breaker for smaller feeders where space in the board is limited."),
      PanelComponent(id: "generic-acb", manufacturer: "Generic", type: "ACB", model: "Air Circuit Breaker", rating: "Set A", poles: "3P/4P", curve: "Withdrawable/fixed", about: "Air circuit breaker for main incoming protection at high current, typically above 800A. Decide early whether it is fixed or withdrawable, since withdrawable versions need far more depth and a defined racking area in front of the board."),
      PanelComponent(id: "abb-emax2", manufacturer: "ABB", type: "ACB", model: "SACE Emax 2", rating: "630-6300A", poles: "3P/4P", curve: "Fixed or withdrawable", about: "Air circuit breaker for main incoming protection with Ekip trip units offering full protection, metering and communications. Withdrawable versions allow maintenance without a full shutdown but need defined racking space in front of the board."),
      PanelComponent(id: "schneider-mtz", manufacturer: "Schneider", type: "ACB", model: "MasterPact MTZ", rating: "630-6300A", poles: "3P/4P", curve: "Micrologic X", about: "Main air circuit breaker with Micrologic X control units providing measurement, diagnostics and remote connectivity. Common as the incomer on large main LV boards."),
      PanelComponent(id: "siemens-3wa", manufacturer: "Siemens", type: "ACB", model: "SENTRON 3WA", rating: "630-6300A", poles: "3P/4P", curve: "ETU trip unit", about: "SENTRON air circuit breaker for main and coupler positions. Confirm the trip unit family early since it drives the metering and communications you can offer later."),
      PanelComponent(id: "eaton-izmx", manufacturer: "Eaton", type: "ACB", model: "IZMX", rating: "630-1600A", poles: "3P/4P", curve: "Fixed or withdrawable", about: "Compact air circuit breaker for main protection where panel depth is constrained but ACB features are still required.")
    ]),
    ComponentGroup(id: "surge-arc", name: "Surge & Arc Protection", items: [
      PanelComponent(id: "generic-spd", manufacturer: "Generic", type: "SPD", model: "Surge Protection Device", rating: "Type 2", poles: "3P+N", curve: "40kA", about: "Surge protection device diverting transient overvoltage from lightning and switching to earth. Type 1 goes at the origin where there is a lightning protection system, Type 2 at distribution boards. It needs a correctly rated backup fuse or breaker and the shortest possible connecting leads."),
      PanelComponent(id: "abb-ovr", manufacturer: "ABB", type: "SPD", model: "OVR T2", rating: "Type 2", poles: "1P-4P", curve: "40kA Imax", about: "Type 2 surge arrester for distribution boards, diverting switching and induced lightning transients. Keep the connecting leads under half a metre or the let-through voltage rises sharply."),
      PanelComponent(id: "schneider-iprd", manufacturer: "Schneider", type: "SPD", model: "Acti9 iPRD", rating: "Type 2", poles: "1P-4P", curve: "20-65kA", about: "Acti9 surge protection with a status window showing when the cartridge is spent, and a remote signalling contact so a failed arrester does not sit unnoticed."),
      PanelComponent(id: "phoenix-valms", manufacturer: "Phoenix", type: "SPD", model: "VAL-MS", rating: "Type 2", poles: "1P-4P", curve: "Pluggable", about: "Pluggable surge protection where the protection module can be replaced without disturbing the wiring, useful on boards in high-exposure locations."),
      PanelComponent(id: "abb-afdd", manufacturer: "ABB", type: "AFDD", model: "S-ARC1", rating: "6-40A", poles: "1P+N", curve: "B/C Curve", about: "Arc fault detection device recognising the signature of a series or parallel arcing fault that a normal MCB or RCD will not see. Specified for fire risk areas such as sleeping accommodation and timber structures."),
      PanelComponent(id: "siemens-5sm6", manufacturer: "Siemens", type: "AFDD", model: "5SM6", rating: "6-40A", poles: "1P+N", curve: "Combined MCB", about: "Arc fault detection combined with overcurrent protection in one device, reducing the DIN width needed compared with separate units."),
      PanelComponent(id: "abb-cm-iwx", manufacturer: "ABB", type: "RCM", model: "CM-IWx", rating: "30mA-30A", poles: "DIN", curve: "Residual current monitor", about: "Residual current monitor that measures and reports leakage continuously instead of tripping, letting you catch a deteriorating circuit before it causes an outage.")
    ]),
    ComponentGroup(id: "switching", name: "Switching & Isolation", items: [
      PanelComponent(id: "generic-isolator", manufacturer: "Generic", type: "Isolator", model: "Load break switch", rating: "Set A", poles: "3P/4P", curve: "Door-coupled", about: "Load break switch providing a visible, lockable point of isolation so a board or section can be worked on safely. Rated for making and breaking load current, unlike a plain disconnector."),
      PanelComponent(id: "abb-ot", manufacturer: "ABB", type: "Isolator", model: "OT switch disconnector", rating: "16-3150A", poles: "3P/4P", curve: "Door or base mount", about: "Switch disconnector for main isolation or outgoing feeders, available with door-coupled rotary handles that can be padlocked off for safe working."),
      PanelComponent(id: "schneider-ins", manufacturer: "Schneider", type: "Isolator", model: "Interpact INS", rating: "40-2500A", poles: "3P/4P", curve: "Load break", about: "Load break switch for isolation duty on incomers and outgoing feeders where switching capability without protection is required."),
      PanelComponent(id: "generic-changeover", manufacturer: "Generic", type: "Changeover Switch", model: "Manual changeover", rating: "Set A", poles: "4P", curve: "I-0-II", about: "Manual changeover switch selecting between two supplies, typically utility and generator. The I-0-II arrangement mechanically prevents both sources being connected at once."),
      PanelComponent(id: "socomec-sirco", manufacturer: "Socomec", type: "Changeover Switch", model: "Sirco MOT", rating: "125-3200A", poles: "3P/4P", curve: "Motorised I-0-II", about: "Motorised changeover switch for automatic transfer between utility and generator, mechanically interlocked so both sources can never be paralleled."),
      PanelComponent(id: "abb-ats021", manufacturer: "ABB", type: "ATS Controller", model: "ATS021", rating: "24VDC", poles: "DIN", curve: "Auto transfer control", about: "Automatic transfer controller monitoring the normal supply and commanding changeover to the standby source. Set the transfer and return delays deliberately so brief dips do not start the generator unnecessarily."),
      PanelComponent(id: "deepsea-dse", manufacturer: "Generic", type: "ATS Controller", model: "Generator controller", rating: "12/24VDC", poles: "Door mount", curve: "Auto mains failure", about: "Auto mains failure controller starting the generator on supply loss, transferring load and returning it once the mains is stable. It needs clear wiring to the generator start contacts and both source sensing points."),
      PanelComponent(id: "generic-fuse", manufacturer: "Generic", type: "Fuse", model: "NH fuse link", rating: "Set A", poles: "1P", curve: "gG/gL", about: "NH fuse link giving very high breaking capacity in a compact body, often used ahead of large feeders or where the fault level exceeds what a breaker can handle economically. gG is for general cable protection, aM for motor circuits."),
      PanelComponent(id: "generic-fuse-holder", manufacturer: "Generic", type: "Fuse Holder", model: "DIN fuse holder", rating: "Set A", poles: "1P/3P", curve: "10x38/NH", about: "DIN rail fuse carrier holding cartridge or NH fuse links, giving isolation when the carrier is withdrawn. Confirm the fuse size it accepts and whether a blown-fuse indicator is required."),
      PanelComponent(id: "abb-af16-30-10", manufacturer: "ABB", type: "Contactor", model: "AF16-30-10", rating: "16A", poles: "3P", curve: "1NO Aux", about: "Three-pole contactor around 16A AC-3 with one normally-open auxiliary, sized for small motors and controlled loads. The AF electronic coil accepts a wide voltage band, which reduces the number of coil variants to stock."),
      PanelComponent(id: "abb-af26-30-00", manufacturer: "ABB", type: "Contactor", model: "AF26-30-00", rating: "26A", poles: "3P", curve: "No Aux", about: "Mid-size three-pole contactor for motor and load switching where no built-in auxiliary contact is required."),
      PanelComponent(id: "abb-af38-30-00", manufacturer: "ABB", type: "Contactor", model: "AF38-30-00", rating: "38A", poles: "3P", curve: "No Aux", about: "Larger three-pole contactor for motors up to roughly 18.5kW at 400V. Check AC-3 rating against motor full-load amps rather than the AC-1 figure."),
      PanelComponent(id: "schneider-lc1d", manufacturer: "Schneider", type: "Contactor", model: "TeSys D", rating: "9-150A", poles: "3P", curve: "AC-3", about: "TeSys D contactor, the workhorse for motor starters and load switching. Add-on auxiliary blocks and mechanical interlocks let it build reversing and star-delta arrangements."),
      PanelComponent(id: "siemens-3rt", manufacturer: "Siemens", type: "Contactor", model: "SIRIUS 3RT", rating: "9-250A", poles: "3P", curve: "AC-3", about: "SIRIUS contactor sized by frame across a wide kW range, designed to clip together with matching 3RU or 3RB overload relays into a compact starter."),
      PanelComponent(id: "eaton-dilm", manufacturer: "Eaton", type: "Contactor", model: "DILM", rating: "7-170A", poles: "3P", curve: "AC-3", about: "Eaton DILM contactor range with matching overloads and accessory blocks, common in machine control panels.")
    ]),
    ComponentGroup(id: "drives", name: "Drives & Soft Starters", items: [
      PanelComponent(id: "abb-acs355", manufacturer: "ABB", type: "VFD", model: "ACS355", rating: "0.37-22kW", poles: "3PH", curve: "Machinery drive", about: "Machinery drive for conveyors, mixers and small pumps, built for panel mounting with straightforward parameter setup."),
      PanelComponent(id: "abb-acs580", manufacturer: "ABB", type: "VFD", model: "ACS580", rating: "0.75-250kW", poles: "3PH", curve: "General purpose", about: "General purpose drive covering most building services and industrial motor loads, with a built-in choke that reduces harmonic current without an external reactor."),
      PanelComponent(id: "abb-ach580", manufacturer: "ABB", type: "VFD", model: "ACH580", rating: "0.75-500kW", poles: "3PH", curve: "HVAC drive", about: "HVAC variant tuned for fans and pumps, including firefighter override and PID control for pressure and flow."),
      PanelComponent(id: "abb-acs880", manufacturer: "ABB", type: "VFD", model: "ACS880", rating: "0.55-3200kW", poles: "3PH", curve: "Industrial drive", about: "Industrial drive for demanding applications including regenerative and common DC bus configurations. Confirm cooling and cabinet depth early, since larger frames are substantial."),
      PanelComponent(id: "schneider-atv12", manufacturer: "Schneider", type: "VFD", model: "Altivar ATV12", rating: "0.18-4kW", poles: "1PH/3PH", curve: "Basic machines", about: "Entry-level drive for small machines and single-phase supplies, typically fitted straight onto the machine panel."),
      PanelComponent(id: "schneider-atv320", manufacturer: "Schneider", type: "VFD", model: "Altivar ATV320", rating: "0.18-15kW", poles: "3PH", curve: "Machine drive", about: "Compact machine drive available in book and compact formats, with integrated safety functions such as Safe Torque Off."),
      PanelComponent(id: "schneider-atv340", manufacturer: "Schneider", type: "VFD", model: "Altivar ATV340", rating: "0.75-75kW", poles: "3PH", curve: "High performance", about: "High performance drive for dynamic machine control where fast response and precise speed regulation matter."),
      PanelComponent(id: "schneider-atv630", manufacturer: "Schneider", type: "VFD", model: "Altivar ATV630", rating: "0.75-315kW", poles: "3PH", curve: "Process drive", about: "Process drive for pumps, fans and compressors with energy-saving control and built-in EMC filtering."),
      PanelComponent(id: "siemens-v20", manufacturer: "Siemens", type: "VFD", model: "SINAMICS V20", rating: "0.12-30kW", poles: "1PH/3PH", curve: "Basic drive", about: "Basic drive for simple fan, pump and conveyor duties where a full parameter set would be overkill."),
      PanelComponent(id: "siemens-g120c", manufacturer: "Siemens", type: "VFD", model: "SINAMICS G120C", rating: "0.55-132kW", poles: "3PH", curve: "Compact drive", about: "Compact single-unit drive combining control and power in one housing, saving panel width against the modular G120."),
      PanelComponent(id: "siemens-g120", manufacturer: "Siemens", type: "VFD", model: "SINAMICS G120", rating: "0.55-250kW", poles: "3PH", curve: "Modular drive", about: "Modular drive where control unit and power module are selected separately, so the same power module can serve different control and communication needs."),
      PanelComponent(id: "danfoss-fc51", manufacturer: "Danfoss", type: "VFD", model: "VLT Micro FC 51", rating: "0.18-22kW", poles: "1PH/3PH", curve: "Micro drive", about: "Micro drive for basic speed control on small motors, common in HVAC and simple machinery."),
      PanelComponent(id: "danfoss-fc202", manufacturer: "Danfoss", type: "VFD", model: "VLT AQUA FC 202", rating: "0.25-1400kW", poles: "3PH", curve: "Pump drive", about: "Drive tuned for water and wastewater duty, with pump-specific features such as dry-run detection, pipe fill and cascade control."),
      PanelComponent(id: "danfoss-fc302", manufacturer: "Danfoss", type: "VFD", model: "VLT Automation FC 302", rating: "0.25-800kW", poles: "3PH", curve: "Automation drive", about: "Automation drive for demanding motor control including closed loop and servo-like applications."),
      PanelComponent(id: "delta-ms300", manufacturer: "Delta", type: "VFD", model: "MS300", rating: "0.4-22kW", poles: "3PH", curve: "Compact vector", about: "Compact vector drive giving good torque control in a small footprint, widely used in OEM machine panels."),
      PanelComponent(id: "delta-c2000", manufacturer: "Delta", type: "VFD", model: "C2000+", rating: "0.75-400kW", poles: "3PH", curve: "Heavy duty vector", about: "Heavy duty vector drive for cranes, hoists and high-torque applications where overload capability matters."),
      PanelComponent(id: "eaton-dc1", manufacturer: "Eaton", type: "VFD", model: "PowerXL DC1", rating: "0.37-11kW", poles: "1PH/3PH", curve: "Compact drive", about: "Compact drive for basic speed control, sized for small panels and simple commissioning."),
      PanelComponent(id: "eaton-dg1", manufacturer: "Eaton", type: "VFD", model: "PowerXL DG1", rating: "0.75-250kW", poles: "3PH", curve: "General purpose", about: "General purpose drive with active energy control, used across pump, fan and conveyor duties."),
      PanelComponent(id: "generic-soft-starter", manufacturer: "Generic", type: "Soft Starter", model: "Motor soft starter", rating: "Set kW", poles: "3PH", curve: "Ramp start/stop", about: "Ramps motor voltage up and down to limit inrush current and mechanical shock on belts, couplings and pumps. Confirm whether a bypass is built in, and remember it still needs upstream isolation and overload protection."),
      PanelComponent(id: "abb-psr", manufacturer: "ABB", type: "Soft Starter", model: "PSR", rating: "3-105A", poles: "3PH", curve: "Compact ramp", about: "Compact soft starter for small motors where the aim is simply to take the shock out of starting. No internal bypass, so allow for the heat it dissipates while ramping."),
      PanelComponent(id: "abb-pse", manufacturer: "ABB", type: "Soft Starter", model: "PSE", rating: "18-370A", poles: "3PH", curve: "Bypass + current limit", about: "Soft starter with internal bypass and current limiting, so it stops dissipating heat once the motor is up to speed."),
      PanelComponent(id: "abb-pstx", manufacturer: "ABB", type: "Soft Starter", model: "PSTX", rating: "30-1250A", poles: "3PH", curve: "Advanced, built-in bypass", about: "Advanced soft starter with built-in bypass, torque control and motor protection, suitable for large pumps and compressors where starting stress is a real problem."),
      PanelComponent(id: "schneider-ats01", manufacturer: "Schneider", type: "Soft Starter", model: "Altistart ATS01", rating: "3-32A", poles: "3PH", curve: "Basic ramp", about: "Basic soft starter for small motors, providing a simple voltage ramp without configurable protection."),
      PanelComponent(id: "schneider-ats22", manufacturer: "Schneider", type: "Soft Starter", model: "Altistart ATS22", rating: "17-590A", poles: "3PH", curve: "Torque control", about: "Soft starter with torque control giving smoother starts and stops on pumps, which reduces water hammer in pipework."),
      PanelComponent(id: "schneider-ats480", manufacturer: "Schneider", type: "Soft Starter", model: "Altistart ATS480", rating: "17-1200A", poles: "3PH", curve: "Advanced, bypass", about: "Advanced soft starter with integrated bypass, protection and diagnostics for larger motors and critical duties."),
      PanelComponent(id: "siemens-3rw30", manufacturer: "Siemens", type: "Soft Starter", model: "SIRIUS 3RW30", rating: "3-106A", poles: "3PH", curve: "Standard ramp", about: "Standard soft starter for straightforward ramp starting on general purpose motors."),
      PanelComponent(id: "siemens-3rw52", manufacturer: "Siemens", type: "Soft Starter", model: "SIRIUS 3RW52", rating: "13-370A", poles: "3PH", curve: "Bypass + protection", about: "Soft starter combining bypass and motor protection in one device, reducing the component count in the starter section."),
      PanelComponent(id: "siemens-3rw44", manufacturer: "Siemens", type: "Soft Starter", model: "SIRIUS 3RW44", rating: "29-1214A", poles: "3PH", curve: "High feature", about: "High-feature soft starter for large motors with adjustable torque control and comprehensive protection and diagnostics."),
      PanelComponent(id: "eaton-ds7", manufacturer: "Eaton", type: "Soft Starter", model: "DS7", rating: "9-135A", poles: "3PH", curve: "Integrated bypass", about: "Soft starter with integrated bypass controlling two phases, compact enough to fit where a full three-phase controlled unit would not.")
    ]),
    ComponentGroup(id: "motor-protection", name: "Motor Protection & Starters", items: [
      PanelComponent(id: "abb-ms132", manufacturer: "ABB", type: "MPCB", model: "MS132", rating: "0.1-32A", poles: "3P", curve: "Manual motor starter", about: "Manual motor starter combining short-circuit, overload and manual switching in one device. Dial the current setting to motor full-load amps and check the breaking capacity against the board fault level."),
      PanelComponent(id: "abb-ms165", manufacturer: "ABB", type: "MPCB", model: "MS165", rating: "10-65A", poles: "3P", curve: "Manual motor starter", about: "Larger frame manual motor starter for motors up to roughly 30kW, with the same combined protection and switching function."),
      PanelComponent(id: "schneider-gv2me", manufacturer: "Schneider", type: "MPCB", model: "TeSys GV2ME", rating: "0.1-32A", poles: "3P", curve: "Thermal-magnetic", about: "TeSys manual motor starter with thermal-magnetic protection and a rotary handle, commonly the first device in a compact motor feeder."),
      PanelComponent(id: "schneider-gv3", manufacturer: "Schneider", type: "MPCB", model: "TeSys GV3", rating: "9-65A", poles: "3P", curve: "Thermal-magnetic", about: "Larger TeSys motor circuit breaker for mid-size motors, often paired with a matching contactor to form a compact starter."),
      PanelComponent(id: "siemens-3rv2", manufacturer: "Siemens", type: "MPCB", model: "SIRIUS 3RV2", rating: "0.11-100A", poles: "3P", curve: "Motor protection", about: "SIRIUS motor starter protector that clips directly to matching 3RT contactors, forming a tested combination without extra wiring."),
      PanelComponent(id: "eaton-pkzm0", manufacturer: "Eaton", type: "MPCB", model: "PKZM0", rating: "0.1-32A", poles: "3P", curve: "Motor protective", about: "Motor protective circuit breaker with adjustable overload, used as a compact combined isolator and protection device."),
      PanelComponent(id: "generic-overload", manufacturer: "Generic", type: "Overload Relay", model: "Thermal overload relay", rating: "Set A", poles: "3P", curve: "Motor protection", about: "Thermal overload relay protecting a motor from sustained overcurrent such as a jammed load or lost phase. Set the dial to motor full-load amps and check the trip class suits the starting time."),
      PanelComponent(id: "abb-ta25du", manufacturer: "ABB", type: "Overload Relay", model: "TA25DU", rating: "0.1-32A", poles: "3P", curve: "Thermal, Class 10", about: "Thermal overload relay mounting directly onto matching contactors. Set the dial to motor full-load amps, and reset behaviour should be chosen deliberately since automatic reset on a motor can restart machinery."),
      PanelComponent(id: "abb-ef19", manufacturer: "ABB", type: "Overload Relay", model: "EF19", rating: "0.1-18.9A", poles: "3P", curve: "Electronic, Class 10-30", about: "Electronic overload relay with a wider setting range and selectable trip class, holding accuracy better than a bimetallic relay across ambient changes."),
      PanelComponent(id: "schneider-lrd", manufacturer: "Schneider", type: "Overload Relay", model: "TeSys LRD", rating: "0.1-140A", poles: "3P", curve: "Thermal, Class 10/20", about: "TeSys thermal overload relay clipping onto LC1D contactors, the standard partner in a Schneider motor starter."),
      PanelComponent(id: "schneider-lr9", manufacturer: "Schneider", type: "Overload Relay", model: "TeSys LR9", rating: "0.3-630A", poles: "3P", curve: "Electronic", about: "Electronic overload relay for larger motors, with a wide adjustment range and better protection against phase loss."),
      PanelComponent(id: "siemens-3ru21", manufacturer: "Siemens", type: "Overload Relay", model: "SIRIUS 3RU21", rating: "0.11-100A", poles: "3P", curve: "Thermal, Class 10", about: "Thermal overload relay designed to mount directly on 3RT contactors, forming a compact tested starter combination."),
      PanelComponent(id: "siemens-3rb30", manufacturer: "Siemens", type: "Overload Relay", model: "SIRIUS 3RB30", rating: "0.1-100A", poles: "3P", curve: "Electronic, Class 5-30", about: "Electronic overload relay with selectable trip class from 5 to 30, useful for motors with long run-up times such as large fans."),
      PanelComponent(id: "generic-dol-starter", manufacturer: "Generic", type: "Motor Starter", model: "Direct-on-line starter", rating: "Set kW", poles: "3PH", curve: "Contactor + overload", about: "Direct-on-line starter combining contactor and overload for the simplest motor start. Draws six to eight times full-load current at start, so confirm the supply and any generator can accept that step."),
      PanelComponent(id: "generic-star-delta", manufacturer: "Generic", type: "Motor Starter", model: "Star-delta starter", rating: "Set kW", poles: "3PH", curve: "3 contactors + timer", about: "Star-delta starter reducing starting current by first running the motor in star, then switching to delta. The motor must have all six leads available and the transition timer needs setting to the actual run-up time."),
      PanelComponent(id: "generic-reversing", manufacturer: "Generic", type: "Motor Starter", model: "Reversing starter", rating: "Set kW", poles: "3PH", curve: "Interlocked pair", about: "Reversing starter using two mechanically and electrically interlocked contactors to swap two phases. The interlock is a safety requirement, not an option, since both closing together is a direct phase-to-phase fault.")
    ]),
    ComponentGroup(id: "control-power", name: "Control Power & UPS", items: [
      PanelComponent(id: "generic-transformer", manufacturer: "Generic", type: "Transformer", model: "Control transformer", rating: "Set VA", poles: "1PH", curve: "400/230V", about: "Control transformer stepping the panel supply down to a separate control voltage, typically 230V or 110V, and isolating the control circuit from the power circuit. Size the VA for the inrush of all contactor coils picking up together, not just their holding current."),
      PanelComponent(id: "phoenix-step", manufacturer: "Phoenix", type: "PSU", model: "STEP POWER", rating: "24VDC", poles: "1PH", curve: "0.5-10A basic", about: "Basic 24VDC supply for small control loads such as a handful of relays and sensors, where power reserve features are unnecessary."),
      PanelComponent(id: "phoenix-trio", manufacturer: "Phoenix", type: "PSU", model: "TRIO POWER", rating: "24VDC", poles: "1PH/3PH", curve: "2.5-20A", about: "Mid-range 24VDC supply for typical control panels, with a stable output and compact DIN footprint."),
      PanelComponent(id: "phoenix-quint", manufacturer: "Phoenix", type: "PSU", model: "QUINT POWER", rating: "24VDC", poles: "1PH/3PH", curve: "5-40A, SFB tech", about: "Premium 24VDC supply whose selective fuse breaking technology delivers extra current briefly, so a downstream fault clears its protective device instead of dragging the whole 24V rail down."),
      PanelComponent(id: "abb-cpd", manufacturer: "ABB", type: "PSU", model: "CP-D", rating: "24VDC", poles: "1PH", curve: "0.42-2.5A compact", about: "Compact 24VDC supply for small control tasks where DIN width is at a premium."),
      PanelComponent(id: "abb-cpe", manufacturer: "ABB", type: "PSU", model: "CP-E", rating: "24VDC", poles: "1PH", curve: "0.75-20A", about: "General purpose 24VDC supply covering most panel control loads, with adjustable output voltage to compensate for line drop."),
      PanelComponent(id: "siemens-psu100s", manufacturer: "Siemens", type: "PSU", model: "SITOP PSU100S", rating: "24VDC", poles: "1PH", curve: "2.5-40A", about: "Single-phase SITOP supply for control circuits and SIMATIC controllers, with reserve capacity for short overloads."),
      PanelComponent(id: "siemens-psu8200", manufacturer: "Siemens", type: "PSU", model: "SITOP PSU8200", rating: "24VDC", poles: "3PH", curve: "10-40A", about: "Three-phase SITOP supply for larger 24VDC loads, balancing the draw across all three phases rather than loading one."),
      PanelComponent(id: "meanwell-dr", manufacturer: "Mean Well", type: "PSU", model: "DR series", rating: "24VDC", poles: "1PH", curve: "15-120W", about: "Economical DIN rail supply for light control duties, widely used in OEM panels."),
      PanelComponent(id: "meanwell-hdr", manufacturer: "Mean Well", type: "PSU", model: "HDR series", rating: "24VDC", poles: "1PH", curve: "15-150W ultra slim", about: "Ultra-slim DIN supply for tight enclosures where every millimetre of rail counts."),
      PanelComponent(id: "meanwell-ndr", manufacturer: "Mean Well", type: "PSU", model: "NDR series", rating: "24VDC", poles: "1PH", curve: "75-480W", about: "Higher power DIN supply for panels with substantial 24VDC load such as banks of valves or extensive I/O."),
      PanelComponent(id: "meanwell-tdr", manufacturer: "Mean Well", type: "PSU", model: "TDR series", rating: "24VDC", poles: "3PH", curve: "240-960W", about: "Three-phase DIN supply for heavy 24VDC loads, keeping phase loading balanced on larger installations."),
      PanelComponent(id: "delta-drp", manufacturer: "Delta", type: "PSU", model: "CliQ DRP", rating: "24VDC", poles: "1PH/3PH", curve: "60-960W", about: "CliQ series supply available in single and three-phase versions with good efficiency and a compact footprint."),
      PanelComponent(id: "eaton-psg", manufacturer: "Eaton", type: "PSU", model: "PSG", rating: "24VDC", poles: "1PH", curve: "1.3-20A", about: "General purpose 24VDC supply for control circuits, with models sized from small interface duty upward."),
      PanelComponent(id: "phoenix-quint-ups", manufacturer: "Phoenix", type: "DC-UPS", model: "QUINT UPS-IQ", rating: "24VDC", poles: "DIN", curve: "5-40A + battery", about: "DC uninterruptible supply with intelligent battery management that reports remaining backup time, so control power outlives a brief mains loss."),
      PanelComponent(id: "siemens-ups1600", manufacturer: "Siemens", type: "DC-UPS", model: "SITOP UPS1600", rating: "24VDC", poles: "DIN", curve: "10-40A managed", about: "Managed DC-UPS with configurable buffer time and diagnostics over the controller network, letting a PLC shut down cleanly rather than dying mid-operation."),
      PanelComponent(id: "abb-cpa-ru", manufacturer: "ABB", type: "DC-UPS", model: "CP-A RU", rating: "24VDC", poles: "DIN", curve: "Redundancy + buffer", about: "Redundancy and buffer module decoupling two power supplies so a single failed unit cannot pull down the shared 24V rail."),
      PanelComponent(id: "meanwell-drc", manufacturer: "Mean Well", type: "DC-UPS", model: "DRC series", rating: "24VDC", poles: "DIN", curve: "Charger + backup", about: "DIN rail supply with an integrated battery charger and changeover, a cost-effective route to backed-up control power on smaller panels.")
    ]),
    ComponentGroup(id: "control-automation", name: "Control & Automation", items: [
      PanelComponent(id: "generic-plc", manufacturer: "Generic", type: "PLC", model: "Compact PLC", rating: "24VDC", poles: "DIN", curve: "Digital I/O", about: "Programmable logic controller running the panel control sequence. Count the digital and analogue I/O needed with spare capacity, and confirm the communication protocol before fixing the enclosure layout."),
      PanelComponent(id: "siemens-s71200", manufacturer: "Siemens", type: "PLC", model: "SIMATIC S7-1200", rating: "24VDC", poles: "DIN", curve: "Compact controller", about: "Compact controller for panel automation with expandable digital and analogue I/O. Confirm the I/O count with spare capacity and whether PROFINET or Modbus is required before finalising the layout."),
      PanelComponent(id: "schneider-m221", manufacturer: "Schneider", type: "PLC", model: "Modicon M221", rating: "24VDC", poles: "DIN", curve: "Machine controller", about: "Machine controller for pump, HVAC and small process panels, with built-in Ethernet on most references."),
      PanelComponent(id: "abb-ac500", manufacturer: "ABB", type: "PLC", model: "AC500-eCo", rating: "24VDC", poles: "DIN", curve: "Modular controller", about: "Modular controller that scales from small to large I/O counts, useful where the same panel design must cover several plant sizes."),
      PanelComponent(id: "delta-dvp", manufacturer: "Delta", type: "PLC", model: "DVP series", rating: "24VDC", poles: "DIN", curve: "Compact controller", about: "Cost-effective compact PLC widely used in OEM machine panels with straightforward digital and analogue expansion."),
      PanelComponent(id: "siemens-ktp", manufacturer: "Siemens", type: "HMI", model: "SIMATIC KTP", rating: "24VDC", poles: "Door mount", curve: "4-15 inch touch", about: "Door-mounted touch panel giving the operator status, alarms and setpoints. Cutting the door aperture accurately matters, and the IP rating only holds if the supplied gasket is fitted correctly."),
      PanelComponent(id: "schneider-hmigxu", manufacturer: "Schneider", type: "HMI", model: "Harmony HMIGXU", rating: "24VDC", poles: "Door mount", curve: "3.5-7 inch touch", about: "Compact operator terminal for smaller panels where a full PC-based interface is unnecessary."),
      PanelComponent(id: "pilz-pnoz", manufacturer: "Generic", type: "Safety Relay", model: "PNOZ safety relay", rating: "24VDC", poles: "DIN", curve: "Emergency stop / guard", about: "Safety relay monitoring emergency stops, guard switches and light curtains, providing a redundant and monitored trip path. It must be wired to the documented category and cannot be bypassed by ordinary control logic."),
      PanelComponent(id: "siemens-3sk1", manufacturer: "Siemens", type: "Safety Relay", model: "SIRIUS 3SK1", rating: "24VDC", poles: "DIN", curve: "Safety monitoring", about: "Safety relay for emergency stop and guard monitoring with expandable output modules for larger safety circuits."),
      PanelComponent(id: "generic-relay", manufacturer: "Generic", type: "Relay", model: "Interface relay", rating: "24VDC", poles: "DIN", curve: "1CO/2CO", about: "Interface relay isolating low-power controller outputs from the coils and loads they switch, and converting between control voltages. The slim DIN format keeps a dense I/O interface tidy."),
      PanelComponent(id: "phoenix-plcrsc", manufacturer: "Phoenix", type: "Relay", model: "PLC-RSC interface", rating: "24VDC", poles: "DIN", curve: "6.2mm slim", about: "Slim plug-in interface relay isolating controller outputs from field loads. The pluggable design lets a failed relay be swapped without disturbing terminal wiring."),
      PanelComponent(id: "finder-55", manufacturer: "Generic", type: "Relay", model: "Finder 55 series", rating: "24-230V", poles: "DIN", curve: "2CO/3CO", about: "General purpose plug-in relay with a socket base, used for interposing and simple control logic in panels of every size."),
      PanelComponent(id: "generic-timer", manufacturer: "Generic", type: "Timer", model: "Time relay", rating: "24-230V", poles: "DIN", curve: "On/off delay", about: "Time relay providing on-delay, off-delay or cyclic switching for sequencing, pump alternation and star-delta transitions."),
      PanelComponent(id: "finder-80", manufacturer: "Generic", type: "Timer", model: "Finder 80 multifunction", rating: "12-240V", poles: "DIN", curve: "Multifunction", about: "Multifunction timer covering on-delay, off-delay, interval and cyclic modes in one part, which cuts down on stocked variants."),
      PanelComponent(id: "abb-cm-mps", manufacturer: "ABB", type: "Monitoring Relay", model: "CM-MPS", rating: "3x400V", poles: "DIN", curve: "Phase failure / sequence", about: "Three-phase monitoring relay detecting phase loss, wrong phase sequence, under and overvoltage. It is what stops a motor running single-phased after an upstream fuse clears one leg."),
      PanelComponent(id: "siemens-3ug4", manufacturer: "Siemens", type: "Monitoring Relay", model: "SIRIUS 3UG4", rating: "3x400V", poles: "DIN", curve: "Voltage / phase monitor", about: "Line monitoring relay for phase sequence, asymmetry and voltage window, commonly interlocked into the start circuit of motor panels.")
    ]),
    ComponentGroup(id: "metering", name: "Metering & Monitoring", items: [
      PanelComponent(id: "generic-meter", manufacturer: "Generic", type: "Meter", model: "Digital meter", rating: "230/400V", poles: "3PH", curve: "Panel mount", about: "Panel-mounted digital meter showing voltage, current and basic energy values on the board door. Confirm whether it measures directly or needs current transformers."),
      PanelComponent(id: "schneider-iem3000", manufacturer: "Schneider", type: "Meter", model: "Acti9 iEM3000", rating: "230/400V", poles: "3PH", curve: "DIN, Modbus", about: "DIN rail energy meter for sub-billing and consumption monitoring, available in direct-connect and CT versions with Modbus output."),
      PanelComponent(id: "siemens-pac3200", manufacturer: "Siemens", type: "Meter", model: "SENTRON PAC3200", rating: "230/400V", poles: "3PH", curve: "Door mount", about: "Door-mounted multifunction meter showing the full set of electrical values with Modbus or PROFINET reporting."),
      PanelComponent(id: "carlogavazzi-em21", manufacturer: "Generic", type: "Meter", model: "Carlo Gavazzi EM21", rating: "230/400V", poles: "3PH", curve: "DIN, Modbus", about: "Compact DIN rail energy meter widely used for sub-metering individual feeders in tenant and process installations."),
      PanelComponent(id: "generic-power-analyzer", manufacturer: "Generic", type: "Power Analyzer", model: "Power quality analyzer", rating: "230/400V", poles: "3PH", curve: "Modbus", about: "Power quality analyser recording harmonics, power factor, demand and event data, usually reporting over Modbus to a monitoring system. Specify where energy billing or harmonic problems need evidence."),
      PanelComponent(id: "schneider-pm2000", manufacturer: "Schneider", type: "Power Analyzer", model: "PowerLogic PM2000", rating: "230/400V", poles: "3PH", curve: "Panel mount", about: "Panel-mounted power meter measuring energy, demand and basic power quality, suited to tenant metering and energy management."),
      PanelComponent(id: "siemens-pac4200", manufacturer: "Siemens", type: "Power Analyzer", model: "SENTRON PAC4200", rating: "230/400V", poles: "3PH", curve: "Harmonics + logging", about: "Advanced meter adding harmonic analysis and data logging, used where power quality has to be proven rather than assumed."),
      PanelComponent(id: "abb-m2m", manufacturer: "ABB", type: "Power Analyzer", model: "M2M network analyzer", rating: "230/400V", poles: "3PH", curve: "Modbus", about: "Network analyser recording power quality and harmonic content, typically fitted where drives and non-linear loads dominate."),
      PanelComponent(id: "generic-ct", manufacturer: "Generic", type: "Current Transformer", model: "Split or solid core CT", rating: "50-5000A", poles: "1PH each", curve: "Class 0.5-1", about: "Current transformer scaling feeder current down to a meter input, usually 5A or 1A. Match the ratio and accuracy class to the meter, and never leave the secondary open circuit while primary current flows."),
      PanelComponent(id: "generic-test-block", manufacturer: "Generic", type: "Test Block", model: "CT test block", rating: "5A", poles: "Panel mount", curve: "Shorting type", about: "Test block allowing meters and protection relays to be tested or replaced without breaking the CT secondary, which it shorts automatically as the plug is withdrawn.")
    ]),
    ComponentGroup(id: "power-quality", name: "Power Factor & Quality", items: [
      PanelComponent(id: "abb-rvt", manufacturer: "ABB", type: "PFC Controller", model: "RVT controller", rating: "230/400V", poles: "Door mount", curve: "6-12 stages", about: "Power factor controller switching capacitor stages to hold the target power factor and avoid reactive energy charges. Set the target and the C/k ratio to suit the CT and the smallest stage."),
      PanelComponent(id: "schneider-varlogic", manufacturer: "Schneider", type: "PFC Controller", model: "Varlogic NR", rating: "230/400V", poles: "Door mount", curve: "6-12 stages", about: "Power factor controller with stage health monitoring, which matters because a failed capacitor stage otherwise goes unnoticed until the bill rises."),
      PanelComponent(id: "abb-clmd", manufacturer: "ABB", type: "Capacitor", model: "CLMD capacitor", rating: "Set kVAr", poles: "3PH", curve: "Dry type", about: "Dry-type power capacitor forming the stages of a correction bank. Capacitors need discharge resistors and adequate ventilation, and they age faster in hot or harmonic-rich environments."),
      PanelComponent(id: "generic-detuned-reactor", manufacturer: "Generic", type: "Reactor", model: "Detuned reactor", rating: "Set kVAr", poles: "3PH", curve: "7% or 14%", about: "Detuned reactor placed in series with capacitor stages to shift the resonant frequency away from prevailing harmonics. Required wherever significant drive or UPS load shares the installation."),
      PanelComponent(id: "generic-line-reactor", manufacturer: "Generic", type: "Reactor", model: "Line/load reactor", rating: "Set A", poles: "3PH", curve: "2-5% impedance", about: "Line or load reactor fitted with a drive to reduce current distortion, protect the drive input and limit voltage stress on long motor cables."),
      PanelComponent(id: "generic-active-filter", manufacturer: "Generic", type: "Harmonic Filter", model: "Active harmonic filter", rating: "30-300A", poles: "3PH", curve: "Real time correction", about: "Active filter injecting counter-current to cancel harmonics in real time. Specify from a measured harmonic survey rather than assumption, since sizing depends on the actual spectrum.")
    ]),
    ComponentGroup(id: "terminals", name: "Terminals & Wiring", items: [
      PanelComponent(id: "phoenix-terminal", manufacturer: "Phoenix", type: "Terminal Block", model: "UK series", rating: "2.5-35mm²", poles: "DIN", curve: "cm rail", about: "Screw-clamp terminal block for field wiring connections. Grouping terminals by function and numbering them consistently is what makes later fault finding fast."),
      PanelComponent(id: "phoenix-ut", manufacturer: "Phoenix", type: "Terminal Block", model: "CLIPLINE UT", rating: "0.14-95mm2", poles: "DIN", curve: "Screw clamp", about: "Screw clamp terminal range covering signal through power cross-sections in a consistent form, with matching bridges, markers and test accessories."),
      PanelComponent(id: "phoenix-pt", manufacturer: "Phoenix", type: "Terminal Block", model: "CLIPLINE PT", rating: "0.14-16mm2", poles: "DIN", curve: "Push-in spring", about: "Push-in spring terminal that accepts a ferruled conductor without a tool, cutting wiring time and removing the retorquing that screw terminals need."),
      PanelComponent(id: "wago-2002", manufacturer: "Generic", type: "Terminal Block", model: "WAGO TOPJOB S", rating: "0.25-16mm2", poles: "DIN", curve: "Push-in CAGE CLAMP", about: "Spring clamp terminal that holds tension regardless of vibration or thermal cycling, which is why it is common on machinery and transport panels."),
      PanelComponent(id: "weidmuller-a", manufacturer: "Generic", type: "Terminal Block", model: "Weidmuller A-series", rating: "0.14-95mm2", poles: "DIN", curve: "Push-in", about: "Push-in terminal system with a uniform accessory set across cross-sections, keeping cross-bridging and marking consistent through the panel."),
      PanelComponent(id: "phoenix-ptfix", manufacturer: "Phoenix", type: "Distribution Block", model: "PTFIX", rating: "1.5-6mm2", poles: "DIN or adhesive", curve: "Potential distributor", about: "Potential distribution block splitting one supply into many outgoing points, tidying up the 24VDC and earth distribution that otherwise turns into daisy-chained terminals."),
      PanelComponent(id: "generic-power-distribution-block", manufacturer: "Generic", type: "Distribution Block", model: "Power distribution block", rating: "125-800A", poles: "1P/3P/4P", curve: "Insulated body", about: "Insulated distribution block taking one large incoming cable and splitting it to several outgoing ways without a full busbar system."),
      PanelComponent(id: "generic-ferrule", manufacturer: "Generic", type: "Ferrule", model: "Bootlace ferrule", rating: "0.5-35mm2", poles: "Per conductor", curve: "Crimped", about: "Bootlace ferrule terminating a stranded conductor so no strand escapes the terminal. Use the correct crimp tool and die, since an under-crimped ferrule becomes a hot joint."),
      PanelComponent(id: "generic-lug", manufacturer: "Generic", type: "Cable Lug", model: "Compression lug", rating: "10-630mm2", poles: "Per conductor", curve: "Crimped", about: "Compression lug terminating large cables onto busbars and breaker pads. Match lug, die and tool from the same system, and confirm bolt torque against the manufacturer figure."),
      PanelComponent(id: "generic-marker", manufacturer: "Generic", type: "Wire Marker", model: "Wire and terminal markers", rating: "All sizes", poles: "Per conductor", curve: "Printed", about: "Printed markers identifying conductors and terminals to the drawing. Consistent numbering is the single thing that most reduces fault-finding time years later."),
      PanelComponent(id: "generic-trunking", manufacturer: "Generic", type: "Trunking", model: "Wiring duct", rating: "Set cm", poles: "PVC", curve: "Slotted", about: "Slotted wiring duct routing and containing panel wiring. Leave real spare capacity, since ducts filled to the brim make later modifications painful and trap heat."),
      PanelComponent(id: "generic-cable-gland", manufacturer: "Generic", type: "Cable Gland", model: "Cable gland", rating: "Set size", poles: "M thread", curve: "IP rated", about: "Cable gland sealing a cable where it enters the enclosure, maintaining the IP rating and providing strain relief. Metal glands additionally terminate cable armour or screen."),
      PanelComponent(id: "generic-din", manufacturer: "Generic", type: "DIN Rail", model: "35mm rail", rating: "1m", poles: "DIN", curve: "Cut to cm", about: "Standard 35mm DIN rail carrying modular devices. Plan rail heights and spacing around wiring duct so devices remain accessible after wiring.")
    ]),
    ComponentGroup(id: "busbars", name: "Busbars & Earthing", items: [
      PanelComponent(id: "generic-busbar-250", manufacturer: "Generic", type: "Busbar", model: "Copper busbar", rating: "250A", poles: "3P+N", curve: "cm/m sizing", about: "Copper busbar system rated around 250A for distributing current across a board section, keeping outgoing connections short and consistent."),
      PanelComponent(id: "generic-busbar-630", manufacturer: "Generic", type: "Busbar", model: "Copper busbar", rating: "630A", poles: "3P+N", curve: "cm/m sizing", about: "Higher rated busbar for main distribution sections, where cable connections to every outgoing device would be impractical."),
      PanelComponent(id: "rittal-riline", manufacturer: "Rittal", type: "Busbar System", model: "RiLine busbar system", rating: "100-1600A", poles: "3P/4P", curve: "Component adaptor", about: "Busbar system with component adaptors that clip devices directly onto the bars, cutting internal cabling and giving a repeatable, tested arrangement."),
      PanelComponent(id: "generic-copper-bar", manufacturer: "Generic", type: "Copper Bar", model: "Copper bar", rating: "Set cm", poles: "Flat bar", curve: "Busbar", about: "Copper bar carrying current between sections and devices inside the board. Size it for continuous current and short-circuit withstand, and check the support spacing for the fault level."),
      PanelComponent(id: "generic-flexible-busbar", manufacturer: "Generic", type: "Busbar", model: "Flexible braided busbar", rating: "Set A", poles: "Per phase", curve: "Laminated", about: "Flexible laminated connector between busbar and device, absorbing vibration and thermal movement and easing awkward connection geometry."),
      PanelComponent(id: "generic-busbar-support", manufacturer: "Generic", type: "Busbar Support", model: "Busbar support block", rating: "Set A", poles: "3P/4P", curve: "Insulated", about: "Insulated busbar support holding bars at a fixed spacing. Support spacing is a short-circuit withstand question, not a tidiness one: bars must not deflect together under fault forces."),
      PanelComponent(id: "generic-earth-bar", manufacturer: "Generic", type: "Earth Bar", model: "PE bar", rating: "Set length", poles: "PE", curve: "Copper/brass", about: "Protective earth bar giving every circuit a common bonding point. It must be sized for the largest fault current and clearly labelled and accessible."),
      PanelComponent(id: "generic-neutral-bar", manufacturer: "Generic", type: "Neutral Bar", model: "N bar", rating: "Set length", poles: "N", curve: "Copper/brass", about: "Neutral bar collecting circuit neutrals. Keep neutrals grouped with their own circuits so that RCD protection and later fault finding both work predictably."),
      PanelComponent(id: "generic-earth-braid", manufacturer: "Generic", type: "Earth Bonding", model: "Earth bonding braid", rating: "6-25mm2", poles: "Per door", curve: "Flexible", about: "Flexible bonding braid earthing doors and hinged plates. Doors carrying any electrical device must be bonded, and paint has to be removed at the fixing point for the bond to be real.")
    ]),
    ComponentGroup(id: "enclosure", name: "Enclosure & Climate", items: [
      PanelComponent(id: "rittal-ae", manufacturer: "Rittal", type: "Enclosure", model: "AE compact enclosure", rating: "IP66", poles: "Wall mount", curve: "Sheet steel", about: "Compact wall-mounting enclosure for smaller boards and control panels. Confirm the IP rating survives every cut-out and gland you add to it."),
      PanelComponent(id: "rittal-vx25", manufacturer: "Rittal", type: "Enclosure", model: "VX25 bayed enclosure", rating: "IP55", poles: "Floor standing", curve: "Frame system", about: "Bayable floor-standing frame system for large boards, allowing sections to be joined into a lineup with continuous busbar and shared cable zones."),
      PanelComponent(id: "generic-fan", manufacturer: "Generic", type: "Fan", model: "Panel fan", rating: "230V", poles: "Filter fan", curve: "Airflow", about: "Filter fan drawing cooler outside air through the enclosure to remove heat from drives, transformers and breakers. It needs a matching exit filter, and the filter mats need a cleaning interval in the maintenance plan."),
      PanelComponent(id: "rittal-sk-fan", manufacturer: "Rittal", type: "Fan", model: "SK filter fan", rating: "230V", poles: "Door or side", curve: "Filtered airflow", about: "Filter fan with matched exit filter for forced ventilation. Size airflow from the calculated heat load and remember it can only cool to ambient, never below it."),
      PanelComponent(id: "rittal-bluee", manufacturer: "Rittal", type: "Cooling Unit", model: "Blue e cooling unit", rating: "230/400V", poles: "Wall or roof", curve: "Active cooling", about: "Active cooling unit refrigerating the enclosure below ambient, needed where drives and transformers exceed what filtered ventilation can remove. It needs condensate management and a sealed enclosure to work correctly."),
      PanelComponent(id: "generic-heater", manufacturer: "Generic", type: "Heater", model: "Panel heater", rating: "230V", poles: "DIN", curve: "PTC element", about: "Panel heater preventing condensation in cold or outdoor enclosures. Condensation, not cold, is what damages electronics, so pair it with a hygrostat or thermostat."),
      PanelComponent(id: "generic-thermostat", manufacturer: "Generic", type: "Thermostat", model: "Panel thermostat", rating: "230V", poles: "DIN", curve: "NO/NC", about: "Panel thermostat switching a fan or heater at a set temperature. Use a normally-closed unit for heating and a normally-open unit for cooling."),
      PanelComponent(id: "generic-hygrostat", manufacturer: "Generic", type: "Hygrostat", model: "Panel hygrostat", rating: "230V", poles: "DIN", curve: "Humidity control", about: "Hygrostat switching a heater on humidity rather than temperature, which is the more reliable way to keep an outdoor enclosure dry."),
      PanelComponent(id: "generic-panel-light", manufacturer: "Generic", type: "Panel Light", model: "LED enclosure light", rating: "230V", poles: "Interior", curve: "Door switch", about: "Interior LED light, usually with a door switch, so maintenance inside a deep board does not depend on a hand torch."),
      PanelComponent(id: "generic-panel-socket", manufacturer: "Generic", type: "Socket", model: "Service socket outlet", rating: "230V", poles: "DIN or panel", curve: "16A", about: "Service socket inside the enclosure for test equipment and tools. It should be fed from its own protected circuit with RCD protection."),
      PanelComponent(id: "generic-door-interlock", manufacturer: "Generic", type: "Door Interlock", model: "Door interlock", rating: "Set A", poles: "Handle", curve: "Mechanical", about: "Mechanical door interlock preventing the enclosure being opened while the main switch is closed, with a defeat facility for authorised testing.")
    ]),
    ComponentGroup(id: "door-devices", name: "Door & Operator Devices", items: [
      PanelComponent(id: "generic-estop", manufacturer: "Generic", type: "Emergency Stop", model: "Emergency stop mushroom", rating: "22/40mm", poles: "NC contacts", curve: "Twist release", about: "Latching emergency stop with positively-driven normally-closed contacts. It must break the control path directly, not merely request a stop from a controller."),
      PanelComponent(id: "generic-push-button", manufacturer: "Generic", type: "Push Button", model: "Push button", rating: "22mm", poles: "NO/NC", curve: "Panel door", about: "22mm door-mounted push button for start, stop and reset commands. Contact blocks are ordered separately, so confirm how many NO and NC contacts each function needs."),
      PanelComponent(id: "schneider-xb4", manufacturer: "Schneider", type: "Push Button", model: "Harmony XB4", rating: "22mm", poles: "NO/NC blocks", curve: "Metal bezel", about: "Metal-bezel control station range for doors, with a wide selection of heads and contact blocks that share one mounting cut-out."),
      PanelComponent(id: "siemens-3su1", manufacturer: "Siemens", type: "Push Button", model: "SIRIUS ACT 3SU1", rating: "22mm", poles: "NO/NC blocks", curve: "Plastic or metal", about: "Modular door control range with plastic and metal versions, and connection options from screw terminals to an integrated bus module."),
      PanelComponent(id: "generic-selector", manufacturer: "Generic", type: "Selector Switch", model: "Selector switch", rating: "22mm", poles: "2/3 position", curve: "Panel door", about: "Panel door selector switch giving a positive two or three position choice such as hand-off-auto. Confirm the contact arrangement matches the control logic before drilling the door."),
      PanelComponent(id: "generic-indicator", manufacturer: "Generic", type: "Indicator Light", model: "Pilot light", rating: "24/230V", poles: "22mm", curve: "LED", about: "Pilot light showing run, trip or supply-healthy status on the door. LED versions draw far less current and last longer than filament equivalents."),
      PanelComponent(id: "generic-ammeter", manufacturer: "Generic", type: "Ammeter", model: "Analogue ammeter", rating: "Via CT", poles: "1PH each", curve: "Moving iron", about: "Analogue ammeter giving an at-a-glance load indication on the door. Still favoured on motor panels because a swinging needle shows a struggling load better than a digital readout."),
      PanelComponent(id: "generic-selector-ammeter", manufacturer: "Generic", type: "Selector Switch", model: "Ammeter selector switch", rating: "Via CT", poles: "3PH+off", curve: "Shorting type", about: "Ammeter selector letting one meter read each phase in turn. It must be the CT-shorting type so the transformer secondary is never opened while switching.")
    ])
  ]
}

struct PanelComponent: Identifiable {
  let id: String
  let manufacturer: String
  let type: String
  let model: String
  let rating: String
  let poles: String
  let curve: String
  var sourceID: String = ""

  /// What this specific part does and what to check when specifying it.
  /// Empty for user-created components, which fall back to the generic
  /// per-type text in `ComponentIcon.description(for:)`.
  var about: String = ""
  /// Unique identifier printed on this physical component, when available.
  var serialNumber: String = ""

  var imageStorageID: String {
    sourceID.isEmpty ? id : sourceID
  }

  var imageLookupIDs: [String] {
    Array(NSOrderedSet(array: [id, imageStorageID])) as? [String] ?? [id, imageStorageID]
  }

  var displayName: String {
    [manufacturer, type, model]
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .joined(separator: " ")
  }

  var ratingLabel: String {
    let trimmed = rating.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.localizedCaseInsensitiveContains("set a") { return "Set A" }
    return trimmed
  }

  var detailLine: String {
    [model, poles, curve, serialNumber.isEmpty ? nil : "SN: \(serialNumber)"]
      .compactMap { $0 }
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .joined(separator: " • ")
  }

  var searchText: String {
    "\(manufacturer) \(type) \(model) \(rating) \(poles) \(curve) \(serialNumber)"
  }
}

struct BoardProductionStage: Identifiable, Equatable {
  let id: String
  let title: String
  let progress: Int
  let state: String
}

struct BoardDraft: Identifiable {
  let id: String
  var number: String
  var group: String
  var name: String
  var customer: String
  var company: String = ""
  var project: String
  var type: String
  var subtype: String = BoardSubtypeCatalog.defaultSubtype
  var manufacturer: String = "Generic"
  var ampere: String
  var cabinetCount: String
  var buildFormat: String = "Panels"
  var dateOut: Date = Date()
  var dueDate: Date? = nil
  var finishDate: Date? = nil
  var finishTimeHours: String = ""
  var mainBreakerType: String
  var mainBreakerModel: String = ""
  var mainBreakerAmpere: String
  var componentTypes: [String]
  var color: Color = Color(hex: 0x5E78FF)

  /// Image-store tokens rather than decoded images — see [ProjectItem].
  var coverToken: String? = nil
  var photoTokens: [String] = []
  var schemeAttachments: [SchemeAttachment] = []
  var completedChecklistItems: Set<String> = []
  var personalChecklistItems: [PersonalChecklistItem] = []
  /// Completed checklist item IDs per cabinet, index 0 = cabinet 1. Each cabinet
  /// is built and tracked on its own; the board's completion averages them.
  var cabinetChecklists: [Set<String>] = []
  /// Cloud assignment is shared with the manager website. Local-only boards
  /// leave this nil; stage movement is tracked independently.
  var assignedTo: String? = nil
  var assignedName: String = ""
  /// QA is deliberately separate from finishing: production can be ready while
  /// final completion remains locked until the reviewer approves it.
  var qaAssignedTo: String? = nil
  var qaAssignedName: String = ""
  var qaStatus: String = "pending"
  var qaNote: String = ""
  var qaReadyAt: Date? = nil
  var qaApprovedAt: Date? = nil
  /// Authoritative workflow stage shared with the manager website.
  var productionStage: String = "design"

  var coverImage: UIImage? {
    get { ImageStore.shared.image(for: coverToken) }
    set { coverToken = ImageStore.shared.store(newValue) }
  }

  /// Use in scrolling views instead of [coverImage].
  var coverThumbnail: UIImage? {
    ImageStore.shared.thumbnail(for: coverToken)
  }

  var photoCount: Int { photoTokens.count }

  /// Every token this board owns, for orphan cleanup.
  var imageTokens: [String] {
    ([coverToken] + photoTokens + schemeAttachments.map(\.imageToken)).compactMap { $0 }
  }

  var searchText: String {
    "\(number) \(group) \(name) \(customer) \(company) \(project) \(type) \(subtype) \(manufacturer) \(ampere) \(cabinetCount) \(buildFormat) \(DateDisplay.short.string(from: dateOut)) \(dueDate.map { DateDisplay.due.string(from: $0) } ?? "") \(finishDate.map { DateDisplay.short.string(from: $0) } ?? "") \(mainBreakerType) \(mainBreakerModel) \(mainBreakerAmpere) \(componentTypes.joined(separator: " "))"
  }

  var displayType: String {
    let cleanSubtype = subtype.trimmingCharacters(in: .whitespacesAndNewlines)
    guard BoardSubtypeCatalog.isVisible(cleanSubtype) else { return type }
    return "\(type) • \(cleanSubtype)"
  }

  var cabinetCountValue: Int { max(Int(cabinetCount) ?? 1, 1) }

  /// Per-cabinet checklists sized to the current cabinet count. Migrates a legacy
  /// single shared checklist into cabinet 1 so existing boards keep their progress.
  var normalizedCabinetChecklists: [Set<String>] {
    var lists = cabinetChecklists
    if lists.isEmpty && !completedChecklistItems.isEmpty {
      lists = [completedChecklistItems]
    }
    let n = cabinetCountValue
    if lists.count < n {
      lists.append(contentsOf: Array(repeating: Set<String>(), count: n - lists.count))
    } else if lists.count > n {
      lists = Array(lists.prefix(n))
    }
    return lists
  }

  var persistenceSignature: String {
    let coverSignature = ImageStore.shared.signature(for: coverToken)
    let photoSignature = photoTokens.joined(separator: "|")
    let schemeSignature = schemeAttachments.map(\.persistenceSignature).joined(separator: "|")
    return [
      id, number, group, name, customer, project, type, subtype, manufacturer,
      company,
      ampere, cabinetCount, buildFormat, "\(dateOut.timeIntervalSince1970)",
      "\(dueDate?.timeIntervalSince1970 ?? 0)",
      "\(finishDate?.timeIntervalSince1970 ?? 0)", finishTimeHours,
      mainBreakerType, mainBreakerModel, mainBreakerAmpere,
      componentTypes.joined(separator: ","), "\(color.archiveHex)",
      coverSignature, photoSignature,
      schemeSignature,
      normalizedCabinetChecklists.map { $0.sorted().joined(separator: ",") }.joined(separator: ";"),
      personalChecklistItems.map { "\($0.id):\($0.title):\($0.isDone)" }.joined(separator: ","),
      assignedTo ?? "", assignedName, qaAssignedTo ?? "", qaAssignedName,
      qaStatus, qaNote, productionStage, "\(qaReadyAt?.timeIntervalSince1970 ?? 0)",
      "\(qaApprovedAt?.timeIntervalSince1970 ?? 0)"
    ].joined(separator: "||")
  }

  var mainBreakerLabel: String {
    [(mainBreakerType == "Main Breaker" ? nil : mainBreakerType), mainBreakerModel, mainBreakerAmpere]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: " • ")
  }

  /// Dashboard progress follows the manager-controlled production stage.
  var completion: Int {
    ["design": 0, "mechanical": 20, "components": 40, "wiring": 60,
     "finishing": 80, "qa": 100, "complete": 100][productionStage] ?? 0
  }

  var productionStages: [BoardProductionStage] {
    var currentID = productionStage
    if qaStatus == "changes_requested" { currentID = "finishing" }
    if qaStatus == "approved" { currentID = "complete" }
    let definitions = [("design", "Design"), ("mechanical", "Mechanical Build"),
      ("components", "Components"), ("wiring", "Wiring"), ("finishing", "Finishing"),
      ("qa", "QA"), ("complete", "Complete")]
    let currentIndex = definitions.firstIndex { $0.0 == currentID } ?? 0
    return definitions.enumerated().map { index, definition in
      let id = definition.0
      let progress = index < currentIndex || (id == "complete" && qaStatus == "approved") ? 100 : 0
      var state = index < currentIndex ? "done" : (index == currentIndex ? "current" : "upcoming")
      if id == "finishing" && qaStatus == "changes_requested" { state = "attention" }
      if id == "qa" && currentID == "qa" { state = "ready" }
      return BoardProductionStage(id: id, title: definition.1, progress: progress, state: state)
    }
  }

  var currentProductionStage: BoardProductionStage {
    productionStages.first { ["current", "ready", "attention"].contains($0.state) }
      ?? BoardProductionStage(id: "design", title: "Design", progress: 0, state: "current")
  }

  var isCompleted: Bool {
    qaStatus == "approved"
  }

  var statusTitle: String {
    if isCompleted { return "Finished" }
    if qaStatus == "changes_requested" { return "QA Changes" }
    if productionStage == "qa" { return "QA Ready" }
    if productionStage == "design" { return "Design" }
    return "In Progress"
  }
}

struct PersonalChecklistItem: Identifiable, Hashable {
  let id: String
  var title: String
  var isDone: Bool

  init(id: String = "personal-\(UUID().uuidString)", title: String, isDone: Bool = false) {
    self.id = id
    self.title = title
    self.isDone = isDone
  }
}

enum EquipmentCompany {
  static let all = ["ABB", "Schneider", "Siemens", "Eaton", "Legrand", "Hager", "Mean Well", "Phoenix", "Generic"]
}

enum BoardSubtypeCatalog {
  static let defaultSubtype = "No subtype"

  static func isVisible(_ subtype: String) -> Bool {
    let cleanSubtype = subtype.trimmingCharacters(in: .whitespacesAndNewlines)
    return !cleanSubtype.isEmpty && cleanSubtype != defaultSubtype && cleanSubtype != "General"
  }

  static func options(for boardType: String) -> [String] {
    let lower = boardType.lowercased()
    var options = [defaultSubtype, "Control", "EV Charger", "Metering", "Automation", "Pump Control", "HVAC Control", "Generator Control", "Solar", "UPS", "Temporary Site"]
    if lower.contains("ev") || lower.contains("charging") {
      options = [defaultSubtype, "EV Charger", "Load Management", "Parking Level", "Fast Charger", "Metering"]
    } else if lower.contains("mcc") || lower.contains("motor") || lower.contains("pump") || lower.contains("hvac") {
      options = [defaultSubtype, "Control", "Pump Control", "HVAC Control", "VFD", "Soft Starter", "Automation"]
    } else if lower.contains("lighting") {
      options = [defaultSubtype, "Indoor Lighting", "Outdoor Lighting", "Emergency Lighting", "Timer Control", "Astronomical Clock"]
    } else if lower.contains("ats") || lower.contains("generator") {
      options = [defaultSubtype, "Generator Control", "ATS Control", "Synchronization", "Bypass"]
    }
    return Array(NSOrderedSet(array: options)) as? [String] ?? options
  }
}

enum EquipmentTypeCatalog {
  static let all = [
    "MCB", "MCCB", "ACB", "RCD/RCCB", "RCBO", "Contactor", "Overload Relay",
    "VFD", "Soft Starter", "PSU", "Transformer", "Busbar", "Terminal Block",
    "SPD", "Fuse", "Fuse Holder", "Isolator", "Changeover Switch", "Meter",
    "Power Analyzer", "PLC", "Relay", "Timer", "Selector Switch", "Push Button",
    "Indicator Light", "Fan", "Thermostat", "Door Interlock", "Cable Gland",
    "DIN Rail", "Trunking", "Copper Bar", "Earth Bar", "Neutral Bar"
  ]
}

enum AmpereRating {
  static let all = [
    "0.5A", "1A", "2A", "3A", "4A", "6A", "10A", "13A", "16A", "20A",
    "25A", "32A", "40A", "50A", "63A", "80A", "100A", "125A", "160A",
    "200A", "225A", "250A", "315A", "400A", "500A", "630A", "800A",
    "1000A", "1250A", "1600A", "2000A", "2500A", "3200A", "4000A",
    "5000A", "6300A"
  ]
}

enum PoleRating {
  static let all = ["1P", "1P+N", "2P", "3P", "3P+N", "4P", "3PH", "1PH", "DIN"]
}

struct PanelVaultSnapshot: Codable {
  let projects: [ProjectRecord]
  let boards: [BoardRecord]
  let customers: [CustomerRecord]
  let companies: [CompanyRecord]?
  let manufacturers: [ManufacturerRecord]?
  let boardTypes: [BoardTypeRecord]?

  init(projects: [ProjectItem], boards: [BoardDraft], customers: [CustomerItem], companies: [ContractorCompany], manufacturers: [ManufacturerItem], boardTypes: [BoardType]) {
    self.projects = projects.map(ProjectRecord.init(project:))
    self.boards = boards.map(BoardRecord.init(board:))
    self.customers = customers.map(CustomerRecord.init(customer:))
    self.companies = companies.map(CompanyRecord.init(company:))
    self.manufacturers = manufacturers.map(ManufacturerRecord.init(manufacturer:))
    self.boardTypes = boardTypes
      .filter { $0.id.hasPrefix("custom-") }
      .map(BoardTypeRecord.init(boardType:))
  }

  func encoded() -> String {
    guard let data = try? JSONEncoder().encode(self) else { return "" }
    return String(data: data, encoding: .utf8) ?? ""
  }

  static func decode(_ rawValue: String) -> PanelVaultSnapshot? {
    guard let data = rawValue.data(using: .utf8), !data.isEmpty else { return nil }
    return try? JSONDecoder().decode(PanelVaultSnapshot.self, from: data)
  }
}

struct BoardTypeRecord: Codable {
  let id: String
  let name: String
  let subtitle: String
  let symbol: String
  let colorHex: UInt32
  let emoji: String?
  let localName: String?
  let overview: String?
  let typicalUses: [String]
  let typicalComponents: [String]
  let designChecks: [String]
  let notes: [String]

  init(boardType: BoardType) {
    id = boardType.id
    name = boardType.name
    subtitle = boardType.subtitle
    symbol = boardType.symbol
    colorHex = boardType.color.archiveHex
    emoji = boardType.emoji
    localName = boardType.localName
    overview = boardType.overview
    typicalUses = boardType.typicalUses
    typicalComponents = boardType.typicalComponents
    designChecks = boardType.designChecks
    notes = boardType.notes
  }

  var boardType: BoardType {
    BoardType(
      id: id,
      name: name,
      subtitle: subtitle,
      symbol: symbol,
      color: Color(hex: colorHex),
      emoji: emoji,
      localName: localName,
      overview: overview,
      typicalUses: typicalUses,
      typicalComponents: typicalComponents,
      designChecks: designChecks,
      notes: notes
    )
  }
}

/// The pictures that ship with the app: one logo per manufacturer, one photo
/// per catalog part.
///
/// The files live in `assets/catalog` at the repo root and are bundled as a
/// folder reference, so PanelVault, the Worker app, the Warehouse app and
/// PanelVault Cloud all show the same photograph of the same part — there is
/// exactly one copy of each file in the repository and every surface points at
/// it. `assets/catalog/index.json`, written by tools/sync_catalog_images.py,
/// maps a catalog id to its filename. A part the manifest does not list simply
/// has no photo yet, and the caller falls back to its category symbol.
///
/// Everything here is a *default*. A photo the user took on this device lives
/// in `ImageStore` and always wins; nothing in this type ever writes there, so
/// a bundled picture can never overwrite or delete someone's own.
enum CatalogImageLibrary {
  /// The folder as it is named inside the built app, which is the last path
  /// component of the folder reference in each Xcode project.
  private static let bundleFolder = "catalog"

  /// Long side of the row thumbnail. Matches `ImageStore.thumbnailDimension`
  /// so a catalog photo and a user photo look identical in the same list.
  private static let thumbnailDimension: CGFloat = 400

  private struct Manifest: Decodable {
    var manufacturers: [String: String]?
    var components: [String: String]?
  }

  /// Decoded once, lazily. A `static let` is initialized under `swift_once`,
  /// so concurrent first access from several rows is safe.
  private static let manifest: Manifest = {
    guard let base = Bundle.main.resourceURL else { return Manifest() }
    let url = base
      .appendingPathComponent(bundleFolder, isDirectory: true)
      .appendingPathComponent("index.json")
    guard let data = try? Data(contentsOf: url),
          let decoded = try? JSONDecoder().decode(Manifest.self, from: data)
    else { return Manifest() }
    return decoded
  }()

  private static let fullCache: NSCache<NSString, UIImage> = {
    let cache = NSCache<NSString, UIImage>()
    cache.countLimit = 12
    cache.totalCostLimit = 32 * 1024 * 1024
    return cache
  }()

  private static let thumbnailCache: NSCache<NSString, UIImage> = {
    let cache = NSCache<NSString, UIImage>()
    cache.countLimit = 240
    cache.totalCostLimit = 24 * 1024 * 1024
    return cache
  }()

  // MARK: - Lookup

  /// Whether a part has a bundled photo, without paying to decode it.
  static func hasComponentImage(id: String) -> Bool {
    manifest.components?[id] != nil
  }

  static func componentImage(id: String) -> UIImage? {
    image(at: manifest.components?[id])
  }

  static func componentThumbnail(id: String) -> UIImage? {
    thumbnail(at: manifest.components?[id])
  }

  /// The first of `ids` that has a photo. Catalog parts carry both an `id` and
  /// a `sourceID` — a part placed on a board keeps its own id but is the same
  /// product as the catalog entry it came from — so callers pass both.
  static func componentThumbnail(ids: [String]) -> UIImage? {
    for id in ids {
      if let image = thumbnail(at: manifest.components?[id]) { return image }
    }
    return nil
  }

  static func manufacturerImage(name: String) -> UIImage? {
    image(at: manifest.manufacturers?[slug(name)])
  }

  static func manufacturerThumbnail(name: String) -> UIImage? {
    thumbnail(at: manifest.manufacturers?[slug(name)])
  }

  /// `Mean Well` -> `mean-well`. Must stay in step with `slug()` in
  /// tools/sync_catalog_images.py, which names the files.
  static func slug(_ name: String) -> String {
    let lowered = name.lowercased()
    let mapped = lowered.map { character -> Character in
      character.isLetter || character.isNumber ? character : "-"
    }
    return String(mapped)
      .split(separator: "-", omittingEmptySubsequences: true)
      .joined(separator: "-")
  }

  // MARK: - Loading

  private static func image(at relativePath: String?) -> UIImage? {
    guard let relativePath, let key = cacheKey(relativePath) else { return nil }
    if let cached = fullCache.object(forKey: key) { return cached }
    guard let url = url(for: relativePath),
          let data = try? Data(contentsOf: url),
          let image = UIImage(data: data) else { return nil }
    fullCache.setObject(image, forKey: key, cost: cost(of: image))
    return image
  }

  private static func thumbnail(at relativePath: String?) -> UIImage? {
    guard let relativePath, let key = cacheKey(relativePath) else { return nil }
    if let cached = thumbnailCache.object(forKey: key) { return cached }
    guard let full = image(at: relativePath) else { return nil }
    let scaled = downscaled(full, to: thumbnailDimension)
    thumbnailCache.setObject(scaled, forKey: key, cost: cost(of: scaled))
    return scaled
  }

  private static func cacheKey(_ relativePath: String) -> NSString? {
    relativePath.isEmpty ? nil : relativePath as NSString
  }

  /// The manifest is generated and ships inside the bundle, so it is trusted —
  /// but a path is a path, and a stray `..` in a hand-edited index.json should
  /// not be able to read files outside the catalog folder.
  private static func url(for relativePath: String) -> URL? {
    guard !relativePath.hasPrefix("/"),
          !relativePath.split(separator: "/").contains("..") else { return nil }
    return Bundle.main.resourceURL?
      .appendingPathComponent(bundleFolder, isDirectory: true)
      .appendingPathComponent(relativePath)
  }

  private static func downscaled(_ image: UIImage, to maximumDimension: CGFloat) -> UIImage {
    let longestSide = max(image.size.width, image.size.height)
    guard longestSide > maximumDimension else { return image }

    let scale = maximumDimension / longestSide
    let targetSize = CGSize(
      width: max((image.size.width * scale).rounded(), 1),
      height: max((image.size.height * scale).rounded(), 1)
    )
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    // Logos arrive as cut-outs on transparency and are drawn over the row, so
    // an opaque context would fill their background with black.
    format.opaque = false
    return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: targetSize))
    }
  }

  private static func cost(of image: UIImage) -> Int {
    Int(image.size.width * image.size.height * image.scale * image.scale * 4)
  }
}

/// Disk-backed image storage, addressed by short filename tokens.
///
/// PanelVault used to base64-encode every photo into the snapshot JSON that
/// lived in UserDefaults. Because UserDefaults is read wholly into memory at
/// launch and rewritten as one plist, that capped the archive at a handful of
/// photos and made saving one text edit rewrite every image in the vault.
///
/// Images now live as individual files in Application Support and records hold
/// only a `<uuid>.jpg` token, so the archive is bounded by disk space rather
/// than by UserDefaults, and memory is bounded by the caches below no matter
/// how many photos exist.
final class ImageStore {
  static let shared = ImageStore()

  /// Long-side cap for the stored original, so the vault never keeps 48MP
  /// camera originals. Applied once, on import.
  static let maximumDimension: CGFloat = 2200

  /// Long side of the list thumbnail. Rows decode this instead of the original.
  static let thumbnailDimension: CGFloat = 400

  private let fullCache = NSCache<NSString, UIImage>()
  private let thumbnailCache = NSCache<NSString, UIImage>()

  /// Reverse map from a live UIImage back to its token, so a view re-assigning
  /// the same image through a binding does not write a duplicate file.
  ///
  /// Weak keys matter: an NSCache retains its keys, which would pin every image
  /// ever stored in memory and defeat the point of moving them to disk. Here the
  /// entry disappears as soon as the caller stops holding the image.
  private let tokenForImage = NSMapTable<UIImage, NSString>.weakToStrongObjects()

  /// NSCache is thread-safe; NSMapTable is not, and `store` runs both on the
  /// main actor and on import tasks.
  private let tokenLock = NSLock()

  private let fileManager = FileManager.default

  private init() {
    // Bounded by bytes, not just count: 400 thumbnails held as decoded bitmaps
    // would be hundreds of megabytes.
    fullCache.countLimit = 24
    fullCache.totalCostLimit = 64 * 1024 * 1024
    thumbnailCache.countLimit = 400
    thumbnailCache.totalCostLimit = 32 * 1024 * 1024
  }

  private(set) lazy var directory: URL = {
    let base = fileManager
      .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
    let folder = base.appendingPathComponent("PanelVault/Images", isDirectory: true)
    try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }()

  // MARK: - Writing

  /// Writes `image` to disk and returns its token.
  ///
  /// Synchronous on purpose: a photo the user just imported has to survive the
  /// app being killed a moment later.
  func store(_ image: UIImage?) -> String? {
    guard let image else { return nil }
    if let known = knownToken(for: image) { return known }

    let prepared = ImageStore.prepared(image)
    let usePNG = prepared.hasTransparency
    guard let data = usePNG
      ? prepared.pngData()
      : prepared.jpegData(compressionQuality: 0.72) else { return nil }

    let token = "\(UUID().uuidString).\(usePNG ? "png" : "jpg")"
    do {
      try data.write(to: url(for: token), options: .atomic)
    } catch {
      return nil
    }

    remember(prepared, as: token)
    if prepared !== image {
      associate(image, with: token)
    }
    writeThumbnail(for: prepared, token: token)
    return token
  }

  func store(_ images: [UIImage]) -> [String] {
    images.compactMap { store($0) }
  }

  /// A freshly imported photo: the prepared image for immediate display, and
  /// the token it was stored under.
  ///
  /// The token is returned rather than looked up later because the reverse cache
  /// is an NSCache and may evict — a lookup miss would silently drop the photo
  /// even though its file was written.
  struct Imported {
    let image: UIImage
    let token: String
  }

  /// Decodes, downscales and writes a freshly picked photo off the main actor.
  ///
  /// Every photo import goes through here, so JPEG encoding never runs on the
  /// main thread and the file is on disk before the UI ever shows it.
  static func imported(from data: Data) async -> Imported? {
    await Task.detached(priority: .userInitiated) {
      guard let decoded = UIImage(data: data) else { return nil as Imported? }
      let prepared = ImageStore.prepared(decoded)
      guard let token = ImageStore.shared.store(prepared) else {
        return nil as Imported?
      }
      return Imported(image: prepared, token: token)
    }.value
  }

  /// Accepts either a current token or a legacy base64 blob from an older
  /// snapshot, so existing archives migrate on first load without data loss.
  func adopt(_ raw: String?) -> String? {
    guard let raw, !raw.isEmpty else { return nil }
    if ImageStore.isToken(raw) { return raw }
    guard let data = Data(base64Encoded: raw),
          let image = UIImage(data: data) else { return nil }
    return store(image)
  }

  func adopt(_ raws: [String]?) -> [String] {
    raws?.compactMap { adopt($0) } ?? []
  }

  // MARK: - Reading

  func image(for token: String?) -> UIImage? {
    // Validating the token also keeps a corrupted index from turning into a
    // path traversal out of the images directory.
    guard let token, ImageStore.isToken(token) else { return nil }
    if let cached = fullCache.object(forKey: token as NSString) { return cached }

    guard let data = try? Data(contentsOf: url(for: token)),
          let image = UIImage(data: data) else { return nil }

    remember(image, as: token)
    return image
  }

  /// Small representation for list rows and grids. Falls back to generating the
  /// thumbnail from the original when it is missing.
  func thumbnail(for token: String?) -> UIImage? {
    guard let token, ImageStore.isToken(token) else { return nil }
    if let cached = thumbnailCache.object(forKey: token as NSString) { return cached }

    if let data = try? Data(contentsOf: thumbnailURL(for: token)),
       let image = UIImage(data: data) {
      cache(image, as: token, in: thumbnailCache)
      return image
    }

    guard let full = image(for: token) else { return nil }
    let thumbnail = ImageStore.prepared(
      full,
      maximumDimension: ImageStore.thumbnailDimension
    )
    if let data = thumbnail.jpegData(compressionQuality: 0.7) {
      try? data.write(to: thumbnailURL(for: token), options: .atomic)
    }
    cache(thumbnail, as: token, in: thumbnailCache)
    return thumbnail
  }

  // MARK: - Deleting

  func delete(_ token: String?) {
    guard let token, ImageStore.isToken(token) else { return }
    fullCache.removeObject(forKey: token as NSString)
    thumbnailCache.removeObject(forKey: token as NSString)
    try? fileManager.removeItem(at: url(for: token))
    try? fileManager.removeItem(at: thumbnailURL(for: token))
  }

  func delete(_ tokens: [String]) {
    tokens.forEach { delete($0) }
  }

  /// Removes image files nothing references any more — photos whose project or
  /// board was deleted, replaced covers, and so on.
  ///
  /// Only ever call this with the token set of a snapshot that actually loaded:
  /// passing an empty set because loading failed would erase the archive.
  func sweepOrphans(keeping tokens: Set<String>) {
    let keptBases = Set(
      tokens
        .filter { ImageStore.isToken($0) }
        .map { ($0 as NSString).deletingPathExtension }
    )

    DispatchQueue.global(qos: .utility).async { [weak self] in
      guard let self else { return }
      guard let names = try? self.fileManager
        .contentsOfDirectory(atPath: self.directory.path) else { return }

      for name in names {
        let base = name.hasSuffix(".thumb.jpg")
          ? String(name.dropLast(".thumb.jpg".count))
          : (name as NSString).deletingPathExtension
        guard !keptBases.contains(base) else { continue }
        try? self.fileManager
          .removeItem(at: self.directory.appendingPathComponent(name))
      }
    }
  }

  // MARK: - Helpers

  /// Change-detection key. Tokens are stable across launches, unlike the object
  /// identity the old implementation hashed — which made saves fire constantly.
  func signature(for token: String?) -> String {
    token ?? "no-image"
  }

  static func isToken(_ value: String) -> Bool {
    // "<uuid>.jpg": 36 UUID characters plus a four-character extension.
    guard value.count == 40,
          value.hasSuffix(".jpg") || value.hasSuffix(".png") else { return false }
    return UUID(uuidString: String(value.dropLast(4))) != nil
  }

  static func prepared(
    _ image: UIImage,
    maximumDimension: CGFloat = ImageStore.maximumDimension
  ) -> UIImage {
    let longestSide = max(image.size.width, image.size.height)
    guard longestSide > maximumDimension else { return image }

    let scale = maximumDimension / longestSide
    let targetSize = CGSize(
      width: max((image.size.width * scale).rounded(), 1),
      height: max((image.size.height * scale).rounded(), 1)
    )
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = !image.hasTransparency
    return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: targetSize))
    }
  }

  private func remember(_ image: UIImage, as token: String) {
    cache(image, as: token, in: fullCache)
    associate(image, with: token)
  }

  private func knownToken(for image: UIImage) -> String? {
    tokenLock.lock()
    defer { tokenLock.unlock() }
    return tokenForImage.object(forKey: image) as String?
  }

  private func associate(_ image: UIImage, with token: String) {
    tokenLock.lock()
    defer { tokenLock.unlock() }
    tokenForImage.setObject(token as NSString, forKey: image)
  }

  /// Caches with a byte cost so `totalCostLimit` can actually bound memory.
  private func cache(
    _ image: UIImage,
    as token: String,
    in cache: NSCache<NSString, UIImage>
  ) {
    cache.setObject(image, forKey: token as NSString, cost: ImageStore.cost(of: image))
  }

  /// Approximate decoded size in bytes.
  private static func cost(of image: UIImage) -> Int {
    guard let cgImage = image.cgImage else {
      return Int(image.size.width * image.size.height * 4)
    }
    return cgImage.bytesPerRow * cgImage.height
  }

  private func writeThumbnail(for image: UIImage, token: String) {
    let thumbnail = ImageStore.prepared(
      image,
      maximumDimension: ImageStore.thumbnailDimension
    )
    guard let data = thumbnail.jpegData(compressionQuality: 0.7) else { return }
    try? data.write(to: thumbnailURL(for: token), options: .atomic)
    cache(thumbnail, as: token, in: thumbnailCache)
  }

  private func url(for token: String) -> URL {
    directory.appendingPathComponent(token)
  }

  private func thumbnailURL(for token: String) -> URL {
    let base = (token as NSString).deletingPathExtension
    return directory.appendingPathComponent("\(base).thumb.jpg")
  }
}

/// The archive index (projects, boards, customers, companies, manufacturers) as
/// a JSON file in Application Support.
///
/// It used to live in UserDefaults, which has no room for a growing archive and
/// silently stops saving once it gets large. A plain file has no such ceiling.
enum ArchiveStore {
  private static let legacySnapshotKey = "panelvault.savedSnapshot"
  private static let writeQueue = DispatchQueue(label: "com.panelvault.archive-writes", qos: .utility)

  static var directory: URL {
    let manager = FileManager.default
    let base = manager
      .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? manager.temporaryDirectory
    let folder = base.appendingPathComponent("PanelVault", isDirectory: true)
    try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }

  static var snapshotURL: URL {
    directory.appendingPathComponent("snapshot.json")
  }

  /// Returns the stored JSON, migrating a legacy UserDefaults snapshot the
  /// first time it runs. A nil result means "nothing stored yet" — callers must
  /// not treat it as "the archive is empty" and start deleting files.
  static func loadSnapshot() -> String? {
    if let migrated = migrateLegacySnapshot() { return migrated }
    guard let data = try? Data(contentsOf: snapshotURL), !data.isEmpty else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  static func saveSnapshot(_ json: String) {
    write(json, to: snapshotURL)
  }

  static func saveSnapshotSynchronously(_ json: String) {
    writeQueue.sync {
      writeSynchronously(json, to: snapshotURL)
    }
  }

  private static func migrateLegacySnapshot() -> String? {
    let defaults = UserDefaults.standard
    guard let legacy = defaults.string(forKey: legacySnapshotKey),
          !legacy.isEmpty else { return nil }

    // Write the old payload across before dropping it, so an interrupted
    // migration cannot lose the archive.
    guard writeSynchronously(legacy, to: snapshotURL) else { return legacy }
    defaults.removeObject(forKey: legacySnapshotKey)
    return legacy
  }

  /// Atomic and off the main thread — the snapshot is now small (tokens, not
  /// images), but it is still written on every edit.
  static func write(_ json: String, to url: URL) {
    let data = Data(json.utf8)
    writeQueue.async {
      try? data.write(to: url, options: .atomic)
    }
  }

  @discardableResult
  static func writeSynchronously(_ json: String, to url: URL) -> Bool {
    do {
      try Data(json.utf8).write(to: url, options: .atomic)
      return true
    } catch {
      return false
    }
  }
}

/// Component photos, keyed by component id. Same story as the snapshot: this
/// was a second base64 blob in UserDefaults.
enum ComponentImageStore {
  private static let legacyKey = "panelvault.componentImages"

  static var fileURL: URL {
    ArchiveStore.directory.appendingPathComponent("componentImages.json")
  }

  /// Component id -> image token.
  static func load() -> [String: String] {
    if let migrated = migrateLegacyImages() { return migrated }
    guard let data = try? Data(contentsOf: fileURL),
          let tokens = try? JSONDecoder().decode([String: String].self, from: data)
    else { return [:] }
    return tokens.filter { ImageStore.isToken($0.value) }
  }

  static func save(_ tokens: [String: String]) {
    guard let data = try? JSONEncoder().encode(tokens),
          let json = String(data: data, encoding: .utf8) else { return }
    ArchiveStore.write(json, to: fileURL)
  }

  private static func migrateLegacyImages() -> [String: String]? {
    let defaults = UserDefaults.standard
    guard let legacy = defaults.string(forKey: legacyKey), !legacy.isEmpty,
          let data = legacy.data(using: .utf8),
          let encoded = try? JSONDecoder().decode([String: String].self, from: data)
    else { return nil }

    let tokens = encoded.compactMapValues { ImageStore.shared.adopt($0) }
    guard let migratedData = try? JSONEncoder().encode(tokens),
          let migratedJSON = String(data: migratedData, encoding: .utf8),
          ArchiveStore.writeSynchronously(migratedJSON, to: fileURL) else {
      return tokens
    }
    defaults.removeObject(forKey: legacyKey)
    return tokens
  }
}

extension UIImage {
  var hasTransparency: Bool {
    guard let alphaInfo = cgImage?.alphaInfo else { return false }
    switch alphaInfo {
    case .first, .last, .premultipliedFirst, .premultipliedLast:
      return true
    default:
      return false
    }
  }
}

struct ProjectRecord: Codable {
  let id: String
  let name: String
  let customer: String
  let detail: String
  let status: String
  let colorHex: UInt32
  let coverImageData: String?
  let photoImageData: [String]?
  let dueDate: Date?
  let schemes: [SchemeRecord]

  init(project: ProjectItem) {
    id = project.id
    name = project.name
    customer = project.customer
    detail = project.detail
    status = project.status
    colorHex = project.color.archiveHex
    coverImageData = project.coverToken
    photoImageData = project.photoTokens
    dueDate = project.dueDate
    schemes = project.schemeAttachments.map(SchemeRecord.init(attachment:))
  }

  var project: ProjectItem {
    // `adopt` passes tokens straight through and converts base64 left over from
    // an older snapshot into files, so existing archives migrate on first load.
    ProjectItem(
      id: id,
      name: name,
      customer: customer,
      detail: detail,
      status: status,
      color: Color(hex: colorHex),
      dueDate: dueDate,
      schemeAttachments: schemes.map(\.attachment),
      coverToken: ImageStore.shared.adopt(coverImageData),
      photoTokens: ImageStore.shared.adopt(photoImageData)
    )
  }
}

struct BoardRecord: Codable {
  let id: String
  let number: String
  let group: String
  let name: String
  let customer: String
  let company: String?
  let project: String
  let type: String
  let subtype: String?
  let manufacturer: String
  let ampere: String
  let cabinetCount: String
  let buildFormat: String
  let dateOut: Date
  let dueDate: Date?
  let finishDate: Date?
  let finishTimeHours: String?
  let mainBreakerType: String
  let mainBreakerModel: String
  let mainBreakerAmpere: String
  let componentTypes: [String]
  let colorHex: UInt32
  let coverImageData: String?
  let photoImageData: [String]?
  let schemes: [SchemeRecord]
  let completedChecklistItems: [String]
  let cabinetChecklists: [[String]]?
  let personalChecklistItems: [PersonalChecklistRecord]
  let assignedTo: String?
  let assignedName: String?
  let qaAssignedTo: String?
  let qaAssignedName: String?
  let qaStatus: String?
  let qaNote: String?
  let qaReadyAt: Date?
  let qaApprovedAt: Date?
  let productionStage: String?

  init(board: BoardDraft) {
    id = board.id
    number = board.number
    group = board.group
    name = board.name
    customer = board.customer
    company = board.company
    project = board.project
    type = board.type
    subtype = board.subtype
    manufacturer = board.manufacturer
    ampere = board.ampere
    cabinetCount = board.cabinetCount
    buildFormat = board.buildFormat
    dateOut = board.dateOut
    dueDate = board.dueDate
    finishDate = board.finishDate
    finishTimeHours = board.finishTimeHours
    mainBreakerType = board.mainBreakerType
    mainBreakerModel = board.mainBreakerModel
    mainBreakerAmpere = board.mainBreakerAmpere
    componentTypes = board.componentTypes
    colorHex = board.color.archiveHex
    coverImageData = board.coverToken
    photoImageData = board.photoTokens
    schemes = board.schemeAttachments.map(SchemeRecord.init(attachment:))
    completedChecklistItems = Array(board.completedChecklistItems)
    cabinetChecklists = board.normalizedCabinetChecklists.map { Array($0) }
    personalChecklistItems = board.personalChecklistItems.map(PersonalChecklistRecord.init(item:))
    assignedTo = board.assignedTo
    assignedName = board.assignedName
    qaAssignedTo = board.qaAssignedTo
    qaAssignedName = board.qaAssignedName
    qaStatus = board.qaStatus
    qaNote = board.qaNote
    qaReadyAt = board.qaReadyAt
    qaApprovedAt = board.qaApprovedAt
    productionStage = board.productionStage
  }

  var board: BoardDraft {
    BoardDraft(
      id: id,
      number: number,
      group: group,
      name: name,
      customer: customer,
      company: company ?? "",
      project: project,
      type: type,
      subtype: subtype ?? BoardSubtypeCatalog.defaultSubtype,
      manufacturer: manufacturer,
      ampere: ampere,
      cabinetCount: cabinetCount,
      buildFormat: buildFormat,
      dateOut: dateOut,
      dueDate: dueDate,
      finishDate: finishDate,
      finishTimeHours: finishTimeHours ?? "",
      mainBreakerType: mainBreakerType,
      mainBreakerModel: mainBreakerModel,
      mainBreakerAmpere: mainBreakerAmpere,
      componentTypes: componentTypes,
      color: Color(hex: colorHex),
      coverToken: ImageStore.shared.adopt(coverImageData),
      photoTokens: ImageStore.shared.adopt(photoImageData),
      schemeAttachments: schemes.map(\.attachment),
      completedChecklistItems: Set(completedChecklistItems),
      personalChecklistItems: personalChecklistItems.map(\.item),
      cabinetChecklists: (cabinetChecklists ?? []).map(Set.init),
      assignedTo: assignedTo,
      assignedName: assignedName ?? "",
      qaAssignedTo: qaAssignedTo,
      qaAssignedName: qaAssignedName ?? "",
      qaStatus: qaStatus ?? "pending",
      qaNote: qaNote ?? "",
      qaReadyAt: qaReadyAt,
      qaApprovedAt: qaApprovedAt,
      productionStage: productionStage ?? (qaStatus == "approved" ? "complete"
        : qaStatus == "ready" ? "qa"
        : qaStatus == "changes_requested" ? "finishing"
        : assignedTo == nil ? "design" : "mechanical")
    )
  }
}

struct CustomerRecord: Codable {
  let id: String
  let name: String
  let kind: String?
  let contactName: String?
  let phone: String
  let note: String
  let contacts: [CustomerContactRecord]?
  let colorHex: UInt32?

  init(customer: CustomerItem) {
    id = customer.id
    name = customer.name
    kind = customer.kind
    contactName = customer.contactName
    phone = customer.phone
    note = customer.note
    contacts = customer.contacts.map(CustomerContactRecord.init(contact:))
    colorHex = customer.colorHex
  }

  var customer: CustomerItem {
    CustomerItem(id: id, name: name, kind: kind ?? "Company", contactName: contactName ?? "", phone: phone, note: note, contacts: contacts?.map(\.contact) ?? [], colorHex: colorHex ?? 0x5E78FF)
  }
}

struct CustomerContactRecord: Codable {
  let id: String
  let name: String
  let role: String
  let phone: String

  init(contact: CustomerContact) {
    id = contact.id
    name = contact.name
    role = contact.role
    phone = contact.phone
  }

  var contact: CustomerContact {
    CustomerContact(id: id, name: name, role: role, phone: phone)
  }
}

struct CompanyRecord: Codable {
  let id: String
  let name: String
  let role: String
  let projectCount: String
  let colorHex: UInt32

  init(company: ContractorCompany) {
    id = company.id
    name = company.name
    role = company.role
    projectCount = company.projectCount
    colorHex = company.color.archiveHex
  }

  var company: ContractorCompany {
    ContractorCompany(id: id, name: name, role: role, projectCount: projectCount, color: Color(hex: colorHex))
  }
}

struct ManufacturerRecord: Codable {
  let id: String
  let name: String
  let colorHex: UInt32
  let imageData: String?

  init(manufacturer: ManufacturerItem) {
    id = manufacturer.id
    name = manufacturer.name
    colorHex = manufacturer.colorHex
    imageData = manufacturer.imageToken
  }

  var manufacturer: ManufacturerItem {
    ManufacturerItem(
      id: id,
      name: name,
      colorHex: colorHex,
      imageToken: ImageStore.shared.adopt(imageData)
    )
  }
}

struct SchemeRecord: Codable {
  let id: String
  let kind: String
  let name: String
  let url: String?
  let imageData: String?

  init(attachment: SchemeAttachment) {
    id = attachment.id
    kind = attachment.kind == .pdf ? "pdf" : "photo"
    name = attachment.name
    url = attachment.url?.absoluteString
    imageData = attachment.imageToken
  }

  var attachment: SchemeAttachment {
    SchemeAttachment(
      id: id,
      kind: kind == "pdf" ? .pdf : .photo,
      name: name,
      imageToken: ImageStore.shared.adopt(imageData),
      url: url.flatMap(URL.init(string:))
    )
  }
}

struct PersonalChecklistRecord: Codable {
  let id: String
  let title: String
  let isDone: Bool

  init(item: PersonalChecklistItem) {
    id = item.id
    title = item.title
    isDone = item.isDone
  }

  var item: PersonalChecklistItem {
    PersonalChecklistItem(id: id, title: title, isDone: isDone)
  }
}

extension Color {
  init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255
    )
  }

  var archiveHex: UInt32 {
    let uiColor = UIColor(self)
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return 0x5E78FF }
    return (UInt32(red * 255) << 16) | (UInt32(green * 255) << 8) | UInt32(blue * 255)
  }
}

// MARK: - Warehouse stock (PanelVault Cloud)
//
// The warehouse app and this app share one key: a component's catalog id.
// `StockMovement.partID` in warehouse/Sources/Models.swift is exactly
// `PanelComponent.id` here, so on-hand counts pulled from Cloud can be shown
// straight on the catalog. Stock is always replayed from the append-only
// movement log; this client never invents or edits a total.

struct PanelCloudLoginResponse: Decodable {
  struct Company: Decodable { let code: String; let name: String }
  struct User: Decodable { let id: String; let name: String; let role: String }
  let token: String
  let expiresAt: String
  let company: Company
  let user: User
}

/// One movement as Cloud returns it, narrowed to what stock derivation needs.
struct PanelCloudMovement: Decodable {
  let id: String
  let partID: String
  let kind: String
  let quantity: Int
  let sequence: Int?

  /// Effect on the on-hand count. Matches `StockMovement.delta` in the
  /// warehouse app: receive adds, consume subtracts, adjust carries a signed
  /// delta.
  var delta: Int {
    switch kind {
    case "receive": return quantity
    case "consume": return -quantity
    default: return quantity
    }
  }
}

struct PanelCloudDownloadResponse: Decodable {
  let movements: [PanelCloudMovement]
  let latestSequence: Int
  let hasMore: Bool
}

/// What PanelVault Cloud read out of an AutoCAD board scheme.
///
/// Every field is optional in practice: the server is told to return an empty
/// string rather than infer a value it cannot see on the drawing, because a
/// blank a manager fills in takes seconds and a confident wrong one gets built.
struct BoardSchemeReading: Decodable {
  struct Board: Decodable {
    var number = ""
    var name = ""
    var customer = ""
    var project = ""
    var type = ""
    var manufacturer = ""
    var mainBreakerType = ""
    var mainBreakerModel = ""
    var mainBreakerAmpere = ""
    var cabinetCount = 1
    var notes = ""
  }

  /// A schedule line matched to a catalog part.
  struct Component: Decodable, Identifiable {
    let partID: String
    var manufacturer = ""
    var model = ""
    var type = ""
    var quantity = 1
    var reference = ""

    var id: String { reference.isEmpty ? partID : "\(partID)-\(reference)" }
    var displayName: String { "\(manufacturer) \(model)".trimmingCharacters(in: .whitespaces) }
  }

  /// A schedule line the catalog has no confident match for. Shown so nobody
  /// assumes the board is complete when part of the schedule was not placed.
  struct Unmatched: Decodable, Identifiable {
    var description = ""
    var type = ""
    var quantity = 1
    var reference = ""

    var id: String { "\(description)-\(reference)" }
  }

  var board = Board()
  var components: [Component] = []
  var unmatched: [Unmatched] = []
  var model: String?

  var componentCount: Int { components.reduce(0) { $0 + $1.quantity } }
  var isEmpty: Bool {
    board.number.isEmpty && board.name.isEmpty && components.isEmpty && unmatched.isEmpty
  }
}

enum WarehouseStockCloudError: LocalizedError {
  case invalidServer
  case server(String)
  case invalidResponse

  var errorDescription: String? {
    switch self {
    case .invalidServer: return "Enter a valid PanelVault Cloud address."
    case .server(let message): return message
    case .invalidResponse: return "PanelVault Cloud returned an invalid response."
    }
  }
}

struct WarehouseStockCloudClient {
  func login(baseURL: String, companyCode: String, name: String, password: String) async throws -> PanelCloudAccount {
    let normalized = try WarehouseStockCloudClient.normalizedBaseURL(baseURL)
    let response: PanelCloudLoginResponse = try await request(
      baseURL: normalized,
      path: "/api/mobile/login",
      method: "POST",
      body: ["companyCode": companyCode, "name": name, "password": password],
      token: nil
    )
    return PanelCloudAccount(
      baseURL: normalized.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
      token: response.token,
      expiresAt: response.expiresAt,
      companyCode: response.company.code,
      companyName: response.company.name,
      userID: response.user.id,
      userName: response.user.name,
      role: response.user.role
    )
  }

  func download(after sequence: Int, account: PanelCloudAccount) async throws -> PanelCloudDownloadResponse {
    try await request(
      baseURL: try WarehouseStockCloudClient.normalizedBaseURL(account.baseURL),
      path: "/api/sync/movements?after=\(sequence)",
      method: "GET",
      body: Optional<[String: String]>.none,
      token: account.token
    )
  }

  /// Send an AutoCAD scheme to PanelVault Cloud and get the board it describes.
  ///
  /// The drawing itself goes up — Gemini reads PDFs natively, so nothing is
  /// rasterised or OCR'd here. Reading a large multi-page scheme is slow by
  /// nature, hence the long timeout; the caller shows progress for it.
  func readBoardScheme(
    fileName: String,
    mimeType: String,
    data: Data,
    account: PanelCloudAccount
  ) async throws -> BoardSchemeReading {
    try await request(
      baseURL: try WarehouseStockCloudClient.normalizedBaseURL(account.baseURL),
      path: "/api/ai/board-scheme",
      method: "POST",
      body: [
        "fileName": fileName,
        "mimeType": mimeType,
        "data": data.base64EncodedString(),
      ],
      token: account.token,
      timeout: 180
    )
  }

  private static func normalizedBaseURL(_ value: String) throws -> URL {
    var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if !text.contains("://") { text = "https://\(text)" }
    guard let url = URL(string: text),
          ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
          let host = url.host else { throw WarehouseStockCloudError.invalidServer }
    if url.scheme?.lowercased() == "http", !isPrivateDevelopmentHost(host) {
      throw WarehouseStockCloudError.invalidServer
    }
    return url
  }

  private static func isPrivateDevelopmentHost(_ rawHost: String) -> Bool {
    let host = rawHost.lowercased()
    if host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".local") {
      return true
    }
    let octets = host.split(separator: ".").compactMap { Int($0) }
    guard octets.count == 4 else { return false }
    if octets[0] == 10 || (octets[0] == 192 && octets[1] == 168) { return true }
    return octets[0] == 172 && (16...31).contains(octets[1])
  }

  private func request<Response: Decodable, Body: Encodable>(
    baseURL: URL,
    path: String,
    method: String,
    body: Body?,
    token: String?,
    timeout: TimeInterval = 30
  ) async throws -> Response {
    guard let url = URL(string: path, relativeTo: baseURL) else { throw WarehouseStockCloudError.invalidServer }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = timeout
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONEncoder().encode(body)
    }

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw WarehouseStockCloudError.invalidResponse }
    guard 200..<300 ~= http.statusCode else {
      let message = (try? JSONDecoder().decode(PanelCloudErrorBody.self, from: data).error)
        ?? "PanelVault Cloud request failed (\(http.statusCode))."
      throw WarehouseStockCloudError.server(message)
    }
    guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
      throw WarehouseStockCloudError.invalidResponse
    }
    return decoded
  }
}

private struct PanelCloudErrorBody: Decodable { let error: String }

/// The session token lives in the keychain, not UserDefaults. Its service id is
/// distinct from the warehouse app's so the two never fight over one entry.
enum PanelCloudKeychain {
  private static let service = "com.panelvault.ios.cloud"
  private static let account = "active-account"

  static func load() -> PanelCloudAccount? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
          let data = result as? Data else { return nil }
    return try? JSONDecoder().decode(PanelCloudAccount.self, from: data)
  }

  static func save(_ value: PanelCloudAccount?) {
    let base: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    SecItemDelete(base as CFDictionary)
    guard let value, let data = try? JSONEncoder().encode(value) else { return }
    var insert = base
    insert[kSecValueData as String] = data
    insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    SecItemAdd(insert as CFDictionary, nil)
  }
}

/// On-hand stock per catalog component, replayed from PanelVault Cloud.
///
/// A shared instance rather than an environment object: the catalog is shown
/// from several sheets, and an `@EnvironmentObject` that fails to propagate
/// into one of them is a crash rather than a blank badge.
@MainActor
final class WarehouseStockStore: ObservableObject {
  static let shared = WarehouseStockStore()

  @Published private(set) var account: PanelCloudAccount?
  @Published private(set) var onHand: [String: Int] = [:]
  @Published private(set) var lastSyncedAt: Date?
  @Published private(set) var isSyncing = false
  @Published var errorMessage: String?

  private var lastSequence = 0
  private let client = WarehouseStockCloudClient()

  var isConnected: Bool { account != nil }

  /// Nil when nothing is connected, so the UI can hide stock entirely rather
  /// than claim every part is at zero.
  func stock(for componentID: String) -> Int? {
    guard isConnected else { return nil }
    return onHand[componentID] ?? 0
  }

  func totalStock(forComponentIDs ids: [String]) -> Int? {
    guard isConnected else { return nil }
    return ids.reduce(0) { $0 + (onHand[$1] ?? 0) }
  }

  private init() {
    account = PanelCloudKeychain.load()
    loadCache()
  }

  func connect(baseURL: String, companyCode: String, name: String, password: String) async {
    isSyncing = true
    errorMessage = nil
    defer { isSyncing = false }
    do {
      let signedIn = try await client.login(baseURL: baseURL, companyCode: companyCode, name: name, password: password)
      // A different company means the cached counts describe someone else's
      // warehouse; start clean rather than blending two logs.
      if signedIn.companyCode != account?.companyCode {
        onHand = [:]
        lastSequence = 0
        lastSyncedAt = nil
      }
      account = signedIn
      PanelCloudKeychain.save(signedIn)
      saveCache()
      await sync()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func disconnect() {
    account = nil
    onHand = [:]
    lastSequence = 0
    lastSyncedAt = nil
    errorMessage = nil
    PanelCloudKeychain.save(nil)
    saveCache()
  }

  func sync() async {
    guard let account else { return }
    isSyncing = true
    errorMessage = nil
    defer { isSyncing = false }

    var counts = onHand
    var cursor = lastSequence
    // The cursor only ever moves forward, so a malformed page cannot spin here
    // forever; the page cap is a belt-and-braces stop.
    var pages = 0

    do {
      while pages < 100 {
        let page = try await client.download(after: cursor, account: account)
        for movement in page.movements {
          counts[movement.partID, default: 0] += movement.delta
        }
        let highest = page.movements.compactMap(\.sequence).max()
        let next = max(highest ?? page.latestSequence, cursor)
        if !page.hasMore || next <= cursor {
          cursor = max(next, page.latestSequence)
          break
        }
        cursor = next
        pages += 1
      }
      onHand = counts
      lastSequence = cursor
      lastSyncedAt = Date()
      saveCache()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  // MARK: - Cache

  private struct Cache: Codable {
    var companyCode: String
    var onHand: [String: Int]
    var lastSequence: Int
    var lastSyncedAt: Date?
  }

  private var cacheURL: URL {
    let base = FileManager.default
      .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    let folder = base.appendingPathComponent("PanelVault", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder.appendingPathComponent("warehouse-stock.json")
  }

  private func loadCache() {
    guard let data = try? Data(contentsOf: cacheURL),
          let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return }
    // Only trust the cache if it belongs to the signed-in company.
    guard cache.companyCode == account?.companyCode else { return }
    onHand = cache.onHand
    lastSequence = cache.lastSequence
    lastSyncedAt = cache.lastSyncedAt
  }

  private func saveCache() {
    let cache = Cache(
      companyCode: account?.companyCode ?? "",
      onHand: onHand,
      lastSequence: lastSequence,
      lastSyncedAt: lastSyncedAt
    )
    guard let data = try? JSONEncoder().encode(cache) else { return }
    try? data.write(to: cacheURL, options: .atomic)
  }
}

/// Small pill showing on-hand stock for a catalog part.
struct StockBadge: View {
  let theme: PanelTheme
  let count: Int
  var compact = false

  private var color: Color {
    if count <= 0 { return theme.danger }
    if count <= 5 { return theme.designAccent }
    return theme.success
  }

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: "shippingbox.fill")
        .font(.system(size: compact ? 8 : 9, weight: .bold))
      Text(count <= 0 ? "None" : "\(count)")
        .font(.system(size: compact ? 10 : 11, weight: .heavy))
    }
    .foregroundStyle(color)
    .lineLimit(1)
    .padding(.horizontal, 7)
    .frame(height: compact ? 19 : 21)
    .background(color.opacity(0.14))
    .clipShape(Capsule())
  }
}

/// Connect this app to PanelVault Cloud and pull warehouse stock.
struct WarehouseStockSheet: View {
  let theme: PanelTheme
  @ObservedObject private var store = WarehouseStockStore.shared
  @Environment(\.dismiss) private var dismiss

  @State private var server = ""
  @State private var companyCode = ""
  @State private var name = ""
  @State private var password = ""

  private var lastSyncedText: String {
    guard let date = store.lastSyncedAt else { return "Never" }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter.localizedString(for: date, relativeTo: Date())
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 14) {
          if let account = store.account {
            GlassCard(theme: theme) {
              VStack(alignment: .leading, spacing: 10) {
                HStack {
                  Label("Connected", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(theme.success)
                  Spacer()
                  if store.isSyncing { ProgressView() }
                }
                Text(account.companyName)
                  .font(.system(size: 17, weight: .heavy))
                Text("\(account.userName) • \(account.role.capitalized)")
                  .font(.caption)
                  .foregroundStyle(.secondary)
                Divider().opacity(0.4)
                HStack {
                  Text("Parts in stock").font(.caption).foregroundStyle(.secondary)
                  Spacer()
                  Text("\(store.onHand.values.filter { $0 > 0 }.count)")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(theme.primary)
                }
                HStack {
                  Text("Last synced").font(.caption).foregroundStyle(.secondary)
                  Spacer()
                  Text(lastSyncedText).font(.caption.bold())
                }
              }
            }

            Button {
              Task { await store.sync() }
            } label: {
              Label("Sync now", systemImage: "arrow.clockwise")
                .font(.system(size: 15, weight: .heavy))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(theme.primary)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: theme.radiusControl, style: .continuous))
            }
            .buttonStyle(PanelPressButtonStyle())
            .disabled(store.isSyncing)

            Button(role: .destructive) {
              store.disconnect()
            } label: {
              Text("Disconnect")
                .font(.system(size: 14, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
            }
            .buttonStyle(PanelPressButtonStyle())
          } else {
            Text("Sign in to PanelVault Cloud to show live warehouse stock on the equipment catalog.")
              .font(.callout)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)

            CreationTextInput(theme: theme, title: "Server", placeholder: "cloud.panelvault.app", symbol: "network", text: $server, keyboardType: .URL, capitalization: .never)
            CreationTextInput(theme: theme, title: "Company code", placeholder: "Company code", symbol: "building.2.fill", text: $companyCode, capitalization: .characters)
            CreationTextInput(theme: theme, title: "Your name", placeholder: "Your name", symbol: "person.fill", text: $name, capitalization: .words)

            CreationFieldShell(theme: theme, title: "Password", symbol: "lock.fill") {
              SecureField("Password", text: $password)
                .font(.system(size: 15, weight: .semibold))
                .multilineTextAlignment(.trailing)
            }

            Button {
              Task {
                await store.connect(baseURL: server, companyCode: companyCode, name: name, password: password)
                if store.errorMessage == nil { password = "" }
              }
            } label: {
              HStack(spacing: 8) {
                if store.isSyncing { ProgressView().tint(.white) }
                Text(store.isSyncing ? "Connecting" : "Connect")
                  .font(.system(size: 15, weight: .heavy))
              }
              .frame(maxWidth: .infinity)
              .frame(height: 48)
              .background(theme.primary)
              .foregroundStyle(.white)
              .clipShape(RoundedRectangle(cornerRadius: theme.radiusControl, style: .continuous))
            }
            .buttonStyle(PanelPressButtonStyle())
            .disabled(store.isSyncing || server.isEmpty || companyCode.isEmpty || name.isEmpty || password.isEmpty)
          }

          if let message = store.errorMessage {
            Text(message)
              .font(.caption)
              .foregroundStyle(theme.danger)
              .frame(maxWidth: .infinity, alignment: .leading)
          }

          BottomTabClearance()
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Warehouse Stock")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }.fontWeight(.bold)
        }
      }
    }
  }
}
