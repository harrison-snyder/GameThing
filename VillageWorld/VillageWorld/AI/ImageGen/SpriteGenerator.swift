//
//  SpriteGenerator.swift
//  VillageWorld
//
//  Generates pixel-art item sprites for the game.
//
//  Current mode: STUB — produces a tinted square with the item's
//  initial letter.  When Apple's ml-stable-diffusion Core ML package
//  is added, this actor switches to a real Stable Diffusion pipeline
//  generating 16-bit pixel art sprites at 128×128 then down-scaled.
//
//  To enable Stable Diffusion:
//    1. Add the ml-stable-diffusion Swift Package
//       (https://github.com/apple/ml-stable-diffusion)
//    2. Place the compiled Core ML model in the bundle.
//    3. Uncomment the pipeline code in `generateWithSD`.
//

import UIKit

actor SpriteGenerator {

    /// Generates (or retrieves from cache) a sprite for `itemName`.
    func generateSprite(
        for itemName: String,
        size: CGSize = CGSize(width: 32, height: 32)
    ) async -> UIImage {
        // Check cache first
        if let cached = SpriteCache.load(name: itemName) {
            return cached
        }

        // Stub: create a tinted pixel-art square
        let image = stubSprite(for: itemName, size: size)
        let processed = SpritePostProcessor.process(image, targetSize: size)
        SpriteCache.save(processed, name: itemName)
        return processed
    }

    // MARK: - Stub sprite

    private func stubSprite(for name: String, size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            // Deterministic pastel colour derived from name
            let hue = CGFloat(abs(name.hashValue) % 360) / 360.0
            UIColor(hue: hue, saturation: 0.40, brightness: 0.88, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            // Border
            UIColor.black.withAlphaComponent(0.25).setStroke()
            ctx.stroke(CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5))

            // Initial letter
            let letter = String(name.prefix(1)).uppercased()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: size.width * 0.45),
                .foregroundColor: UIColor.white,
            ]
            let ts = (letter as NSString).size(withAttributes: attrs)
            let origin = CGPoint(x: (size.width  - ts.width)  / 2,
                                 y: (size.height - ts.height) / 2)
            (letter as NSString).draw(at: origin, withAttributes: attrs)
        }
    }

    // MARK: - Stable Diffusion (placeholder)

    /*
    private func generateWithSD(for itemName: String) async throws -> UIImage {
        let prompt = """
        16-bit pixel art sprite of \(itemName), top-down view, \
        pastel colors, clean outlines, cozy fantasy style, \
        transparent background, 64x64 pixels
        """
        let image = try pipeline.generateImages(
            prompt: prompt,
            negativePrompt: "realistic, 3D, photograph, blurry",
            stepCount: 20,
            guidanceScale: 7.5
        ).first!
        return UIImage(cgImage: image)
    }
    */
}

// MARK: - Simple disk cache

private enum SpriteCache {

    private static var cacheDir: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GeneratedSprites", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func save(_ image: UIImage, name: String) {
        guard let data = image.pngData() else { return }
        let url = cacheDir.appendingPathComponent(sanitised(name) + ".png")
        try? data.write(to: url)
    }

    static func load(name: String) -> UIImage? {
        let url = cacheDir.appendingPathComponent(sanitised(name) + ".png")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private static func sanitised(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}
