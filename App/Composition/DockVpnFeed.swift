import Combine
import Foundation

/// Ref-counted live feed for the Dock II VPN Status wing card.
/// Polls `VPNServiceParser` + `SystemMonitorSampler.network()` at 1 Hz only while retained on screen.
@MainActor
final class DockVpnFeed: ObservableObject {
    static let shared = DockVpnFeed()

    @Published private(set) var state = DockVpnStatusState()
    @Published private(set) var profiles: [VPNServiceParser.Entry] = []
    @Published private(set) var isToggling = false
    @Published private(set) var geoIPLocation: GeoIPLocation?

    private var timer: Timer?
    private var holders = 0
    private var lastNet: NetCounters?
    private var lastSampleDate = Date()
    private var lastConnectedForGeoIP: Bool?
    private var lastGeoIPAttemptDate: Date = .distantPast
    private var tickCount = 0
    private var isGeoIPEnabled: Bool {
        UserDefaults.standard.bool(forKey: "com.katikati.dockII.vpnGeoIPEnabled")
    }

    private init() {}

    func retain() {
        holders += 1
        guard timer == nil else { return }
        lastNet = SystemMonitorSampler.network()
        lastSampleDate = Date()
        tickCount = 0
        refreshProfilesAndRates(forceGeoIP: true)
        let next = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        next.tolerance = 0.15
        timer = next
    }

    func release() {
        holders = max(0, holders - 1)
        guard holders == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    func toggleConnection() {
        guard !isToggling else { return }
        let targetOn = !state.isConnected
        isToggling = true
        Task.detached(priority: .userInitiated) {
            _ = VPNServiceParser.set(targetOn)
            let updatedProfiles = VPNServiceParser.list()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isToggling = false
                self.applyProfiles(updatedProfiles, forceGeoIP: true)
            }
        }
    }

    func refreshNow() {
        refreshProfilesAndRates(forceGeoIP: true)
    }

    private func tick() {
        tickCount += 1
        // Network counters tick every second; `scutil --nc list` spawns a process so run every 3 seconds.
        let now = Date()
        let net = SystemMonitorSampler.network()
        if let prev = lastNet {
            let rate = NetCounters.rate(from: prev, to: net, seconds: now.timeIntervalSince(lastSampleDate))
            state.downloadBytesPerSec = rate.down
            state.uploadBytesPerSec = rate.up
        }
        lastNet = net
        lastSampleDate = now

        if tickCount % 3 == 0 {
            refreshProfilesOnly(forceGeoIP: false)
        }
    }

    private func refreshProfilesAndRates(forceGeoIP: Bool) {
        tick()
        refreshProfilesOnly(forceGeoIP: forceGeoIP)
    }

    private func refreshProfilesOnly(forceGeoIP: Bool) {
        Task.detached(priority: .utility) {
            let list = VPNServiceParser.list()
            await MainActor.run { [weak self] in
                self?.applyProfiles(list, forceGeoIP: forceGeoIP)
            }
        }
    }

    private func applyProfiles(_ list: [VPNServiceParser.Entry], forceGeoIP: Bool) {
        profiles = list
        let active = list.first(where: \.connected)
        let connected = active != nil
        let previousConnected = lastConnectedForGeoIP
        lastConnectedForGeoIP = connected

        state.isConnected = connected
        state.profileName = active?.name ?? list.first?.name ?? ""

        if !isGeoIPEnabled {
            geoIPLocation = nil
            state.cityLabel = nil
            state.countryCode = nil
            return
        }

        let stateChanged = previousConnected != connected
        let cooldownElapsed = Date().timeIntervalSince(lastGeoIPAttemptDate) >= 15
        if (forceGeoIP || stateChanged) && cooldownElapsed {
            lastGeoIPAttemptDate = Date()
            Task { [weak self] in
                let loc = await GeoIPLookupService.fetchCurrentLocation()
                guard let self, self.isGeoIPEnabled else { return }
                self.geoIPLocation = loc
                self.state.cityLabel = loc?.formattedPlace
                self.state.countryCode = loc?.countryCode
            }
        }
    }
}
