import SwiftUI
import UIKit

// iOS 15 compatibility layer.
//
// The app was written against iOS 16 SwiftUI. Everything here uses the real iOS 16+ API when it exists and falls
// back to an iOS 15 equivalent when it does not, so call sites stay the same on every version. Anything with no
// iOS 15 equivalent (sheet detents, hiding scroll indicators) quietly does nothing there.

// MARK: - Navigation

/// The pages a legacy (iOS 15) stack can open, keyed by the type of value that opens them.
final class HNavRegistry {
    private var builders: [ObjectIdentifier: (Any) -> AnyView] = [:]

    func register<D: Hashable>(_ type: D.Type, _ build: @escaping (D) -> AnyView) {
        builders[ObjectIdentifier(type)] = { value in
            guard let typed = value as? D else { return AnyView(EmptyView()) }
            return build(typed)
        }
    }

    func view(for value: AnyHashable) -> AnyView {
        guard let build = builders[ObjectIdentifier(type(of: value.base))] else { return AnyView(EmptyView()) }
        return build(value.base)
    }
}

private struct HNavRegistryKey: EnvironmentKey { static let defaultValue: HNavRegistry? = nil }
private struct HNavPushKey: EnvironmentKey { static let defaultValue: ((AnyHashable) -> Void)? = nil }

extension EnvironmentValues {
    fileprivate var hNavRegistry: HNavRegistry? {
        get { self[HNavRegistryKey.self] }
        set { self[HNavRegistryKey.self] = newValue }
    }
    fileprivate var hNavPush: ((AnyHashable) -> Void)? {
        get { self[HNavPushKey.self] }
        set { self[HNavPushKey.self] = newValue }
    }
}

/// NavigationStack on iOS 16 and later; a NavigationView driven by the same path on iOS 15.
struct HNavStack<Content: View>: View {
    private let content: Content
    private let path: Binding<[AnyHashable]>?
    private let modern: (Content) -> AnyView
    @State private var localPath: [AnyHashable] = []

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
        self.path = nil
        self.modern = { c in
            if #available(iOS 16.0, *) { return AnyView(NavigationStack { c }) }
            return AnyView(c)
        }
    }

    init<T: Hashable>(path: Binding<[T]>, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.path = Binding<[AnyHashable]>(
            get: { path.wrappedValue.map { AnyHashable($0) } },
            set: { path.wrappedValue = $0.compactMap { $0.base as? T } })
        self.modern = { c in
            if #available(iOS 16.0, *) { return AnyView(NavigationStack(path: path) { c }) }
            return AnyView(c)
        }
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            modern(content)
        } else {
            HLegacyStack(path: path ?? $localPath, content: content)
        }
    }
}

private struct HLegacyStack<Content: View>: View {
    @Binding var path: [AnyHashable]
    let content: Content
    @State private var registry = HNavRegistry()

    var body: some View {
        NavigationView {
            content.background(HNavLevel(index: 0, path: $path, registry: registry))
        }
        .navigationViewStyle(.stack)
        .environment(\.hNavRegistry, registry)
        .environment(\.hNavPush, { value in path.append(value) })
    }
}

/// One hidden link per level of the path: level N is active while the path is longer than N, and shows path[N].
private struct HNavLevel: View {
    let index: Int
    @Binding var path: [AnyHashable]
    let registry: HNavRegistry

    var body: some View {
        NavigationLink(
            isActive: Binding(
                get: { path.count > index },
                set: { active in if !active && path.count > index { path.removeSubrange(index...) } }),
            destination: {
                if path.count > index {
                    registry.view(for: path[index])
                        .background(HNavLevel(index: index + 1, path: $path, registry: registry))
                } else {
                    EmptyView()
                }
            },
            label: { EmptyView() })
        .hidden()
    }
}

private struct HLegacyDestination<D: Hashable>: ViewModifier {
    @Environment(\.hNavRegistry) private var registry
    let build: (D) -> AnyView

    func body(content: Content) -> some View {
        registry?.register(D.self, build)
        return content
    }
}

extension View {
    /// `navigationDestination(for:destination:)`.
    @ViewBuilder
    func hNavDestination<D: Hashable, C: View>(for data: D.Type, @ViewBuilder destination: @escaping (D) -> C) -> some View {
        if #available(iOS 16.0, *) {
            self.navigationDestination(for: data, destination: destination)
        } else {
            self.modifier(HLegacyDestination<D>(build: { AnyView(destination($0)) }))
        }
    }
}

private struct HRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1).contentShape(Rectangle())
    }
}

/// `NavigationLink(value:label:)`.
struct HNavLink<V: Hashable, Label: View>: View {
    let value: V
    let label: Label
    @Environment(\.hNavPush) private var push

    init(value: V, @ViewBuilder label: () -> Label) {
        self.value = value
        self.label = label()
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationLink(value: value) { label }
        } else {
            // A plain button that asks the stack to push. (A NavigationLink with a dummy destination pushed an extra
            // blank page on iOS 15, so the real navigation is only ever done by the stack's own path.)
            Button { push?(AnyHashable(value)) } label: { label }
                .buttonStyle(HRowButtonStyle())
        }
    }
}

// MARK: - Small modifiers

extension View {
    /// `.toolbar(.hidden / .visible, for: .navigationBar)`.
    @ViewBuilder
    func hNavBarHidden(_ hidden: Bool) -> some View {
        if #available(iOS 16.0, *) {
            self.toolbar(hidden ? .hidden : .visible, for: .navigationBar)
        } else {
            self.navigationBarHidden(hidden)
        }
    }

    /// `.scrollIndicators(.hidden)`. Nothing on iOS 15.
    @ViewBuilder
    func hScrollIndicatorsHidden() -> some View {
        if #available(iOS 16.0, *) { self.scrollIndicators(.hidden) } else { self }
    }

    /// `.scrollDismissesKeyboard(.immediately)`. Nothing on iOS 15.
    @ViewBuilder
    func hDismissKeyboardOnScroll() -> some View {
        if #available(iOS 16.0, *) { self.scrollDismissesKeyboard(.immediately) } else { self }
    }

    /// `.persistentSystemOverlays(.hidden)`. Nothing on iOS 15.
    @ViewBuilder
    func hHideSystemOverlays() -> some View {
        if #available(iOS 16.0, *) { self.persistentSystemOverlays(.hidden) } else { self.statusBar(hidden: true) }
    }

    /// `.defersSystemGestures(on: .all)`. Nothing on iOS 15.
    @ViewBuilder
    func hDeferSystemGestures() -> some View {
        if #available(iOS 16.0, *) { self.defersSystemGestures(on: .all) } else { self }
    }

    /// `.presentationDragIndicator(.visible)`. Nothing on iOS 15.
    @ViewBuilder
    func hDragIndicator() -> some View {
        if #available(iOS 16.0, *) { self.presentationDragIndicator(.visible) } else { self }
    }

    /// `.presentationDetents(_:)`. On iOS 15 the sheet is full height.
    @ViewBuilder
    func hPresentationDetents(_ detents: [HDetent]) -> some View {
        if #available(iOS 16.0, *) {
            self.presentationDetents(Set(detents.map { $0.modern }))
        } else {
            self
        }
    }
}

enum HDetent {
    case medium
    case height(CGFloat)

    @available(iOS 16.0, *)
    var modern: PresentationDetent {
        switch self {
        case .medium: return .medium
        case .height(let h): return .height(h)
        }
    }
}

extension Text {
    /// `Text.tracking(_:)`, which is `kerning` on iOS 15.
    func hTracking(_ value: CGFloat) -> Text {
        if #available(iOS 16.0, *) { return tracking(value) }
        return kerning(value)
    }
}

extension Color {
    /// `Color.gradient`.
    var hGradient: LinearGradient {
        LinearGradient(colors: [self.opacity(0.82), self], startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - LabeledContent

/// `LabeledContent`: the label on the left, the content on the right in secondary colour.
struct HLabeledContent<Label: View, Content: View>: View {
    let label: Label
    let content: Content

    init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.content = content()
        self.label = label()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            label
            Spacer(minLength: 12)
            content.foregroundColor(.secondary).multilineTextAlignment(.trailing)
        }
    }
}

extension HLabeledContent where Label == Text {
    init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.label = Text(String(title))
    }
}

extension HLabeledContent where Label == Text, Content == Text {
    init<S: StringProtocol, V: StringProtocol>(_ title: S, value: V) {
        self.content = Text(String(value))
        self.label = Text(String(title))
    }
}

// MARK: - ShareLink

private struct HActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// `ShareLink(item:label:)` for a file URL or a string, through the system share sheet on every version.
struct HShareLink<Label: View>: View {
    private let items: [Any]
    private let label: Label
    @State private var showing = false

    init(item: URL, @ViewBuilder label: () -> Label) {
        self.items = [item]
        self.label = label()
    }

    init(item: String, @ViewBuilder label: () -> Label) {
        self.items = [item]
        self.label = label()
    }

    var body: some View {
        Button { showing = true } label: { label }
            .sheet(isPresented: $showing) { HActivityView(items: items) }
    }
}
