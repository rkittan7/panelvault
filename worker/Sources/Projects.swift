// Copied from the PanelVault app (ios/Runner/SceneDelegate.swift) by
// tools/split_worker.py. The worker app is a deliberate copy of PanelVault's
// design system and data model, with manager-only creation removed and the
// warehouse added. Edit here; do not re-run the splitter over hand edits.

import SwiftUI

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
  @Binding var selectedTab: WorkerTab
  @Binding var pendingProjectOpenID: String?
  @Binding var recentVisits: [RecentVisit]
  @State private var selectedProject: ProjectItem?
  @State private var selectedBoardID: String?

  private var statuses: [String] {
    archiveMode == .projects ? ["All", "In Progress", "Completed", "Design"] : ["All", "In Progress", "Finished"]
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
            // No "New Project" here. Projects and boards are created in the
            // manager app or in PanelVault Cloud; this app works the ones a
            // worker has been given.
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
                )
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
      .sheet(item: $selectedProject) { project in
        // onUpdateProject stays wired: it is how project photos and scheme
        // attachments get written back, and a worker does add those. There is
        // no onDeleteProject, and no Edit button to change the project's name
        // or customer — that is the manager app's job.
        ProjectDetailSheet(theme: theme, project: project, boards: $boards, boardTypes: boardTypes, manufacturers: manufacturers) { board in
          remember(.board, id: board.id)
        } onUpdateProject: { updatedProject, previousName in
          if let index = projects.firstIndex(where: { $0.id == updatedProject.id }) {
            projects[index] = updatedProject
          }
          for index in boards.indices where boards[index].project == previousName {
            boards[index].project = updatedProject.name
          }
        }
          .presentationDetents([.large])
          .presentationDragIndicator(.visible)
      }
      .sheet(item: selectedBoardBinding) { boardSelection in
        NavigationStack {
          if let index = boards.firstIndex(where: { $0.id == boardSelection.id }) {
            BoardScreen(theme: theme, board: $boards[index], boardTypes: boardTypes, manufacturers: manufacturers) {
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

struct ProjectDetailSheet: View {
  let theme: PanelTheme
  let project: ProjectItem
  @Binding var boards: [BoardDraft]
  let boardTypes: [BoardType]
  let manufacturers: [ManufacturerItem]
  var onVisitBoard: (BoardDraft) -> Void = { _ in }
  var onUpdateProject: ((ProjectItem, String) -> Void)? = nil
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
  @State private var attachBoardsOpen = false

  init(
    theme: PanelTheme,
    project: ProjectItem,
    boards: Binding<[BoardDraft]>,
    boardTypes: [BoardType],
    manufacturers: [ManufacturerItem],
    onVisitBoard: @escaping (BoardDraft) -> Void = { _ in },
    onUpdateProject: ((ProjectItem, String) -> Void)? = nil
  ) {
    self.theme = theme
    self.project = project
    self._boards = boards
    self.boardTypes = boardTypes
    self.manufacturers = manufacturers
    self.onVisitBoard = onVisitBoard
    self.onUpdateProject = onUpdateProject
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
        // No Edit: the project's identity belongs to the manager app.
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
      .sheet(item: $selectedBoard) { board in
        NavigationStack {
          if let index = boards.firstIndex(where: { $0.id == board.id }) {
            BoardScreen(theme: theme, board: $boards[index], boardTypes: boardTypes, manufacturers: manufacturers) {
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
