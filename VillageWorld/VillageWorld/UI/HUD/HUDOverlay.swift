//
//  HUDOverlay.swift
//  VillageWorld
//
//  Phase 1: resource bar + title.
//  Phase 2: character info card shown when the player taps a character.
//

import SwiftUI

struct HUDOverlay: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack {
            topBar
            Spacer()
            if let char = appState.selectedCharacter {
                characterCard(for: char)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            resourceBar
        }
        .animation(.spring(duration: 0.3), value: appState.selectedCharacter?.id)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Text("VillageWorld")
                .font(.system(.headline, design: .monospaced))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.8), radius: 2, x: 1, y: 1)
                .padding(.leading, 16)
            Spacer()
        }
        .padding(.top, 8)
    }

    // MARK: - Character Card

    private func characterCard(for char: CharacterEntity) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(char.name)
                        .font(.system(.headline, design: .monospaced))
                    Text(char.role.rawValue.capitalized)
                        .font(.caption.bold())
                        .foregroundStyle(roleColor(char.role))
                }
                Spacer()
                Button {
                    appState.selectedCharacter = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
            }

            Divider()

            Text("\"\(char.personality)\"")
                .font(.caption)
                .foregroundStyle(.secondary)
                .italic()

            Button {
                appState.startDialogue(with: char)
            } label: {
                Label("Talk", systemImage: "bubble.left.fill")
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(roleColor(char.role))
            .disabled(appState.isDialogueActive)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    // MARK: - Resource Bar

    private var resourceBar: some View {
        HStack(spacing: 12) {
            ResourceChip(icon: "tree.fill",        label: "Wood",  value: appState.resources["Wood"]  ?? 0)
            ResourceChip(icon: "square.fill",      label: "Stone", value: appState.resources["Stone"] ?? 0)
            ResourceChip(icon: "leaf.circle.fill", label: "Food",  value: appState.resources["Food"]  ?? 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
    }

    // MARK: - Role Colour

    private func roleColor(_ role: CharacterRole) -> Color {
        switch role {
        case .researcher: return .purple
        case .farmer:     return .green
        case .worker:     return .orange
        case .npc:        return .gray
        }
    }
}

// MARK: - Resource Chip

private struct ResourceChip: View {
    let icon:  String
    let label: String
    let value: Int

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.caption2).foregroundStyle(.secondary)
            Text("\(value)").font(.system(.caption, design: .monospaced).bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
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
