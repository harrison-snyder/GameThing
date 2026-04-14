//
//  HUDOverlay.swift
//  VillageWorld
//
//  Phase 1: resource bar + title.
//  Phase 2: character info card shown when the player taps a character.
//  Phase 4: tech tree button, task indicators, role context in card.
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

            // Tech tree button
            Button {
                appState.isTechTreeVisible.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "book.closed.fill")
                        .font(.caption)
                    Text("\(appState.techTreeManager.entries.count)")
                        .font(.system(.caption, design: .monospaced).bold())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(.trailing, 16)
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
                    HStack(spacing: 6) {
                        Text(char.role.rawValue.capitalized)
                            .font(.caption.bold())
                            .foregroundStyle(roleColor(char.role))
                        // Show state badge
                        if char.currentState == .working {
                            Text("Working")
                                .font(.caption2.bold())
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.orange.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(.orange)
                        }
                    }
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

            // Role-specific context line
            roleContext(for: char)

            Button {
                appState.startDialogue(with: char)
            } label: {
                Label("Talk", systemImage: "bubble.left.fill")
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(roleColor(char.role))
            .disabled(appState.isDialogueActive || char.currentState == .working)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    // MARK: - Role Context

    @ViewBuilder
    private func roleContext(for char: CharacterEntity) -> some View {
        switch char.role {
        case .researcher:
            let count = appState.techTreeManager.entries.filter { $0.category == .technology }.count
            Text("Discoveries: \(count)")
                .font(.caption2)
                .foregroundStyle(.purple.opacity(0.8))
        case .farmer:
            let crops = appState.techTreeManager.entries.filter { $0.category == .crop || $0.category == .animal }.count
            Text("Farm plans: \(crops)")
                .font(.caption2)
                .foregroundStyle(.green.opacity(0.8))
        case .worker:
            if let task = char.currentTask {
                Text("Task: \(task.description)")
                    .font(.caption2)
                    .foregroundStyle(.orange.opacity(0.8))
            } else {
                Text("Idle — ready for work")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .npc:
            if let lastMemory = char.memory.last {
                Text(lastMemory.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
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
