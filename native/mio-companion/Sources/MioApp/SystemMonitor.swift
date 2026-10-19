import AppKit
import Network
import IOKit.ps
import MioCore

@MainActor final class SystemMonitor {
    let emit: (SystemEvent) -> Void
    let inbox: URL
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var timer: Timer?
    private var network: NWPathMonitor?
    private var lastNetwork: String?
    private var lastPower: String?
    private var breakStarted = Date()
    init(inbox: URL, emit: @escaping (SystemEvent) -> Void) { self.inbox = inbox; self.emit = emit }
    func start() {
        guard timer == nil else { return }
        breakStarted = Date()
        let workspace = NSWorkspace.shared.notificationCenter
        func observe(_ center: NotificationCenter, _ name: Notification.Name, _ handler: @escaping @MainActor (Notification) -> Void) {
            observers.append((center, center.addObserver(forName: name, object: nil, queue: .main) { note in
                MainActor.assumeIsolated { handler(note) }
            }))
        }
        for (name, kind, label) in [
            (NSWorkspace.didActivateApplicationNotification, "app.active", "切换应用"),
            (NSWorkspace.didLaunchApplicationNotification, "app.launch", "应用启动"),
            (NSWorkspace.didTerminateApplicationNotification, "app.quit", "应用退出")
        ] {
            observe(workspace, name) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier != Bundle.main.bundleIdentifier,
                      app.activationPolicy == .regular else { return }
                self?.emit(SystemEvent(kind: kind, summary: "\(label) · \(app.localizedName ?? "应用")",
                                       metadata: ["bundle_id": app.bundleIdentifier ?? "unknown"]))
            }
        }
        for (name, kind, label) in [
            (NSWorkspace.didWakeNotification, "wake", "电脑已唤醒"),
            (NSWorkspace.willSleepNotification, "sleep", "电脑即将睡眠"),
            (NSWorkspace.sessionDidBecomeActiveNotification, "session.active", "会话恢复"),
            (NSWorkspace.sessionDidResignActiveNotification, "session.inactive", "会话已离开"),
            (NSWorkspace.didMountNotification, "volume.mount", "存储设备已挂载"),
            (NSWorkspace.didUnmountNotification, "volume.unmount", "存储设备已移除")
        ] {
            observe(workspace, name) { [weak self] _ in
                if kind == "wake" { self?.breakStarted = Date() }
                self?.emit(SystemEvent(kind: kind, summary: label))
            }
        }
        observe(NotificationCenter.default, ProcessInfo.thermalStateDidChangeNotification) { [weak self] _ in
            let value = ProcessInfo.processInfo.thermalState.rawValue
            self?.emit(SystemEvent(kind: "thermal", summary: "温度状态改变", metadata: ["level": String(value)]))
        }
        let path = NWPathMonitor()
        path.pathUpdateHandler = { [weak self] update in
            let status = update.status == .satisfied ? "online" : "offline"
            Task { @MainActor in
                guard let self, status != self.lastNetwork else { return }
                self.lastNetwork = status
                self.emit(SystemEvent(kind: "network", summary: status == "online" ? "网络已连接" : "网络已断开", metadata: ["status": status]))
            }
        }
        network = path; path.start(queue: DispatchQueue(label: "io.harumachi.mio.network"))
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        tick()
    }
    func stop() {
        observers.forEach { $0.0.removeObserver($0.1) }; observers.removeAll()
        timer?.invalidate(); timer = nil
        network?.cancel(); network = nil
    }
    private func tick() {
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let power = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?, power != lastPower {
            lastPower = power
            emit(SystemEvent(kind: "power", summary: power == kIOPSACPowerValue ? "使用外接电源" : "使用电池", metadata: ["source": power]))
        }
        if Date().timeIntervalSince(breakStarted) >= 45 * 60 {
            breakStarted = Date(); emit(SystemEvent(kind: "break.due", summary: "已陪伴工作 45 分钟"))
        }
        readInbox()
    }
    private func readInbox() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: inbox, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { return }
        for file in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).prefix(20) {
            guard let attrs = try? file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]),
                  attrs.isSymbolicLink == false, attrs.isRegularFile == true, (attrs.fileSize ?? Int.max) <= 8192 else { continue }
            let processed = inbox.appendingPathComponent(".processed", isDirectory: true)
            try? fm.createDirectory(at: processed, withIntermediateDirectories: true)
            let destination = processed.appendingPathComponent(UUID().uuidString + ".json")
            // Claim the file before reading; producers must use an atomic rename into the inbox.
            do {
                try fm.moveItem(at: file, to: destination)
                let data = try Data(contentsOf: destination)
                guard data.count <= 8192, let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let text = body["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    try? fm.removeItem(at: destination); continue
                }
                emit(SystemEvent(kind: "message", summary: text, metadata: ["source": "inbox"]))
                // Messages are transient, not a second persistent activity log.
                try? fm.removeItem(at: destination)
            } catch { try? fm.removeItem(at: destination) }
        }
    }
}
