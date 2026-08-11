import Foundation

enum OrcaDeviceIdentity {
    private static let key = "pod.device_id"

    static func current(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: key), existing.count >= 16 {
            return existing
        }
        let value = UUID().uuidString
        defaults.set(value, forKey: key)
        return value
    }
}
