import Foundation

/// The physical modifier keys Zonta listens to.
enum HotkeyKey: Hashable {
    case globe, rightCommand, rightOption
}

/// What a key does when held. `off` leaves the key unbound.
enum HotkeyAction: String, Codable, CaseIterable, Identifiable {
    case chat, dictate, translate, off

    var id: String { rawValue }

    var label: String {
        switch self {
        case .chat: return "Chat"
        case .dictate: return "Dictate"
        case .translate: return "Translate"
        case .off: return "Off"
        }
    }
}

/// The user's key-to-action assignments. Stored inside `Settings`.
struct HotkeyBindings: Codable, Equatable {
    var globe: HotkeyAction
    var rightCommand: HotkeyAction
    var rightOption: HotkeyAction

    static let defaults = HotkeyBindings(
        globe: .chat, rightCommand: .dictate, rightOption: .translate
    )

    private enum CodingKeys: String, CodingKey {
        case globe, rightCommand, rightOption
    }

    init(globe: HotkeyAction, rightCommand: HotkeyAction, rightOption: HotkeyAction) {
        self.globe = globe
        self.rightCommand = rightCommand
        self.rightOption = rightOption
    }

    /// Missing keys and unknown values both fall back to the original mapping,
    /// so an old or hand-edited settings blob can never discard the user's
    /// other settings.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = HotkeyBindings.defaults
        globe = Self.decode(c, .globe, fallback: d.globe)
        rightCommand = Self.decode(c, .rightCommand, fallback: d.rightCommand)
        rightOption = Self.decode(c, .rightOption, fallback: d.rightOption)
    }

    private static func decode(
        _ c: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys,
        fallback: HotkeyAction
    ) -> HotkeyAction {
        guard let raw = try? c.decode(String.self, forKey: key),
              let action = HotkeyAction(rawValue: raw) else { return fallback }
        return action
    }

    func action(for key: HotkeyKey) -> HotkeyAction {
        switch key {
        case .globe: return globe
        case .rightCommand: return rightCommand
        case .rightOption: return rightOption
        }
    }

    /// Every key bound to an action — a user may bind the same action twice.
    func keys(for action: HotkeyAction) -> Set<HotkeyKey> {
        var result: Set<HotkeyKey> = []
        if globe == action { result.insert(.globe) }
        if rightCommand == action { result.insert(.rightCommand) }
        if rightOption == action { result.insert(.rightOption) }
        return result
    }
}
