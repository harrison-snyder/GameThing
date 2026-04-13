//
//  ClassificationResult.swift
//  VillageWorld
//

import Foundation

struct ClassificationResult: Sendable {

    struct Observation: Sendable {
        let label:      String
        let confidence: Float
    }

    /// Top-1 label (e.g. "solar_panel").
    let label: String
    /// Top-1 confidence score (0–1).
    let confidence: Float
    /// Top-K observations for further refinement.
    let topK: [Observation]
}

enum ClassificationError: Error, LocalizedError {
    case invalidImage
    case noResults

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "The image could not be processed."
        case .noResults:    return "No classification results were returned."
        }
    }
}
