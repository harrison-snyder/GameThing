//
//  VisionClassifier.swift
//  VillageWorld
//
//  On-device image classification using Apple's Vision framework.
//  Uses the built-in VNClassifyImageRequest (available iOS 13+)
//  to identify objects in photos the player takes.
//
//  The Researcher and Farmer roles use this to classify items
//  the player photographs (e.g. a solar panel, a tomato plant).
//

import UIKit
import Vision

final class VisionClassifier: Sendable {

    /// Classifies `image` and returns the top result plus top-5 observations.
    func classify(image: UIImage) async throws -> ClassificationResult {
        guard let cgImage = image.cgImage else {
            throw ClassificationError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNClassifyImageRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let observations = request.results as? [VNClassificationObservation],
                      let top = observations.first else {
                    continuation.resume(throwing: ClassificationError.noResults)
                    return
                }

                let topK = observations.prefix(5).map {
                    ClassificationResult.Observation(label: $0.identifier,
                                                     confidence: $0.confidence)
                }
                continuation.resume(returning: ClassificationResult(
                    label:      top.identifier,
                    confidence: top.confidence,
                    topK:       Array(topK)
                ))
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
