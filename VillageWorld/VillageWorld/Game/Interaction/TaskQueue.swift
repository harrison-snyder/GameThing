//
//  TaskQueue.swift
//  VillageWorld
//
//  FIFO queue of GameTasks assigned to Worker characters.
//  Populated by the player interaction system in Phase 4.
//

import Foundation

final class TaskQueue {
    private(set) var tasks: [GameTask] = []

    var isEmpty: Bool { tasks.isEmpty }

    func enqueue(_ task: GameTask) {
        tasks.append(task)
    }

    @discardableResult
    func dequeue() -> GameTask? {
        guard !tasks.isEmpty else { return nil }
        return tasks.removeFirst()
    }

    func markComplete(id: UUID) {
        if let idx = tasks.firstIndex(where: { $0.id == id }) {
            tasks[idx].isComplete = true
        }
    }
}
