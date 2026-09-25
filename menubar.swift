// Menu-bar badge: gtforge PRs waiting on your review. Click one to review it in a
// fresh Claude or Codex session; skip one to drop it until new commits land.
import Cocoa

let dir = NSString(string: "~/.pr-review-inbox").expandingTildeInPath
let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

struct PR {
    let repo: String, number: Int, title: String, url: String, sha: String, reason: String
    var spec: String { "\(repo.hasPrefix("gtforge/") ? String(repo.dropFirst(8)) : repo)#\(number)" }
}

var rows: [PR] = []

func setting(_ name: String, _ fallback: String) -> String {
    let v = (try? String(contentsOfFile: dir + "/" + name, encoding: .utf8))?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return v.isEmpty ? fallback : v
}

/// The inbox data comes from the pr-review-inbox skill - this app only displays it.
func candidates() -> String {
    setting("candidates-path",
            NSString(string: "~/.claude/skills/pr-review-inbox/candidates.py").expandingTildeInPath)
}

func log(_ line: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    guard let h = FileHandle(forWritingAtPath: dir + "/review.log") ??
            (FileManager.default.createFile(atPath: dir + "/review.log", contents: nil)
             ? FileHandle(forWritingAtPath: dir + "/review.log") : nil) else { return }
    h.seekToEndOfFile()
    h.write("\(stamp) \(line)\n".data(using: .utf8)!)
    try? h.close()
}

@discardableResult
func shell(_ cmd: String) -> String {
    let p = Process()
    p.launchPath = "/bin/sh"
    p.arguments = ["-c", cmd]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    guard (try? p.run()) != nil else { return "" }
    let d = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(data: d, encoding: .utf8) ?? ""
}

let herdr = ["/opt/homebrew/bin/herdr", "/usr/local/bin/herdr"]
    .first { FileManager.default.isExecutableFile(atPath: $0) }

func result(_ output: String) -> [String: Any] {
    guard let d = output.data(using: .utf8),
          let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
          let r = j["result"] as? [String: Any] else { return [:] }
    return r
}

/// tab create and workspace create both answer with the pane to drive.
func paneID(_ output: String) -> String? {
    (result(output)["root_pane"] as? [String: Any])?["pane_id"] as? String
}

/// Reviews get their own workspace, found by label and made the first time.
func reviewPane(_ bin: String, _ label: String, _ cwd: String, _ tab: String) -> String? {
    let listed = result(shell("\(bin) workspace list"))["workspaces"] as? [[String: Any]] ?? []
    if let id = listed.first(where: { $0["label"] as? String == label })?["workspace_id"] as? String {
        shell("\(bin) workspace focus '\(id)'")
        let out = shell("\(bin) tab create --workspace '\(id)' --cwd '\(cwd)' --label '\(tab)' --focus")
        log("tab in \(label) (\(id)) -> \(out.prefix(200))")
        return paneID(out)
    }
    // no workspace yet: its own first tab is the one to review in
    let out = shell("\(bin) workspace create --label '\(label)' --cwd '\(cwd)'")
    log("created workspace \(label) -> \(out.prefix(200))")
    if let id = (result(out)["workspace"] as? [String: Any])?["workspace_id"] as? String {
        shell("\(bin) workspace focus '\(id)'")
    }
    return paneID(out)
}

func parse(_ text: String) -> [PR] {
    guard let d = text.data(using: .utf8),
          let list = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { return [] }
    let order = ["amended": 0, "unreviewed": 1, "tagged": 2]
    return list.compactMap { r in
        guard let repo = r["repo"] as? String, let n = r["number"] as? Int else { return nil }
        return PR(repo: repo, number: n, title: r["title"] as? String ?? "",
                  url: r["url"] as? String ?? "", sha: r["sha"] as? String ?? "",
                  reason: r["reason"] as? String ?? "unreviewed")
    }.sorted { (order[$0.reason] ?? 9, $0.repo) < (order[$1.reason] ?? 9, $1.repo) }
}

func updateBadge() {
    // An empty inbox says nothing: hide the item rather than park a 0 in the menu bar.
    item.isVisible = !rows.isEmpty
    item.button?.title = "👀 \(rows.count)"
}

/// The search takes ~10s, so it runs off the main thread and the menu shows the
/// last result until the new one lands.
func poll() {
    DispatchQueue.global().async {
        let out = shell("python3 '\(candidates())'")
        let fresh = parse(out)
        guard !out.isEmpty else { return }  // a failed run keeps what we had
        try? out.write(toFile: dir + "/inbox.json", atomically: true, encoding: .utf8)
        DispatchQueue.main.async {
            rows = fresh
            updateBadge()
        }
    }
}

func checkoutOf(_ repo: String) -> String {
    let name = repo.contains("/") ? String(repo.split(separator: "/").last!) : repo
    let path = NSString(string: "~/go/src/github.com/gtforge/\(name)").expandingTildeInPath
    return FileManager.default.fileExists(atPath: path) ? path : NSHomeDirectory()
}

class Handler: NSObject, NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for (i, pr) in rows.enumerated() {
            let mi = NSMenuItem(title: "[\(pr.reason)]  \(pr.spec) — \(pr.title)",
                                action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for (label, sel) in [("Review in \(setting("agent", "claude"))", #selector(review(_:))),
                                 ("Skip until it changes", #selector(skip(_:)))] {
                let a = NSMenuItem(title: label, action: sel, keyEquivalent: "")
                a.target = self
                a.representedObject = i
                sub.addItem(a)
            }
            mi.submenu = sub
            menu.addItem(mi)
        }
        if rows.isEmpty {
            menu.addItem(NSMenuItem(title: "nothing waiting on you", action: nil, keyEquivalent: ""))
        }
        menu.addItem(.separator())
        let am = NSMenuItem(title: "Review with", action: nil, keyEquivalent: "")
        let asub = NSMenu()
        for kind in ["claude", "codex"] {
            let a = NSMenuItem(title: kind, action: #selector(setAgent(_:)), keyEquivalent: "")
            a.target = self
            a.representedObject = kind
            a.state = kind == setting("agent", "claude") ? .on : .off
            asub.addItem(a)
        }
        am.submenu = asub
        menu.addItem(am)
        for (title, sel) in [("Refresh now", #selector(refresh)), ("Quit", #selector(quit))] {
            let mi = NSMenuItem(title: title, action: sel, keyEquivalent: title == "Quit" ? "q" : "")
            mi.target = self
            menu.addItem(mi)
        }
    }

    /// Fresh tab, agent of your choice, the review skill invoked on the PR. Codex
    /// takes the same skill under a different prefix.
    @objc func review(_ sender: NSMenuItem) {
        guard let i = sender.representedObject as? Int, i < rows.count else { return }
        let pr = rows[i]
        let kind = setting("agent", "claude")
        let ask = (kind == "codex" ? "$" : "/") + "pr-review \(pr.url)"
        let cwd = checkoutOf(pr.repo)
        DispatchQueue.global().async {
            guard let bin = herdr else {
                shell("open -na Ghostty --args -e \(kind) '\(ask)'")
                return
            }
            guard let pane = reviewPane(bin, setting("workspace", "PR review"), cwd,
                                        "review \(pr.spec)") else {
                log("no pane to review \(pr.spec) in - giving up")
                return
            }
            let name = "review-" + pr.spec.replacingOccurrences(of: "#", with: "-")
            log("agent start \(name) --kind \(kind) --pane \(pane) -> " +
                shell("\(bin) agent start '\(name)' --kind \(kind) --pane '\(pane)' --timeout 60000").prefix(300))
            log("agent prompt -> " + shell("\(bin) agent prompt '\(name)' '\(ask)'").prefix(300))
        }
    }

    // Records the PR at its current head, so it stays out until new commits land.
    @objc func skip(_ sender: NSMenuItem) {
        guard let i = sender.representedObject as? Int, i < rows.count else { return }
        let spec = rows[i].spec
        DispatchQueue.global().async {
            shell("python3 '\(candidates())' --reviewed '\(spec)'")
            DispatchQueue.main.async { poll() }
        }
    }

    @objc func setAgent(_ sender: NSMenuItem) {
        try? (sender.representedObject as? String ?? "claude")
            .write(toFile: dir + "/agent", atomically: true, encoding: .utf8)
    }
    @objc func refresh() { poll() }
    @objc func quit() { NSApp.terminate(nil) }
}

let handler = Handler()
let menu = NSMenu()
menu.delegate = handler
item.menu = menu

// Show the last known inbox immediately; the first poll replaces it seconds later.
if let cached = try? String(contentsOfFile: dir + "/inbox.json", encoding: .utf8) {
    rows = parse(cached)
}
NSApplication.shared.setActivationPolicy(.accessory)
updateBadge()
poll()
Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in poll() }
NSApplication.shared.run()
