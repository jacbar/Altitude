#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
sources = [
    "Altitude/main.swift",
    "Altitude/AppDelegate.swift",
    "Altitude/Backend/CGSPrivate.swift",
    "Altitude/Backend/DockSwipeSwitcher.swift",
    "Altitude/Backend/SkyLightBackend.swift",
    "Altitude/Backend/SkyLightBridgedSPI.swift",
    "Altitude/Domain/ConfigStore.swift",
    "Altitude/Domain/FocusedWindowResolver.swift",
    "Altitude/Domain/SpaceModels.swift",
    "Altitude/Hotkeys/HotkeyRegistrar.swift",
    "Altitude/UI/MenuBarController.swift",
    "Altitude/UI/SpaceIndicatorRenderer.swift",
    # Append new sources at the end so existing file IDs stay stable.
    "Altitude/Backend/SystemMotionSuppressor.swift",
    "Altitude/Domain/LaunchAtLogin.swift",
    "Altitude/Domain/HotkeyBounds.swift",
]

test_sources = [
    "AltitudeTests/ConfigStoreTests.swift",
    "AltitudeTests/HotkeyBoundsTests.swift",
]

ids = {
    "project": "A10000000000000000000001",
    "target": "A10000000000000000000002",
    "sources_phase": "A10000000000000000000003",
    "resources_phase": "A10000000000000000000004",
    "frameworks_phase": "A10000000000000000000005",
    "altitude_group": "A10000000000000000000006",
    "products_group": "A10000000000000000000007",
    "main_group": "A10000000000000000000008",
    "product_ref": "A10000000000000000000009",
    "debug_proj": "A1000000000000000000000A",
    "release_proj": "A1000000000000000000000B",
    "debug_tgt": "A1000000000000000000000C",
    "release_tgt": "A1000000000000000000000D",
    "config_list_proj": "A1000000000000000000000E",
    "config_list_tgt": "A1000000000000000000000F",
    "assets": "A10000000000000000000010",
    "assets_build": "A10000000000000000000011",
    "info": "A10000000000000000000012",
    "entitlements": "A10000000000000000000013",
    "backend_group": "A10000000000000000000014",
    "domain_group": "A10000000000000000000015",
    "hotkeys_group": "A10000000000000000000016",
    "ui_group": "A10000000000000000000017",
    "resources_group": "A10000000000000000000018",
    "config_example": "A10000000000000000000019",
    "config_example_build": "A1000000000000000000001A",
    # AltitudeTests unit-test target
    "test_target": "C10000000000000000000001",
    "test_sources_phase": "C10000000000000000000002",
    "test_frameworks_phase": "C10000000000000000000003",
    "test_product_ref": "C10000000000000000000004",
    "test_group": "C10000000000000000000005",
    "test_debug_tgt": "C10000000000000000000006",
    "test_release_tgt": "C10000000000000000000007",
    "config_list_test": "C10000000000000000000008",
    "test_dep": "C10000000000000000000009",
    "test_proxy": "C1000000000000000000000A",
}

file_ids = {}
build_ids = {}
for i, src in enumerate(sources):
    file_ids[src] = f"B1{i:022d}"
    build_ids[src] = f"B2{i:022d}"

test_file_ids = {}
test_build_ids = {}
for i, src in enumerate(test_sources):
    test_file_ids[src] = f"D1{i:022d}"
    test_build_ids[src] = f"D2{i:022d}"

carbon_ref = "A10000000000000000000020"
carbon_build = "A10000000000000000000021"
appkit_ref = "A10000000000000000000022"
appkit_build = "A10000000000000000000023"
xctest_ref = "C1000000000000000000000B"
xctest_build = "C1000000000000000000000C"

lines = []
lines.append("// !$*UTF8*$!")
lines.append("{")
lines.append("\tarchiveVersion = 1;")
lines.append("\tclasses = {")
lines.append("\t};")
lines.append("\tobjectVersion = 56;")
lines.append("\tobjects = {")
lines.append("")
lines.append("/* Begin PBXBuildFile section */")
for src in sources:
    name = Path(src).name
    lines.append(
        f"\t\t{build_ids[src]} /* {name} in Sources */ = "
        f"{{isa = PBXBuildFile; fileRef = {file_ids[src]} /* {name} */; }};"
    )
for src in test_sources:
    name = Path(src).name
    lines.append(
        f"\t\t{test_build_ids[src]} /* {name} in Sources */ = "
        f"{{isa = PBXBuildFile; fileRef = {test_file_ids[src]} /* {name} */; }};"
    )
lines.append(
    f"\t\t{ids['assets_build']} /* Assets.xcassets in Resources */ = "
    f"{{isa = PBXBuildFile; fileRef = {ids['assets']} /* Assets.xcassets */; }};"
)
lines.append(
    f"\t\t{ids['config_example_build']} /* config.example.toml in Resources */ = "
    f"{{isa = PBXBuildFile; fileRef = {ids['config_example']} /* config.example.toml */; }};"
)
lines.append(
    f"\t\t{carbon_build} /* Carbon.framework in Frameworks */ = "
    f"{{isa = PBXBuildFile; fileRef = {carbon_ref} /* Carbon.framework */; }};"
)
lines.append(
    f"\t\t{appkit_build} /* AppKit.framework in Frameworks */ = "
    f"{{isa = PBXBuildFile; fileRef = {appkit_ref} /* AppKit.framework */; }};"
)
lines.append(
    f"\t\t{xctest_build} /* XCTest.framework in Frameworks */ = "
    f"{{isa = PBXBuildFile; fileRef = {xctest_ref} /* XCTest.framework */; }};"
)
lines.append("/* End PBXBuildFile section */")
lines.append("")
lines.append("/* Begin PBXContainerItemProxy section */")
lines.append(f"\t\t{ids['test_proxy']} /* PBXContainerItemProxy */ = {{")
lines.append("\t\t\tisa = PBXContainerItemProxy;")
lines.append(f"\t\t\tcontainerPortal = {ids['project']} /* Project object */;")
lines.append("\t\t\tproxyType = 1;")
lines.append(f"\t\t\tremoteGlobalIDString = {ids['target']};")
lines.append('\t\t\tremoteInfo = Altitude;')
lines.append("\t\t};")
lines.append("/* End PBXContainerItemProxy section */")
lines.append("")
lines.append("/* Begin PBXFileReference section */")
for src in sources:
    name = Path(src).name
    lines.append(
        f"\t\t{file_ids[src]} /* {name} */ = "
        f"{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
        f'path = {name}; sourceTree = "<group>"; }};'
    )
for src in test_sources:
    name = Path(src).name
    lines.append(
        f"\t\t{test_file_ids[src]} /* {name} */ = "
        f"{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
        f'path = {name}; sourceTree = "<group>"; }};'
    )
lines.append(
    f"\t\t{ids['product_ref']} /* Altitude.app */ = {{isa = PBXFileReference; "
    f"explicitFileType = wrapper.application; includeInIndex = 0; "
    f"path = Altitude.app; sourceTree = BUILT_PRODUCTS_DIR; }};"
)
lines.append(
    f"\t\t{ids['test_product_ref']} /* AltitudeTests.xctest */ = {{isa = PBXFileReference; "
    f"explicitFileType = wrapper.cfbundle; includeInIndex = 0; "
    f"path = AltitudeTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};"
)
lines.append(
    f"\t\t{ids['assets']} /* Assets.xcassets */ = {{isa = PBXFileReference; "
    f'lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; }};'
)
lines.append(
    f"\t\t{ids['info']} /* Info.plist */ = {{isa = PBXFileReference; "
    f'lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};'
)
lines.append(
    f"\t\t{ids['entitlements']} /* Altitude.entitlements */ = {{isa = PBXFileReference; "
    f'lastKnownFileType = text.plist.entitlements; path = Altitude.entitlements; '
    f'sourceTree = "<group>"; }};'
)
lines.append(
    f"\t\t{ids['config_example']} /* config.example.toml */ = {{isa = PBXFileReference; "
    f"lastKnownFileType = text; name = config.example.toml; "
    f"path = config/config.example.toml; sourceTree = SOURCE_ROOT; }};"
)
lines.append(
    f"\t\t{carbon_ref} /* Carbon.framework */ = {{isa = PBXFileReference; "
    f"lastKnownFileType = wrapper.framework; name = Carbon.framework; "
    f"path = System/Library/Frameworks/Carbon.framework; sourceTree = SDKROOT; }};"
)
lines.append(
    f"\t\t{appkit_ref} /* AppKit.framework */ = {{isa = PBXFileReference; "
    f"lastKnownFileType = wrapper.framework; name = AppKit.framework; "
    f"path = System/Library/Frameworks/AppKit.framework; sourceTree = SDKROOT; }};"
)
lines.append(
    f"\t\t{xctest_ref} /* XCTest.framework */ = {{isa = PBXFileReference; "
    f"lastKnownFileType = wrapper.framework; name = XCTest.framework; "
    f"path = Library/Frameworks/XCTest.framework; sourceTree = DEVELOPER_DIR; }};"
)
lines.append("/* End PBXFileReference section */")
lines.append("")


def emit_group(oid, name, path, child_lines):
    lines.append(f"\t\t{oid} /* {name} */ = {{")
    lines.append("\t\t\tisa = PBXGroup;")
    lines.append("\t\t\tchildren = (")
    for child in child_lines:
        lines.append(f"\t\t\t\t{child},")
    lines.append("\t\t\t);")
    if path is not None:
        lines.append(f"\t\t\tpath = {path};")
    else:
        lines.append(f"\t\t\tname = {name};")
    lines.append('\t\t\tsourceTree = "<group>";')
    lines.append("\t\t};")


backend_srcs = [s for s in sources if "/Backend/" in s]
domain_srcs = [s for s in sources if "/Domain/" in s]
hotkeys_srcs = [s for s in sources if "/Hotkeys/" in s]
ui_srcs = [s for s in sources if "/UI/" in s]
root_srcs = [s for s in sources if s.count("/") == 1]

lines.append("/* Begin PBXFrameworksBuildPhase section */")
lines.append(f"\t\t{ids['frameworks_phase']} /* Frameworks */ = {{")
lines.append("\t\t\tisa = PBXFrameworksBuildPhase;")
lines.append("\t\t\tbuildActionMask = 2147483647;")
lines.append("\t\t\tfiles = (")
lines.append(f"\t\t\t\t{appkit_build} /* AppKit.framework in Frameworks */,")
lines.append(f"\t\t\t\t{carbon_build} /* Carbon.framework in Frameworks */,")
lines.append("\t\t\t);")
lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
lines.append("\t\t};")
lines.append(f"\t\t{ids['test_frameworks_phase']} /* Frameworks */ = {{")
lines.append("\t\t\tisa = PBXFrameworksBuildPhase;")
lines.append("\t\t\tbuildActionMask = 2147483647;")
lines.append("\t\t\tfiles = (")
lines.append(f"\t\t\t\t{xctest_build} /* XCTest.framework in Frameworks */,")
lines.append("\t\t\t);")
lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
lines.append("\t\t};")
lines.append("/* End PBXFrameworksBuildPhase section */")
lines.append("")
lines.append("/* Begin PBXGroup section */")

lines.append(f"\t\t{ids['main_group']} = {{")
lines.append("\t\t\tisa = PBXGroup;")
lines.append("\t\t\tchildren = (")
lines.append(f"\t\t\t\t{ids['altitude_group']} /* Altitude */,")
lines.append(f"\t\t\t\t{ids['test_group']} /* AltitudeTests */,")
lines.append(f"\t\t\t\t{ids['products_group']} /* Products */,")
lines.append(f"\t\t\t\t{carbon_ref} /* Carbon.framework */,")
lines.append(f"\t\t\t\t{appkit_ref} /* AppKit.framework */,")
lines.append(f"\t\t\t\t{xctest_ref} /* XCTest.framework */,")
lines.append("\t\t\t);")
lines.append('\t\t\tsourceTree = "<group>";')
lines.append("\t\t};")

emit_group(
    ids["products_group"],
    "Products",
    None,
    [
        f"{ids['product_ref']} /* Altitude.app */",
        f"{ids['test_product_ref']} /* AltitudeTests.xctest */",
    ],
)

altitude_children = (
    [f"{file_ids[s]} /* {Path(s).name} */" for s in root_srcs]
    + [
        f"{ids['backend_group']} /* Backend */",
        f"{ids['domain_group']} /* Domain */",
        f"{ids['hotkeys_group']} /* Hotkeys */",
        f"{ids['ui_group']} /* UI */",
        f"{ids['resources_group']} /* Resources */",
        f"{ids['info']} /* Info.plist */",
        f"{ids['entitlements']} /* Altitude.entitlements */",
    ]
)
emit_group(ids["altitude_group"], "Altitude", "Altitude", altitude_children)
emit_group(
    ids["backend_group"],
    "Backend",
    "Backend",
    [f"{file_ids[s]} /* {Path(s).name} */" for s in backend_srcs],
)
emit_group(
    ids["domain_group"],
    "Domain",
    "Domain",
    [f"{file_ids[s]} /* {Path(s).name} */" for s in domain_srcs],
)
emit_group(
    ids["hotkeys_group"],
    "Hotkeys",
    "Hotkeys",
    [f"{file_ids[s]} /* {Path(s).name} */" for s in hotkeys_srcs],
)
emit_group(
    ids["ui_group"],
    "UI",
    "UI",
    [f"{file_ids[s]} /* {Path(s).name} */" for s in ui_srcs],
)
emit_group(
    ids["resources_group"],
    "Resources",
    "Resources",
    [
        f"{ids['assets']} /* Assets.xcassets */",
        f"{ids['config_example']} /* config.example.toml */",
    ],
)
emit_group(
    ids["test_group"],
    "AltitudeTests",
    "AltitudeTests",
    [f"{test_file_ids[s]} /* {Path(s).name} */" for s in test_sources],
)

lines.append("/* End PBXGroup section */")
lines.append("")
lines.append("/* Begin PBXNativeTarget section */")
lines.append(f"\t\t{ids['target']} /* Altitude */ = {{")
lines.append("\t\t\tisa = PBXNativeTarget;")
lines.append(
    f"\t\t\tbuildConfigurationList = {ids['config_list_tgt']} "
    f'/* Build configuration list for PBXNativeTarget "Altitude" */;'
)
lines.append("\t\t\tbuildPhases = (")
lines.append(f"\t\t\t\t{ids['sources_phase']} /* Sources */,")
lines.append(f"\t\t\t\t{ids['frameworks_phase']} /* Frameworks */,")
lines.append(f"\t\t\t\t{ids['resources_phase']} /* Resources */,")
lines.append("\t\t\t);")
lines.append("\t\t\tbuildRules = (")
lines.append("\t\t\t);")
lines.append("\t\t\tdependencies = (")
lines.append("\t\t\t);")
lines.append("\t\t\tname = Altitude;")
lines.append("\t\t\tproductName = Altitude;")
lines.append(f"\t\t\tproductReference = {ids['product_ref']} /* Altitude.app */;")
lines.append('\t\t\tproductType = "com.apple.product-type.application";')
lines.append("\t\t};")
lines.append(f"\t\t{ids['test_target']} /* AltitudeTests */ = {{")
lines.append("\t\t\tisa = PBXNativeTarget;")
lines.append(
    f"\t\t\tbuildConfigurationList = {ids['config_list_test']} "
    f'/* Build configuration list for PBXNativeTarget "AltitudeTests" */;'
)
lines.append("\t\t\tbuildPhases = (")
lines.append(f"\t\t\t\t{ids['test_sources_phase']} /* Sources */,")
lines.append(f"\t\t\t\t{ids['test_frameworks_phase']} /* Frameworks */,")
lines.append("\t\t\t);")
lines.append("\t\t\tbuildRules = (")
lines.append("\t\t\t);")
lines.append("\t\t\tdependencies = (")
lines.append(f"\t\t\t\t{ids['test_dep']} /* PBXTargetDependency */,")
lines.append("\t\t\t);")
lines.append("\t\t\tname = AltitudeTests;")
lines.append("\t\t\tproductName = AltitudeTests;")
lines.append(f"\t\t\tproductReference = {ids['test_product_ref']} /* AltitudeTests.xctest */;")
lines.append('\t\t\tproductType = "com.apple.product-type.bundle.unit-test";')
lines.append("\t\t};")
lines.append("/* End PBXNativeTarget section */")
lines.append("")
lines.append("/* Begin PBXProject section */")
lines.append(f"\t\t{ids['project']} /* Project object */ = {{")
lines.append("\t\t\tisa = PBXProject;")
lines.append("\t\t\tattributes = {")
lines.append("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
lines.append("\t\t\t\tLastSwiftUpdateCheck = 1600;")
lines.append("\t\t\t\tLastUpgradeCheck = 1600;")
lines.append("\t\t\t\tTargetAttributes = {")
lines.append(f"\t\t\t\t\t{ids['test_target']} = {{")
lines.append("\t\t\t\t\t\tTestTargetID = A10000000000000000000002;")
lines.append("\t\t\t\t\t};")
lines.append("\t\t\t\t};")
lines.append("\t\t\t};")
lines.append(
    f"\t\t\tbuildConfigurationList = {ids['config_list_proj']} "
    f'/* Build configuration list for PBXProject "Altitude" */;'
)
lines.append('\t\t\tcompatibilityVersion = "Xcode 14.0";')
lines.append("\t\t\tdevelopmentRegion = en;")
lines.append("\t\t\thasScannedForEncodings = 0;")
lines.append("\t\t\tknownRegions = (")
lines.append("\t\t\t\ten,")
lines.append("\t\t\t\tBase,")
lines.append("\t\t\t);")
lines.append(f"\t\t\tmainGroup = {ids['main_group']};")
lines.append(f"\t\t\tproductRefGroup = {ids['products_group']} /* Products */;")
lines.append('\t\t\tprojectDirPath = "";')
lines.append('\t\t\tprojectRoot = "";')
lines.append("\t\t\ttargets = (")
lines.append(f"\t\t\t\t{ids['target']} /* Altitude */,")
lines.append(f"\t\t\t\t{ids['test_target']} /* AltitudeTests */,")
lines.append("\t\t\t);")
lines.append("\t\t};")
lines.append("/* End PBXProject section */")
lines.append("")
lines.append("/* Begin PBXResourcesBuildPhase section */")
lines.append(f"\t\t{ids['resources_phase']} /* Resources */ = {{")
lines.append("\t\t\tisa = PBXResourcesBuildPhase;")
lines.append("\t\t\tbuildActionMask = 2147483647;")
lines.append("\t\t\tfiles = (")
lines.append(f"\t\t\t\t{ids['assets_build']} /* Assets.xcassets in Resources */,")
lines.append(f"\t\t\t\t{ids['config_example_build']} /* config.example.toml in Resources */,")
lines.append("\t\t\t);")
lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
lines.append("\t\t};")
lines.append("/* End PBXResourcesBuildPhase section */")
lines.append("")
lines.append("/* Begin PBXSourcesBuildPhase section */")
lines.append(f"\t\t{ids['sources_phase']} /* Sources */ = {{")
lines.append("\t\t\tisa = PBXSourcesBuildPhase;")
lines.append("\t\t\tbuildActionMask = 2147483647;")
lines.append("\t\t\tfiles = (")
for src in sources:
    lines.append(f"\t\t\t\t{build_ids[src]} /* {Path(src).name} in Sources */,")
lines.append("\t\t\t);")
lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
lines.append("\t\t};")
lines.append(f"\t\t{ids['test_sources_phase']} /* Sources */ = {{")
lines.append("\t\t\tisa = PBXSourcesBuildPhase;")
lines.append("\t\t\tbuildActionMask = 2147483647;")
lines.append("\t\t\tfiles = (")
for src in test_sources:
    lines.append(f"\t\t\t\t{test_build_ids[src]} /* {Path(src).name} in Sources */,")
lines.append("\t\t\t);")
lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
lines.append("\t\t};")
lines.append("/* End PBXSourcesBuildPhase section */")
lines.append("")
lines.append("/* Begin PBXTargetDependency section */")
lines.append(f"\t\t{ids['test_dep']} /* PBXTargetDependency */ = {{")
lines.append("\t\t\tisa = PBXTargetDependency;")
lines.append(f"\t\t\ttarget = {ids['target']} /* Altitude */;")
lines.append(f"\t\t\ttargetProxy = {ids['test_proxy']} /* PBXContainerItemProxy */;")
lines.append("\t\t};")
lines.append("/* End PBXTargetDependency section */")
lines.append("")
lines.append("/* Begin XCBuildConfiguration section */")

for oid, name, extra in [
    (
        ids["debug_proj"],
        "Debug",
        [
            "ALWAYS_SEARCH_USER_PATHS = NO;",
            "CLANG_ENABLE_MODULES = YES;",
            "CLANG_ENABLE_OBJC_ARC = YES;",
            "COPY_PHASE_STRIP = NO;",
            "DEBUG_INFORMATION_FORMAT = dwarf;",
            "ENABLE_TESTABILITY = YES;",
            "GCC_DYNAMIC_NO_PIC = NO;",
            "MACOSX_DEPLOYMENT_TARGET = 14.0;",
            "ONLY_ACTIVE_ARCH = YES;",
            "SDKROOT = macosx;",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;",
            'SWIFT_OPTIMIZATION_LEVEL = "-Onone";',
        ],
    ),
    (
        ids["release_proj"],
        "Release",
        [
            "ALWAYS_SEARCH_USER_PATHS = NO;",
            "CLANG_ENABLE_MODULES = YES;",
            "CLANG_ENABLE_OBJC_ARC = YES;",
            "COPY_PHASE_STRIP = NO;",
            'DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";',
            "MACOSX_DEPLOYMENT_TARGET = 14.0;",
            "SDKROOT = macosx;",
            "SWIFT_COMPILATION_MODE = wholemodule;",
        ],
    ),
]:
    lines.append(f"\t\t{oid} /* {name} */ = {{")
    lines.append("\t\t\tisa = XCBuildConfiguration;")
    lines.append("\t\t\tbuildSettings = {")
    for setting in extra:
        lines.append(f"\t\t\t\t{setting}")
    lines.append("\t\t\t};")
    lines.append(f"\t\t\tname = {name};")
    lines.append("\t\t};")

for oid, name in [(ids["debug_tgt"], "Debug"), (ids["release_tgt"], "Release")]:
    lines.append(f"\t\t{oid} /* {name} */ = {{")
    lines.append("\t\t\tisa = XCBuildConfiguration;")
    lines.append("\t\t\tbuildSettings = {")
    lines.append("\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;")
    lines.append("\t\t\t\tCODE_SIGN_ENTITLEMENTS = Altitude/Altitude.entitlements;")
    lines.append('\t\t\t\tCODE_SIGN_IDENTITY = "Apple Development";')
    lines.append("\t\t\t\tCODE_SIGN_STYLE = Automatic;")
    lines.append("\t\t\t\tDEVELOPMENT_TEAM = F4DP6FX254;")
    lines.append("\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;")
    lines.append("\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
    lines.append("\t\t\t\tENABLE_DEBUG_DYLIB = NO;")
    lines.append("\t\t\t\tENABLE_HARDENED_RUNTIME = YES;")
    lines.append("\t\t\t\tGENERATE_INFOPLIST_FILE = NO;")
    lines.append("\t\t\t\tINFOPLIST_FILE = Altitude/Info.plist;")
    lines.append("\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (")
    lines.append('\t\t\t\t\t"$(inherited)",')
    lines.append('\t\t\t\t\t"@executable_path/../Frameworks",')
    lines.append("\t\t\t\t);")
    lines.append("\t\t\t\tMARKETING_VERSION = 0.1.0;")
    lines.append("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.altitude.app;")
    lines.append('\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";')
    lines.append("\t\t\t\tSWIFT_VERSION = 5.0;")
    lines.append("\t\t\t};")
    lines.append(f"\t\t\tname = {name};")
    lines.append("\t\t};")

for oid, name in [(ids["test_debug_tgt"], "Debug"), (ids["test_release_tgt"], "Release")]:
    lines.append(f"\t\t{oid} /* {name} */ = {{")
    lines.append("\t\t\tisa = XCBuildConfiguration;")
    lines.append("\t\t\tbuildSettings = {")
    lines.append("\t\t\t\tBUNDLE_LOADER = \"$(TEST_HOST)\";")
    lines.append('\t\t\t\tCODE_SIGN_IDENTITY = "-";')
    lines.append("\t\t\t\tCODE_SIGN_STYLE = Manual;")
    lines.append("\t\t\t\tCODE_SIGNING_ALLOWED = NO;")
    lines.append("\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;")
    lines.append("\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
    lines.append("\t\t\t\tGENERATE_INFOPLIST_FILE = YES;")
    lines.append("\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (")
    lines.append('\t\t\t\t\t"$(inherited)",')
    lines.append('\t\t\t\t\t"@executable_path/../Frameworks",')
    lines.append('\t\t\t\t\t"@loader_path/../Frameworks",')
    lines.append("\t\t\t\t);")
    lines.append("\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;")
    lines.append("\t\t\t\tMARKETING_VERSION = 0.1.0;")
    lines.append("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.altitude.app.tests;")
    lines.append('\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";')
    lines.append("\t\t\t\tSWIFT_VERSION = 5.0;")
    lines.append(
        '\t\t\t\tTEST_HOST = "$(BUILT_PRODUCTS_DIR)/Altitude.app/Contents/MacOS/Altitude";'
    )
    lines.append("\t\t\t};")
    lines.append(f"\t\t\tname = {name};")
    lines.append("\t\t};")

lines.append("/* End XCBuildConfiguration section */")
lines.append("")
lines.append("/* Begin XCConfigurationList section */")
lines.append(
    f"\t\t{ids['config_list_proj']} /* Build configuration list for PBXProject \"Altitude\" */ = {{"
)
lines.append("\t\t\tisa = XCConfigurationList;")
lines.append("\t\t\tbuildConfigurations = (")
lines.append(f"\t\t\t\t{ids['debug_proj']} /* Debug */,")
lines.append(f"\t\t\t\t{ids['release_proj']} /* Release */,")
lines.append("\t\t\t);")
lines.append("\t\t\tdefaultConfigurationIsVisible = 0;")
lines.append("\t\t\tdefaultConfigurationName = Release;")
lines.append("\t\t};")
lines.append(
    f"\t\t{ids['config_list_tgt']} /* Build configuration list for PBXNativeTarget \"Altitude\" */ = {{"
)
lines.append("\t\t\tisa = XCConfigurationList;")
lines.append("\t\t\tbuildConfigurations = (")
lines.append(f"\t\t\t\t{ids['debug_tgt']} /* Debug */,")
lines.append(f"\t\t\t\t{ids['release_tgt']} /* Release */,")
lines.append("\t\t\t);")
lines.append("\t\t\tdefaultConfigurationIsVisible = 0;")
lines.append("\t\t\tdefaultConfigurationName = Release;")
lines.append("\t\t};")
lines.append(
    f"\t\t{ids['config_list_test']} /* Build configuration list for PBXNativeTarget \"AltitudeTests\" */ = {{"
)
lines.append("\t\t\tisa = XCConfigurationList;")
lines.append("\t\t\tbuildConfigurations = (")
lines.append(f"\t\t\t\t{ids['test_debug_tgt']} /* Debug */,")
lines.append(f"\t\t\t\t{ids['test_release_tgt']} /* Release */,")
lines.append("\t\t\t);")
lines.append("\t\t\tdefaultConfigurationIsVisible = 0;")
lines.append("\t\t\tdefaultConfigurationName = Release;")
lines.append("\t\t};")
lines.append("/* End XCConfigurationList section */")
lines.append("\t};")
lines.append(f"\trootObject = {ids['project']} /* Project object */;")
lines.append("}")

out = root / "Altitude.xcodeproj" / "project.pbxproj"
out.write_text("\n".join(lines) + "\n")
print(f"Wrote {out}")
