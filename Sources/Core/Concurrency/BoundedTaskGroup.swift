import Foundation

func boundedConcurrentMap<Input: Sendable, Output: Sendable>(
    _ inputs: [Input],
    limit: Int,
    operation: @escaping @Sendable (Input) async -> Output
) async -> [Output] {
    guard !inputs.isEmpty else { return [] }
    let boundedLimit = max(1, min(limit, inputs.count))

    return await withTaskGroup(of: Output.self, returning: [Output].self) { group in
        var iterator = inputs.makeIterator()
        var results: [Output] = []
        results.reserveCapacity(inputs.count)

        for _ in 0..<boundedLimit {
            guard let input = iterator.next() else { break }
            group.addTask { await operation(input) }
        }

        while let result = await group.next() {
            results.append(result)
            if let input = iterator.next() {
                group.addTask { await operation(input) }
            }
        }
        return results
    }
}
