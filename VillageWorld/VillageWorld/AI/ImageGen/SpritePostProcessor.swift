//
//  SpritePostProcessor.swift
//  VillageWorld
//
//  Post-processing for AI-generated or stub sprites:
//    1. Resize to the target pixel-art resolution (e.g. 32×32)
//    2. Apply nearest-neighbour filtering for crisp edges
//    3. Reduce the colour palette to a limited set of levels
//

import UIKit

enum SpritePostProcessor {

    /// Resize + palette-reduce `source` to `targetSize`.
    static func process(_ source: UIImage, targetSize: CGSize) -> UIImage {
        let resized  = resize(source, to: targetSize)
        let reduced  = reducePalette(resized, levels: 8)  // 8 levels per channel
        return reduced
    }

    // MARK: - Resize (nearest-neighbour)

    private static func resize(_ image: UIImage, to size: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        defer { UIGraphicsEndImageContext() }

        guard let ctx = UIGraphicsGetCurrentContext() else { return image }
        ctx.interpolationQuality = .none   // nearest-neighbour = pixel-art crisp
        image.draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext() ?? image
    }

    // MARK: - Palette reduction

    /// Quantises each colour channel to `levels` discrete values.
    /// E.g. levels=8 → 8³=512-colour palette — enough for pixel art.
    private static func reducePalette(_ image: UIImage, levels: Int) -> UIImage {
        guard let cgImage = image.cgImage else { return image }

        let width  = cgImage.width
        let height = cgImage.height
        let bitsPerComponent = 8
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        var pixelData = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data:             &pixelData,
            width:            width,
            height:           height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow:      bytesPerRow,
            space:            colorSpace,
            bitmapInfo:       CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let step = UInt8(max(256 / levels, 1))
        let half = step / 2
        for i in stride(from: 0, to: pixelData.count, by: 4) {
            pixelData[i]     = (pixelData[i]     / step) * step + half  // R
            pixelData[i + 1] = (pixelData[i + 1] / step) * step + half  // G
            pixelData[i + 2] = (pixelData[i + 2] / step) * step + half  // B
            // A stays as-is
        }

        guard let output = context.makeImage() else { return image }
        return UIImage(cgImage: output)
    }
}
