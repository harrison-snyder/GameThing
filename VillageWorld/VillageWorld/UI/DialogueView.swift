//
//  DialogueView.swift
//  VillageWorld
//
//  Chat panel for talking to characters. Shows streamed LLM
//  responses token-by-token. Role-specific action buttons let the
//  player trigger research, farming, or worker task flows.
//

import SwiftUI
import PhotosUI

// MARK: - Dialogue Mode

enum DialogueMode: Equatable {
    case chat                // free text chat
    case researchTech        // researcher: tell about technology
    case researchPhoto       // researcher: show a photo
    case checkResearch       // researcher: check progress
    case farmInput           // farmer: tell about plant/animal
    case farmPhoto           // farmer: show a photo
    case checkFarm           // farmer: check farm progress
    case workerTasks         // worker: pick a task
}

// MARK: - DialogueView

struct DialogueView: View {
    @EnvironmentObject var appState: AppState
    @State private var playerInput: String = ""
    @State private var dialogueMode: DialogueMode = .chat
    @State private var selectedPhoto: UIImage?
    @State private var showPhotoPicker: Bool = false
    @State private var showCamera: Bool = false

    var body: some View {
        VStack(spacing: 0) {
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
            .frame(maxHeight: 180)

            Divider()

            // Role-specific action buttons
            if !appState.isGenerating {
                roleActions
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }

            // Photo picker bar (shown in photo modes)
            if dialogueMode == .researchPhoto || dialogueMode == .farmPhoto {
                photoBar
            }

            // Input bar (shown in chat/research/farm modes)
            if dialogueMode == .chat || dialogueMode == .researchTech || dialogueMode == .farmInput {
                inputBar
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.bottom, 80)
        .onChange(of: selectedPhoto) { _, image in
            guard let image else { return }
            appState.handlePhotoInput(image: image)
            selectedPhoto = nil
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker(image: $selectedPhoto)
        }
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

    // MARK: - Role Actions

    @ViewBuilder
    private var roleActions: some View {
        if let char = appState.dialogueCharacter {
            switch char.role {
            case .researcher:
                researcherActions
            case .farmer:
                farmerActions
            case .worker:
                workerActions
            case .npc:
                EmptyView()
            }
        }
    }

    private var researcherActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                actionButton("Tell about technology", icon: "lightbulb.fill") {
                    dialogueMode = .researchTech
                    appState.dialogueText = "What technology would you like to tell me about? Type its name below!"
                }
                actionButton("Show a photo", icon: "camera.fill") {
                    dialogueMode = .researchPhoto
                    showPhotoPicker = true
                }
                actionButton("Check research", icon: "list.clipboard") {
                    dialogueMode = .checkResearch
                    appState.showResearchProgress()
                }
                actionButton("Just chat", icon: "bubble.left") {
                    dialogueMode = .chat
                }
            }
        }
    }

    private var farmerActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                actionButton("Tell about plant/animal", icon: "leaf.fill") {
                    dialogueMode = .farmInput
                    appState.dialogueText = "What plant or animal would you like to tell me about? Type its name below!"
                }
                actionButton("Show a photo", icon: "camera.fill") {
                    dialogueMode = .farmPhoto
                    showPhotoPicker = true
                }
                actionButton("Check farm", icon: "list.clipboard") {
                    dialogueMode = .checkFarm
                    appState.showFarmProgress()
                }
                actionButton("Just chat", icon: "bubble.left") {
                    dialogueMode = .chat
                }
            }
        }
    }

    private var workerActions: some View {
        VStack(spacing: 6) {
            let tasks = appState.availableWorkerTasks()
            if tasks.isEmpty {
                Text("No tasks available yet. Research something first!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tasks, id: \.description) { task in
                            actionButton(task.description, icon: taskIcon(task.type)) {
                                appState.assignTask(task)
                                appState.endDialogue()
                            }
                        }
                    }
                }
            }
            actionButton("Just chat", icon: "bubble.left") {
                dialogueMode = .chat
            }
        }
    }

    // MARK: - Photo Bar

    private var photoBar: some View {
        HStack(spacing: 12) {
            PhotoPicker(selectedImage: $selectedPhoto, isPresented: $showPhotoPicker)
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showCamera = true
                } label: {
                    Label("Take a Photo", systemImage: "camera.fill")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField(inputPlaceholder, text: $playerInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .disabled(appState.isGenerating)

            Button {
                let text = playerInput.trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { return }
                playerInput = ""
                sendForMode(text)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(playerInput.trimmingCharacters(in: .whitespaces).isEmpty
                      || appState.isGenerating)
        }
        .padding(12)
    }

    // MARK: - Helpers

    private var inputPlaceholder: String {
        switch dialogueMode {
        case .researchTech:  return "Name a technology..."
        case .farmInput:     return "Name a plant or animal..."
        default:             return "Say something..."
        }
    }

    private func sendForMode(_ text: String) {
        switch dialogueMode {
        case .researchTech:
            appState.handleResearcherInput(text: text)
        case .farmInput:
            appState.handleFarmerInput(text: text)
        default:
            appState.sendMessage(text)
        }
        dialogueMode = .chat
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.bold())
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .tint(appState.dialogueCharacter.map { roleColor($0.role) } ?? .blue)
    }

    private func taskIcon(_ type: TaskType) -> String {
        switch type {
        case .gather:  return "cube.fill"
        case .build:   return "hammer.fill"
        case .explore: return "binoculars.fill"
        }
    }

    private func roleColor(_ role: CharacterRole) -> Color {
        switch role {
        case .researcher: return .purple
        case .farmer:     return .green
        case .worker:     return .orange
        case .npc:        return .gray
        }
    }
}
