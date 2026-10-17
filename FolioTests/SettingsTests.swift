import Foundation
import Testing
@testable import Folio

struct SettingsTests {
    @Test func clampKeepsTheThresholdInRangeAndFallsBackOnGarbage() {
        #expect(Settings.clamp(0.1) == 0.4)
        #expect(Settings.clamp(2) == 0.95)
        #expect(Settings.clamp(0.7) == 0.7)
        #expect(Settings.clamp(.nan) == defaultConfidenceThreshold)
    }
}
