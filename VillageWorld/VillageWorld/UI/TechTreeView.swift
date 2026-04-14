//
//  TechTreeView.swift
//  VillageWorld
//
//  Displays all discovered tech tree entries with their status
//  and resource requirements. Accessible from the HUD.
//

import SwiftUI

struct TechTreeView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if appState.techTreeManager.entries.isEmpty {
                emptyState
            } else {
                entryList
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
        .padding(.vertical, 60)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label("Tech Tree", systemImage: "book.closed.fill")
                .font(.system(.headline, design: .monospaced))
            Spacer()
            Button {
                appState.isTechTreeVisible = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }
        }
        .padding(14)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No discoveries yet")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("Talk to the Researcher or Farmer\nto start discovering!")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    // MARK: - Entry List

    private var entryList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(appState.techTreeManager.entries) { entry in
                    entryCard(entry)
                }
            }
            .padding(12)
        }
    }

    // MARK: - Entry Card

    private func entryCard(_ entry: TechTreeEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: categoryIcon(entry.category))
                    .foregroundStyle(categoryColor(entry.category))
                Text(entry.name)
                    .font(.system(.subheadline, design: .monospaced).bold())
                Spacer()
                statusBadge(entry.status)
            }

            Text(entry.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            // Requirements
            HStack(spacing: 6) {
                ForEach(entry.requirements, id: \.resource) { req in
                    let available = appState.resources[req.resource.capitalized] ?? appState.resources[req.resource] ?? 0
                    let met = available >= req.amount

                    HStack(spacing: 3) {
                        Image(systemName: met ? "checkmark.circle.fill" : "circle")
                            .font(.caption2)
                            .foregroundStyle(met ? .green : .red)
                        Text("\(req.amount) \(req.resource)")
                            .font(.caption2)
                    }
                }
            }

            // Difficulty + build time
            HStack {
                Text(entry.difficulty.rawValue.capitalized)
                    .font(.caption2.bold())
                    .foregroundStyle(difficultyColor(entry.difficulty))
                Text("~\(entry.buildTimeMinutes) min")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Helpers

    private func categoryIcon(_ cat: TechCategory) -> String {
        switch cat {
        case .technology: return "gearshape.fill"
        case .crop:       return "leaf.fill"
        case .animal:     return "hare.fill"
        }
    }

    private func categoryColor(_ cat: TechCategory) -> Color {
        switch cat {
        case .technology: return .purple
        case .crop:       return .green
        case .animal:     return .orange
        }
    }

    private func statusBadge(_ status: TechStatus) -> some View {
        let (text, color): (String, Color) = {
            switch status {
            case .researched:      return ("Researched", .gray)
            case .requirementsMet: return ("Ready", .blue)
            case .built:           return ("Built", .green)
            }
        }()

        return Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(color)
    }

    private func difficultyColor(_ d: Difficulty) -> Color {
        switch d {
        case .easy:   return .green
        case .medium: return .orange
        case .hard:   return .red
        }
    }
}
