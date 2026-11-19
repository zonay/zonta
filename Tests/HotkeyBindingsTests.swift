import Foundation

@main
struct HotkeyBindingsTests {
    static func main() throws {
        check(HotkeyBindings.defaults.globe == .chat, "default globe")
        check(HotkeyBindings.defaults.rightCommand == .dictate, "default right command")
        check(HotkeyBindings.defaults.rightOption == .translate, "default right option")

        let b = HotkeyBindings(globe: .translate, rightCommand: .off, rightOption: .chat)
        check(b.action(for: .globe) == .translate, "action(for: .globe)")
        check(b.action(for: .rightCommand) == .off, "action(for: .rightCommand)")
        check(b.keys(for: .chat) == [.rightOption], "keys(for: .chat)")
        check(b.keys(for: .off) == [.rightCommand], "keys(for: .off)")

        let round = try JSONDecoder().decode(
            HotkeyBindings.self, from: JSONEncoder().encode(b)
        )
        check(round == b, "encode/decode round trip")

        let partial = try JSONDecoder().decode(
            HotkeyBindings.self,
            from: Data(#"{"globe":"dictate"}"#.utf8)
        )
        check(partial.globe == .dictate, "partial JSON: explicit key")
        check(partial.rightCommand == .dictate, "partial JSON: fallback right command")
        check(partial.rightOption == .translate, "partial JSON: fallback right option")

        let unknown = try JSONDecoder().decode(
            HotkeyBindings.self,
            from: Data(#"{"globe":"bananas","rightCommand":"chat"}"#.utf8)
        )
        check(unknown.globe == .chat, "unknown value falls back to default")
        check(unknown.rightCommand == .chat, "unknown value keeps the other key")

        let oldBlob = Data(#"{"whisperModel":"my-model","chatLLM":{"baseURL":"http://x/v1","apiKey":"k","model":"m"}}"#.utf8)
        let settings = try JSONDecoder().decode(Settings.self, from: oldBlob)
        check(settings.hotkeys == .defaults, "old Settings blob gets default hotkeys")
        check(settings.whisperModel == "my-model", "old Settings blob keeps other fields")

        print("all hotkey binding tests passed")
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ label: String) {
        if !condition() { fatalError("FAILED: \(label)") }
    }
}

@MainActor
private func compileTimeHotkeyInterface(_ hotkey: Hotkey) {
    hotkey.onDown = { (_: HotkeyKey) in }
    hotkey.onUp = { (_: HotkeyKey) in }
    hotkey.onCancel = { (_: HotkeyKey) in }
    hotkey.onDoubleTap = { (_: HotkeyKey) in }
    hotkey.configure(doubleTapKeys: [.globe])
}
