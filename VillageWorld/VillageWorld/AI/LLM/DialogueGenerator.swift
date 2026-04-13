//
//  DialogueGenerator.swift
//  VillageWorld
//
//  Streams character dialogue one token at a time via LLMService.
//  Automatically builds the correct system prompt for the character's
//  role, personality, and memory.
//

import Foundation

final class DialogueGenerator: Sendable {

    private let llm: LLMService

    init(llm: LLMService) {
        self.llm = llm
    }

    /// Streams dialogue tokens for `character` responding to `playerInput`.
    /// Yields one word (plus trailing space) at a time for incremental UI display.
    func generateDialogue(
        character:   CharacterEntity,
        playerInput: String?,
        context:     InteractionContext
    ) async -> AsyncStream<String> {
        let system = PromptBuilder.systemPrompt(for: character, context: context)
        let user   = PromptBuilder.userPrompt(playerInput: playerInput, context: context)
        return await llm.generate(systemPrompt: system, userPrompt: user,
                                  maxTokens: 200, temperature: 0.8)
    }

    /// Collects the full response for use cases that don't need streaming
    /// (e.g. NPC-to-NPC background chatter).
    func generateFullDialogue(
        character:   CharacterEntity,
        playerInput: String?,
        context:     InteractionContext
    ) async -> String {
        let system = PromptBuilder.systemPrompt(for: character, context: context)
        let user   = PromptBuilder.userPrompt(playerInput: playerInput, context: context)
        return await llm.generateFull(systemPrompt: system, userPrompt: user,
                                      maxTokens: 200, temperature: 0.8)
    }
}
