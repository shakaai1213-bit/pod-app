import Foundation

@MainActor
@Observable
final class SystemViewModel {
    var digest: ControlRoomDigestDTO?
    var runtimeRegistry: RuntimeRegistryDTO?
    var boards: [SystemBoardDTO] = []
    var isLoading = false
    var errorMessage: String?

    private let repository: SystemRepository

    init(repository: SystemRepository = SystemRepository()) {
        self.repository = repository
    }

    func load() async {
        await refresh()
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let digestResult = loadDigest()
        async let runtimeResult = loadRuntimeRegistry()
        async let boardsResult = loadBoards()

        let results = await [digestResult, runtimeResult, boardsResult]
        let failures = results.filter { !$0 }
        if !failures.isEmpty {
            errorMessage = failures.count == results.count
                ? "System view is unavailable."
                : "Some system sections could not refresh."
        }
    }

    private func loadDigest() async -> Bool {
        do {
            digest = try await repository.fetchControlRoomDigest()
            return true
        } catch {
            digest = nil
            return false
        }
    }

    private func loadRuntimeRegistry() async -> Bool {
        do {
            runtimeRegistry = try await repository.fetchRuntimeRegistry()
            return true
        } catch {
            runtimeRegistry = nil
            return false
        }
    }

    private func loadBoards() async -> Bool {
        do {
            boards = try await repository.fetchBoards()
            return true
        } catch {
            boards = []
            return false
        }
    }
}
