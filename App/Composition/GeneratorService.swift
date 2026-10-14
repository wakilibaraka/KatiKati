import AppKit
import CoreWLAN
import Darwin

/// Phase 28b: the app-layer values for the system-backed generator rows (JSON / IP / Wi-Fi). The pure
/// generators delegate to `CommandGenerator.value()`. Everything is fail-closed — a missing value just
/// means no row. No shell-out except the keychain read for the Wi-Fi password.
enum GeneratorService {
    static func value(for generator: CommandGenerator) -> String? {
        switch generator {
        case .uuid, .nanoID, .loremIpsum: return generator.value()
        case .formatJSON: return clipboardJSON()
        case .ipAddress: return ipAddress()
        case .wifiPassword: return wifiPassword()
        }
    }

    /// Pretty-prints whatever JSON is on the clipboard.
    static func clipboardJSON() -> String? {
        guard let raw = NSPasteboard.general.string(forType: .string) else { return nil }
        return JSONPrettyPrinter.pretty(raw)
    }

    /// The primary IPv4 address (en0) via `getifaddrs` — in-process, no shell-out.
    static func ipAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var result: String?
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let interface = current.pointee
            if let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
               let name = String(validatingUTF8: interface.ifa_name), name == "en0" {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    result = String(cString: host)
                }
            }
            pointer = interface.ifa_next
        }
        return result
    }

    /// The current network's Wi-Fi password, read from the login keychain. Fail-closed (may need approval).
    static func wifiPassword() -> String? {
        guard let ssid = CWWiFiClient.shared().interface()?.ssid(), !ssid.isEmpty else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-D", "AirPort network password", "-a", ssid, "-w"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (text?.isEmpty == false) ? text : nil
    }
}
