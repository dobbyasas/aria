import Foundation

extension TimeInterval {
    var ariaClockTime: String {
        guard isFinite, self >= 0 else { return "0:00" }

        let totalSeconds = Int(self.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        return String(format: "%d:%02d", minutes, seconds)
    }
}
