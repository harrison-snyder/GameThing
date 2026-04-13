//
//  HUDOverlay.swift
//  VillageWorld
//
//  Phase 1 HUD — minimal chrome ready to be filled in later phases.
//  Sits in a ZStack above the SpriteView.
//

import SwiftUI

struct HUDOverlay: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack {
            topBar
            Spacer()
            resourceBar
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Village name / phase label
            Text("VillageWorld")
                .font(.system(.headline, design: .monospaced))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.8), radius: 2, x: 1, y: 1)
                .padding(.leading, 16)
            Spacer()
        }
        .padding(.top, 8)
    }

    // MARK: - Resource Bar

    private var resourceBar: some View {
        HStack(spacing: 12) {
            ResourceChip(icon: "tree.fill",       label: "Wood",  value: appState.resources["Wood"]  ?? 0)
            ResourceChip(icon: "square.fill",     label: "Stone", value: appState.resources["Stone"] ?? 0)
            ResourceChip(icon: "leaf.circle.fill", label: "Food",  value: appState.resources["Food"]  ?? 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
    }
}

// MARK: - Resource Chip

private struct ResourceChip: View {
    let icon:  String
    let label: String
    let value: Int

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(.caption, design: .monospaced).bold())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    HUDOverlay()
        .environmentObject(AppState())
        .background(Color.teal)
}
