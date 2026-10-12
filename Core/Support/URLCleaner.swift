import Foundation

// Phase 8e — pure link cleaner: strips known tracking query parameters from a copied URL.
//
// Only a conservative, well-known set is removed (`utm_*`, ad-click ids like `fbclid`/`gclid`, mail-campaign
// ids). Parameters that can change what a page shows (`ref`, `si`, `id`, `v`, `q`…) are never touched.
// Everything else about the URL — scheme, host, path, fragment, the encoding of the parameters that stay —
// is preserved byte for byte. Returns `nil` when there is nothing to clean, so callers can tell "leave the
// clipboard alone" from "rewrite it". Dual-compiled so every rule is unit-tested.

enum URLCleaner {
    static let trackingNames: Set<String> = [
        "fbclid", "gclid", "gbraid", "wbraid", "dclid", "msclkid", "yclid", "twclid", "ttclid",
        "mc_cid", "mc_eid", "igshid", "_hsenc", "_hsmi", "mkt_tok", "vero_id", "oly_enc_id", "oly_anon_id",
    ]

    static func isTracking(_ name: String) -> Bool {
        let lower = name.removingPercentEncoding?.lowercased() ?? name.lowercased()
        return lower.hasPrefix("utm_") || trackingNames.contains(lower)
    }

    /// The cleaned URL string, or `nil` if `text` isn't a single http(s) URL or has no tracking parameters.
    static func clean(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace),
              let comps = URLComponents(string: trimmed),
              let scheme = comps.scheme?.lowercased(), scheme == "http" || scheme == "https",
              comps.host?.isEmpty == false,
              let query = comps.percentEncodedQuery, !query.isEmpty else { return nil }

        let pairs = query.split(separator: "&", omittingEmptySubsequences: false).map(String.init)
        let kept = pairs.filter { pair in
            let name = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? pair
            return !isTracking(name)
        }
        guard kept.count != pairs.count else { return nil }

        var out = comps
        out.percentEncodedQuery = kept.isEmpty ? nil : kept.joined(separator: "&")
        return out.string
    }
}
