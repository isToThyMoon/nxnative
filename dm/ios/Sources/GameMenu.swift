// The in-game menu, opened by the gamepad's menu button at the top centre (DmGamepad.m): the controller layout, then the settings-screen settings the running game takes at once
// (front_ios.m dm_setting_live), grouped as on the settings screen but without its headings, one row each, so the menu stays short over the game (its text size is fixed: front_ios.m
// startGame). A pick is saved as Play saves it (LauncherModel.choose), so the settings screen shows it at the next start; a setting an env file fixes is shown, not changed. Settings
// that need the next start (language, pipelines, the frame rate and so on), and the sliders, stay on the settings screen, which the menu's title points to.
import UIKit

var gameMenuModel: LauncherModel?   // the settings screen's model (Launcher.swift); nil in an app without one: the menu has the layout only

// The menu's own words in the player's language (LNPANDY/NX2Apple#1129): DM_GAME_MENU_TEXT, one per line in GameMenuText's order, passed by the
// launcher as DM_HOME_QUIT_TEXT is for the quit prompt: the shell sets it at launch, and a game's own app gets it in its bundled dm/env.txt (the build's
// --env-file), where the lines are joined by a backslash and n. A line that is missing or empty stays English.
enum GameMenuText: Int, CaseIterable {
    case moreSettings, controllerLayout, keysThatToggle, none
    var english: String {
        switch self {
        case .moreSettings: return "More settings on the start screen"
        case .controllerLayout: return "Controller layout"
        case .keysThatToggle: return "Keys that toggle"
        case .none: return "None"
        }
    }
    static func line(_ t: GameMenuText, in text: String?) -> String {
        let lines = (text ?? "").replacingOccurrences(of: "\\n", with: "\n").components(separatedBy: "\n")
        let line = t.rawValue < lines.count ? lines[t.rawValue].trimmingCharacters(in: .whitespaces) : ""
        return line.isEmpty ? t.english : line
    }
    var text: String { Self.line(self, in: getenv("DM_GAME_MENU_TEXT").map { String(cString: $0) }) }
}

@_cdecl("dm_game_menu")
public func dmGameMenu() -> UnsafeMutableRawPointer {
    let title = gameMenuModel != nil ? GameMenuText.moreSettings.text : ""
    let menu = UIMenu(title: title, children: [UIDeferredMenuElement.uncached { done in done(gameMenuItems()) }])   // built each time it opens, so it shows the current choices
    return Unmanaged.passRetained(menu).toOpaque()
}

private func gameMenuItems() -> [UIMenuElement] {
    let names = ["2D", "3D", "Tap"]
    let layouts = (0..<3).filter { dm_pad_layout_offered(Int32($0)) }.map { l in
        UIAction(title: names[l], state: dm_pad_layout() == l ? .on : .off) { _ in dm_pad_layout_set(Int32(l)) }
    }
    let layout = UIMenu(title: GameMenuText.controllerLayout.text, options: .singleSelection, children: layouts)   // a choice's value shows in its submenu: a subtitle would make each row two lines
    let controls: [UIMenuElement] = dm_pad_toggle_offered() ? [layout, keysThatToggle()] : [layout]
    var items: [UIMenuElement] = []
    var placed = false
    if let m = gameMenuModel {
        for section in m.sections {
            var rows: [UIMenuElement] = section == "Controls" ? controls : []
            if section == "Controls" { placed = true }
            for s in m.rows(in: section) where (s.kind == "choice" || s.kind == "toggle") && dm_setting_live(s.env, nil) { rows.append(gameMenuRow(m, s)) }
            if !rows.isEmpty { items.append(UIMenu(options: .displayInline, children: rows)) }
        }
    }
    if !placed { items.insert(UIMenu(options: .displayInline, children: controls), at: 0) }
    items.append(Unmanaged<UIMenu>.fromOpaque(dm_quit_menu()).takeRetainedValue())   // Quit <game>, last and on its own: it opens the quit prompt (front_ios.m)
    return items
}

// Keys that toggle (LNPANDY/NX2Apple#658), in a game's own app: a tap turns a checked key on, the next tap off. Several can be checked, one per
// pick, and a pick applies at once and is kept for the next start (DmGamepad.m). The shell sets the same keys in its touch layout editor.
// The numbers are DmPadGeometry.h's DM_PAD_C_* of the single keys.
private let toggleKeys: [(control: Int32, name: String)] = [(1, "A"), (2, "B"), (3, "X"), (4, "Y"), (8, "L"), (10, "R"), (7, "ZL"), (9, "ZR"),
                                                            (11, "L3"), (12, "R3"), (13, "−"), (14, "+")]

private func keysThatToggle() -> UIMenuElement {
    let on = toggleKeys.filter { dm_pad_toggles($0.control) }.map(\.name)
    let keys = toggleKeys.map { key in
        UIAction(title: key.name, state: dm_pad_toggles(key.control) ? .on : .off) { _ in
            dm_pad_toggle_set(key.control, !dm_pad_toggles(key.control))
        }
    }
    return UIMenu(title: GameMenuText.keysThatToggle.text, subtitle: on.isEmpty ? GameMenuText.none.text : on.joined(separator: " "), children: keys)
}

private func gameMenuRow(_ m: LauncherModel, _ s: Setting) -> UIMenuElement {
    let now = m.values[s.env] ?? s.def, fixed = m.fixed.contains(s.env)
    let attributes: UIMenuElement.Attributes = fixed ? .disabled : []
    func pick(_ v: String) { m.choose(s, v); _ = dm_setting_live(s.env, v) }
    if s.kind == "toggle" {
        let a = UIAction(title: s.label, attributes: attributes, state: now == s.onValue ? .on : .off) { _ in pick(now == s.onValue ? s.offValue : s.onValue) }
        if fixed { a.subtitle = "Set in env.txt" }
        return a
    }
    let options = s.options ?? []
    let current = options.first { $0[0] == now }?[1] ?? now
    let actions = options.map { o in UIAction(title: o[1], attributes: attributes, state: o[0] == now ? .on : .off) { _ in pick(o[0]) } }
    return UIMenu(title: s.label, subtitle: fixed ? "\(current), set in env.txt" : nil, options: .singleSelection, children: actions)
}
