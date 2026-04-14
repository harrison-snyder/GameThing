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
    @Published var isResourcesVisible: Bool = false

    // MARK: - Phase 5 — Biome State

    @Published var discoveredBiomeNames: [String] = ["Grass Plains"]
    @Published var biomeNotification: String? = nil

    // MARK: - Event Log (for InteractionContext)

    private var recentEvents: [String] = []

    // MARK: - Build InteractionContext from live state

    func buildContext() -> InteractionContext {
        InteractionContext(
            knownTechnologies: techTreeManager.knownTechnologies,
            knownCrops:        techTreeManager.knownCrops,
            knownAnimals:      techTreeManager.knownAnimals,
            knownComponents:   techTreeManager.knownComponents,
            knownBiomes:       discoveredBiomeNames,
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
                knownResources: context.knownResources,
                knownComponents: context.knownComponents
            )

            // Add to tech tree
            let entry = techTreeManager.addEntry(
                from: reqs,
                category: .technology,
                createdBy: character.id
            )

            registerResources(for: entry)

            // Update memory with the item reference
            character.memory.append(MemoryEntry(
                timestamp: Date(),
                summary: "Researched \(entry.name): needs \(reqs.requirements.map { "\($0.amount) \($0.resource)" }.joined(separator: ", "))",
                relatedItemID: entry.id
            ))

            techTreeManager.refreshStatuses(resources: resources)
            syncTechCount()
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
                knownResources: context.knownResources,
                knownComponents: context.knownComponents
            )

            let entry = techTreeManager.addEntry(
                from: reqs,
                category: category,
                createdBy: character.id
            )

            registerResources(for: entry)

            // Auto-create infrastructure entry if needed and not already known
            if let infra = reqs.infrastructure, !infra.isEmpty {
                ensureInfrastructureEntry(named: infra, for: entry, character: character, context: context)
            }

            character.memory.append(MemoryEntry(
                timestamp: Date(),
                summary: "Planned \(category.rawValue) \(entry.name): needs \(reqs.requirements.map { "\($0.amount) \($0.resource)" }.joined(separator: ", "))" +
                    (reqs.infrastructure.map { " (requires \($0))" } ?? ""),
                relatedItemID: entry.id
            ))

            techTreeManager.refreshStatuses(resources: resources)
            syncTechCount()
            recentEvents.append("\(character.name) planned \(entry.name)")

            var addedText = "\n\n[Added to Tech Tree: \(entry.name)]"
            if let infra = reqs.infrastructure, !infra.isEmpty {
                let infraBuilt = techTreeManager.entries.contains {
                    $0.name.lowercased() == infra.lowercased() && $0.status == .built
                }
                if !infraBuilt {
                    addedText += "\n[Requires: \(infra) — ask the Worker to build it first]"
                }
            }
            dialogueText += addedText
            isGenerating = false
        }
    }

    // MARK: - Engineer Interaction Flow

    func handleEngineerInput(text: String) {
        guard let character = dialogueCharacter else { return }
        dialogueText = ""
        isGenerating = true

        character.memory.append(MemoryEntry(
            timestamp: Date(),
            summary: "Player asked me to create component: \(text)",
            relatedItemID: nil
        ))

        Task {
            let context = buildContext()
            let stream = await dialogueGenerator.generateDialogue(
                character: character,
                playerInput: "I need you to figure out how to craft this component: \(text). What materials do you need?",
                context: context
            )

            var gotTokens = false
            for await token in stream {
                gotTokens = true
                dialogueText += token
            }

            if !gotTokens {
                dialogueText = "Interesting challenge! Let me work out the materials for \(text)..."
            }

            let reqs = await requirementsGenerator.generate(
                itemName: text,
                role: .engineer,
                knownBiomes: context.knownBiomes,
                knownResources: context.knownResources,
                knownComponents: context.knownComponents
            )

            let entry = techTreeManager.addEntry(
                from: reqs,
                category: .component,
                createdBy: character.id
            )

            registerResources(for: entry)

            character.memory.append(MemoryEntry(
                timestamp: Date(),
                summary: "Designed component \(entry.name): needs \(reqs.requirements.map { "\($0.amount) \($0.resource)" }.joined(separator: ", "))",
                relatedItemID: entry.id
            ))

            techTreeManager.refreshStatuses(resources: resources)
            syncTechCount()
            recentEvents.append("\(character.name) designed component: \(entry.name)")

            dialogueText += "\n\n[Component Added: \(entry.name)]"
            isGenerating = false
        }
    }

    func showComponentProgress() {
        let components = techTreeManager.entries.filter { $0.category == .component }
        if components.isEmpty {
            dialogueText = "I haven't designed any components yet! Tell me what you need built."
        } else {
            let lines = components.map { entry in
                let canCraft = techTreeManager.canBuild(entry, resources: resources)
                let count = resources[entry.name.capitalized] ?? resources[entry.name] ?? 0
                let status = canCraft ? "Ready to craft" : "Needs materials"
                return "- \(entry.name) (have \(count)): \(status)"
            }
            dialogueText = "Here are my component designs:\n\n" + lines.joined(separator: "\n")
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
                } else if character.role == .engineer {
                    dialogueText += "Let me figure out how to make this as a component..."
                    isGenerating = false
                    handleEngineerInput(text: label)
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
            let lines = farms.map { entry -> String in
                if entry.status == .built {
                    let verb = entry.category == .animal ? "Raised" : "Growing"
                    return "- \(entry.name) (\(entry.category.rawValue)): \(verb)"
                }

                let infraMet = techTreeManager.isInfrastructureMet(entry)
                let resourcesMet = techTreeManager.canBuild(entry, resources: resources)

                if !infraMet {
                    return "- \(entry.name) (\(entry.category.rawValue)): Needs \(entry.infrastructure ?? "infrastructure")"
                } else if !resourcesMet {
                    return "- \(entry.name) (\(entry.category.rawValue)): Needs resources"
                } else {
                    let verb = entry.category == .animal ? "Ready to place" : "Ready to plant"
                    return "- \(entry.name) (\(entry.category.rawValue)): \(verb)"
                }
            }
            dialogueText = "Here's our farming progress:\n\n" + lines.joined(separator: "\n")
        }
    }

    // MARK: - Resource Helpers

    /// Ensures every resource named in a tech entry exists in the inventory (at 0 if new).
    private func registerResources(for entry: TechTreeEntry) {
        for req in entry.requirements {
            let key = req.resource.capitalized
            if resources[key] == nil {
                resources[key] = 0
            }
        }
    }

    /// Auto-creates a technology entry for infrastructure (e.g. Garden Bed, Animal Pen)
    /// if one doesn't already exist.
    private func ensureInfrastructureEntry(
        named name: String,
        for parentEntry: TechTreeEntry,
        character: CharacterEntity,
        context: InteractionContext
    ) {
        let alreadyExists = techTreeManager.entries.contains {
            $0.name.lowercased() == name.lowercased()
        }
        guard !alreadyExists else { return }

        Task {
            let reqs = await requirementsGenerator.generate(
                itemName: name,
                role: .researcher,
                knownBiomes: context.knownBiomes,
                knownResources: context.knownResources,
                knownComponents: context.knownComponents
            )

            let infraEntry = techTreeManager.addEntry(
                from: reqs,
                category: .technology,
                createdBy: character.id
            )
            registerResources(for: infraEntry)
            techTreeManager.refreshStatuses(resources: resources)
            syncTechCount()
            recentEvents.append("Infrastructure needed: \(infraEntry.name)")
        }
    }

    // MARK: - Farmer Tasks

    /// Generates tasks the Farmer can perform: planting crops and placing animals
    /// whose infrastructure is built and resources are available.
    func availableFarmerTasks() -> [GameTask] {
        guard let character = dialogueCharacter else { return [] }
        let center = character.gridPosition
        var tasks: [GameTask] = []

        for entry in techTreeManager.plantableEntries(resources: resources) {
            let offset = GridPosition(col: center.col + Int.random(in: -3...3),
                                      row: center.row + Int.random(in: -3...3))
            let verb = entry.category == .animal ? "Place" : "Plant"
            tasks.append(GameTask(
                type: .plant(techEntryID: entry.id),
                assignedTo: character.id,
                targetPosition: offset,
                duration: Double(entry.buildTimeMinutes) * 2.0,
                displayName: "\(verb) \(entry.name)"
            ))
        }

        return tasks
    }

    // MARK: - Worker Tasks

    /// Generates the list of available tasks a Worker can be assigned to.
    func availableWorkerTasks() -> [GameTask] {
        guard let character = dialogueCharacter else { return [] }
        var tasks: [GameTask] = []
        let center = character.gridPosition

        // Gather tasks — dynamically include any resource the tech tree needs
        var neededResources = Set(resources.keys)
        for entry in techTreeManager.entries where entry.status != .built {
            for req in entry.requirements {
                neededResources.insert(req.resource.capitalized)
            }
        }
        for resource in neededResources.sorted() {
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

    /// Generates the list of components an Engineer can craft right now.
    func availableEngineerTasks() -> [GameTask] {
        guard let character = dialogueCharacter else { return [] }
        let center = character.gridPosition

        var tasks: [GameTask] = []

        // Craft tasks — from component entries with requirements met
        for entry in techTreeManager.craftableComponents(resources: resources) {
            let offset = GridPosition(col: center.col + Int.random(in: -3...3),
                                      row: center.row + Int.random(in: -3...3))
            tasks.append(GameTask(
                type: .craft(techEntryID: entry.id),
                assignedTo: character.id,
                targetPosition: offset,
                duration: Double(entry.buildTimeMinutes) * 2.0,
                displayName: "Craft \(entry.name)"
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
            syncTechCount()

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
            syncTechCount()

        case .explore(let direction):
            recentEvents.append("Explored \(direction) — revealed new area")
            gameScene.revealExploredArea(around: task.targetPosition)
            gameScene.triggerBiomeFromExplore(around: task.targetPosition)

        case .craft(let techEntryID):
            if let costs = techTreeManager.craftComponent(techEntryID) {
                for cost in costs {
                    let key = cost.resource.capitalized
                    resources[key, default: 0] = max(0, (resources[key] ?? 0) - cost.amount)
                }
                if let entry = techTreeManager.entries.first(where: { $0.id == techEntryID }) {
                    // Add the crafted component to resources
                    let componentKey = entry.name.capitalized
                    resources[componentKey, default: 0] += 1
                    recentEvents.append("Crafted \(entry.name)!")
                }
            }
            techTreeManager.refreshStatuses(resources: resources)
            syncTechCount()

        case .plant(let techEntryID):
            if let costs = techTreeManager.markBuilt(techEntryID) {
                for cost in costs {
                    let key = cost.resource.capitalized
                    resources[key, default: 0] = max(0, (resources[key] ?? 0) - cost.amount)
                }
                if let entry = techTreeManager.entries.first(where: { $0.id == techEntryID }) {
                    let verb = entry.category == .animal ? "Placed" : "Planted"
                    recentEvents.append("\(verb) \(entry.name)!")
                    gameScene.placeBuiltItem(name: entry.name, near: task.targetPosition)
                }
            }
            techTreeManager.refreshStatuses(resources: resources)
            syncTechCount()
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

        // Phase 5 — wire biome discovery
        scene.biomeDiscovery.biomeGenerator = biomeGenerator
        scene.biomeDiscovery.onBiomeDiscovered = { [weak self] biome in
            guard let self else { return }
            let name = biome.template.name
            if !self.discoveredBiomeNames.contains(name) {
                self.discoveredBiomeNames.append(name)
            }
            // Register biome resources in the inventory
            for res in biome.template.resources {
                let key = res.name.capitalized
                if self.resources[key] == nil {
                    self.resources[key] = 0
                }
            }
            self.recentEvents.append("Discovered new biome: \(name)")
            self.biomeNotification = "New Biome: \(name)"
        }

        // Keep GameScene's tech count in sync for biome triggers
        scene.onBiomeDiscovered = { _ in }  // placeholder, real callback above
    }

    // MARK: - Tech Count Sync

    /// Called after any tech tree change to keep GameScene's trigger counter current.
    private func syncTechCount() {
        gameScene.techEntryCount = techTreeManager.entries.count
    }
}
