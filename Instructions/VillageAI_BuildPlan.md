# VillageAI — Build Plan

> A top-down pixel-art village sim driven entirely by on-device AI. The player introduces real-world knowledge (via text or photos) to guide a growing village through technological and agricultural discovery.

---

## Table of Contents

1. [Game Overview](#1-game-overview)
2. [Architecture](#2-architecture)
3. [Project Structure](#3-project-structure)
4. [Phase 1 — World Foundation](#4-phase-1--world-foundation)
5. [Phase 2 — Character System](#5-phase-2--character-system)
6. [Phase 3 — On-Device AI Engine](#6-phase-3--on-device-ai-engine)
7. [Phase 4 — Interaction Loops](#7-phase-4--interaction-loops)
8. [Phase 5 — World Expansion & Biomes](#8-phase-5--world-expansion--biomes)
9. [Phase 6 — Polish & Persistence](#9-phase-6--polish--persistence)
10. [Art Style Guide](#10-art-style-guide)
11. [Technical Risks & Mitigations](#11-technical-risks--mitigations)
12. [Data Models](#12-data-models)
13. [AI Prompt Templates](#13-ai-prompt-templates)

---

## 1. Game Overview

### Core Concept

The player exists in a small village with 3 initial villagers: a Researcher, a Farmer, and a Worker. The player introduces real-world knowledge — by typing about a technology/science, describing a plant/animal, or showing a photo from their camera — and the village AI characters research how to build or grow those things within the game world.

### Character Roles

| Role | Input | Behavior |
|------|-------|----------|
| **Researcher** | Text description of a technology/science OR a camera photo | Classifies the input, determines resource requirements, logs it as a buildable item in the tech tree |
| **Farmer** | Text description of a plant/animal OR a camera photo | Classifies the input, determines climate/biome requirements, logs it as a growable/tameable entry |
| **Worker** | Player-assigned tasks | Travels to locations, gathers resources, constructs items, performs manual labor |
| **NPC** (no role) | None — arrives periodically | Wanders, interacts with other characters via AI dialogue, adds life to the village |

### World Rules

- Starts as a grass plains biome surrounded by dark fog/haze
- New biomes are discovered over time (triggered by population, tech level, or time)
- Each biome has unique resources, climate, and terrain
- Biome characteristics are AI-generated
- Resources from biomes gate tech tree progression

### What AI Controls vs What Code Controls

| AI Controls | Code Controls |
|-------------|---------------|
| All character dialogue | Character movement/pathfinding |
| NPC-to-NPC interaction content | Collision detection |
| Photo/text classification | Tile rendering |
| Tech tree requirements generation | State machine transitions |
| Biome characteristics generation | Timer/spawn logic |
| Item sprite art generation | Physics, camera, input handling |
| Character memory and personality | Save/load, UI layout |

---

## 2. Architecture

### Layer Diagram

```
┌─────────────────────────────────────────────────────┐
│  PRESENTATION — SwiftUI + SpriteKit                 │
│  ┌──────────┐ ┌──────────┐ ┌────────┐ ┌──────────┐ │
│  │SpriteKit │ │ SwiftUI  │ │ Camera │ │Dialogue  │ │
│  │Game Scene│ │HUD/Menus │ │ Input  │ │   UI     │ │
│  └──────────┘ └──────────┘ └────────┘ └──────────┘ │
├─────────────────────────────────────────────────────┤
│  GAME ENGINE                                        │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ │
│  │World Manager │ │Character Sys │ │Interaction   │ │
│  │Tiles, biomes │ │Movement,roles│ │Engine        │ │
│  │fog of war    │ │state machine │ │tasks, queues │ │
│  └──────────────┘ └──────────────┘ └──────────────┘ │
├─────────────────────────────────────────────────────┤
│  ON-DEVICE AI ENGINE                                │
│  ┌────────┐ ┌──────────┐ ┌─────────┐ ┌───────────┐ │
│  │  LLM   │ │  Vision  │ │Image Gen│ │ Biome Gen │ │
│  │Dialogue│ │Classifier│ │Sprites  │ │World build│ │
│  │& logic │ │Core ML   │ │Stable D.│ │via LLM    │ │
│  └────────┘ └──────────┘ └─────────┘ └───────────┘ │
├─────────────────────────────────────────────────────┤
│  DATA LAYER — SwiftData + Local Files               │
│  ┌──────────┐ ┌──────────┐ ┌─────────┐ ┌─────────┐ │
│  │World     │ │Character │ │Tech Tree│ │Asset    │ │
│  │State     │ │Memory    │ │& Recipes│ │Cache    │ │
│  └──────────┘ └──────────┘ └─────────┘ └─────────┘ │
├─────────────────────────────────────────────────────┤
│  PLATFORM SERVICES                                  │
│  AVFoundation · Core ML · GameKit · SwiftData       │
└─────────────────────────────────────────────────────┘
```

**All AI runs locally on-device. No cloud dependency.**

### Technology Choices

| Component | Technology | Reason |
|-----------|-----------|--------|
| Game rendering | SpriteKit (`SKScene`, `SKTileMapNode`) | Native Apple 2D engine, great for tile-based games |
| UI overlays | SwiftUI | Declarative UI for HUD, menus, dialogue |
| Hosting | `SpriteView` in SwiftUI | Bridges SpriteKit scene into SwiftUI lifecycle |
| Local LLM | `llama.cpp` via `LLamaSwift` or MLX Swift | Runs quantized models on Apple Neural Engine + GPU |
| LLM model | Llama 3.2 1B (Q4_K_M quantized) | Small enough for iPhone, capable enough for dialogue |
| Vision | Core ML `VNClassifyImageRequest` or MobileNetV3 | Fast on-device image classification |
| Image generation | Apple `ml-stable-diffusion` Core ML | On-device pixel art sprite generation |
| Persistence | SwiftData | Native Swift ORM, automatic migrations |
| Camera | AVFoundation + `UIImagePickerController` | Standard iOS camera access |
| Pathfinding | GameplayKit `GKGridGraph` + `GKAStar` | Built-in A* for tile grids |

---

## 3. Project Structure

```
VillageAI/
├── VillageAI.xcodeproj
├── VillageAI/
│   ├── App/
│   │   ├── VillageAIApp.swift              # @main entry point
│   │   ├── ContentView.swift               # Root view: SpriteView + SwiftUI overlays
│   │   └── AppState.swift                  # Global observable game state
│   │
│   ├── Game/
│   │   ├── Scenes/
│   │   │   ├── GameScene.swift             # Main SKScene — world rendering + input
│   │   │   └── GameSceneDelegate.swift     # Touch handling, tap-to-move, tap-on-NPC
│   │   ├── Tiles/
│   │   │   ├── TileMapManager.swift        # SKTileMapNode creation and updates
│   │   │   ├── BiomeRenderer.swift         # Paints tiles per biome type
│   │   │   ├── FogOfWar.swift              # Dark haze mask system
│   │   │   └── TileTypes.swift             # Enum of tile terrain types
│   │   ├── Characters/
│   │   │   ├── CharacterEntity.swift        # Base character: sprite, role, state
│   │   │   ├── CharacterStateMachine.swift  # Idle → Wander → Interact → Work
│   │   │   ├── CharacterMovement.swift      # Pathfinding via GKGridGraph
│   │   │   ├── CharacterSpawner.swift       # Timer-based NPC arrival
│   │   │   └── Roles/
│   │   │       ├── ResearcherRole.swift     # Research-specific behavior
│   │   │       ├── FarmerRole.swift          # Farming-specific behavior
│   │   │       └── WorkerRole.swift          # Task execution behavior
│   │   └── Interaction/
│   │       ├── InteractionManager.swift     # Proximity detection, triggers
│   │       ├── TaskQueue.swift              # Pending worker tasks
│   │       └── NPCConversation.swift        # NPC-to-NPC random chat trigger
│   │
│   ├── AI/
│   │   ├── LLM/
│   │   │   ├── LLMService.swift            # llama.cpp wrapper, async inference
│   │   │   ├── PromptBuilder.swift         # Constructs system + user prompts
│   │   │   ├── DialogueGenerator.swift     # Character dialogue via LLM
│   │   │   └── RequirementsGenerator.swift # "What do we need to build X?"
│   │   ├── Vision/
│   │   │   ├── VisionClassifier.swift      # Core ML image classification
│   │   │   └── ClassificationResult.swift  # Structured output from classifier
│   │   ├── ImageGen/
│   │   │   ├── SpriteGenerator.swift       # Stable Diffusion pipeline
│   │   │   ├── PixelArtPrompt.swift        # Prompt templates for pixel art style
│   │   │   └── SpritePostProcessor.swift   # Resize, palette reduce, cache
│   │   └── BiomeGen/
│   │       ├── BiomeGenerator.swift        # LLM generates biome metadata
│   │       └── BiomeTemplate.swift         # Structured biome definition
│   │
│   ├── Data/
│   │   ├── Models/
│   │   │   ├── WorldState.swift            # SwiftData: map grid, discovered biomes
│   │   │   ├── CharacterModel.swift        # SwiftData: character data + memory
│   │   │   ├── TechTreeItem.swift          # SwiftData: items, recipes, status
│   │   │   ├── BiomeModel.swift            # SwiftData: biome definitions
│   │   │   └── ResourceModel.swift         # SwiftData: resource types + locations
│   │   ├── TechTree/
│   │   │   ├── TechTreeManager.swift       # Query, unlock, dependency checks
│   │   │   └── Recipe.swift                # Resource requirements for an item
│   │   └── AssetCache/
│   │       ├── GeneratedAssetCache.swift   # Disk cache for AI-generated sprites
│   │       └── AssetManager.swift          # Load base + generated assets
│   │
│   ├── UI/
│   │   ├── HUD/
│   │   │   ├── HUDOverlay.swift            # SwiftUI overlay on game scene
│   │   │   ├── InventoryView.swift         # Player inventory panel
│   │   │   ├── MinimapView.swift           # Small world overview
│   │   │   └── ResourceBar.swift           # Current resource counts
│   │   ├── Dialogue/
│   │   │   ├── DialogueView.swift          # Chat bubble UI (streaming tokens)
│   │   │   ├── DialogueChoices.swift       # Player input options
│   │   │   └── CharacterPortrait.swift     # Speaker portrait display
│   │   ├── Camera/
│   │   │   ├── CameraView.swift            # Photo capture SwiftUI wrapper
│   │   │   └── PhotoPreview.swift          # Confirm photo before sending to AI
│   │   └── Menus/
│   │       ├── MainMenuView.swift          # Start, load, settings
│   │       ├── TechTreeView.swift          # Visual tech tree browser
│   │       ├── BiomeMapView.swift          # Full world map viewer
│   │       └── SettingsView.swift          # AI quality, sound, etc.
│   │
│   └── Resources/
│       ├── Sprites/                        # Base pixel art character sprites
│       │   ├── player.png
│       │   ├── researcher.png
│       │   ├── farmer.png
│       │   ├── worker.png
│       │   └── npc_variants/
│       ├── Tiles/                          # Tile set images per biome
│       │   ├── grass_tileset.png
│       │   └── (generated biome tiles cached at runtime)
│       ├── UI/                             # UI element sprites
│       └── MLModels/                       # Core ML model files
│           ├── llama-3.2-1b-q4km.mlmodelc  # (or .gguf for llama.cpp)
│           ├── mobilenet-v3.mlmodelc
│           └── sd-pixel-art.mlmodelc
│
├── VillageAITests/
└── README.md
```

---

## 4. Phase 1 — World Foundation

**Goal:** Render a scrollable tile-based world with a player character, tap-to-move, and fog of war.

### 4.1 Tile Map System

**File:** `TileMapManager.swift`

- Use `SKTileMapNode` with a 16×16 pixel tile set
- Initial map size: 64×64 tiles (expandable)
- Each tile references a `TileType` enum:

```swift
enum TileType: Int, Codable {
    case grass = 0
    case dirt = 1
    case water = 2
    case stone = 3
    case sand = 4
    // Extended by biomes at runtime
}
```

- Tiles are rendered at 3× scale on phones (48×48 screen points per tile)
- The backing data structure is a 2D array: `var grid: [[TileCell]]` where each cell stores:

```swift
struct TileCell: Codable {
    var tileType: TileType
    var biomeID: UUID?
    var isWalkable: Bool
    var resourceType: ResourceType?
    var resourceAmount: Int
    var isDiscovered: Bool  // false = fog of war covers it
}
```

### 4.2 Game Scene

**File:** `GameScene.swift`

- `SKScene` with `scaleMode = .resizeFill`
- Camera node (`SKCameraNode`) follows the player with smooth lerp
- Touch input: tap anywhere walkable → pathfind player there
- Pinch to zoom (constrained between 0.5× and 2.0×)
- The scene owns:
  - `tileMapNode: SKTileMapNode`
  - `playerNode: SKSpriteNode`
  - `characterNodes: [UUID: SKSpriteNode]`
  - `fogNode: SKNode` (fog of war layer)

### 4.3 Fog of War

**File:** `FogOfWar.swift`

- Rendered as a separate `SKNode` layer above the tile map
- Each undiscovered tile has a dark semi-transparent sprite
- When a biome is discovered, animate the fog fading away for those tiles
- Implementation: `SKCropNode` with an inverse mask, or simply an array of dark `SKSpriteNode` tiles removed on discovery

### 4.4 Player Movement

**File:** `CharacterMovement.swift`

- Use `GKGridGraph` from GameplayKit for A* pathfinding
- On tap: calculate path → convert to `SKAction` sequence of move actions
- Walking animation: cycle through sprite frames (4-frame walk cycle per direction)
- Movement speed: ~3 tiles per second
- Directions: 4-directional (up, down, left, right) — consistent with pixel art style

### 4.5 SwiftUI Integration

**File:** `ContentView.swift`

```swift
struct ContentView: View {
    @StateObject var appState = AppState()
    
    var body: some View {
        ZStack {
            SpriteView(scene: appState.gameScene)
                .ignoresSafeArea()
            
            HUDOverlay()
                .environmentObject(appState)
            
            if appState.isDialogueActive {
                DialogueView()
                    .environmentObject(appState)
            }
        }
    }
}
```

### Phase 1 Deliverables

- [ ] Xcode project with SpriteKit + SwiftUI scaffold
- [ ] Tile map rendering with grass biome
- [ ] Player sprite with tap-to-move pathfinding
- [ ] Camera follow with zoom
- [ ] Fog of war rendering
- [ ] Basic HUD overlay (empty, ready for content)

---

## 5. Phase 2 — Character System

**Goal:** NPCs that wander, have roles, and can be tapped to open dialogue.

### 5.1 Character Entity

**File:** `CharacterEntity.swift`

```swift
class CharacterEntity: Identifiable, ObservableObject {
    let id: UUID
    let name: String
    let role: CharacterRole
    var spriteNode: SKSpriteNode
    var homePosition: CGPoint           // Where they default to
    var currentState: CharacterState
    var memory: [MemoryEntry]           // Past interactions
    var personality: String             // LLM personality prompt fragment
    var currentTask: GameTask?          // For workers
    
    // Grid position (derived from sprite position)
    var gridPosition: GridPosition { ... }
}

enum CharacterRole: String, Codable {
    case researcher
    case farmer
    case worker
    case npc
}

struct MemoryEntry: Codable {
    let timestamp: Date
    let summary: String      // Short text: "Player told me about solar panels"
    let relatedItemID: UUID? // Links to tech tree item if applicable
}
```

### 5.2 State Machine

**File:** `CharacterStateMachine.swift`

States and transitions:

```
idle → wander (after random delay 2-5 seconds)
wander → idle (reached destination)
wander → interacting (another character entered proximity)
idle → interacting (player tapped, or NPC approached)
interacting → idle (conversation ended)
idle → working (worker assigned a task)
working → idle (task complete)
```

- **Idle:** Stand still, play idle animation, face random direction
- **Wander:** Pick random walkable tile within 8 tiles of home → pathfind there
- **Interacting:** Stop movement, face the other character, trigger dialogue
- **Working:** Walk to target location, play work animation, decrement task timer

### 5.3 NPC Spawning

**File:** `CharacterSpawner.swift`

- Timer fires every 3-5 game-minutes (configurable)
- 85% chance of spawning a generic NPC, 15% chance of a role-bearing character
- NPCs spawn at the edge of the discovered area and walk in
- Each NPC gets a random name (from a name list) and personality trait
- Cap total characters at ~20 to manage performance

### 5.4 Proximity Interactions

**File:** `InteractionManager.swift`

- Each game tick, check pairwise distances between all characters
- If two non-player characters are within 2 tiles and neither is busy:
  - 30% chance per tick to trigger an NPC-to-NPC conversation
  - The conversation runs through the LLM in background
  - A small chat bubble appears above them briefly
- Player taps a character:
  - Dialogue UI opens
  - Different options shown based on role (see Phase 4)

### Phase 2 Deliverables

- [ ] CharacterEntity with roles and memory
- [ ] State machine driving behavior
- [ ] Wander AI (random walk near home)
- [ ] NPC spawning on timer
- [ ] Proximity detection for NPC-to-NPC interactions
- [ ] Tap-on-character to trigger player interaction
- [ ] 3 starter characters placed: Researcher, Farmer, Worker

---

## 6. Phase 3 — On-Device AI Engine

**Goal:** All four AI subsystems running locally.

### 6.1 LLM Service

**File:** `LLMService.swift`

Wrapper around `llama.cpp` (via Swift package `llama.swift` or similar):

```swift
actor LLMService {
    private var model: LlamaModel
    
    init(modelPath: String) async throws {
        // Load quantized model (Q4_K_M, ~1.2 GB)
        model = try await LlamaModel(path: modelPath, contextSize: 2048)
    }
    
    /// Generate text with streaming callback
    func generate(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int = 256,
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        // Build messages, run inference, stream tokens
    }
}
```

Key parameters:
- Context window: 2048 tokens (enough for character system prompt + memory + conversation)
- Max generation: 256 tokens per response (keeps responses snappy)
- Temperature: 0.8 for dialogue, 0.3 for requirements generation
- Model: Llama 3.2 1B Instruct (Q4_K_M) — ~1.2 GB, runs at 15-30 tok/s on A16+

### 6.2 Vision Classifier

**File:** `VisionClassifier.swift`

```swift
class VisionClassifier {
    func classify(image: UIImage) async throws -> ClassificationResult {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image.cgImage!)
        try handler.perform([request])
        
        guard let observations = request.results as? [VNClassificationObservation],
              let top = observations.first else {
            throw ClassificationError.noResults
        }
        
        return ClassificationResult(
            label: top.identifier,       // e.g. "solar_panel"
            confidence: top.confidence,  // e.g. 0.87
            topK: observations.prefix(5).map { ($0.identifier, $0.confidence) }
        )
    }
}
```

For better results, we can supplement with a custom Core ML model trained on categories relevant to the game (technologies, plants, animals, materials). Fallback to the built-in classifier for unknown categories.

### 6.3 Requirements Generator

**File:** `RequirementsGenerator.swift`

After the vision model or player text identifies an item, the LLM generates what's needed:

```swift
struct RequirementsGenerator {
    let llm: LLMService
    
    func generateRequirements(
        for item: String,
        role: CharacterRole,  // .researcher or .farmer
        knownBiomes: [BiomeModel],
        knownResources: [ResourceModel]
    ) async throws -> GeneratedRequirements {
        let prompt = """
        You are a \(role.rawValue) in a small village.
        Known biomes: \(knownBiomes.map(\.name).joined(separator: ", "))
        Known resources: \(knownResources.map(\.name).joined(separator: ", "))
        
        The player wants to \(role == .researcher ? "build" : "grow/raise"): \(item)
        
        Respond in JSON:
        {
            "item_name": "...",
            "description": "...",
            "requirements": [
                {"resource": "...", "amount": N, "biome_hint": "..."}
            ],
            "build_time_minutes": N,
            "difficulty": "easy|medium|hard"
        }
        """
        // Parse JSON response into GeneratedRequirements struct
    }
}
```

### 6.4 Sprite Generator

**File:** `SpriteGenerator.swift`

Uses Apple's `ml-stable-diffusion` Core ML package:

```swift
actor SpriteGenerator {
    private var pipeline: StableDiffusionPipeline
    
    func generateSprite(for item: String) async throws -> UIImage {
        let prompt = """
        16-bit pixel art sprite of \(item), top-down view, \
        pastel colors, clean outlines, cozy fantasy style, \
        transparent background, 64x64 pixels
        """
        
        let image = try pipeline.generateImages(
            prompt: prompt,
            negativePrompt: "realistic, 3D, photograph, blurry",
            stepCount: 20,          // Lower steps for speed
            guidanceScale: 7.5
        ).first!
        
        // Post-process: resize to 16x16 or 32x32, reduce palette
        return postProcess(image)
    }
}
```

Generation strategy:
- Generate at 128×128 or 256×256 (smallest SD supports well)
- Downscale to 32×32 for in-game sprite
- Apply palette reduction to match pixel art style
- Cache result to disk — never regenerate the same item
- Show a "crafting..." animation in-game while generating (10-30 seconds)

### 6.5 Dialogue Generator

**File:** `DialogueGenerator.swift`

Builds character-specific prompts:

```swift
struct DialogueGenerator {
    let llm: LLMService
    
    func generateDialogue(
        character: CharacterEntity,
        playerInput: String?,
        context: InteractionContext
    ) async throws -> AsyncStream<String> {
        let systemPrompt = buildCharacterPrompt(character)
        let userPrompt = buildUserPrompt(playerInput, context)
        
        return AsyncStream { continuation in
            Task {
                try await llm.generate(
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    maxTokens: 200
                ) { token in
                    continuation.yield(token)
                }
                continuation.finish()
            }
        }
    }
}
```

### Phase 3 Deliverables

- [ ] LLMService wrapping llama.cpp with streaming
- [ ] VisionClassifier using Core ML
- [ ] RequirementsGenerator producing structured tech tree entries
- [ ] SpriteGenerator with Stable Diffusion pipeline
- [ ] DialogueGenerator with per-character prompts
- [ ] Model files bundled or downloaded on first launch

---

## 7. Phase 4 — Interaction Loops

**Goal:** Connect character roles to AI systems and create the core gameplay loop.

### 7.1 Player-to-Researcher Interaction

When player taps the Researcher, dialogue opens with options:

```
┌─────────────────────────────┐
│  🔬 Researcher Ada          │
│  "What knowledge do you     │
│   bring today?"             │
│                             │
│  [Tell about technology]    │
│  [Show a photo]             │
│  [Check research progress]  │
│  [Just chat]                │
└─────────────────────────────┘
```

**"Tell about technology"** flow:
1. Text input field appears
2. Player types: "solar panels"
3. LLM generates researcher response + requirements
4. Requirements added to tech tree
5. Researcher memory updated

**"Show a photo"** flow:
1. Camera opens (or photo library)
2. Player takes/selects photo
3. Vision classifier runs → "solar_panel" (confidence 0.87)
4. Result passed to researcher as if player said it
5. Same requirements generation flow

### 7.2 Player-to-Farmer Interaction

Same structure as Researcher, but the LLM prompt focuses on:
- What climate/biome the plant or animal needs
- What food/care/water is required
- Growth time or breeding time
- Output: adds a "growable" entry to the tech tree

### 7.3 Player-to-Worker Interaction

```
┌─────────────────────────────┐
│  🔨 Worker Bob              │
│  "Ready to work! What       │
│   should I do?"             │
│                             │
│  [Gather wood]              │  ← from available tasks
│  [Mine stone]               │
│  [Build solar panel]        │  ← if requirements met
│  [Explore east]             │
│  [Just chat]                │
└─────────────────────────────┘
```

Available tasks are dynamically generated from:
- Resources visible in discovered biomes
- Tech tree items with all requirements met
- Exploration directions with undiscovered biomes

### 7.4 Task Queue System

**File:** `TaskQueue.swift`

```swift
struct GameTask: Identifiable, Codable {
    let id: UUID
    let type: TaskType
    let assignedTo: UUID        // Character ID
    let targetPosition: GridPosition
    let duration: TimeInterval  // Game-time seconds
    var progress: Double        // 0.0 to 1.0
    var status: TaskStatus
    
    enum TaskType: Codable {
        case gather(resource: ResourceType, amount: Int)
        case build(itemID: UUID)
        case explore(direction: Direction)
        case farm(cropID: UUID)
    }
    
    enum TaskStatus: Codable {
        case queued
        case inProgress
        case complete
        case failed(reason: String)
    }
}
```

### 7.5 Core Gameplay Loop

```
Player explores world
    │
    ├─→ Finds something in real life (or knows about it)
    │
    ├─→ Tells Researcher about a technology
    │   └─→ Vision or text → LLM requirements → Tech tree entry
    │
    ├─→ Tells Farmer about a plant/animal
    │   └─→ Vision or text → LLM requirements → Farm entry
    │
    ├─→ Assigns Workers to gather/build/explore
    │   └─→ Worker walks to location → completes task → resources/items gained
    │
    ├─→ Resources gathered unlock blocked tech tree items
    │
    ├─→ New items built → village visually changes
    │
    ├─→ Population grows → new biome discovered
    │   └─→ Fog recedes → new resources available
    │
    └─→ Repeat with more complex tech chains
```

### Phase 4 Deliverables

- [ ] Researcher interaction flow (text + photo)
- [ ] Farmer interaction flow (text + photo)
- [ ] Worker task assignment UI
- [ ] Task queue with progress tracking
- [ ] Tech tree entries created from AI output
- [ ] Visual feedback: items appearing in village when built

---

## 8. Phase 5 — World Expansion & Biomes

**Goal:** AI-generated biomes expand the world over time.

### 8.1 Biome Discovery Triggers

A new biome is generated when ANY of these conditions are met:
- Village population reaches a threshold (5, 10, 15, 20...)
- A tech tree milestone is hit (first tool, first building, first crop...)
- Cumulative playtime reaches a threshold (every ~15 real minutes)
- Player explicitly sends a Worker to "explore"

### 8.2 Biome Generation

**File:** `BiomeGenerator.swift`

The LLM generates biome metadata:

```swift
struct BiomeGenerator {
    let llm: LLMService
    
    func generateBiome(
        existingBiomes: [BiomeModel],
        playerTechLevel: Int
    ) async throws -> BiomeTemplate {
        let prompt = """
        Generate a new biome for a fantasy village world.
        Existing biomes: \(existingBiomes.map(\.name).joined(separator: ", "))
        
        Create something different. Respond in JSON:
        {
            "name": "...",
            "description": "...",
            "climate": "temperate|arid|tropical|cold|volcanic",
            "primary_color_hex": "#...",
            "secondary_color_hex": "#...",
            "resources": [
                {"name": "...", "rarity": "common|uncommon|rare", "description": "..."}
            ],
            "wildlife": ["..."],
            "plants": ["..."],
            "terrain_features": ["..."],
            "danger_level": 1-5
        }
        """
        // Parse and return BiomeTemplate
    }
}
```

### 8.3 Biome Rendering

**File:** `BiomeRenderer.swift`

When a biome is generated:
1. Pick a direction to expand (away from center, toward unexplored fog)
2. Allocate a chunk of tiles (16×16 to 32×32)
3. Paint tiles using biome colors and terrain features
4. Place resource nodes on random tiles within the biome
5. Animate fog dissolving to reveal the new area

Tile painting uses a noise function (GameplayKit `GKNoiseMap`) to create natural-looking terrain variation within the biome.

### 8.4 Resource Placement

Each biome's resources are scattered across its tiles:
- Common resources: 40-60% of tiles
- Uncommon: 15-25% of tiles
- Rare: 3-8% of tiles
- Resources are represented as small sprite overlays on tiles
- Workers can be sent to harvest specific resources

### Phase 5 Deliverables

- [ ] Biome discovery trigger system
- [ ] LLM-based biome generation
- [ ] Dynamic tile painting for new biomes
- [ ] Fog of war retreat animation
- [ ] Resource node placement
- [ ] Biome-specific tile sets (procedural or generated)

---

## 9. Phase 6 — Polish & Persistence

### 9.1 Save System

**File:** SwiftData models in `Data/Models/`

Auto-save triggers:
- Every 60 seconds during gameplay
- On app entering background
- After significant events (biome discovered, item built)

What gets saved:
- Full tile grid state
- All character positions, states, and memories
- Tech tree progress
- Task queue
- Generated asset references (sprites cached to disk separately)
- Camera position and zoom

### 9.2 Settings

- **AI Quality**: Fast (fewer tokens, lower temp) vs Quality (more tokens, higher temp)
- **Generation Detail**: Skip sprite generation (use placeholder) vs Generate sprites
- **Auto-save interval**: 30s / 60s / 120s
- **Sound/Music**: On/Off/Volume

### 9.3 Onboarding

First launch experience:
1. Brief animated intro showing the village appearing from fog
2. Tutorial: "Tap to move" → "Tap a character to talk" → "Tell the Researcher something you know"
3. First interaction is guided (suggest "Tell them about a wheel")
4. After first tech tree entry, tutorial ends

### Phase 6 Deliverables

- [ ] SwiftData models for full game state
- [ ] Auto-save system
- [ ] Settings screen
- [ ] Onboarding tutorial
- [ ] App icon and launch screen

---

## 10. Art Style Guide

### Core Aesthetic

**"Cozy top-down fantasy pixel art with a pastel 16-bit RPG aesthetic."**

### Defining Traits

- **Tile size:** 16×16 pixels, rendered at 2-3× scale
- **Sprite size:** Characters 16×24 pixels (slightly taller than a tile)
- **Palette:** Soft, pastel-leaning tones — avoid neon or high-saturation
- **Outlines:** Clean, colored outlines (not harsh black everywhere)
- **Shading:** Hand-placed pixel shading, no smooth gradients
- **Proportions:** Cute chibi characters — large heads, small bodies
- **Animation:** 4-frame walk cycles, 2-frame idle breathing
- **Mood:** Warm, whimsical, cozy fantasy village

### Color Palette Guide

```
Grass:      #7EC850, #5CA036, #3E7A28
Dirt:       #C4A882, #A68B64, #8A7050
Water:      #5B9BD5, #4080B0, #2E6690
Stone:      #9E9E9E, #787878, #5A5A5A
Sand:       #E8D5A0, #D4BC78, #BFA360
Wood:       #B08050, #8E6438, #6E4A28
Skin tones: #FFD5B8, #F0B888, #D49868
Foliage:    #68B040, #509030, #387020
Rooftops:   #D06040, #B04830, #903828
```

### Stable Diffusion Prompt Template for Generated Sprites

```
Positive: "16-bit pixel art [ITEM], top-down perspective, 
pastel colors, clean colored outlines, fantasy RPG style, 
simple silhouette, transparent background, chibi proportions, 
cozy village aesthetic"

Negative: "realistic, photograph, 3D render, blurry, 
dark colors, complex detail, side view, isometric"
```

### Reference Games for Inspiration

- Stardew Valley (overworld tiles)
- Earthbound / Mother series (palette, charm)
- Secret of Mana (SNES tile-work)
- Celeste (pixel art clarity)
- Cozy Grove (color palette, mood)

---

## 11. Technical Risks & Mitigations

### LLM Performance

| Risk | Impact | Mitigation |
|------|--------|------------|
| Slow token generation (<10 tok/s) | Dialogue feels laggy | Stream tokens to UI, show typing indicator. Use quantized Q4_K_M model. Pre-generate NPC chats during idle. |
| Model too large (>2 GB) | App size bloated | Use on-demand resources (download after install). Consider Phi-3 mini (1.3B) as alternative. |
| Poor dialogue quality | Immersion breaks | Carefully crafted system prompts with character personality. Few-shot examples in prompt. |
| Context overflow | Character loses memory | Summarize old memories, keep rolling window of last 5 interactions. |

### Image Generation

| Risk | Impact | Mitigation |
|------|--------|------------|
| Slow generation (30+ seconds) | Player waits too long | Generate at 128×128, use 20 steps (not 50). Show "crafting" animation. Queue in background. |
| Style inconsistency | Sprites don't match base art | LoRA fine-tuned on pixel art. Post-process with palette reduction. Fallback to placeholder sprites. |
| Model size (~2 GB) | Combined with LLM = 4+ GB | On-demand resources. Option to disable generation (use placeholders). |

### Vision Classification

| Risk | Impact | Mitigation |
|------|--------|------------|
| Misclassification | Wrong item researched | Show classification result to player for confirmation before proceeding. Top-5 results as options. |
| Unsupported category | "I don't know what this is" | Graceful fallback: researcher says "Interesting... I'll need to study this more." Log for potential future support. |

### Device Compatibility

| Risk | Impact | Mitigation |
|------|--------|------------|
| Older devices (A14 and below) | AI too slow | Minimum requirement: A15 chip (iPhone 13+). Degrade gracefully: simpler model, disable image gen. |
| Memory pressure | App crashes | Monitor memory. Unload models when not in use. Generate sprites one at a time. |

---

## 12. Data Models

### SwiftData Schema

```swift
@Model
class WorldState {
    var gridWidth: Int
    var gridHeight: Int
    var tileData: Data          // Compressed 2D grid of TileCell
    var discoveredBiomeIDs: [UUID]
    var gameTime: TimeInterval  // In-game elapsed time
    var playerGridX: Int
    var playerGridY: Int
    var cameraZoom: Float
}

@Model
class CharacterModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var role: String            // CharacterRole.rawValue
    var personality: String
    var gridX: Int
    var gridY: Int
    var homeGridX: Int
    var homeGridY: Int
    var memories: [MemoryEntry] // Codable array
    var currentState: String    // CharacterState.rawValue
    var spawnedAt: Date
}

@Model
class TechTreeItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var itemDescription: String
    var category: String        // "technology", "crop", "animal", "building"
    var requirements: [ResourceRequirement] // Codable
    var isUnlocked: Bool
    var isBuilt: Bool
    var spriteAssetPath: String? // Path to generated sprite on disk
    var discoveredBy: UUID?     // Character who researched it
    var discoveredAt: Date?
}

@Model
class BiomeModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var biomeDescription: String
    var climate: String
    var primaryColorHex: String
    var secondaryColorHex: String
    var resources: [BiomeResource]  // Codable
    var gridOriginX: Int
    var gridOriginY: Int
    var gridWidth: Int
    var gridHeight: Int
    var discoveredAt: Date
}

@Model
class ResourceNode {
    @Attribute(.unique) var id: UUID
    var resourceType: String
    var biomeID: UUID
    var gridX: Int
    var gridY: Int
    var amount: Int
    var maxAmount: Int
    var regenerationRate: Float  // Per game-minute
}
```

---

## 13. AI Prompt Templates

### Researcher System Prompt

```
You are {name}, a researcher in a small fantasy village. You are curious, 
analytical, and excited about new discoveries. You speak in short, 
enthusiastic sentences.

Your personality: {personality_trait}

Your memories of past conversations:
{formatted_memories}

The village currently has these technologies: {known_tech_list}
Available biomes: {known_biomes}
Available resources: {known_resources}

When the player tells you about something new, you should:
1. Express excitement or curiosity
2. Explain what you understand about it
3. Describe what materials you'd need to build/create it
4. Mention which biome those materials might come from

Keep responses under 3 sentences for casual chat.
When generating requirements, be specific and reference known resources/biomes.
```

### Farmer System Prompt

```
You are {name}, a farmer in a small fantasy village. You are gentle, 
patient, and deeply connected to nature. You speak with warmth and 
use nature metaphors.

Your personality: {personality_trait}

Your memories of past conversations:
{formatted_memories}

The village currently grows: {known_crops}
Known animals: {known_animals}
Available biomes and their climates: {biome_climate_list}

When the player tells you about a plant or animal, you should:
1. Share what you know about caring for it
2. Describe what climate and soil/habitat it needs
3. List what resources are needed to start growing/raising it
4. Suggest which biome would be best

Keep responses under 3 sentences for casual chat.
```

### Worker System Prompt

```
You are {name}, a hardworking villager. You are practical, loyal, 
and eager to help. You speak simply and directly.

Your personality: {personality_trait}

Your current task: {current_task_or_none}
Your memories: {formatted_memories}

You take orders from the player and report on your progress.
If asked about something outside your role, suggest talking to 
the Researcher or Farmer instead.

Keep responses to 1-2 sentences.
```

### NPC System Prompt

```
You are {name}, a villager with no special role. You are 
{personality_trait}. You enjoy chatting about village life.

Your memories: {formatted_memories}
Recent village events: {recent_events}

You make small talk, comment on village happenings, and 
occasionally share rumors or observations. Keep it brief 
and charming — 1-2 sentences max.
```

### NPC-to-NPC Conversation Prompt

```
Generate a short, charming conversation between two villagers:
- {char1_name} ({char1_role}): {char1_personality}
- {char2_name} ({char2_role}): {char2_personality}

Recent village context: {recent_events}

Write 2-4 exchanges total. Keep it light and cozy. The conversation 
should feel natural for a small village. Format as:
{char1_name}: "..."
{char2_name}: "..."
```

### Biome Generation Prompt

```
You are a world-builder for a cozy fantasy village game.

Existing biomes in the world: {existing_biome_names_and_descriptions}
Current village tech level: {tech_level_description}

Generate a NEW biome that:
1. Is different from all existing biomes
2. Introduces 3-5 unique resources not found elsewhere
3. Has a distinct climate and visual identity
4. Fits the cozy fantasy aesthetic

Respond ONLY in this JSON format:
{
    "name": "...",
    "description": "A 1-2 sentence description",
    "climate": "temperate|arid|tropical|cold|volcanic|mystical",
    "primary_color_hex": "#......",
    "secondary_color_hex": "#......",
    "resources": [
        {"name": "...", "rarity": "common|uncommon|rare", "description": "..."}
    ],
    "wildlife": ["animal1", "animal2"],
    "plants": ["plant1", "plant2"],
    "terrain_features": ["feature1", "feature2"],
    "danger_level": 1
}
```

### Requirements Generation Prompt (Researcher)

```
You are a researcher determining what materials are needed to build something.

Item to build: {item_name}
Available resources in known biomes: {resource_list_with_biomes}

Respond ONLY in this JSON format:
{
    "item_name": "{item_name}",
    "description": "What this item does, 1 sentence",
    "requirements": [
        {"resource": "resource_name", "amount": N, "from_biome": "biome_name_or_unknown"}
    ],
    "build_time_minutes": N,
    "difficulty": "easy|medium|hard",
    "unlocks": ["what this enables, if anything"]
}

Use ONLY resources from the known list when possible. 
If a required resource isn't available yet, set from_biome to "unknown" — 
this hints that a new biome may need to be discovered.
```

---

## Build Order Summary

| Phase | Duration Estimate | Dependencies |
|-------|------------------|--------------|
| Phase 1: World Foundation | 1-2 weeks | None |
| Phase 2: Character System | 1-2 weeks | Phase 1 |
| Phase 3: AI Engine | 2-3 weeks | Phase 1 (can parallel with Phase 2) |
| Phase 4: Interaction Loops | 1-2 weeks | Phase 2 + Phase 3 |
| Phase 5: World Expansion | 1-2 weeks | Phase 4 |
| Phase 6: Polish | 1-2 weeks | Phase 5 |

**Start with Phase 1.** Get the world rendering and player moving first — everything else layers on top.
