import Cocoa
import Foundation
import SQLite3

private let codexHome: URL = {
    if let override = ProcessInfo.processInfo.environment["CODEX_HOME"], !override.isEmpty {
        return URL(fileURLWithPath: override, isDirectory: true)
    }
    return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
}()
private let soundDir = codexHome.appendingPathComponent("completion_sound", isDirectory: true)
private let presetsDir = soundDir.appendingPathComponent("presets", isDirectory: true)
private let logDB = codexHome.appendingPathComponent("logs_1.sqlite")
private let stateFile = soundDir.appendingPathComponent("state.json")
private let volumeFile = soundDir.appendingPathComponent("volume.txt")
private let currentSoundFile = soundDir.appendingPathComponent("current_sound.txt")
private let pollInterval: TimeInterval = 2.0
private let minPlayGapSeconds: TimeInterval = 0.75
private let mergeCompletionSignalsSeconds: Double = 3.0
private let legacySuppressionWindowSeconds: Double = 10.0
private let soundCandidates = ["sound.mp3", "sound.wav", "sound.m4a", "sound.aiff", "sound.caf"]

private enum CompletionEventKind {
    case finalAnswer
    case legacyTurnCompleted
}

private struct CompletionEvent {
    let id: Int64
    let eventTime: Double
    let kind: CompletionEventKind
}

private struct SoundPreset {
    let name: String
    let fileName: String
}

private let soundPresets = [
    SoundPreset(name: "Neon Drift", fileName: "neon_drift.wav"),
    SoundPreset(name: "Glass Comet", fileName: "glass_comet.wav"),
    SoundPreset(name: "Orbit Tick", fileName: "orbit_tick.wav"),
    SoundPreset(name: "Nova Bloom", fileName: "nova_bloom.wav"),
    SoundPreset(name: "Quiet Vector", fileName: "quiet_vector.wav"),
    SoundPreset(name: "Ion Lantern", fileName: "ion_lantern.wav"),
    SoundPreset(name: "Prism Relay", fileName: "prism_relay.wav"),
    SoundPreset(name: "Blue Halo", fileName: "blue_halo.wav"),
    SoundPreset(name: "Star Current", fileName: "star_current.wav"),
    SoundPreset(name: "Velvet Radar", fileName: "velvet_radar.wav"),
]

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var pollTimer: Timer?
    private var lastSeenID: Int64 = 0
    private var lastPlayedAtMonotonic: TimeInterval = 0
    private var lastCompletionSignalAt: Double = 0
    private var lastFinalAnswerEventTime: Double = 0
    private var menu: NSMenu?
    private var volumeValueLabel: NSTextField?
    private var volumeSlider: NSSlider?
    private var soundMenu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ensureDirectories()
        loadState()
        configureStatusItem()
        startPolling()
        pollLogs()
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveState()
    }

    private func ensureDirectories() {
        try? FileManager.default.createDirectory(at: soundDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: presetsDir, withIntermediateDirectories: true)
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.image = makeStatusImage()
            button.toolTip = "Codex Completion Sonar"
        }

        let menu = NSMenu()
        let titleItem = NSMenuItem(title: "Codex Completion Sonar", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        let aboutItem = NSMenuItem(title: "About Codex Completion Sonar", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(makeVolumeMenuItem())

        let soundsItem = NSMenuItem(title: "Sounds", action: nil, keyEquivalent: "")
        let soundMenu = NSMenu()
        soundsItem.submenu = soundMenu
        self.soundMenu = soundMenu
        menu.addItem(soundsItem)
        rebuildSoundMenu()

        menu.addItem(NSMenuItem.separator())

        let testItem = NSMenuItem(title: "Play Test Sound", action: #selector(playTestSound), keyEquivalent: "")
        testItem.target = self
        menu.addItem(testItem)

        let openItem = NSMenuItem(title: "Open Sound Folder", action: #selector(openSoundFolder), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Codex Completion Sonar", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        self.menu = menu
        statusItem.menu = menu
    }

    private func makeVolumeMenuItem() -> NSMenuItem {
        let item = NSMenuItem()

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 54))

        let label = NSTextField(labelWithString: "Volume")
        label.frame = NSRect(x: 14, y: 30, width: 100, height: 16)
        container.addSubview(label)

        let valueLabel = NSTextField(labelWithString: "")
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: 180, y: 30, width: 64, height: 16)
        container.addSubview(valueLabel)
        volumeValueLabel = valueLabel

        let slider = NSSlider(value: currentVolumeValue(), minValue: 0.0, maxValue: 1.0, target: self, action: #selector(volumeSliderChanged(_:)))
        slider.frame = NSRect(x: 14, y: 8, width: 230, height: 18)
        slider.numberOfTickMarks = 11
        slider.allowsTickMarkValuesOnly = false
        container.addSubview(slider)
        volumeSlider = slider
        updateVolumeUI()

        item.view = container
        return item
    }

    private func rebuildSoundMenu() {
        guard let soundMenu else { return }
        soundMenu.removeAllItems()

        let selectedFileName = selectedSoundFileName()

        for preset in soundPresets {
            let item = NSMenuItem(title: preset.name, action: #selector(selectSoundPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.fileName
            item.state = preset.fileName == selectedFileName ? .on : .off
            soundMenu.addItem(item)
        }
    }

    private func makeStatusImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let ink = NSColor.labelColor
        ink.setStroke()
        ink.setFill()

        // Left bracket.
        let leftBracket = NSBezierPath()
        leftBracket.lineWidth = 1.55
        leftBracket.move(to: NSPoint(x: 4.7, y: 4.1))
        leftBracket.line(to: NSPoint(x: 2.8, y: 9.0))
        leftBracket.line(to: NSPoint(x: 4.7, y: 13.9))
        leftBracket.stroke()

        // Center slash for the terminal/code feel.
        let slash = NSBezierPath()
        slash.lineWidth = 1.45
        slash.move(to: NSPoint(x: 7.9, y: 4.2))
        slash.line(to: NSPoint(x: 9.6, y: 13.8))
        slash.stroke()

        // Right bracket.
        let rightBracket = NSBezierPath()
        rightBracket.lineWidth = 1.55
        rightBracket.move(to: NSPoint(x: 11.2, y: 4.1))
        rightBracket.line(to: NSPoint(x: 13.1, y: 9.0))
        rightBracket.line(to: NSPoint(x: 11.2, y: 13.9))
        rightBracket.stroke()

        // Matrix-style code rain bars.
        let rainBars: [(CGFloat, CGFloat, CGFloat)] = [
            (14.8, 11.4, 2.5),
            (14.8, 7.9, 1.6),
            (16.2, 12.8, 1.1),
            (16.2, 9.5, 2.1),
            (16.2, 6.1, 1.3),
        ]
        for (x, y, height) in rainBars {
            let bar = NSBezierPath(
                roundedRect: NSRect(x: x, y: y, width: 1.0, height: height),
                xRadius: 0.45,
                yRadius: 0.45
            )
            bar.fill()
        }

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.pollLogs()
        }
        if let pollTimer {
            RunLoop.main.add(pollTimer, forMode: .common)
        }
    }

    private func pollLogs() {
        autoreleasepool {
            guard let db = openDatabase() else { return }
            defer { sqlite3_close(db) }

            if lastSeenID == 0 {
                lastSeenID = latestID(in: db)
                saveState()
                return
            }

            let events = fetchCompletionEvents(in: db, afterID: lastSeenID)
            guard !events.isEmpty else { return }

            for event in events {
                if event.kind == .legacyTurnCompleted,
                   lastFinalAnswerEventTime > 0,
                   event.eventTime - lastFinalAnswerEventTime <= legacySuppressionWindowSeconds {
                    lastCompletionSignalAt = event.eventTime
                    lastSeenID = event.id
                    continue
                }

                let now = ProcessInfo.processInfo.systemUptime
                if event.eventTime - lastCompletionSignalAt >= mergeCompletionSignalsSeconds,
                   now - lastPlayedAtMonotonic >= minPlayGapSeconds {
                    playSound()
                    lastPlayedAtMonotonic = now
                }
                if event.kind == .finalAnswer {
                    lastFinalAnswerEventTime = event.eventTime
                }
                lastCompletionSignalAt = event.eventTime
                lastSeenID = event.id
            }

            saveState()
        }
    }

    private func openDatabase() -> OpaquePointer? {
        var db: OpaquePointer?
        if sqlite3_open_v2(logDB.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK {
            return db
        }
        if let db {
            sqlite3_close(db)
        }
        return nil
    }

    private func latestID(in db: OpaquePointer) -> Int64 {
        let sql = "select coalesce(max(id), 0) from logs"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return 0
        }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }
        return sqlite3_column_int64(statement, 0)
    }

    private func fetchCompletionEvents(in db: OpaquePointer, afterID: Int64) -> [CompletionEvent] {
        let sql = """
        select
            id,
            ts + (ts_nanos / 1000000000.0) as event_time,
            case
                when target = 'log' then 'final_answer'
                else 'legacy_turn_completed'
            end as event_kind
        from logs
        where id > ?
          and (
                (
                    target = 'log'
                    and feedback_log_body like 'Received message {"type":"response.output_item.done"%'
                    and feedback_log_body like '%"phase":"final_answer"%'
                    and feedback_log_body like '%"role":"assistant"%'
                    and feedback_log_body like '%"type":"message"%'
                )
             or (
                    target = 'codex_app_server::outgoing_message'
                    and feedback_log_body like 'app-server event: turn/completed%'
                )
          )
        order by id asc
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }

        sqlite3_bind_int64(statement, 1, afterID)

        var results: [CompletionEvent] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            let eventTime = sqlite3_column_double(statement, 1)
            let rawKind = sqlite3_column_text(statement, 2).flatMap { String(cString: $0) } ?? "legacy_turn_completed"
            let kind: CompletionEventKind = rawKind == "final_answer" ? .finalAnswer : .legacyTurnCompleted
            results.append(CompletionEvent(id: id, eventTime: eventTime, kind: kind))
        }
        return results
    }

    private func saveState() {
        let state: [String: Int64] = ["last_seen_id": lastSeenID]
        guard let data = try? JSONSerialization.data(withJSONObject: state, options: []) else { return }
        try? data.write(to: stateFile, options: .atomic)
    }

    private func loadState() {
        guard let data = try? Data(contentsOf: stateFile),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let lastSeen = object["last_seen_id"] as? NSNumber else {
            return
        }
        lastSeenID = lastSeen.int64Value
    }

    private func currentSoundURL() -> URL? {
        let selectedPresetURL = presetsDir.appendingPathComponent(selectedSoundFileName())
        if FileManager.default.fileExists(atPath: selectedPresetURL.path) {
            return selectedPresetURL
        }

        for name in soundCandidates {
            let candidate = soundDir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private func selectedSoundFileName() -> String {
        if let text = try? String(contentsOf: currentSoundFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           soundPresets.contains(where: { $0.fileName == text }) {
            return text
        }
        let fallback = soundPresets.first?.fileName ?? "neon_drift.wav"
        try? fallback.write(to: currentSoundFile, atomically: true, encoding: .utf8)
        return fallback
    }

    private func setSelectedSoundFileName(_ fileName: String) {
        try? fileName.write(to: currentSoundFile, atomically: true, encoding: .utf8)
        rebuildSoundMenu()
    }

    private func currentVolumeValue() -> Double {
        guard let text = try? String(contentsOf: volumeFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              let value = Double(text) else {
            return 0.35
        }
        return min(1.0, max(0.0, value))
    }

    private func currentVolume() -> String {
        String(currentVolumeValue())
    }

    private func updateVolumeUI() {
        let volume = currentVolumeValue()
        volumeSlider?.doubleValue = volume
        volumeValueLabel?.stringValue = "\(Int((volume * 100).rounded()))%"
    }

    private func playSound() {
        guard let soundURL = currentSoundURL() else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        process.arguments = ["-v", currentVolume(), soundURL.path]
        try? process.run()
    }

    @objc private func playTestSound() {
        playSound()
    }

    @objc private func volumeSliderChanged(_ sender: NSSlider) {
        let clamped = min(1.0, max(0.0, sender.doubleValue))
        let formatted = String(format: "%.3f", clamped)
        try? formatted.write(to: volumeFile, atomically: true, encoding: .utf8)
        updateVolumeUI()
    }

    @objc private func selectSoundPreset(_ sender: NSMenuItem) {
        guard let fileName = sender.representedObject as? String else { return }
        setSelectedSoundFileName(fileName)
        playSound()
    }

    @objc private func openSoundFolder() {
        NSWorkspace.shared.open(soundDir)
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Codex Completion Sonar"
        alert.informativeText = """
        A standalone menu bar utility for Codex completion sounds.

        It watches final Codex replies, lets you switch between custom presets, and stores volume and sound selection locally in ~/.codex/completion_sound.

        The included sounds are generated with code: AI-made sounds for an AI workflow.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
