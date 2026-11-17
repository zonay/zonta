import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

enum Pasteboard {
    /// App that was frontmost when Globe went down.
    private(set) static var targetPID: pid_t?

    static func rememberTarget() {
        let own = ProcessInfo.processInfo.processIdentifier
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier, pid != own {
            targetPID = pid
        }
    }

    /// Puts `text` on the clipboard and into the focused field of the target app.
    /// Returns a message only when the insert failed (clipboard still holds the text).
    @discardableResult
    static func paste(_ text: String) -> String? {
        let pb = NSPasteboard.general
        pb.clearContents()
        guard pb.setString(text, forType: .string) else {
            return "Could not write the clipboard."
        }

        guard accessibilityGranted else {
            requestAccessibility()
            return "Copied. Allow Zonta under Accessibility, then dictate again."
        }

        let own = ProcessInfo.processInfo.processIdentifier
        let pid = targetPID
            ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard let pid, pid != own else {
            return "Copied. Click a text field first, then hold Right ⌘."
        }

        // Paste the way the app pastes: press its Edit > Paste item. Native, so
        // the caret lands after the text instead of the text staying selected.
        if pressPasteMenu(pid: pid) {
            return nil
        }

        // Apps without a Paste menu: write into the focused element directly.
        if insertAtCursor(text, pid: pid) {
            return nil
        }

        return "Copied. Zonta could not paste into that app."
    }

    static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [key: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    /// Writes into the caret of the target app. Does not depend on which app is frontmost.
    /// Returns false when the app refused the write or accepted it and ignored it.
    private static func insertAtCursor(_ text: String, pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused
        else { return false }

        let element = focused as! AXUIElement

        // Where the caret is now, so the text can replace the selection and the
        // caret can end up after the insert instead of the text staying selected.
        var rangeValue: CFTypeRef?
        var caret: Int?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
           let rangeValue {
            var range = CFRange()
            if AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) {
                caret = range.location + range.length
            }
        }

        var before: CFTypeRef?
        let readable = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &before) == .success
        let beforeText = readable ? before as? String : nil

        guard AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        ) == .success else { return false }

        // Some apps report success and change nothing. Read the value back.
        if let beforeText,
           AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &before) == .success,
           let afterText = before as? String {
            if afterText == beforeText { return false }
        }

        // Collapse the selection to the end of what was just inserted.
        if let caret {
            var end = CFRange(location: caret + text.utf16.count, length: 0)
            if let value = AXValueCreate(.cfRange, &end) {
                AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value)
            }
        }
        return true
    }

    /// Presses the app's Edit > Paste menu item. The item is found by its
    /// command character, so a translated menu still matches.
    private static func pressPasteMenu(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &bar) == .success,
              let bar
        else { return false }
        return findPasteItem(bar as! AXUIElement, depth: 0)
    }

    private static func findPasteItem(_ element: AXUIElement, depth: Int) -> Bool {
        guard depth < 5 else { return false }
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
              let list = children as? [AXUIElement]
        else { return false }

        for child in list {
            var cmd: CFTypeRef?
            if AXUIElementCopyAttributeValue(child, kAXMenuItemCmdCharAttribute as CFString, &cmd) == .success,
               let char = cmd as? String, char.lowercased() == "v" {
                var mods: CFTypeRef?
                let hasMods = AXUIElementCopyAttributeValue(
                    child, kAXMenuItemCmdModifiersAttribute as CFString, &mods
                ) == .success
                // 0 is command and nothing else.
                if (!hasMods || (mods as? Int) == 0),
                   AXUIElementPerformAction(child, kAXPressAction as CFString) == .success {
                    return true
                }
            }
            if findPasteItem(child, depth: depth + 1) {
                return true
            }
        }
        return false
    }
}
