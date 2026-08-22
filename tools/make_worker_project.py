#!/usr/bin/env python3
"""Generate worker/Worker.xcodeproj from the files in worker/Sources.

worker/project.yml is the source of truth and `xcodegen generate` regenerates
this properly. This script exists so the project builds on a Mac that does not
have XcodeGen installed, and produces the same structure XcodeGen does for the
warehouse app — the settings below are copied from
warehouse/Warehouse.xcodeproj so the two apps build identically.

Run from the repo root:  python3 tools/make_worker_project.py
"""

import hashlib
import os
import sys

APP = "Worker"
BUNDLE_ID = "com.panelvault.worker"
DISPLAY_NAME = "PanelVault Worker"
SOURCES = "worker/Sources"
PROJECT_DIR = f"worker/{APP}.xcodeproj"

# The shared component and manufacturer photos, bundled as a folder reference
# so the app ships the same files the website serves. Path is relative to
# worker/, matching the `sources:` entry in worker/project.yml — keep the two
# in step, since either tool may have written the project you are building.
RESOURCE_FOLDER = "../assets/catalog"
RESOURCE_NAME = "catalog"


def object_id(*parts):
    """Stable 24-hex-character object id, so regenerating gives no diff."""
    digest = hashlib.sha1("::".join(parts).encode()).hexdigest()
    return digest[:24].upper()


def swift_files():
    """(group_path, filename, path_relative_to_worker) for every source file."""
    found = []
    for root, _, names in os.walk(SOURCES):
        group = os.path.relpath(root, SOURCES)
        group = "" if group == "." else group
        for name in sorted(names):
            if name.endswith(".swift"):
                found.append((group, name, os.path.join(root, name)))
    return sorted(found, key=lambda item: (item[0], item[1]))


def main():
    if not os.path.isdir(SOURCES):
        sys.exit(f"run from the repo root: {SOURCES} not found")

    files = swift_files()
    if not files:
        sys.exit(f"no Swift files under {SOURCES}")

    groups = {}
    for group, name, _ in files:
        groups.setdefault(group, []).append(name)

    ids = {}
    for group, name, _ in files:
        key = f"{group}/{name}"
        ids[key] = {
            "file": object_id("fileref", key),
            "build": object_id("buildfile", key),
        }

    project_id = object_id("project", APP)
    main_group = object_id("maingroup", APP)
    products_group = object_id("products", APP)
    target_id = object_id("target", APP)
    product_ref = object_id("product", APP)
    sources_phase = object_id("sourcesphase", APP)
    resources_phase = object_id("resourcesphase", APP)
    resource_ref = object_id("fileref", RESOURCE_FOLDER)
    resource_build = object_id("buildfile", RESOURCE_FOLDER)
    project_config_list = object_id("configlist", "project", APP)
    target_config_list = object_id("configlist", "target", APP)
    configs = {
        ("project", "Debug"): object_id("config", "project", "Debug", APP),
        ("project", "Release"): object_id("config", "project", "Release", APP),
        ("target", "Debug"): object_id("config", "target", "Debug", APP),
        ("target", "Release"): object_id("config", "target", "Release", APP),
    }
    group_ids = {group: object_id("group", group or "Sources") for group in groups}

    out = []
    add = out.append

    add("// !$*UTF8*$!")
    add("{")
    add("\tarchiveVersion = 1;")
    add("\tclasses = {")
    add("\t};")
    add("\tobjectVersion = 77;")
    add("\tobjects = {")

    add("\n/* Begin PBXBuildFile section */")
    for group, name, _ in files:
        key = f"{group}/{name}"
        add(f"\t\t{ids[key]['build']} /* {name} in Sources */ = {{isa = PBXBuildFile; "
            f"fileRef = {ids[key]['file']} /* {name} */; }};")
    add(f"\t\t{resource_build} /* {RESOURCE_NAME} in Resources */ = {{isa = PBXBuildFile; "
        f"fileRef = {resource_ref} /* {RESOURCE_NAME} */; }};")
    add("/* End PBXBuildFile section */")

    add("\n/* Begin PBXFileReference section */")
    for group, name, _ in files:
        key = f"{group}/{name}"
        add(f"\t\t{ids[key]['file']} /* {name} */ = {{isa = PBXFileReference; "
            f"lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = \"<group>\"; }};")
    add(f"\t\t{product_ref} /* {APP}.app */ = {{isa = PBXFileReference; includeInIndex = 0; "
        f"lastKnownFileType = wrapper.application; path = {APP}.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
    # `lastKnownFileType = folder` is what makes this a folder reference: Xcode
    # copies the directory into the bundle whole, so photos added to it later
    # need no project change.
    add(f"\t\t{resource_ref} /* {RESOURCE_NAME} */ = {{isa = PBXFileReference; "
        f"lastKnownFileType = folder; name = {RESOURCE_NAME}; path = {RESOURCE_FOLDER}; "
        f"sourceTree = SOURCE_ROOT; }};")
    add("/* End PBXFileReference section */")

    add("\n/* Begin PBXGroup section */")
    add(f"\t\t{products_group} /* Products */ = {{")
    add("\t\t\tisa = PBXGroup;")
    add("\t\t\tchildren = (")
    add(f"\t\t\t\t{product_ref} /* {APP}.app */,")
    add("\t\t\t);")
    add("\t\t\tname = Products;")
    add("\t\t\tsourceTree = \"<group>\";")
    add("\t\t};")

    for group in sorted(groups):
        label = group or "Sources"
        add(f"\t\t{group_ids[group]} /* {label} */ = {{")
        add("\t\t\tisa = PBXGroup;")
        add("\t\t\tchildren = (")
        # Nested folders (Warehouse/) are listed inside the root Sources group.
        if group == "":
            for nested in sorted(g for g in groups if g):
                add(f"\t\t\t\t{group_ids[nested]} /* {nested} */,")
        for name in sorted(groups[group]):
            add(f"\t\t\t\t{ids[f'{group}/{name}']['file']} /* {name} */,")
        add("\t\t\t);")
        add(f"\t\t\tpath = {label if group else 'Sources'};")
        add("\t\t\tsourceTree = \"<group>\";")
        add("\t\t};")

    add(f"\t\t{main_group} = {{")
    add("\t\t\tisa = PBXGroup;")
    add("\t\t\tchildren = (")
    add(f"\t\t\t\t{group_ids['']} /* Sources */,")
    add(f"\t\t\t\t{resource_ref} /* {RESOURCE_NAME} */,")
    add(f"\t\t\t\t{products_group} /* Products */,")
    add("\t\t\t);")
    add("\t\t\tsourceTree = \"<group>\";")
    add("\t\t};")
    add("/* End PBXGroup section */")

    add("\n/* Begin PBXNativeTarget section */")
    add(f"\t\t{target_id} /* {APP} */ = {{")
    add("\t\t\tisa = PBXNativeTarget;")
    add(f"\t\t\tbuildConfigurationList = {target_config_list} /* Build configuration list for PBXNativeTarget \"{APP}\" */;")
    add("\t\t\tbuildPhases = (")
    add(f"\t\t\t\t{sources_phase} /* Sources */,")
    add(f"\t\t\t\t{resources_phase} /* Resources */,")
    add("\t\t\t);")
    add("\t\t\tbuildRules = (")
    add("\t\t\t);")
    add("\t\t\tdependencies = (")
    add("\t\t\t);")
    add(f"\t\t\tname = {APP};")
    add("\t\t\tpackageProductDependencies = (")
    add("\t\t\t);")
    add(f"\t\t\tproductName = {APP};")
    add(f"\t\t\tproductReference = {product_ref} /* {APP}.app */;")
    add("\t\t\tproductType = \"com.apple.product-type.application\";")
    add("\t\t};")
    add("/* End PBXNativeTarget section */")

    add("\n/* Begin PBXProject section */")
    add(f"\t\t{project_id} /* Project object */ = {{")
    add("\t\t\tisa = PBXProject;")
    add("\t\t\tattributes = {")
    add("\t\t\t\tBuildIndependentTargetsInParallel = YES;")
    add("\t\t\t\tLastUpgradeCheck = 1430;")
    add("\t\t\t\tTargetAttributes = {")
    add("\t\t\t\t};")
    add("\t\t\t};")
    add(f"\t\t\tbuildConfigurationList = {project_config_list} /* Build configuration list for PBXProject \"{APP}\" */;")
    add("\t\t\tdevelopmentRegion = en;")
    add("\t\t\thasScannedForEncodings = 0;")
    add("\t\t\tknownRegions = (")
    add("\t\t\t\tBase,")
    add("\t\t\t\ten,")
    add("\t\t\t);")
    add(f"\t\t\tmainGroup = {main_group};")
    add("\t\t\tminimizedProjectReferenceProxies = 1;")
    add("\t\t\tpreferredProjectObjectVersion = 77;")
    add(f"\t\t\tproductRefGroup = {products_group} /* Products */;")
    add("\t\t\tprojectDirPath = \"\";")
    add("\t\t\tprojectRoot = \"\";")
    add("\t\t\ttargets = (")
    add(f"\t\t\t\t{target_id} /* {APP} */,")
    add("\t\t\t);")
    add("\t\t};")
    add("/* End PBXProject section */")

    add("\n/* Begin PBXSourcesBuildPhase section */")
    add(f"\t\t{sources_phase} /* Sources */ = {{")
    add("\t\t\tisa = PBXSourcesBuildPhase;")
    add("\t\t\tbuildActionMask = 2147483647;")
    add("\t\t\tfiles = (")
    for group, name, _ in files:
        add(f"\t\t\t\t{ids[f'{group}/{name}']['build']} /* {name} in Sources */,")
    add("\t\t\t);")
    add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    add("\t\t};")
    add("/* End PBXSourcesBuildPhase section */")

    add("\n/* Begin PBXResourcesBuildPhase section */")
    add(f"\t\t{resources_phase} /* Resources */ = {{")
    add("\t\t\tisa = PBXResourcesBuildPhase;")
    add("\t\t\tbuildActionMask = 2147483647;")
    add("\t\t\tfiles = (")
    add(f"\t\t\t\t{resource_build} /* {RESOURCE_NAME} in Resources */,")
    add("\t\t\t);")
    add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    add("\t\t};")
    add("/* End PBXResourcesBuildPhase section */")

    shared = [
        "ALWAYS_SEARCH_USER_PATHS = NO",
        "CLANG_ANALYZER_NONNULL = YES",
        "CLANG_ENABLE_MODULES = YES",
        "CLANG_ENABLE_OBJC_ARC = YES",
        "CLANG_WARN_BOOL_CONVERSION = YES",
        "CLANG_WARN_CONSTANT_CONVERSION = YES",
        "CLANG_WARN_DOCUMENTATION_COMMENTS = YES",
        "CLANG_WARN_EMPTY_BODY = YES",
        "CLANG_WARN_ENUM_CONVERSION = YES",
        "CLANG_WARN_INFINITE_RECURSION = YES",
        "CLANG_WARN_INT_CONVERSION = YES",
        "CLANG_WARN_RANGE_LOOP_ANALYSIS = YES",
        "CLANG_WARN_UNREACHABLE_CODE = YES",
        "ENABLE_STRICT_OBJC_MSGSEND = YES",
        "GCC_NO_COMMON_BLOCKS = YES",
        "GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR",
        "GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE",
        "GCC_WARN_UNUSED_FUNCTION = YES",
        "GCC_WARN_UNUSED_VARIABLE = YES",
        "IPHONEOS_DEPLOYMENT_TARGET = 16.0",
        "PRODUCT_NAME = \"$(TARGET_NAME)\"",
        "SDKROOT = iphoneos",
        "SWIFT_VERSION = 5.0",
    ]
    project_debug = shared + [
        "DEBUG_INFORMATION_FORMAT = dwarf",
        "ENABLE_TESTABILITY = YES",
        "GCC_OPTIMIZATION_LEVEL = 0",
        "ONLY_ACTIVE_ARCH = YES",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG",
        "SWIFT_OPTIMIZATION_LEVEL = \"-Onone\"",
    ]
    project_release = shared + [
        "DEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\"",
        "ENABLE_NS_ASSERTIONS = NO",
        "SWIFT_COMPILATION_MODE = wholemodule",
        "SWIFT_OPTIMIZATION_LEVEL = \"-O\"",
    ]
    target_settings = [
        "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon",
        "CODE_SIGN_IDENTITY = \"iPhone Developer\"",
        "CURRENT_PROJECT_VERSION = 1",
        "INFOPLIST_FILE = Info.plist",
        "INFOPLIST_KEY_UILaunchScreen_Generation = YES",
        "MARKETING_VERSION = 1.0.0",
        f"PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID}",
        "SDKROOT = iphoneos",
        "SWIFT_VERSION = 5.0",
        "TARGETED_DEVICE_FAMILY = 1",
    ]

    add("\n/* Begin XCBuildConfiguration section */")
    for (scope, name), settings in (
        (("project", "Debug"), project_debug),
        (("project", "Release"), project_release),
        (("target", "Debug"), target_settings),
        (("target", "Release"), target_settings),
    ):
        add(f"\t\t{configs[(scope, name)]} /* {name} */ = {{")
        add("\t\t\tisa = XCBuildConfiguration;")
        add("\t\t\tbuildSettings = {")
        for setting in settings:
            add(f"\t\t\t\t{setting};")
        add("\t\t\t};")
        add(f"\t\t\tname = {name};")
        add("\t\t};")
    add("/* End XCBuildConfiguration section */")

    add("\n/* Begin XCConfigurationList section */")
    for list_id, scope, label in (
        (project_config_list, "project", f"PBXProject \"{APP}\""),
        (target_config_list, "target", f"PBXNativeTarget \"{APP}\""),
    ):
        add(f"\t\t{list_id} /* Build configuration list for {label} */ = {{")
        add("\t\t\tisa = XCConfigurationList;")
        add("\t\t\tbuildConfigurations = (")
        add(f"\t\t\t\t{configs[(scope, 'Debug')]} /* Debug */,")
        add(f"\t\t\t\t{configs[(scope, 'Release')]} /* Release */,")
        add("\t\t\t);")
        add("\t\t\tdefaultConfigurationIsVisible = 0;")
        add("\t\t\tdefaultConfigurationName = Debug;")
        add("\t\t};")
    add("/* End XCConfigurationList section */")

    add("\t};")
    add(f"\trootObject = {project_id} /* Project object */;")
    add("}")

    os.makedirs(PROJECT_DIR, exist_ok=True)
    with open(os.path.join(PROJECT_DIR, "project.pbxproj"), "w", encoding="utf-8") as handle:
        handle.write("\n".join(out) + "\n")

    workspace = os.path.join(PROJECT_DIR, "project.xcworkspace")
    os.makedirs(workspace, exist_ok=True)
    with open(os.path.join(workspace, "contents.xcworkspacedata"), "w", encoding="utf-8") as handle:
        handle.write(
            '<?xml version="1.0" encoding="UTF-8"?>\n'
            '<Workspace\n'
            '   version = "1.0">\n'
            '   <FileRef\n'
            '      location = "self:">\n'
            '   </FileRef>\n'
            '</Workspace>\n'
        )

    print(f"{PROJECT_DIR} — {len(files)} source files, target {APP} ({BUNDLE_ID})")
    print(f"{DISPLAY_NAME}: open worker/{APP}.xcodeproj in Xcode and run the {APP} scheme.")


if __name__ == "__main__":
    main()
