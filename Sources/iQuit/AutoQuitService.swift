import AppKit
import Foundation

@MainActor
final class AutoQuitService {
    private var timer: Timer?
    var onTick: (() -> Void)?

    func start() {
        stop()
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.onTick?()
            }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
