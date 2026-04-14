//
//  TaskQueue.swift
//  VillageWorld
//
//  Manages the queue of GameTasks assigned to Worker characters.
//  Tracks active tasks, updates progress, and fires completion callbacks.
//

import Foundation

final class TaskQueue {
    private(set) var tasks: [GameTask] = []

    /// Called when a task completes. GameScene/AppState wires this up.
    var onTaskCompleted: ((GameTask) -> Void)?

    var isEmpty: Bool { tasks.isEmpty }

    // MARK: - Queue Operations

    func enqueue(_ task: GameTask) {
        tasks.append(task)
    }

    /// Returns the next queued task for a given character, marking it in-progress.
    func dequeueNext(for characterID: UUID) -> GameTask? {
        guard let idx = tasks.firstIndex(where: {
            $0.assignedTo == characterID && $0.status == .queued
        }) else { return nil }
        tasks[idx].status = .inProgress
        return tasks[idx]
    }

    /// Returns the currently active task for a character.
    func activeTask(for characterID: UUID) -> GameTask? {
        tasks.first { $0.assignedTo == characterID && $0.status == .inProgress }
    }

    /// Returns all pending tasks for a character.
    func pendingTasks(for characterID: UUID) -> [GameTask] {
        tasks.filter { $0.assignedTo == characterID && $0.status == .queued }
    }

    // MARK: - Progress

    /// Advances task progress by delta. Returns true if the task just completed.
    @discardableResult
    func updateProgress(taskID: UUID, delta: Double) -> Bool {
        guard let idx = tasks.firstIndex(where: { $0.id == taskID }) else { return false }
        tasks[idx].progress = min(tasks[idx].progress + delta, 1.0)

        if tasks[idx].progress >= 1.0 {
            tasks[idx].status = .complete
            onTaskCompleted?(tasks[idx])
            return true
        }
        return false
    }

    // MARK: - Status

    func markComplete(id: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].status = .complete
        tasks[idx].progress = 1.0
        onTaskCompleted?(tasks[idx])
    }

    func markFailed(id: UUID, reason: String) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].status = .failed(reason: reason)
    }

    /// Remove completed/failed tasks from the list.
    func prune() {
        tasks.removeAll { task in
            if task.status == .complete { return true }
            if case .failed = task.status { return true }
            return false
        }
    }
}
