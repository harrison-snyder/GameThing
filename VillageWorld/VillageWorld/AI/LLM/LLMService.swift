//
//  LLMService.swift
//  VillageWorld
//
//  Thread-safe actor wrapping on-device LLM inference via llama.cpp.
//
//  Ships with a stub backend (canned role-aware responses) that works
//  without any model file.  Once a GGUF is bundled and loadModel(at:)
//  is called, the actor transparently switches to real inference.
//

import Foundation
import llama

// MARK: - Errors

enum LLMError: Error {
    case modelLoadFailed
    case contextCreationFailed
}

// MARK: - Actor

actor LLMService {

    // MARK: State

    private(set) var isModelLoaded = false
    private var model:   OpaquePointer?
    private var context: OpaquePointer?

    // MARK: - Model loading

    /// Call once at launch after the GGUF file is available.
    func loadModel(at path: String) async throws {
        llama_backend_init()

        var mp = llama_model_default_params()
        mp.n_gpu_layers = 99          // Metal: offload all layers to GPU

        guard let m = llama_model_load_from_file(path, mp) else {
            throw LLMError.modelLoadFailed
        }

        var cp = llama_context_default_params()
        cp.n_ctx   = 2048
        cp.n_batch = 512

        guard let c = llama_init_from_model(m, cp) else {
            llama_model_free(m)
            throw LLMError.contextCreationFailed
        }

        self.model   = m
        self.context = c
        isModelLoaded = true
    }

    // MARK: - Token streaming

    /// Returns an AsyncStream that yields tokens as they are produced.
    func generate(
        systemPrompt: String,
        userPrompt:   String,
        maxTokens:    Int    = 256,
        temperature:  Double = 0.8
    ) -> AsyncStream<String> {
        if isModelLoaded {
            return llamaCppGenerate(system: systemPrompt, user: userPrompt,
                                    maxTokens: maxTokens, temperature: temperature)
        } else {
            return stubGenerate(system: systemPrompt, user: userPrompt)
        }
    }

    /// Convenience — collects the full response into a single string.
    func generateFull(
        systemPrompt: String,
        userPrompt:   String,
        maxTokens:    Int    = 256,
        temperature:  Double = 0.8
    ) async -> String {
        var result = ""
        for await token in generate(systemPrompt: systemPrompt,
                                    userPrompt:   userPrompt,
                                    maxTokens:    maxTokens,
                                    temperature:  temperature) {
            result += token
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - llama.cpp backend

    private func llamaCppGenerate(
        system: String, user: String, maxTokens: Int, temperature: Double
    ) -> AsyncStream<String> {
        guard let model, let context else {
            return stubGenerate(system: system, user: user)
        }

        // Capture pointers for use inside the non-isolated Task below.
        let m = model
        let c = context

        return AsyncStream { continuation in
            Task {
                defer { continuation.finish() }

                // Llama 3.2 Instruct chat template
                let prompt = """
                <|begin_of_text|><|start_header_id|>system<|end_header_id|>

                \(system)<|eot_id|><|start_header_id|>user<|end_header_id|>

                \(user)<|eot_id|><|start_header_id|>assistant<|end_header_id|>

                """

                // ── Tokenise ──────────────────────────────────────────────
                // llama_tokenize now takes llama_vocab*, not llama_model*
                let vocab = llama_model_get_vocab(m)
                let maxPromptTokens = 1024
                var tokens = [llama_token](repeating: 0, count: maxPromptTokens)
                let nTokens = prompt.withCString { ptr in
                    llama_tokenize(vocab, ptr, Int32(prompt.utf8.count),
                                   &tokens, Int32(maxPromptTokens),
                                   /*add_special*/ true,
                                   /*parse_special*/ true)
                }
                guard nTokens > 0 else { return }
                tokens = Array(tokens.prefix(Int(nTokens)))

                // ── Sampler chain ─────────────────────────────────────────
                var sparams = llama_sampler_chain_default_params()
                let sampler = llama_sampler_chain_init(sparams)
                llama_sampler_chain_add(sampler,
                    llama_sampler_init_temp(Float(temperature)))
                llama_sampler_chain_add(sampler,
                    llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max)))
                defer { llama_sampler_free(sampler) }

                // ── Prefill (process entire prompt) ───────────────────────
                llama_memory_clear(llama_get_memory(c), true)
                var batch = llama_batch_get_one(&tokens, Int32(tokens.count))
                guard llama_decode(c, batch) == 0 else { return }

                // ── Decode loop ───────────────────────────────────────────
                for _ in 0 ..< maxTokens {
                    let token = llama_sampler_sample(sampler, c, -1)

                    if llama_token_is_eog(vocab, token) { break }

                    // Token ID → UTF-8 string piece
                    var buf = [CChar](repeating: 0, count: 256)
                    let len = llama_token_to_piece(vocab, token, &buf, 256,
                                                   /*lstrip*/ 0,
                                                   /*special*/ false)
                    if len > 0 {
                        let bytes = buf.prefix(Int(len)).map { UInt8(bitPattern: $0) }
                        if let piece = String(bytes: bytes, encoding: .utf8), !piece.isEmpty {
                            continuation.yield(piece)
                        }
                    }

                    // Accept + decode next token
                    llama_sampler_accept(sampler, token)
                    var t = token
                    batch = llama_batch_get_one(&t, 1)
                    guard llama_decode(c, batch) == 0 else { break }
                }

                llama_memory_clear(llama_get_memory(c), true)
            }
        }
    }

    // MARK: - Stub backend

    private func stubGenerate(system: String, user: String) -> AsyncStream<String> {
        let role     = detectRole(in: system)
        // Requirements prompts ask for JSON — return stub JSON instead of chat text
        let isJsonRequest = system.lowercased().contains("respond only with the requested json")
        let response: String
        if isJsonRequest {
            response = StubResponses.requirementsJSON(role: role, userInput: user)
        } else {
            response = StubResponses.pick(role: role, userInput: user)
        }
        return streamWords(response)
    }

    private func detectRole(in systemPrompt: String) -> String {
        let lower = systemPrompt.lowercased()
        if lower.contains("researcher") { return "researcher" }
        if lower.contains("farmer")     { return "farmer" }
        if lower.contains("worker")     { return "worker" }
        return "npc"
    }

    private func streamWords(_ text: String) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task { [text] in
                for word in text.split(separator: " ") {
                    try? await Task.sleep(for: .milliseconds(Int.random(in: 35...75)))
                    continuation.yield(String(word) + " ")
                }
                continuation.finish()
            }
        }
    }
}

// MARK: - Canned responses for stub mode

private enum StubResponses {

    static func pick(role: String, userInput: String) -> String {
        switch role {
        case "researcher": return researcher.randomElement()!
        case "farmer":     return farmer.randomElement()!
        case "worker":     return worker.randomElement()!
        case "engineer":   return engineer.randomElement()!
        default:           return npc.randomElement()!
        }
    }

    /// Returns a valid JSON stub for offline requirements generation.
    /// Uses the item name from the user prompt to build plausible requirements.
    static func requirementsJSON(role: String, userInput: String) -> String {
        // Extract the item name from the prompt ("The player wants to build/grow/raise: <item>")
        let item: String
        if let range = userInput.range(of: ": ", options: .backwards) {
            item = String(userInput[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            item = "item"
        }

        let pools: [([[String: Any]], Int, String)] = [
            ([["resource": "wood",    "amount": 6, "biome_hint": "Forest"],
              ["resource": "iron",    "amount": 3, "biome_hint": "Mountains"]], 12, "medium"),
            ([["resource": "clay",    "amount": 5, "biome_hint": "Riverbank"],
              ["resource": "fiber",   "amount": 4, "biome_hint": "Grass Plains"]], 8, "easy"),
            ([["resource": "stone",   "amount": 8, "biome_hint": "Mountains"],
              ["resource": "coal",    "amount": 3, "biome_hint": "Mountains"]], 20, "hard"),
            ([["resource": "leather", "amount": 4, "biome_hint": "Savanna"],
              ["resource": "bone",    "amount": 2, "biome_hint": "Savanna"]], 10, "medium"),
            ([["resource": "glass",   "amount": 3, "biome_hint": "Desert"],
              ["resource": "sand",    "amount": 5, "biome_hint": "Desert"]], 15, "medium"),
            ([["resource": "silk",    "amount": 3, "biome_hint": "Forest"],
              ["resource": "dye",     "amount": 2, "biome_hint": "Meadow"]], 7, "easy"),
            ([["resource": "resin",   "amount": 4, "biome_hint": "Forest"],
              ["resource": "wood",    "amount": 3, "biome_hint": "Forest"]], 9, "easy"),
            ([["resource": "copper",  "amount": 5, "biome_hint": "Mountains"],
              ["resource": "tin",     "amount": 3, "biome_hint": "Mountains"]], 18, "hard"),
        ]

        let idx = abs(item.hashValue) % pools.count
        let (reqs, time, diff) = pools[idx]
        let reqsJSON = reqs.map { r in
            "{\"resource\":\"\(r["resource"]!)\",\"amount\":\(r["amount"]!),\"biome_hint\":\"\(r["biome_hint"]!)\"}"
        }.joined(separator: ",")

        return """
        {"item_name":"\(item)","description":"A \(item) crafted using local materials.","requirements":[\(reqsJSON)],"build_time_minutes":\(time),"difficulty":"\(diff)"}
        """
    }

    static let researcher = [
        "Fascinating! I've been pondering something very similar. Let me dig through my notes and I'll have a full report for you shortly.",
        "This is remarkable — the underlying principles could advance our village significantly. I'll need some time to study the details.",
        "Hmm, intriguing. I've read about something like this in the old texts. Give me a moment to cross-reference my findings.",
        "Excellent! The theoretical framework is sound. We'll need specific materials to put it into practice, but I believe it's within reach.",
        "A bold idea! Let me think about the resource requirements. I suspect the mountains hold what we need.",
    ]

    static let farmer = [
        "The soil speaks to those who listen. I reckon with the right conditions we could grow just about anything here.",
        "Nature has its own pace, friend. But I can feel it — this season is going to be bountiful.",
        "I've seen something like that in the wild meadows east of here. With a bit of patience, we could cultivate it.",
        "The rains have been kind this year. If we prepare the beds now, we'll have a fine harvest before long.",
        "Every seed tells a story. Let me study this one and I'll know exactly what it needs to flourish.",
    ]

    static let worker = [
        "Just point me where you need me. I've got the tools and the will to get it done.",
        "That's a solid plan. Give me the materials and I'll have it built before sundown.",
        "Nothing a bit of hard work can't fix. Let me take a look at what we need.",
        "I can handle that. Stone, wood, and steady hands — that's what construction takes.",
        "Ready when you are. I'll start clearing the site right away.",
    ]

    static let engineer = [
        "Now that's a challenge I can sink my teeth into. Let me sketch out the blueprints.",
        "I've been tinkering with something similar. The key is getting the right components together.",
        "Give me the raw materials and I'll forge you something extraordinary. Precision is my specialty.",
        "Every great machine starts with a single gear. Let me figure out what we need.",
        "I can build that! We'll need some specific parts — let me work out the material list.",
    ]

    static let npc = [
        "Beautiful day in the village, isn't it? I was just taking a walk by the old path.",
        "I heard the researcher has been working on something big. Exciting times!",
        "Have you tried the farmer's latest crop? Simply delicious, I must say.",
        "This village has come a long way since I arrived. It feels like home now.",
        "I was just chatting with the worker — seems like there are big plans ahead.",
        "The fog beyond the village gives me the chills. I wonder what lies out there.",
    ]
}
