import Foundation
import IOKit

/// Opt-in Apple Silicon thermal & clock reader.
/// Uses dynamic `IOKit` HID event system symbol lookup (`dlopen`/`dlsym`), fail-closed when
/// symbols or sensors are unavailable on a host machine.
enum AppleSiliconSensorReader {
    private typealias CreateClientFn = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatchingFn = @convention(c) (AnyObject, CFDictionary) -> Void
    private typealias CopyServicesFn = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyPropertyFn = @convention(c) (AnyObject, CFString) -> Unmanaged<AnyObject>?
    private typealias CopyEventFn = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias GetFloatValueFn = @convention(c) (AnyObject, Int32) -> Double

    private static let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
    private static let kIOHIDEventTypeTemperature: Int64 = 15
    private static let kIOHIDEventFieldTemperatureLevel: Int32 = 15 << 16

    static var isSupported: Bool {
        handle != nil
            && dlsym(handle, "IOHIDEventSystemClientCreate") != nil
            && dlsym(handle, "IOHIDEventSystemClientSetMatching") != nil
            && dlsym(handle, "IOHIDEventSystemClientCopyServices") != nil
            && dlsym(handle, "IOHIDServiceClientCopyProperty") != nil
            && dlsym(handle, "IOHIDServiceClientCopyEvent") != nil
            && dlsym(handle, "IOHIDEventGetFloatValue") != nil
    }

    /// Reads the median/representative SoC temperature in Celsius from Apple Silicon HID thermal sensors
    /// (typically `PMU tdie*` / `SOC MTR Temp Sensor*`), or `nil` when unavailable.
    static func readSoCTemperatureCelsius() -> Double? {
        guard let h = handle,
              let createSym = dlsym(h, "IOHIDEventSystemClientCreate"),
              let matchSym = dlsym(h, "IOHIDEventSystemClientSetMatching"),
              let servicesSym = dlsym(h, "IOHIDEventSystemClientCopyServices"),
              let propSym = dlsym(h, "IOHIDServiceClientCopyProperty"),
              let eventSym = dlsym(h, "IOHIDServiceClientCopyEvent"),
              let floatSym = dlsym(h, "IOHIDEventGetFloatValue")
        else {
            return nil
        }

        let createClient = unsafeBitCast(createSym, to: CreateClientFn.self)
        let setMatching = unsafeBitCast(matchSym, to: SetMatchingFn.self)
        let copyServices = unsafeBitCast(servicesSym, to: CopyServicesFn.self)
        let copyProperty = unsafeBitCast(propSym, to: CopyPropertyFn.self)
        let copyEvent = unsafeBitCast(eventSym, to: CopyEventFn.self)
        let getFloatValue = unsafeBitCast(floatSym, to: GetFloatValueFn.self)

        guard let client = createClient(kCFAllocatorDefault)?.takeRetainedValue() else { return nil }
        let matching: [String: Any] = [
            "PrimaryUsagePage": 0xFF00,
            "PrimaryUsage": 5
        ]
        setMatching(client, matching as CFDictionary)
        guard let cfServices = copyServices(client)?.takeRetainedValue() else { return nil }
        let services = cfServices as [AnyObject]

        var readings: [Double] = []
        for service in services {
            let name = (copyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String) ?? ""
            guard let event = copyEvent(service, kIOHIDEventTypeTemperature, 0, 0)?.takeRetainedValue() else {
                continue
            }
            let celsius = getFloatValue(event, kIOHIDEventFieldTemperatureLevel)
            guard celsius.isFinite, celsius > 5, celsius < 130 else { continue }
            if name.localizedCaseInsensitiveContains("tdie")
                || name.localizedCaseInsensitiveContains("soc")
                || name.localizedCaseInsensitiveContains("cpu") {
                readings.append(celsius)
            } else if readings.isEmpty {
                readings.append(celsius)
            }
        }

        guard !readings.isEmpty else { return nil }
        let sorted = readings.sorted()
        return sorted[sorted.count / 2]
    }

    /// Reads nominal CPU clock in GHz when reported by `hw.cpufrequency` (Intel) or `hw.cpufrequency_max`;
    /// returns `nil` if the host does not expose frequency via sysctl.
    static func nominalFrequencyGHz() -> Double? {
        for key in ["hw.cpufrequency", "hw.cpufrequency_max"] {
            var hz: UInt64 = 0
            var size = MemoryLayout<UInt64>.size
            if sysctlbyname(key, &hz, &size, nil, 0) == 0, hz > 0 {
                return Double(hz) / 1_000_000_000.0
            }
        }
        return nil
    }
}
