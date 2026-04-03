import Foundation

/// Prevent system sleep while external displays are connected (uses caffeinate process)
class SleepPreventer {
    private var process: Process?
    private(set) var isPreventing = false

    func preventSleep() {
        guard !isPreventing else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        p.arguments = ["-d"] // prevent display sleep
        try? p.run()
        process = p; isPreventing = true
    }

    func allowSleep() {
        process?.terminate(); process = nil; isPreventing = false
    }

    deinit { allowSleep() }
}
