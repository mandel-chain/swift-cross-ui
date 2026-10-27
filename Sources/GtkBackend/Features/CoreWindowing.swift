import CGtk
import Gtk
@_spi(Backends) import SwiftCrossUI

extension GtkBackend: BackendFeatures.CoreWindowing {
    public typealias Window = Gtk.ApplicationWindow

    public var supportsMultipleWindows: Bool { true }
    public var canOverrideWindowColorScheme: Bool { false }
    public var restoresWindowFrames: Bool { false }

    public func createWindow(withDefaultSize defaultSize: SIMD2<Int>?, id: String) -> Window {
        let window: Gtk.ApplicationWindow
        if let precreatedWindow {
            self.precreatedWindow = nil
            window = precreatedWindow
        } else {
            window = Gtk.ApplicationWindow(application: gtkApp)
        }

        windows.append(window)

        if let defaultSize {
            window.defaultSize = Size(
                width: defaultSize.x,
                height: defaultSize.y
            )
        }

        window.setChild(Gtk.Box())

        // Telling the app of a change of the window's is-active recomputes
        // the root environment (appPhase, scenePhase) and lays out every
        // window again. A menu's popup takes the window's active state and
        // gives it back, twice, within a moment, and with a large window
        // laying it all out on each change kept GTK from mapping the popup
        // at all. So the app hears only of changes that settle.
        window.notifyIsActive = { [weak self] _ in
            self?.windowActivationChanged()
        }

        return window
    }

    /// How long a change of a window's active state has to last before the
    /// app hears of it, so that a popup's taking it and giving it back
    /// cancel out.
    static let activationSettleMilliseconds = 100

    /// Tells the app that which windows are active has changed, once no window
    /// has changed its active state for ``activationSettleMilliseconds``, and
    /// only if the active windows differ from those the app last heard of.
    func windowActivationChanged() {
        activationChangeGeneration &+= 1
        let generation = activationChangeGeneration
        Self.runInMainThread(afterMilliseconds: Self.activationSettleMilliseconds) { [weak self] in
            guard let self, generation == activationChangeGeneration else { return }
            let activeWindows = Set(windows.filter(\.isActive).map(ObjectIdentifier.init))
            guard activeWindows != reportedActiveWindows else { return }
            reportedActiveWindows = activeWindows
            rootEnvironmentChangeHandler?()
        }
    }

    public func updateWindow(_ window: Window, environment: EnvironmentValues) {
        // TODO(stackotter): Support preferredColorScheme
    }

    public func setTitle(ofWindow window: Window, to title: String) {
        window.title = title
    }

    public func setChild(ofWindow window: Window, to child: Widget) {
        let container = wrapInCustomRootContainer(child)
        window.setChild(container)
    }

    public func size(ofWindow window: Window) -> SIMD2<Int> {
        let child = window.getChild() as! CustomRootWidget
        let size = child.getSize()
        return SIMD2(size.width, size.height)
    }

    public func isWindowProgrammaticallyResizable(_ window: Window) -> Bool {
        // TODO: Detect whether window is fullscreen
        return true
    }

    public func setSize(ofWindow window: Window, to newSize: SIMD2<Int>) {
        let child = window.getChild() as! CustomRootWidget
        window.size = Size(
            width: newSize.x,
            height: newSize.y + menubarHeight(ofWindow: window)
        )
        child.preemptAllocatedSize(allocatedWidth: newSize.x, allocatedHeight: newSize.y)
    }

    public func setSizeLimits(
        ofWindow window: Window,
        minimum minimumSize: SIMD2<Int>,
        maximum maximumSize: SIMD2<Int>?
    ) {
        window.setMinimumSize(to: Size(width: minimumSize.x, height: minimumSize.y))

        // NB: GTK does not support setting maximum sizes for widgets. It just doesn't.
        // https://discourse.gnome.org/t/how-to-build-fixed-size-windows-in-gtk-4/22807/10
        if maximumSize != nil {
            debugLogOnce("GTK does not support setting maximum window sizes")
        }
    }

    public func setResizeHandler(
        ofWindow window: Window,
        to action: @escaping (_ newSize: SIMD2<Int>) -> Void
    ) {
        let child = window.getChild() as! CustomRootWidget
        child.setResizeHandler { size in
            self.runInMainThread {
                action(SIMD2(size.width, size.height))
            }
        }
    }

    public func show(window: Window) {
        window.show()
    }

    public func activate(window: Window) {
        window.present()
    }

    public func computeWindowEnvironment(
        window: Window,
        rootEnvironment: EnvironmentValues
    ) -> EnvironmentValues {
        // TODO: Record window scale factor in here
        rootEnvironment
            .with(\.scenePhase, window.isActive ? .active : .inactive)
    }

    public func setWindowEnvironmentChangeHandler(
        of window: Window,
        to action: @escaping @Sendable @MainActor () -> Void
    ) {
        // TODO: Notify when window scale factor changes
    }

    func wrapInCustomRootContainer(_ widget: Widget) -> Widget {
        let container = CustomRootWidget()
        container.setChild(to: widget)
        return container
    }

    func menubarHeight(ofWindow window: Window) -> Int {
        #if os(macOS)
            return 0
        #else
            if window.showMenuBar {
                // TODO: Don't hardcode this (if possible), because some Gtk
                //   themes may affect the height of the menu bar.
                25
            } else {
                0
            }
        #endif
    }
}
