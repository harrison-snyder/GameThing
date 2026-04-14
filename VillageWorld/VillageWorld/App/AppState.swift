//
//  AppState.swift
//  VillageWorld
//
//  Global observable state shared between SwiftUI overlays and the
//  SpriteKit scene.  Owns AI engine services and manages the core
//  gameplay loops: dialogue, research, farming, task assignment.
//

import SwiftUI
import SpriteKit

@MainActor
final class AppState: ObservableObject {

    // MARK: - Game Scene

    let gameScene: GameScene

    // MARK: - AI Engine (Phase 3)

    let llmService:            LLMService
    let dialogueGenerator:     DialogueGenerator
    let requirementsGenerator: RequirementsGenerator
    let visionClassifier:      VisionClassifier
    let spriteGenerator:       SpriteGenerator
    let biomeGenerator:        BiomeGenerator

    // MARK: - Tech Tree (Phase 4)

    let techTreeManager = TechTreeManager()

    // MARK: - HUD / Dialogue State

    @Published var isDialogueActive: Bool = false
    @Published var dialogueText: String = ""
    @Published var dialogueCharacter: CharacterEntity? = nil
    @Published var isGenerating: Bool = false

    @Published var resources: [String: Int] = [
        "Wood":  10,
        "Stone": 5,
        "Food":  8,
    ]

    // MARK: - Character Selection

    @Published var selectedCharacter: CharacterEntity? = nil

    // MARK: - Tech Tree UI

    @Published var isTechTreeVisible: Bool = false

    // MARK: - Event Log (for InteractionContext)

    private var recentEvents: [String] = []

    // MARK: - Build InteractionContext from live state

    func buildContext() -> InteractionContext {
        InteractionContext(
            knownTechnologies: techTreeManager.knownTechnologies,
            knownCrops:        techTreeManager.knownCrops,
            knownAnimals:      techTreeManager.knownAnimals,
            knownBiomes:       ["Grass Plains"],
            knownResources:    Array(resources.keys),
            recentEvents:      Array(recentEvents.suffix(5))
        )
    }

    // MARK: - Dialogue

    func startDialogue(with character: CharacterEntity) {
        dialogueCharacter = character
        dialogueText = ""
        isDialogueActive = true
        isGenerating = true

        Task {
            let context = buildContext()
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

        // Record memory of this interaction
        character.memory.append(MemoryEntry(
            timestamp: Date(),
            summary: "Player said: \(text)",
            relatedItemID: nil
        ))

        Task {
            let context = buildContext()
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

    // MARK: - Researcher Interaction Flow

    func handleResearcherInput(text: String) {
        guard let character = dialogueCharacter else { return }
        dialogueText = ""
        isGenerating = true

        character.memory.append(MemoryEntry(
            timestamp: Date(),
            summary: "Player told me about technology: \(text)",
            relatedItemID: nil
        ))

        Task {
            // Stream the researcher's excited response
            let context = buildContext()
            let stream = await dialogueGenerator.generateDialogue(
                character: character,
                playerInput: "I want to tell you about this technology: \(text). Can we research how to build it?",
                context: context
            )

            var gotTokens = false
            for await token in stream {
                gotTokens = true
                dialogueText += token
            }

            if !gotTokens {
                dialogueText = "Fascinating! Let me research \(text)..."
            }

            // Generate requirements in parallel
            let reqs = await requirementsGenerator.generate(
                itemName: text,
                role: .researcher,
                knownBiomes: context.knownBiomes,
                knownResources: context.knownResources
            )

            // Add to tech tree
            let entry = techTreeManager.addEntry(
                from: reqs,
                category: .technology,
                createdBy: character.id
            )

            // Update memory with the item reference
            character.memory.append(MemoryEntry(
                timestamp: Date(),
                summary: "Researched \(entry.name): needs \(reqs.requirements.map { "\($0.amount) \($0.resource)" }.joined(separator: ", "))",
                relatedItemID: entry.id
            ))

            techTreeManager.refreshStatuses(resources: resources)
            recentEvents.append("\(character.name) researched \(entry.name)")

            dialogueText += "\n\n[Added to Tech Tree: \(entry.name)]"
            isGenerating = false
        }
    }

    // MARK: - Farmer Interaction Flow

    func handleFarmerInput(text: String) {
        guard let character = dialogueCharacter else { return }
        dialogueText = ""
        isGenerating = true

        // Determine if this is likely a crop or animal
        let animalKeywords = ["cow", "pig", "chicken", "horse", "sheep", "goat", "dog", "cat", "rabbit", "fish", "bee"]
        let isAnimal = animalKeywords.contains(where: { text.lowercased().contains($0) })
        let category: TechCategory = isAnimal ? .animal : .crop

        character.memory.append(MemoryEntry(
            timestamp: Date(),
            summary: "Player told me about \(isAnimal ? "animal" : "plant"): \(text)",
            relatedItemID: nil
        ))

        Task {
            let context = buildContext()
            let prompt = isAnimal
                ? "I want to tell you about this animal: \(text). Can we raise it in the village?"
                : "I want to tell you about this plant: \(text). Can we grow it in the village?"

            let stream = await dialogueGenerator.generateDialogue(
                character: character,
                playerInput: prompt,
                context: context
            )

            var gotTokens = false
            for await token in stream {
                gotTokens = true
                dialogueText += token
            }

            if !gotTokens {
                dialogueText = "How wonderful! Let me think about how to care for \(text)..."
            }

            let reqs = await requirementsGenerator.generate(
                itemName: text,
                role: .farmer,
                knownBiomes: context.knownBiomes,
                knownResources: context.knownResources
            )

            let entry = techTreeManager.addEntry(
                from: reqs,
                category: category,
                createdBy: character.id
            )

            character.memory.append(MemoryEntry(
                timestamp: Date(),
                summary: "Planned \(category.rawValue) \(entry.name): needs \(reqs.requirements.map { "\($0.amount) \($0.resource)" }.joined(separator: ", "))",
                relatedItemID: entry.id
            ))

            techTreeManager.refreshStatuses(resources: resources)
            recentEvents.append("\(character.name) planned \(entry.name)")

            dialogueText += "\n\n[Added to Tech Tree: \(entry.name)]"
            isGenerating = false
        }
    }

    // MARK: - Photo Input

    func handlePhotoInput(image: UIImage) {
        guard let character = dialogueCharacter else { return }
        dialogueText = "Let me take a look at that..."
        isGenerating = true

        Task {
            do {
                let result = try await visionClassifier.classify(image: image)
                let label = result.label.replacingOccurrences(of: "_", with: " ")
                dialogueText = "I see... that looks like a \(label)! (confidence: \(Int(result.confidence * 100))%)\n\n"

                // Route to the appropriate handler based on character role
                if character.role == .researcher {
                    dialogueText += "Let me research how we can use this in the village..."
                    isGenerating = false
                    handleResearcherInput(text: label)
                } else if character.role == .farmer {
                    dialogueText += "Let me think about how we can grow or raise this..."
                    isGenerating = false
                    handleFarmerInput(text: label)
                }
            } catch {
                dialogueText = "Hmm, I couldn't quite make out what that is. Could you describe it instead?"
                isGenerating = false
            }
        }
    }

    // MARK: - Research/Farm Progress

    func showResearchProgress() {
        let techs = techTreeManager.entries.filter { $0.category == .technology }
        if techs.isEmpty {
            dialogueText = "We haven't researched anything yet! Tell me about a technology you know."
        } else {
            let lines = techs.map { entry in
                let status = entry.status == .built ? "Built" :
                             entry.status == .requirementsMet ? "Ready to build" : "Needs resources"
                return "- \(entry.name): \(status)"
            }
            dialogueText = "Here's our research progress:\n\n" + lines.joined(separator: "\n")
        }
    }

    func showFarmProgress() {
        let farms = techTreeManager.entries.filter { $0.category == .crop || $0.category == .animal }
        if farms.isEmpty {
            dialogueText = "We haven't planned any farming yet! Tell me about a plant or animal."
        } else {
            let lines = farms.map { entry in
                let status = entry.status == .built ? "Growing/Raised" :
                             entry.status == .requirementsMet ? "Ready to start" : "Needs resources"
                return "- \(entry.name) (\(entry.category.rawValue)): \(status)"
            }
            dialogueText = "Here's our farming progress:\n\n" + lines.joined(separator: "\n")
        }
    }

    // MARK: - Worker Tasks

    /// Generates the list of available tasks a Worker can be assigned to.
    func availableWorkerTasks() -> [GameTask] {
        guard let character = dialogueCharacter else { return [] }
        var tasks: [GameTask] = []
        let center = character.gridPosition

        // Gather tasks — always available if there are resources on the map
        for resource in ["Wood", "Stone", "Food"] {
            let offset = GridPosition(col: center.col + Int.random(in: -5...5),
                                      row: center.row + Int.random(in: -5...5))
            tasks.append(GameTask(
                type: .gather(resource: resource, amount: 3),
                assignedTo: character.id,
                targetPosition: offset,
                duration: 8.0
            ))
        }

        // Build tasks — from tech tree items with requirements met
        for entry in techTreeManager.buildableEntries(resources: resources) {
            let offset = GridPosition(col: center.col + Int.random(in: -3...3),
                                      row: center.row + Int.random(in: -3...3))
            tasks.append(GameTask(
                type: .build(techEntryID: entry.id),
                assignedTo: character.id,
                targetPosition: offset,
                duration: Double(entry.buildTimeMinutes) * 2.0,  // scaled game time
                displayName: "Build \(entry.name)"
            ))
        }

        // Explore tasks
        for dir in ["North", "South", "East", "West"] {
            let offset: GridPosition
            switch dir {
            case "North": offset = GridPosition(col: center.col, row: center.row + 15)
            case "South": offset = GridPosition(col: center.col, row: center.row - 15)
            case "East":  offset = GridPosition(col: center.col + 15, row: center.row)
            case "West":  offset = GridPosition(col: center.col - 15, row: center.row)
            default:      offset = center
            }
            tasks.append(GameTask(
                type: .explore(direction: dir),
                assignedTo: character.id,
                targetPosition: offset,
                duration: 12.0
            ))
        }

        return tasks
    }

    /// Assigns a task to the worker character and starts working.
    func assignTask(_ task: GameTask) {
        guard let character = dialogueCharacter else { return }

        character.memory.append(MemoryEntry(
            timestamp: Date(),
            summary: "Assigned to: \(task.description)",
            relatedItemID: nil
        ))

        gameScene.assignTask(task, to: character)
        recentEvents.append("\(character.name) started: \(task.description)")
    }

    // MARK: - Task Completion (called by GameScene)

    func handleTaskCompleted(_ task: GameTask) {
        switch task.type {
        case .gather(let resource, let amount):
            let key = resource.capitalized
            resources[key, default: 0] += amount
            recentEvents.append("Gathered \(amount) \(resource)")
            techTreeManager.refreshStatuses(resources: resources)

        case .build(let techEntryID):
            if let costs = techTreeManager.markBuilt(techEntryID) {
                for cost in costs {
                    let key = cost.resource.capitalized
                    resources[key, default: 0] = max(0, (resources[key] ?? 0) - cost.amount)
                }
                if let entry = techTreeManager.entries.first(where: { $0.id == techEntryID }) {
                    recentEvents.append("Built \(entry.name)!")
                    gameScene.placeBuiltItem(name: entry.name, near: task.targetPosition)
                }
            }
            techTreeManager.refreshStatuses(resources: resources)

        case .explore(let direction):
            recentEvents.append("Explored \(direction) — revealed new area")
            gameScene.revealExploredArea(around: task.targetPosition)
        }
    }

    // MARK: - Init

    init() {
        // Scene
        let scene = GameScene()
        scene.scaleMode = .resizeFill
        self.gameScene = scene

        // AI services
        let llm = LLMService()
        self.llmService            = llm
        self.dialogueGenerator     = DialogueGenerator(llm: llm)
        self.requirementsGenerator = RequirementsGenerator(llm: llm)
        self.visionClassifier      = VisionClassifier()
        self.spriteGenerator       = SpriteGenerator()
        self.biomeGenerator        = BiomeGenerator(llm: llm)
        if let modelPath = Bundle.main.path(forResource: "Llama-3.2-1B-Instruct-Q4_K_M", ofType: "gguf") {
            Task {
                try? await llm.loadModel(at: modelPath)
            }
        }

        // Wire scene → state callbacks
        scene.onCharacterTapped = { [weak self] character in
            self?.selectedCharacter = character
        }

        scene.onTaskCompleted = { [weak self] task in
            self?.handleTaskCompleted(task)
        }

        // Wire NPC-NPC dialogue generation
        scene.interactionManager.dialogueGenerator = dialogueGenerator
        scene.interactionManager.interactionContext = { [weak self] in
            self?.buildContext() ?? InteractionContext()
        }
    }
}
