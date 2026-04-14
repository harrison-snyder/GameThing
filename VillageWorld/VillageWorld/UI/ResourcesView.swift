//
//  ResourcesView.swift
//  VillageWorld
//
//  Collapsible resource inventory panel, toggled from the HUD bag button.
//  Shows all resources (including AI-generated ones) with their current amounts.
//

import SwiftUI

struct ResourcesView: View {
    @EnvironmentObject var appState: AppState

    // Icons for known resource names; falls back to a generic cube
    private func icon(for resource: String) -> String {
        switch resource.lowercased() {
        // Raw materials
        case "wood":     return "tree.fill"
        case "stone":    return "square.fill"
        case "food":     return "leaf.circle.fill"
        case "water":    return "drop.fill"
        case "iron":     return "hammer.fill"
        case "grass":    return "leaf.fill"
        case "clay":     return "circle.fill"
        case "fiber":    return "line.3.horizontal"
        case "coal":     return "flame.fill"
        case "gold":     return "star.fill"
        case "copper":   return "circle.circle.fill"
        case "rubber":   return "seal.fill"
        case "silicon":  return "cpu"
        case "glass":    return "rectangle.fill"
        case "leather":  return "shield.fill"
        case "acid":     return "drop.triangle.fill"
        case "wire":     return "line.diagonal"
        case "sand":     return "square.3.layers.3d.down.right"
        // Components (crafted by Engineer)
        case "battery":  return "battery.100"
        case "motor":    return "gear.badge.checkmark"
        case "gear":     return "gearshape.fill"
        case "circuit":  return "cpu.fill"
        case "lens":     return "eye.fill"
        case "spring":   return "arrow.up.arrow.down"
        case "axle":     return "arrow.left.arrow.right"
        case "pipe":     return "pipe.and.drop.fill"
        case "piston":   return "arrow.up.and.down.square"
        default:         return "cube.fill"
        }
    }

    /// Whether a resource key matches a known component in the tech tree.
    private func isComponent(_ resource: String) -> Bool {
        appState.techTreeManager.entries
            .filter { $0.category == .component }
            .contains { $0.name.lowercased() == resource.lowercased() }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if appState.resources.isEmpty {
                emptyState
            } else {
                resourceList
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
        .padding(.top, 60)
        .padding(.bottom, 60)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label("Resources", systemImage: "bag.fill")
                .font(.system(.headline, design: .monospaced))
            Spacer()
            Text("Total: \(appState.resources.values.reduce(0, +))")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            Button {
                appState.isResourcesVisible = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }
            .padding(.leading, 8)
        }
        .padding(14)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bag")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No resources yet")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("Assign Stone (Worker) to gather tasks.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
    }

    // MARK: - Resource List

    private var resourceList: some View {
        let allKeys = appState.resources.keys.sorted()
        let componentKeys = allKeys.filter { isComponent($0) }
        let materialKeys  = allKeys.filter { !isComponent($0) }

        return ScrollView {
            LazyVStack(spacing: 6) {
                if !materialKeys.isEmpty {
                    sectionHeader("Raw Materials")
                    ForEach(materialKeys, id: \.self) { key in
                        resourceRow(key: key)
                    }
                }
                if !componentKeys.isEmpty {
                    sectionHeader("Components")
                        .padding(.top, 8)
                    ForEach(componentKeys, id: \.self) { key in
                        resourceRow(key: key)
                    }
                }
            }
            .padding(12)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(.caption, design: .monospaced).bold())
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
    }

    private func resourceRow(key: String) -> some View {
        let amount = appState.resources[key] ?? 0
        let needed = totalNeeded(for: key)
        let comp = isComponent(key)

        return HStack(spacing: 12) {
            Image(systemName: icon(for: key))
                .font(.body)
                .foregroundStyle(comp ? .teal : .secondary)
                .frame(width: 24)

            Text(key)
                .font(.system(.body, design: .monospaced))

            if comp {
                Image(systemName: "gearshape")
                    .font(.caption2)
                    .foregroundStyle(.teal.opacity(0.6))
            }

            Spacer()

            if needed > 0 {
                Text("\(amount) / \(needed) needed")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(amount >= needed ? .green : .secondary)
            } else {
                Text("\(amount)")
                    .font(.system(.body, design: .monospaced).bold())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Helpers

    /// Total amount of this resource needed across all unbuilt tech tree entries.
    private func totalNeeded(for resource: String) -> Int {
        appState.techTreeManager.entries
            .filter { $0.status != .built }
            .flatMap(\.requirements)
            .filter { $0.resource.capitalized == resource }
            .map(\.amount)
            .reduce(0, +)
    }
}
