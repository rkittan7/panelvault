#!/usr/bin/env python3
"""Split ios/Runner/SceneDelegate.swift into the worker app's Sources/.

The PanelVault app is one 12,840-line file. The worker app is a copy of it, so
this script slices that file by top-level declaration instead of retyping it:
byte-exact for everything kept, with the manager-only declarations dropped and
a small hand-written delta applied afterwards.

Run from the repo root:  python3 tools/split_worker.py
"""

import os
import re
import sys

SOURCE = "ios/Runner/SceneDelegate.swift"
OUT = "worker/Sources"

HEADER = """// Copied from the PanelVault app (ios/Runner/SceneDelegate.swift) by
// tools/split_worker.py. The worker app is a deliberate copy of PanelVault's
// design system and data model, with manager-only creation removed and the
// warehouse added. Edit here; do not re-run the splitter over hand edits.

"""

# Top-level declarations that belong to the manager app only. Every one of
# these creates or redefines a record; the worker app changes state, not
# definitions.
DROP = {
    # Board and project creation
    "NewHubSelection", "NewHubView",
    "NewBoardPickerSheet", "NewBoardView",
    "NewBoardEntryMode", "NewBoardModeCard",
    "MainBreakerStepView", "MainBreakerPickerSheet",
    "NewBoardStepIndicator", "NewProjectSheet",
    # Reading an AutoCAD scheme is the first step of creating a board, so it
    # is manager-only too. `BoardSchemeReading` is not here: it is the shape of
    # a Cloud response and stays with the rest of the client.
    "PanelVaultSchemeReader", "NewBoardSchemeIntakeView",
    "SchemeReadingSummaryCard", "SchemeReadingReviewCard",
    # Editing a record's definition
    "ProjectEditSheet", "BoardEditSheet", "BoardEditPickerSheet",
    # Catalogue and company management
    "CustomerManagerSheet", "CustomerManagerRow", "CustomerArchiveDetailSheet",
    "CustomerEditSheet", "CustomerContactEditorRow",
    "ManufacturerManagerSheet", "ManufacturerEditorRow",
    "BoardTypeManagerSheet", "SimpleBoardTypeRow",
    "CompanySwitcherSheet", "CompanyManagerSheet",
    "AddComponentSheet",
    # Only ever used by the two edit sheets above
    "DeleteRecordButton",
    # Replaced by the worker app's own root, tab set and warehouse-backed store
    "SceneDelegate", "PanelVaultAppView", "PanelTab", "PanelVaultTabBar",
    "WarehouseStockStore", "WarehouseStockSheet",
}

# Everything kept, grouped into files by concern.
FILES = {
    "Theme.swift": [
        "PanelTheme", "AccentChoice", "AccentPalette", "ColorSwatchPicker",
        "InterfaceSize", "Color",
    ],
    "DesignSystem.swift": [
        "TabBarButtonStyle", "BottomTabClearance", "PanelPressButtonStyle",
        "PanelToggleStyle", "GlassCard", "TopScrollBlur", "EmptyStateCard",
        "ViewAllInlineButton", "InfoLine", "SimpleListRow", "SimpleListSheet",
        "MoreRow", "PickerLikeRow", "BoardReferenceSection", "BoardBulletList",
        # DeleteIconButton stays: the worker's personal checklist owns its rows.
        "DeleteIconButton",
    ],
    "Badges.swift": [
        "StatusBadge", "BoardProgressStatusBadge", "RecentStatusBadge",
        "RecentKindBadge", "RecentBoardTypeChip", "RecentBoardInfoChip",
        "RecentManufacturerChip", "DueDateBadge", "BoardTypeIcon",
        "EquipmentBrandBadge", "EquipmentPill", "TransparentImageBubble",
        "PanelVaultLogoMark", "ABBLogo", "ManufacturerLogoView",
        "ManufacturerMarkView", "ManufacturerInlineMark", "CompanyColorLogo",
        "ComponentIcon", "ComponentSummaryCard",
    ],
    "Formatting.swift": [
        "DateDisplay", "dueDateComesFirst", "activeBoardPrioritySort",
        "boardPrioritySort", "projectPrioritySort", "syncedManufacturer",
        "dueUrgencyColor",
    ],
    "CreationInputs.swift": [
        "CreationFormSection", "CreationTextInput", "CreationMenuInput",
        "CreationPickerInput", "ManufacturerPickerInput", "CreationDateInput",
        "CreationToggleInput", "CreationFieldShell", "CreationOptionPickerSheet",
        "ManufacturerCreationPickerSheet", "BoardTypeCreationPickerSheet",
        "ProjectCreationPickerSheet", "CreationPickerSearch",
        "CreationOptionCard", "SuggestionChips",
    ],
    "Dashboard.swift": [
        "DashboardView", "DashboardSheet", "ProjectMetricCard",
        "ProjectDashboardRow", "DashboardProjectRecentRow",
        "DashboardBoardProgressRow", "DashboardBoardRecentRow",
        "DashboardStatsSheet", "ProjectsListSheet", "BoardGalleryRow",
        "BoardCardThumbnail",
    ],
    "Projects.swift": [
        "ProjectsView", "ArchiveSectionDivider", "BoardStageDivider",
        "ArchiveMode", "ProjectDetailSheet", "ProjectPropertiesOverview",
        "ProjectPropertyPill", "ManufacturerPropertyPill", "DueDatePropertyPill",
        "AddablePropertyPill", "FinishStatusPropertyPill",
        "BoardPropertiesOverview", "BoardTypesSheet", "BoardTypeDetailSheet",
    ],
    "BoardDetail.swift": [
        "CreatedBoardScreen", "ComponentTypeSelection", "ComponentTypeCatalogSheet",
        "BoardCoverPhotoSection", "ProjectCoverPhotoSection", "CoverPhotoView",
        "CoverPhotoEditorSheet", "CabinetTab", "ChecklistTemplate",
        "ChecklistItem", "ChecklistProgressSection", "PersonalChecklistSection",
        "SchemeAttachmentSection", "SchemeAttachmentRow", "PhotoPickerSection",
        "BoardAttachPickerSheet", "BoardAttachPickerContent", "BoardAttachRow",
        "ImagePreviewItem", "ImagePreviewSheet",
    ],
    "Search.swift": [
        "SearchView", "SearchFilterSection", "SearchFilterChip", "SearchScope",
        "ProjectSearchRow", "BoardSearchRow",
    ],
    "More.swift": [
        "MoreView", "MoreSheet", "ProfileAvatarView", "ProfileEditorSheet",
        "ProfileMoreRow", "ThemeRow", "ThemePickerRow", "ThemePickerSheet",
        "DisplaySizePickerSheet", "CompanyRow",
    ],
    "Catalog.swift": [
        "ComponentCatalogView", "ComponentBoardPickerSheet", "CatalogCategoryBlock",
        "ComponentRow", "ComponentRatingSheet", "RatingChipSection",
        "ComponentDetailSheet", "ManufacturerDetailSheet", "ManufacturerSelection",
        "BoardIDSelection",
    ],
    "Models.swift": [
        "ContractorCompany", "CustomerContact", "CustomerItem", "RecentVisit",
        "RecentBoardSelection", "SchemeAttachment", "ManufacturerItem",
        "PanelStat", "BoardType", "ProjectItem", "ComponentGroup",
        "PanelComponent", "BoardDraft", "PersonalChecklistItem",
        "EquipmentCompany", "BoardSubtypeCatalog", "EquipmentTypeCatalog",
        "AmpereRating", "PoleRating",
    ],
    "Persistence.swift": [
        "PanelVaultSnapshot", "ImageStore", "ArchiveStore", "ComponentImageStore",
        "UIImage", "ProjectRecord", "BoardRecord", "CustomerRecord",
        "CustomerContactRecord", "CompanyRecord", "ManufacturerRecord",
        "SchemeRecord", "PersonalChecklistRecord",
    ],
    "CatalogImages.swift": ["CatalogImageLibrary"],
    "Cloud.swift": [
        "PanelCloudAccount", "PanelCloudLoginResponse", "PanelCloudMovement",
        "PanelCloudDownloadResponse", "BoardSchemeReading",
        "PanelCapabilities", "PanelRole",
        "PanelCloudError", "PanelCloudClient",
        "PanelCloudErrorBody", "PanelCloudKeychain", "StockBadge",
    ],
}

IMPORTS = {
    "Theme.swift": ["SwiftUI", "UIKit"],
    "DesignSystem.swift": ["SwiftUI"],
    "Badges.swift": ["SwiftUI"],
    "Formatting.swift": ["SwiftUI"],
    "CreationInputs.swift": ["SwiftUI"],
    "Dashboard.swift": ["SwiftUI"],
    "Projects.swift": ["SwiftUI"],
    "BoardDetail.swift": ["SwiftUI", "PhotosUI", "UniformTypeIdentifiers"],
    "Search.swift": ["SwiftUI"],
    "More.swift": ["SwiftUI", "PhotosUI"],
    "Catalog.swift": ["SwiftUI", "PhotosUI"],
    "Models.swift": ["SwiftUI", "UIKit"],
    "Persistence.swift": ["SwiftUI", "UIKit"],
    "CatalogImages.swift": ["UIKit"],
    "Cloud.swift": ["SwiftUI", "Foundation", "Security"],
}

DECL = re.compile(
    r"^(?:@main\s+)?(?:public\s+|private\s+|fileprivate\s+|internal\s+)?"
    r"(?:final\s+)?(struct|class|enum|extension|protocol|actor|func|var|let)\s+"
    r"([A-Za-z_][A-Za-z0-9_]*)"
)

# `private` on a top-level declaration means "visible in this file", and in the
# PanelVault app that file is the entire app. Slicing it into Sources/ turns one
# file scope into a dozen, so a top-level `private` helper would stop being
# visible to the callers it was written for -- `syncedManufacturer` alone is
# used from five of the files below. Drop the modifier on the way out: internal
# is still module-scoped, so nothing becomes visible outside the app that was
# not already visible to every line of the file this came from.
TOP_LEVEL_PRIVATE = re.compile(r"^((?:@main\s+)?)(?:private|fileprivate)\s+")


def slice_declarations(path):
    """Return [(name, kind, [lines])] for every top-level declaration.

    Any attribute or doc-comment lines immediately above a declaration belong
    to it, so they travel with it into the destination file.
    """
    lines = open(path, encoding="utf-8").read().split("\n")
    starts = []
    for i, line in enumerate(lines):
        match = DECL.match(line)
        if not match:
            continue
        # Walk back over the declaration's own doc comments and attributes.
        j = i
        while j > 0:
            above = lines[j - 1].strip()
            if above.startswith(("///", "//", "@", "/*", "*", "*/")):
                j -= 1
            else:
                break
        starts.append((j, i, match.group(1), match.group(2)))

    out = []
    for index, (top, decl, kind, name) in enumerate(starts):
        end = starts[index + 1][0] if index + 1 < len(starts) else len(lines)
        body = lines[top:end]
        # Only the declaration's own line, never a `private` on a member inside
        # it -- those still mean what they meant.
        body[decl - top] = TOP_LEVEL_PRIVATE.sub(r"\1", body[decl - top], count=1)
        out.append((name, kind, body))
    return out


def main():
    if not os.path.exists(SOURCE):
        sys.exit(f"run from the repo root: {SOURCE} not found")

    declarations = slice_declarations(SOURCE)
    by_name = {}
    for name, kind, body in declarations:
        by_name.setdefault(name, []).append((kind, body))

    wanted = {name: filename for filename, names in FILES.items() for name in names}

    # Every declaration must be routed somewhere or explicitly dropped, so a
    # future edit to the PanelVault app cannot silently vanish from the copy.
    unrouted = [n for n in by_name if n not in wanted and n not in DROP]
    if unrouted:
        sys.exit("unrouted declarations: " + ", ".join(sorted(unrouted)))
    missing = [n for n in wanted if n not in by_name]
    if missing:
        sys.exit("routed but not found in source: " + ", ".join(sorted(missing)))

    os.makedirs(OUT, exist_ok=True)
    for filename, names in FILES.items():
        chunks = []
        for name in names:
            for _, body in by_name[name]:
                text = "\n".join(body).rstrip()
                if text:
                    chunks.append(text)
        imports = "\n".join(f"import {module}" for module in IMPORTS[filename])
        content = HEADER + imports + "\n\n" + "\n\n".join(chunks) + "\n"
        with open(os.path.join(OUT, filename), "w", encoding="utf-8") as handle:
            handle.write(content)
        print(f"{filename:22s} {len(content.splitlines()):6d} lines")

    dropped = sum(
        len(body)
        for name in DROP
        if name in by_name
        for _, body in by_name[name]
    )
    print(f"\ndropped {dropped} lines of manager-only code")


if __name__ == "__main__":
    main()
