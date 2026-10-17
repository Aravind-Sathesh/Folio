import Foundation

/// User settings in UserDefaults. Read fresh on every use, so a change applies to the very next file.
enum Settings {
    static let thresholdKey = "confidenceThreshold"
    static let notifyKey = "notifyAboutReview"
    static let thresholdRange = 0.4...0.95

    static var threshold: Double {
        get { clamp(UserDefaults.standard.object(forKey: thresholdKey) as? Double ?? defaultConfidenceThreshold) }
        set { UserDefaults.standard.set(clamp(newValue), forKey: thresholdKey) }
    }

    static var notifyAboutReview: Bool {
        UserDefaults.standard.object(forKey: notifyKey) as? Bool ?? true
    }

    static func clamp(_ value: Double) -> Double {
        value.isFinite ? min(max(value, thresholdRange.lowerBound), thresholdRange.upperBound) : defaultConfidenceThreshold
    }
}
