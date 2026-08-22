#!/usr/bin/env python3
"""Structural checks for worker/Sources, standing in for a compiler.

The worker app is assembled from two existing codebases by script, and the
machine that assembles it has no Swift toolchain. These are the failures that
assembly can actually cause, so they are the ones worth catching before the
first build on a Mac:

  1. Unbalanced braces, parens or brackets in a file (a bad slice boundary).
  2. Two files declaring the same type (a collision between the PanelVault copy
     and the ported warehouse).
  3. A capitalized name used but declared nowhere, and not a system type (a
     reference left dangling by a removed declaration).

This is not type checking. It will not catch a wrong argument label or a
mismatched closure signature. It catches the class of mistake this particular
build process makes.

Run from the repo root:  python3 tools/check_worker.py
"""

import os
import re
import sys

ROOT = "worker/Sources"

# Names that resolve outside the module: SwiftUI, UIKit, Foundation, Combine,
# PhotosUI, Vision, VisionKit, AVFoundation, Security, and the standard library.
SYSTEM = {
    # Standard library
    "Any", "AnyHashable", "Array", "Bool", "CGFloat", "CGPoint", "CGRect",
    "CGSize", "Character", "Codable", "CodingKey", "CodingKeys", "Comparable", "Data",
    "Date", "DateFormatter", "DateComponents", "Calendar", "Decodable",
    "Decoder", "Dictionary", "Double", "Encodable", "Encoder", "Equatable",
    "Error", "Float", "Hashable", "Identifiable", "Int", "Int32", "Int64",
    "JSONDecoder", "JSONEncoder", "LocalizedError", "Locale", "Never",
    "NSNumber", "NSString", "Numeric", "Optional", "RawRepresentable",
    "Result", "Self", "Sequence", "Set", "String", "StringProtocol",
    "Substring", "TimeInterval", "UInt", "UInt8", "UInt32", "UInt64", "URL",
    "URLRequest", "URLResponse", "URLSession", "UUID", "Void", "CaseIterable",
    "CharacterSet", "IndexSet", "Range", "ClosedRange", "Task", "Thread",
    "ISO8601DateFormatter", "RelativeDateTimeFormatter", "NumberFormatter",
    "Measurement", "OperationQueue", "Bundle", "FileManager", "UserDefaults",
    "NotificationCenter", "Notification", "DispatchQueue", "DispatchWorkItem",
    "DispatchTime", "MainActor", "Sendable", "AnyObject", "Collection",
    "ExpressibleByStringLiteral", "CustomStringConvertible", "Timer",
    "ProcessInfo", "HTTPURLResponse", "NSError", "NSLock", "OSStatus",
    "Regex", "Scanner", "Stride", "Strideable", "Duration",
    # Combine
    "ObservableObject", "Published", "AnyCancellable", "Cancellable",
    "PassthroughSubject", "CurrentValueSubject", "ObservableObjectPublisher",
    # SwiftUI
    "AccessibilityChildBehavior", "Alignment", "Angle", "AnyView", "App",
    "AppStorage", "Axis", "Binding", "Button", "ButtonRole", "ButtonStyle",
    "Capsule", "Circle", "Color", "ColorScheme", "Divider", "EdgeInsets",
    "Edge", "Environment", "EnvironmentObject", "EnvironmentValues",
    "FocusState", "Font", "ForEach", "Form", "GeometryReader", "GridItem",
    "Group", "HStack", "Image", "LazyHGrid", "LazyHStack", "LazyVGrid",
    "LazyVStack", "LinearGradient", "List", "Label", "Menu", "NavigationLink",
    "NavigationPath", "NavigationSplitView", "NavigationStack", "NavigationView",
    "ObservedObject", "Path", "Picker", "ProgressView", "RadialGradient",
    "Rectangle", "RoundedRectangle", "ScaledMetric", "Scene", "ScenePhase",
    "ScrollView", "ScrollViewReader", "SecureField", "Section", "ShapeStyle",
    "Slider", "Spacer", "State", "StateObject", "Stepper", "Text", "TextEditor",
    "TextField", "Toggle", "ToolbarItem", "ToolbarItemGroup", "UnitPoint",
    "VStack", "View", "ViewBuilder", "ViewModifier", "WindowGroup", "ZStack",
    "PreviewProvider", "Transaction", "Animation", "AnyTransition", "Namespace",
    "MatchedGeometryEffect", "Gesture", "DragGesture", "TapGesture", "Shape",
    "InsettableShape", "StrokeStyle", "Material", "AngularGradient", "Gradient",
    "SafeAreaRegions", "TextAlignment", "ContentMode", "Prominence",
    "PresentationDetent", "ToolbarPlacement", "KeyboardType", "SubmitLabel",
    "OpenURLAction", "DismissAction", "Preview", "EmptyView", "TupleView",
    "EquatableView", "GeometryProxy", "ContainerRelativeShape", "Ellipse",
    "UnevenRoundedRectangle", "RoundedCornerStyle", "SymbolRenderingMode",
    "ControlSize", "LabelStyle", "ProgressViewStyle", "ToggleStyle",
    "PrimitiveButtonStyle", "TextFieldStyle", "PickerStyle", "ListStyle",
    "DatePicker", "DatePickerComponents", "ColorPicker", "Link", "ShareLink",
    "PhotosPicker", "PhotosPickerItem", "PhotosPickerSelectionBehavior",
    "PHPickerFilter", "Table", "TabView", "TimelineView", "Canvas",
    "FocusedValue", "AccessibilityTraits", "LayoutDirection", "DynamicTypeSize",
    # UIKit
    "UIApplication", "UIColor", "UIDevice", "UIFont", "UIImage", "UIView",
    "UIViewController", "UIViewControllerRepresentable", "UIViewRepresentable",
    "UIWindow", "UIWindowScene", "UIScene", "UISceneSession", "UIResponder",
    "UIHostingController", "UIImagePickerController", "UINavigationController",
    "UIGraphicsImageRenderer", "UIScreen", "UIImpactFeedbackGenerator",
    "UINotificationFeedbackGenerator", "UISelectionFeedbackGenerator",
    "UIActivityViewController", "UIDocumentPickerViewController",
    "UIPasteboard", "UIInterfaceOrientationMask", "UIUserInterfaceStyle",
    "UITraitCollection", "UIBezierPath", "UIVisualEffectView", "UIBlurEffect",
    "UIViewControllerTransitioningDelegate", "UIContextMenuConfiguration",
    "CGAffineTransform", "CGContext", "CGImage", "CGColor",
    # UniformTypeIdentifiers
    "UTType",
    # Vision / VisionKit / AVFoundation — the delivery-note scanner
    "VNRecognizeTextRequest", "VNImageRequestHandler", "VNRequest",
    "VNRecognizedTextObservation", "VNBarcodeObservation",
    "VNDetectBarcodesRequest", "VNBarcodeSymbology", "VNTextObservation",
    "VNRecognizeTextRequestRevision", "VNObservation",
    "VNDocumentCameraViewController", "VNDocumentCameraScan",
    "VNDocumentCameraViewControllerDelegate",
    "AVCaptureSession", "AVCaptureDevice", "AVCaptureDeviceInput",
    "AVCaptureMetadataOutput", "AVCaptureVideoPreviewLayer",
    "AVMetadataObject", "AVMetadataMachineReadableCodeObject",
    "AVCaptureMetadataOutputObjectsDelegate", "AVCaptureVideoDataOutput",
    "AVLayerVideoGravity", "AVAuthorizationStatus", "AVMediaType",
    # Security (keychain)
    "SecItemAdd", "SecItemCopyMatching", "SecItemDelete", "CFDictionary",
    "CFTypeRef", "CFString",
    # Foundation reference types and regex
    "NSCache", "NSMapTable", "NSObject", "NSOrderedSet", "NSRange",
    "NSRegularExpression", "NSTextCheckingResult", "NSAttributedString",
    # More SwiftUI / UIKit spellings
    "LabeledContent", "TextInputAutocapitalization", "UIKeyboardType",
    "UIGraphicsImageRendererFormat", "UIReturnKeyType",
    # VisionKit's live scanner
    "DataScannerViewController", "DataScannerViewControllerDelegate",
    "RecognizedItem",
    # Protocol associated types used by name inside conformances
    "Configuration", "Context", "Coordinator", "Body",
}

DECL = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*"
    r"(?:public\s+|private\s+|fileprivate\s+|internal\s+|open\s+)?"
    r"(?:final\s+|indirect\s+)?"
    r"(struct|class|enum|protocol|actor|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)"
)
USE = re.compile(r"\b([A-Z][A-Za-z0-9_]*)\b")
# `import SwiftUI` is a module, not a type.
IMPORT = re.compile(r"^\s*(?:@\w+\s+)?import\s+")
# Generic parameters (`<Content: View>`) and `where` clauses introduce names
# that are declared nowhere else.
GENERIC = re.compile(r"<([^<>]*)>")

# Comments and string literals are not code.
LINE_COMMENT = re.compile(r"//.*$")
STRING = re.compile(r'"(?:\\.|[^"\\])*"')


def swift_files():
    for root, _, names in os.walk(ROOT):
        for name in sorted(names):
            if name.endswith(".swift"):
                yield os.path.join(root, name)


def strip_noise(text):
    """Remove block comments, line comments and string literals."""
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    lines = []
    for line in text.split("\n"):
        line = STRING.sub('""', line)
        line = LINE_COMMENT.sub("", line)
        lines.append(line)
    return "\n".join(lines)


def check_balance(problems):
    for path in swift_files():
        code = strip_noise(open(path, encoding="utf-8").read())
        for open_ch, close_ch, label in (("{", "}", "braces"), ("(", ")", "parens"), ("[", "]", "brackets")):
            depth = 0
            for ch in code:
                if ch == open_ch:
                    depth += 1
                elif ch == close_ch:
                    depth -= 1
                    if depth < 0:
                        break
            if depth != 0:
                problems.append(f"{path}: unbalanced {label} (net {depth:+d})")


def collect_declarations(problems):
    """Returns every declared name, and reports top-level collisions.

    Only top-level declarations can collide in one module. A `Coordinator`
    nested in two different UIViewControllerRepresentables, or the `Company`
    inside each of the two login responses, is not a clash — but both still
    count as declared for the undefined-name check.
    """
    top_level = {}
    every = set()
    for path in swift_files():
        code = strip_noise(open(path, encoding="utf-8").read())
        for line in code.split("\n"):
            match = DECL.match(line)
            if not match:
                continue
            name = match.group(2)
            every.add(name)
            if line[:1].isspace():
                continue
            if name in top_level and top_level[name] != path:
                problems.append(
                    f"{name} declared at top level in both {top_level[name]} and {path}"
                )
            top_level.setdefault(name, path)
    return top_level, every


def generic_parameters(code):
    """Names introduced by generic parameter lists, e.g. <Content: View>."""
    found = set()
    for group in GENERIC.findall(code):
        for part in group.split(","):
            name = part.split(":")[0].strip()
            if re.fullmatch(r"[A-Z][A-Za-z0-9_]*", name):
                found.add(name)
    return found


def check_uses(declared, problems):
    known = declared | SYSTEM
    unknown = {}
    for path in swift_files():
        code = strip_noise(open(path, encoding="utf-8").read())
        known_here = known | generic_parameters(code)
        for number, line in enumerate(code.split("\n"), 1):
            if IMPORT.match(line):
                continue
            # A capitalized word right after a dot is a member (.Kind, .shared),
            # resolved against a type this checker cannot infer.
            cleaned = re.sub(r"\.\s*[A-Za-z_][A-Za-z0-9_]*", "", line)
            for name in USE.findall(cleaned):
                if name in known_here:
                    continue
                unknown.setdefault(name, []).append(f"{path}:{number}")
    for name in sorted(unknown):
        where = ", ".join(unknown[name][:3])
        problems.append(f"undefined name {name!r} used at {where}")


def main():
    if not os.path.isdir(ROOT):
        sys.exit(f"run from the repo root: {ROOT} not found")

    problems = []
    check_balance(problems)
    top_level, every = collect_declarations(problems)
    check_uses(every, problems)

    files = list(swift_files())
    lines = sum(len(open(f, encoding="utf-8").read().split("\n")) for f in files)
    print(f"{len(files)} files, {lines} lines, {len(top_level)} top-level types\n")

    if problems:
        for problem in problems:
            print("  " + problem)
        print(f"\n{len(problems)} problem(s)")
        return 1
    print("No structural problems found.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
