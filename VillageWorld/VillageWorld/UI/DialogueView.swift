//
//  DialogueView.swift
//  VillageWorld
//
//  Chat panel for talking to characters. Shows streamed LLM
//  responses token-by-token and accepts player text input.
//

import SwiftUI

struct DialogueView: View {
    @EnvironmentObject var appState: AppState
    @State private var playerInput: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            Divider()

            // Response area
            ScrollView {
                Text(appState.dialogueText.isEmpty && appState.isGenerating
                     ? "..."
                     : appState.dialogueText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxHeight: 200)

            Divider()

            // Input bar
            inputBar
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.bottom, 100)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            if let char = appState.dialogueCharacter {
                VStack(alignment: .leading, spacing: 2) {
                    Text(char.name)
                        .font(.system(.headline, design: .monospaced))
                    Text(char.role.rawValue.capitalized)
                        .font(.caption.bold())
                        .foregroundStyle(roleColor(char.role))
                }
            }
            Spacer()
            Button {
                appState.endDialogue()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }
        }
        .padding(12)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Say something...", text: $playerInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .disabled(appState.isGenerating)

            Button {
                let text = playerInput.trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { return }
                playerInput = ""
                appState.sendMessage(text)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(playerInput.trimmingCharacters(in: .whitespaces).isEmpty
                      || appState.isGenerating)
        }
        .padding(12)
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
