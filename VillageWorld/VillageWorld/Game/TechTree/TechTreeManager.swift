//
//  TechTreeManager.swift
//  VillageWorld
//
//  Manages the village's tech tree — all discoveries made through
//  Researcher and Farmer interactions. Tracks which items have been
//  researched, which are buildable, and which have been built.
//

import Foundation

@MainActor
final class TechTreeManager: ObservableObject {

    @Published private(set) var entries: [TechTreeEntry] = []

    // MARK: - Add Entry

    /// Creates a tech tree entry from AI-generated requirements.
    @discardableResult
    func addEntry(
        from reqs: GeneratedRequirements,
        category: TechCategory,
        createdBy: UUID
    ) -> TechTreeEntry {
        // Avoid duplicates by name
        if let existing = entries.first(where: {
            $0.name.lowercased() == reqs.itemName.lowercased()
        }) {
            return existing
        }

        let entry = TechTreeEntry(
            name: reqs.itemName,
            description: reqs.description,
            category: category,
            requirements: reqs.requirements,
            buildTimeMinutes: reqs.buildTimeMinutes,
            difficulty: reqs.difficulty,
            createdBy: createdBy
        )
        entries.append(entry)
        return entry
    }

    // MARK: - Queries

    /// Whether the village has enough resources to build this entry.
    func canBuild(_ entry: TechTreeEntry, resources: [String: Int]) -> Bool {
        guard entry.status != .built else { return false }
        for req in entry.requirements {
            let available = resources[req.resource.capitalized] ?? resources[req.resource] ?? 0
            if available < req.amount { return false }
        }
        return true
    }

    /// Returns entries that a Worker can build right now.
    func buildableEntries(resources: [String: Int]) -> [TechTreeEntry] {
        entries.filter { $0.status != .built && canBuild($0, resources: resources) }
    }

    /// Update status to reflect current resource availability.
    func refreshStatuses(resources: [String: Int]) {
        for i in entries.indices where entries[i].status != .built {
            entries[i].status = canBuild(entries[i], resources: resources)
                ? .requirementsMet
                : .researched
        }
    }

    // MARK: - Build

    /// Mark an entry as built and return the resources to deduct.
    func markBuilt(_ entryID: UUID) -> [ResourceRequirement]? {
        guard let idx = entries.firstIndex(where: { $0.id == entryID }) else {
            return nil
        }
        entries[idx].status = .built
        return entries[idx].requirements
    }

    // MARK: - Convenience accessors

    var knownTechnologies: [String] {
        entries.filter { $0.category == .technology }.map(\.name)
    }

    var knownCrops: [String] {
        entries.filter { $0.category == .crop }.map(\.name)
    }

    var knownAnimals: [String] {
        entries.filter { $0.category == .animal }.map(\.name)
    }
}
