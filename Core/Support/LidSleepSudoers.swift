import Foundation

/// The one sudoers rule the lid-closed mode installs: this user may run exactly two `pmset` commands as root
/// without a password. Returns nil for a user name that is not a plain account name, so a odd name can never
/// widen the rule or break out of the shell command that writes it.
enum LidSleepSudoers {
    static let path = "/etc/sudoers.d/katikati-keepawake"

    static func rule(user: String) -> String? {
        guard !user.isEmpty, user.count <= 32,
              user.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }),
              !user.hasPrefix("-") else { return nil }
        return "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0"
    }
}
