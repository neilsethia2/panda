import AppKit
import Foundation

// panda-host: the native-messaging bridge between the Panda browser extension and the Panda app.
// Chrome starts this process when the extension connects and talks to it over stdin/stdout
// using length-prefixed JSON. It sits blocked on a read (zero CPU) until the extension asks
// whether a tab should be closed.

let input = FileHandle.standardInput
let output = FileHandle.standardOutput

func readExactly(_ count: Int) -> Data? {
    var buffer = Data()
    while buffer.count < count {
        let chunk = input.readData(ofLength: count - buffer.count)
        if chunk.isEmpty { return nil }
        buffer.append(chunk)
    }
    return buffer
}

func readMessage() -> [String: Any]? {
    guard let header = readExactly(4) else { return nil }
    let bytes = [UInt8](header)
    let length = Int(bytes[0]) | (Int(bytes[1]) << 8) | (Int(bytes[2]) << 16) | (Int(bytes[3]) << 24)
    guard length > 0, length < 1_048_576, let body = readExactly(length) else { return nil }
    return (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
}

let outputLock = NSLock()

func writeMessage(_ message: [String: Any]) {
    guard let body = try? JSONSerialization.data(withJSONObject: message) else { return }
    outputLock.lock()
    defer { outputLock.unlock() }
    let length = UInt32(body.count)
    var header = Data(count: 4)
    header[0] = UInt8(length & 0xff)
    header[1] = UInt8((length >> 8) & 0xff)
    header[2] = UInt8((length >> 16) & 0xff)
    header[3] = UInt8((length >> 24) & 0xff)
    output.write(header)
    output.write(body)
}

func appIsRunning() -> Bool {
    if ProcessInfo.processInfo.environment["PANDA_ASSUME_APP_RUNNING"] == "1" { return true }
    return !NSRunningApplication.runningApplications(withBundleIdentifier: PandaPaths.bundleID).isEmpty
}

/// Tell the app something happened. The payload rides in the notification's object string,
/// which macOS always delivers between processes.
func notifyApp(_ payload: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: payload),
          let json = String(data: data, encoding: .utf8) else { return }
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name(PandaPaths.eventNotification),
        object: json,
        userInfo: nil,
        deliverImmediately: true
    )
    DebugLog.write("posted \(payload["event"] as? String ?? "?") \(payload["kind"] as? String ?? "?")")
}

// Which browser launched us. The extension works in any Chromium browser, so we look it up.
let parent = NSRunningApplication(processIdentifier: getppid())
let browserBundle = parent?.bundleIdentifier ?? "unknown.browser"
let browserName = parent?.localizedName ?? "your browser"

// Presence file: lets the app know this browser has a live extension, so it does not also
// need to watch that browser through macOS Automation.
let presenceFile = PandaPaths.presenceDir.appendingPathComponent("\(getpid()).json")
try? FileManager.default.createDirectory(at: PandaPaths.presenceDir, withIntermediateDirectories: true)
if let data = try? JSONSerialization.data(withJSONObject: [
    "pid": Int(getpid()),
    "bundle": browserBundle,
    "name": browserName,
]) {
    try? data.write(to: presenceFile, options: .atomic)
}

// The extension keeps a copy of the host names on the user's blocklist, so ordinary browsing
// never has to be sent here. When the app rewrites its settings file, tell the extension.
// This is a kernel file-system event on the folder, not a timer: it costs nothing while idle.
var lastSentHosts: [String] = SharedSettings.load().customHosts
let hostsLock = NSLock()

func pushSitesIfChanged() {
    let hosts = SharedSettings.load().customHosts
    hostsLock.lock()
    let changed = hosts != lastSentHosts
    if changed { lastSentHosts = hosts }
    hostsLock.unlock()
    if changed {
        writeMessage(["type": "sites", "hosts": hosts])
        DebugLog.write("pushed \(hosts.count) blocklist hosts")
    }
}

PandaPaths.ensureSupportDir()
let watchDescriptor = open(PandaPaths.supportDir.path, O_EVTONLY)
var settingsWatcher: DispatchSourceFileSystemObject?
if watchDescriptor >= 0 {
    let source = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: watchDescriptor,
        eventMask: [.write, .rename, .delete],
        queue: DispatchQueue.global(qos: .utility)
    )
    source.setEventHandler { pushSitesIfChanged() }
    source.resume()
    settingsWatcher = source
}

func number(_ value: Any?) -> Double? {
    if let d = value as? Double { return d }
    if let i = value as? Int { return Double(i) }
    if let n = value as? NSNumber { return n.doubleValue }
    return nil
}

while let message = readMessage() {
    let type = message["type"] as? String ?? ""
    switch type {
    case "hello":
        let hosts = SharedSettings.load().customHosts
        hostsLock.lock()
        lastSentHosts = hosts
        hostsLock.unlock()
        writeMessage([
            "type": "hello",
            "appRunning": appIsRunning(),
            "browser": browserName,
            "hosts": hosts,
        ])

    case "check":
        let id = message["id"] ?? 0
        let url = message["url"] as? String ?? ""
        let running = appIsRunning()
        let settings = SharedSettings.load()
        let kind = running ? Rules.verdict(for: url, settings: settings) : nil
        let delay = kind == nil ? 0 : max(0, min(settings.closeDelayMs, 2000))

        writeMessage([
            "type": "verdict",
            "id": id,
            "block": kind != nil,
            "kind": kind?.rawValue ?? "",
            "delayMs": delay,
            "appRunning": running,
        ])

        if let kind = kind {
            // Geometry only. The page address stays inside this process.
            var payload: [String: Any] = [
                "event": "caught",
                "kind": kind.rawValue,
                "bundle": browserBundle,
                "browser": browserName,
                "delayMs": delay,
            ]
            for key in ["left", "top", "width", "index", "count", "pinned"] {
                if let value = number(message[key]) { payload[key] = value }
            }
            notifyApp(payload)
        }

    case "closed":
        let kind = message["kind"] as? String ?? ""
        notifyApp([
            "event": "closed",
            "kind": kind,
            "bundle": browserBundle,
            "browser": browserName,
        ])

    default:
        break
    }
}

// The browser closed the pipe (it quit, or the extension was reloaded). Give the last
// notification a moment to leave this process before exiting.
Thread.sleep(forTimeInterval: 0.3)
try? FileManager.default.removeItem(at: presenceFile)
