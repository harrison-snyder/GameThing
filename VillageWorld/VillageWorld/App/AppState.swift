//
//  AppState.swift
//  VillageWorld
//
//  Global observable state shared between SwiftUI overlays and the
//  SpriteKit scene.  Also owns the AI engine services (Phase 3).
//

import SwiftUI
import SpriteKit

@MainActor
final class AppState: ObservableObject {

    // MARK: - Game Scene

    let gameScene: GameScene

    // MARK: - AI Engine (Phase 3)

    let llmService:           LLMService
    let dialogueGenerator:    DialogueGenerator
    let requirementsGenerator: RequirementsGenerator
    let visionClassifier:     VisionClassifier
    let spriteGenerator:      SpriteGenerator
    let biomeGenerator:       BiomeGenerator

    // MARK: - HUD / Dialogue State

    @Published var isDialogueActive: Bool = false
    @Published var dialogueText: String = ""
    @Published var dialogueCharacter: CharacterEntity? = nil
    @Published var isGenerating: Bool = false

    @Published var resources: [String: Int] = [
        "Wood":  0,
        "Stone": 0,
        "Food":  0,
    ]

    // MARK: - Character Selection

    @Published var selectedCharacter: CharacterEntity? = nil

    // MARK: - Dialogue

    func startDialogue(with character: CharacterEntity) {
        dialogueCharacter = character
        dialogueText = ""
        isDialogueActive = true
        isGenerating = true

        Task {
            let context = InteractionContext()
            let stream = await dialogueGenerator.generateDialogue(
                character: character,
                playerInput: nil,
                context: context
            )

            var gotTokens = false
            for await token in stream {
                gotTokens = true
                dialogueText += token
            }

            if !gotTokens {
                dialogueText = "No LLM connection"
            }
            isGenerating = false
        }
    }

    func sendMessage(_ text: String) {
        guard let character = dialogueCharacter else { return }
        dialogueText = ""
        isGenerating = true

        Task {
            let context = InteractionContext()
            let stream = await dialogueGenerator.generateDialogue(
                character: character,
                playerInput: text,
                context: context
            )

            var gotTokens = false
            for await token in stream {
                gotTokens = true
                dialogueText += token
            }

            if !gotTokens {
                dialogueText = "No LLM connection"
            }
            isGenerating = false
        }
    }

    func endDialogue() {
        isDialogueActive = false
        dialogueCharacter = nil
        dialogueText = ""
        isGenerating = false
    }

    // MARK: - Init

    init() {
        // Scene
        let scene = GameScene()
        scene.scaleMode = .resizeFill
        self.gameScene = scene

        // AI services — starts in stub mode (no model file required).
        // Call  llmService.loadModel(at:)  after downloading a GGUF model
        // to switch to real inference.
        let llm = LLMService()
        self.llmService            = llm
        self.dialogueGenerator     = DialogueGenerator(llm: llm)
        self.requirementsGenerator = RequirementsGenerator(llm: llm)
        self.visionClassifier      = VisionClassifier()
        self.spriteGenerator       = SpriteGenerator()
        self.biomeGenerator        = BiomeGenerator(llm: llm)
        if let modelPath = Bundle.main.path(forResource: "Llama-3.2-1B-Instruct-Q4_K_M", ofType: "gguf"){
            Task{
                try? await llm.loadModel(at: modelPath)
            }
        }

        // Wire scene → state callbacks
        scene.onCharacterTapped = { [weak self] character in
            self?.selectedCharacter = character
        }
    }
}
