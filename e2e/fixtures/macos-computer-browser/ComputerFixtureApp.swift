import AppKit
import Foundation

final class FixtureController: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
    private let statePath: String
    private let windowTitle: String
    private let buttonTitle: String
    private let initialText: String

    private var window: NSWindow!
    private var button: NSButton!
    private var textField: NSTextField!
    private var statusLabel: NSTextField!

    private var launchCount: Int = 1
    private var buttonPressCount: Int = 0
    private var lastText: String

    init(statePath: String, windowTitle: String, buttonTitle: String, initialText: String) {
        self.statePath = statePath
        self.windowTitle = windowTitle
        self.buttonTitle = buttonTitle
        self.initialText = initialText
        self.lastText = initialText
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildWindow()
        writeState()
        NSApp.activate(ignoringOtherApps: true)
    }

    func controlTextDidChange(_ obj: Notification) {
        lastText = textField.stringValue
        statusLabel.stringValue = "Typed: \(lastText)"
        writeState()
    }

    @objc private func pressButton(_ sender: Any?) {
        buttonPressCount += 1
        statusLabel.stringValue = "Button pressed \(buttonPressCount)x"
        window.makeFirstResponder(textField)
        writeState()
    }

    private func buildWindow() {
        let frame = NSRect(x: 0, y: 0, width: 520, height: 220)
        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = windowTitle
        window.center()

        guard let contentView = window.contentView else {
            fatalError("missing content view")
        }

        let instructions = NSTextField(labelWithString: "Spider computer fixture: press the button, then type into the field.")
        instructions.frame = NSRect(x: 20, y: 170, width: 480, height: 24)

        button = NSButton(title: buttonTitle, target: self, action: #selector(pressButton(_:)))
        button.frame = NSRect(x: 20, y: 120, width: 220, height: 32)

        textField = NSTextField(string: initialText)
        textField.frame = NSRect(x: 20, y: 72, width: 320, height: 28)
        textField.delegate = self
        textField.placeholderString = "Type into the fixture field"

        statusLabel = NSTextField(labelWithString: "Typed: \(lastText)")
        statusLabel.frame = NSRect(x: 20, y: 32, width: 420, height: 24)

        contentView.addSubview(instructions)
        contentView.addSubview(button)
        contentView.addSubview(textField)
        contentView.addSubview(statusLabel)

        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(button)
    }

    private func writeState() {
        let payload: [String: Any] = [
            "window_title": windowTitle,
            "button_title": buttonTitle,
            "launch_count": launchCount,
            "button_press_count": buttonPressCount,
            "last_text": lastText,
            "status_label": statusLabel.stringValue,
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: statePath), options: .atomic)
        } catch {
            fputs("failed to write fixture state: \(error)\n", stderr)
        }
    }
}

let env = ProcessInfo.processInfo.environment
let statePath = env["SPIDER_FIXTURE_STATE_PATH"] ?? NSTemporaryDirectory() + "/spider-computer-fixture-state.json"
let windowTitle = env["SPIDER_FIXTURE_WINDOW_TITLE"] ?? "Spider Computer Fixture Window"
let buttonTitle = env["SPIDER_FIXTURE_BUTTON_TITLE"] ?? "Press Fixture Button"
let initialText = env["SPIDER_FIXTURE_INITIAL_TEXT"] ?? ""

let delegate = FixtureController(
    statePath: statePath,
    windowTitle: windowTitle,
    buttonTitle: buttonTitle,
    initialText: initialText
)

let app = NSApplication.shared
app.delegate = delegate
app.run()
