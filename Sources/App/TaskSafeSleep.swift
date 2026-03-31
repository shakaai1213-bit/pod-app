import Foundation

/// Reliable async sleep that works on iOS 26 and inside task groups.
/// Task.sleep can fire immediately inside withThrowingTaskGroup on iOS 26.
/// This uses DispatchSemaphore as a wall-clock timer instead.
enum TaskSafeSleep {
    /// Sleep for the given number of seconds. Works reliably on iOS 26.
    /// - Parameter seconds: Duration in seconds
    static func sleep(seconds: Double) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                let semaphore = DispatchSemaphore(value: 0)
                DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                    semaphore.signal()
                }
                _ = semaphore.wait(timeout: .now() + seconds + 0.5)
                continuation.resume()
            }
        }
    }

    /// Sleep for the given nanoseconds. Works reliably on iOS 26.
    static func sleep(nanoseconds: UInt64) async {
        await sleep(seconds: Double(nanoseconds) / 1_000_000_000)
    }
}
