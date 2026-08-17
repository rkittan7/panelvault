// Copied from the PanelVault app (ios/Runner/SceneDelegate.swift) by
// tools/split_worker.py. The worker app is a deliberate copy of PanelVault's
// design system and data model, with manager-only creation removed and the
// warehouse added. Edit here; do not re-run the splitter over hand edits.

import SwiftUI

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
          BoardScreen(theme: theme, board: $boards[index], boardTypes: boardTypes, manufacturers: manufacturers, onDeleteBoard: {
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
