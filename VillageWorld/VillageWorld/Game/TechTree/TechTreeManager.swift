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
            createdBy: createdBy,
            infrastructure: reqs.infrastructure
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

    /// Returns entries that a Worker can build right now (technology / infrastructure only).
    func buildableEntries(resources: [String: Int]) -> [TechTreeEntry] {
        entries.filter {
            $0.status != .built
            && $0.category == .technology
            && canBuild($0, resources: resources)
        }
    }

    /// Whether an entry's infrastructure prerequisite (if any) has been built.
    func isInfrastructureMet(_ entry: TechTreeEntry) -> Bool {
        guard let infra = entry.infrastructure, !infra.isEmpty else { return true }
        return entries.contains { $0.name.lowercased() == infra.lowercased() && $0.status == .built }
    }

    /// Returns crop/animal entries the Farmer can plant/place right now
    /// (resources met AND infrastructure built).
    func plantableEntries(resources: [String: Int]) -> [TechTreeEntry] {
        entries.filter {
            $0.status != .built
            && ($0.category == .crop || $0.category == .animal)
            && canBuild($0, resources: resources)
            && isInfrastructureMet($0)
        }
    }

    /// Returns crop/animal infrastructure entries that need to be built.
    var pendingInfrastructure: [String] {
        let needed = Set(
            entries
                .filter { ($0.category == .crop || $0.category == .animal) && $0.status != .built }
                .compactMap(\.infrastructure)
                .map { $0.lowercased() }
        )
        let built = Set(
            entries
                .filter { $0.status == .built }
                .map { $0.name.lowercased() }
        )
        return Array(needed.subtracting(built)).sorted()
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

    var knownComponents: [String] {
        entries.filter { $0.category == .component }.map(\.name)
    }

    /// Components that can be crafted right now (all resource requirements met).
    func craftableComponents(resources: [String: Int]) -> [TechTreeEntry] {
        entries.filter { $0.category == .component && $0.status != .built && canBuild($0, resources: resources) }
    }

    /// Mark a component as crafted: deduct resources, add 1 to the component resource count.
    /// Returns the resource costs to deduct, or nil if not found.
    func craftComponent(_ entryID: UUID) -> [ResourceRequirement]? {
        guard let idx = entries.firstIndex(where: { $0.id == entryID }),
              entries[idx].category == .component else { return nil }
        // Components stay craftable (don't mark as .built) — they're repeatable
        return entries[idx].requirements
    }
}
