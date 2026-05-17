import Foundation

enum RoutineOrdering {
    /// Apply a drag-reorder on a pre-sorted list and re-assign `sortIndex` contiguously
    /// (0..<n) so `nextSortIndex` (max + 1) keeps producing monotonic appends.
    static func reorder(
        sortedRoutines: [FreeTimeRoutine],
        from source: IndexSet,
        to destination: Int
    ) -> [FreeTimeRoutine] {
        var working = sortedRoutines
        working.move(fromOffsets: source, toOffset: destination)
        for index in working.indices {
            working[index].sortIndex = index
        }
        return working
    }
}
