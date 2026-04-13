//
//  PromptBuilder.swift
//  VillageWorld
//
//  Constructs role-specific system and user prompts using the
//  templates from the build plan.  Every character's LLM call
//  flows through these builders so prompts stay consistent.
//

import Foundation

// MARK: - Interaction Context

/// Snapshot of game state handed to the prompt builder.
/// Populated from live game data in Phase 4.
struct InteractionContext {
    var knownTechnologies: [String] = []
    var knownCrops:        [String] = []
    var knownAnimals:      [String] = []
    var knownBiomes:       [String] = ["Grass Plains"]
    var knownResources:    [String] = ["wood", "stone", "food"]
    var recentEvents:      [String] = []
}

// MARK: - Prompt Builder

enum PromptBuilder {

    /// Builds the *system* prompt that defines who the character is.
    static func systemPrompt(for character: CharacterEntity,
                             context: InteractionContext) -> String {
        switch character.role {
        case .researcher: return researcherSystem(character, context)
        case .farmer:     return farmerSystem(character, context)
        case .worker:     return workerSystem(character, context)
        case .npc:        return npcSystem(character, context)
        }
    }

    /// Builds the *user* prompt that represents what the player said.
    static func userPrompt(playerInput: String?,
                           context: InteractionContext) -> String {
        guard let input = playerInput, !input.isEmpty else {
            return "The player approaches you and greets you."
        }
        return "The player says: \"\(input)\""
    }

    // MARK: - Role Templates

    private static func researcherSystem(
        _ c: CharacterEntity, _ ctx: InteractionContext
    ) -> String {
        """
        You are \(c.name), a researcher in a small fantasy village. \
        You are curious, analytical, and excited about new discoveries. \
        You speak in short, enthusiastic sentences.

        Your personality: \(c.personality)

        Your memories of past conversations:
        \(formattedMemories(c.memory))

        The village currently has these technologies: \(ctx.knownTechnologies.joined(separator: ", ").ifEmpty("none yet"))
        Available biomes: \(ctx.knownBiomes.joined(separator: ", "))
        Available resources: \(ctx.knownResources.joined(separator: ", "))

        When the player tells you about something new, you should:
        1. Express excitement or curiosity
        2. Explain what you understand about it
        3. Describe what materials you'd need to build/create it
        4. Mention which biome those materials might come from

        Keep responses under 3 sentences for casual chat.
        When generating requirements, be specific and reference known resources/biomes.
        """
    }

    private static func farmerSystem(
        _ c: CharacterEntity, _ ctx: InteractionContext
    ) -> String {
        """
        You are \(c.name), a farmer in a small fantasy village. \
        You are gentle, patient, and deeply connected to nature. \
        You speak with warmth and use nature metaphors.

        Your personality: \(c.personality)

        Your memories of past conversations:
        \(formattedMemories(c.memory))

        The village currently grows: \(ctx.knownCrops.joined(separator: ", ").ifEmpty("nothing yet"))
        Known animals: \(ctx.knownAnimals.joined(separator: ", ").ifEmpty("none yet"))
        Available biomes and their climates: \(ctx.knownBiomes.joined(separator: ", "))

        When the player tells you about a plant or animal, you should:
        1. Share what you know about caring for it
        2. Describe what climate and soil/habitat it needs
        3. List what resources are needed to start growing/raising it
        4. Suggest which biome would be best

        Keep responses under 3 sentences for casual chat.
        """
    }

    private static func workerSystem(
        _ c: CharacterEntity, _ ctx: InteractionContext
    ) -> String {
        let taskDesc = c.currentTask?.description ?? "none"
        return """
        You are \(c.name), a hardworking villager. You are practical, loyal, \
        and eager to help. You speak simply and directly.

        Your personality: \(c.personality)

        Your current task: \(taskDesc)
        Your memories: \(formattedMemories(c.memory))

        You take orders from the player and report on your progress.
        If asked about something outside your role, suggest talking to \
        the Researcher or Farmer instead.

        Keep responses to 1-2 sentences.
        """
    }

    private static func npcSystem(
        _ c: CharacterEntity, _ ctx: InteractionContext
    ) -> String {
        """
        You are \(c.name), a villager with no special role. \
        You are \(c.personality). You enjoy chatting about village life.

        Your memories: \(formattedMemories(c.memory))
        Recent village events: \(ctx.recentEvents.joined(separator: "; ").ifEmpty("nothing notable"))

        You make small talk, comment on village happenings, and \
        occasionally share rumors or observations. Keep it brief \
        and charming — 1-2 sentences max.
        """
    }

    // MARK: - Helpers

    private static func formattedMemories(_ memories: [MemoryEntry]) -> String {
        guard !memories.isEmpty else { return "none yet" }
        return memories.suffix(5).map { "- \($0.summary)" }.joined(separator: "\n")
    }
}

// MARK: - String convenience

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
