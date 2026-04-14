//
//  BiomeDiscoveryManager.swift
//  VillageWorld
//
//  Phase 5: Monitors game state and triggers biome discovery when
//  any of these conditions are newly met:
//    - Village population reaches a threshold (5, 10, 15, 20...)
//    - A tech tree milestone is hit (1st entry, 3rd, 5th, 8th, 12th...)
//    - Cumulative playtime reaches a threshold (every ~15 real minutes)
//    - Player explicitly sends a Worker to explore (via callback)
//
//  When triggered, asks BiomeGenerator for a new biome template,
//  then hands it to BiomeRenderer to paint into the world.
//

import SpriteKit

final class BiomeDiscoveryManager {

    // MARK: - Config

    /// Population thresholds that trigger new biomes.
    private let populationThresholds = [5, 10, 15, 20, 25, 30]
    /// Tech tree entry counts that trigger new biomes.
    private let techThresholds = [1, 3, 5, 8, 12, 17, 23]
    /// Playtime interval (in seconds) between automatic biome discoveries.
    private let playtimeInterval: TimeInterval = 900  // 15 minutes

    // MARK: - State

    private(set) var discoveredBiomes: [BiomeModel] = []
    private var lastPopulationTrigger = 0
    private var lastTechTrigger = 0
    private var totalPlaytime: TimeInterval = 0
    private var lastPlaytimeTrigger: TimeInterval = 0
    private var isGenerating = false

    /// The maximum number of biomes the 64×64 world can hold.
    private let maxBiomes = 6

    // MARK: - External Dependencies (set by GameScene/AppState)

    var biomeGenerator: BiomeGenerator?
    var biomeRenderer: BiomeRenderer?

    /// Called when a new biome is discovered — wired by AppState.
    var onBiomeDiscovered: ((BiomeModel) -> Void)?

    // MARK: - Update (called each frame by GameScene)

    func update(
        deltaTime: TimeInterval,
        populationCount: Int,
        techEntryCount: Int,
        playerPosition: GridPosition,
        grid: inout [[TileCell]],
        tileMapManager: TileMapManager,
        fogOfWar: FogOfWar,
        scene: SKScene
    ) {
        guard !isGenerating, discoveredBiomes.count < maxBiomes else { return }

        totalPlaytime += deltaTime

        var shouldTrigger = false

        // Population check
        if let nextPop = populationThresholds.first(where: { $0 > lastPopulationTrigger }),
           populationCount >= nextPop {
            lastPopulationTrigger = nextPop
            shouldTrigger = true
        }

        // Tech milestone check
        if let nextTech = techThresholds.first(where: { $0 > lastTechTrigger }),
           techEntryCount >= nextTech {
            lastTechTrigger = nextTech
            shouldTrigger = true
        }

        // Playtime check
        if totalPlaytime - lastPlaytimeTrigger >= playtimeInterval {
            lastPlaytimeTrigger = totalPlaytime
            shouldTrigger = true
        }

        if shouldTrigger {
            triggerDiscovery(
                playerPosition: playerPosition,
                grid: &grid,
                tileMapManager: tileMapManager,
                fogOfWar: fogOfWar,
                scene: scene
            )
        }
    }

    // MARK: - Explicit Trigger (from explore task completion)

    func triggerExploreDiscovery(
        playerPosition: GridPosition,
        grid: inout [[TileCell]],
        tileMapManager: TileMapManager,
        fogOfWar: FogOfWar,
        scene: SKScene
    ) {
        guard !isGenerating, discoveredBiomes.count < maxBiomes else { return }
        triggerDiscovery(
            playerPosition: playerPosition,
            grid: &grid,
            tileMapManager: tileMapManager,
            fogOfWar: fogOfWar,
            scene: scene
        )
    }

    // MARK: - Accessors

    var biomeNames: [String] {
        discoveredBiomes.map(\.template.name)
    }

    /// All unique resource names across discovered biomes.
    var biomeResourceNames: [String] {
        discoveredBiomes
            .flatMap(\.template.resources)
            .map(\.name)
            .uniqued()
    }

    // MARK: - Private

    private func triggerDiscovery(
        playerPosition: GridPosition,
        grid: inout [[TileCell]],
        tileMapManager: TileMapManager,
        fogOfWar: FogOfWar,
        scene: SKScene
    ) {
        guard let generator = biomeGenerator,
              let renderer = biomeRenderer else { return }

        isGenerating = true
        let existingNames = discoveredBiomes.map(\.template.name)
        let techLevel = discoveredBiomes.count + 1
        let existingModels = discoveredBiomes

        // We need to capture grid as inout won't work across async boundaries.
        // Instead, generate the template synchronously via a detached task
        // and render on return. For stub mode this is instant; for real LLM
        // we accept a brief pause.

        // Use a synchronous stub-friendly approach: generate in a Task,
        // then render on the main thread.
        let gridSnapshot = grid  // value copy for the async generator
        _ = gridSnapshot  // silence unused warning — generator only needs names/level

        Task { @MainActor [weak self] in
            guard let self else { return }

            let template = await generator.generate(
                existingBiomes: existingNames,
                techLevel: techLevel
            )

            // Render needs mutable grid — we access it through the scene callback
            self.renderBiome(
                template: template,
                playerPosition: playerPosition,
                existingModels: existingModels,
                tileMapManager: tileMapManager,
                fogOfWar: fogOfWar,
                scene: scene
            )
        }
    }

    /// Called on main thread after generation completes.
    /// Requires the caller to provide a mutable grid reference.
    @MainActor
    private func renderBiome(
        template: BiomeTemplate,
        playerPosition: GridPosition,
        existingModels: [BiomeModel],
        tileMapManager: TileMapManager,
        fogOfWar: FogOfWar,
        scene: SKScene
    ) {
        // We'll get the grid reference from the scene via the render callback
        onBiomeReady?(template, playerPosition, existingModels, tileMapManager, fogOfWar, scene)
        isGenerating = false
    }

    /// Callback that GameScene provides so we can access the mutable grid.
    /// Signature: (template, playerPos, existingBiomes, tileMapMgr, fog, scene)
    var onBiomeReady: ((BiomeTemplate, GridPosition, [BiomeModel], TileMapManager, FogOfWar, SKScene) -> Void)?

    /// Called by GameScene after rendering to register the new biome.
    func registerBiome(_ biome: BiomeModel) {
        discoveredBiomes.append(biome)
        onBiomeDiscovered?(biome)
    }
}

// MARK: - Array uniqued helper

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
