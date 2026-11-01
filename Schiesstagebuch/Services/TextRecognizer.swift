import UIKit
import Vision

/// On-device text recognition (Vision). Nothing leaves the phone.
enum TextRecognizer {
    /// The recognised lines of one photo with their positions, origin top left.
    static func lines(in image: UIImage) async -> [OCRLine] {
        guard let cgImage = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            // The strips are mostly numbers; language correction would "fix" them into words.
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["de-DE", "fr-FR", "it-IT", "en-US"]
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            try? handler.perform([request])
            return (request.results ?? []).compactMap { observation -> OCRLine? in
                guard let top = observation.topCandidates(1).first else { return nil }
                let box = observation.boundingBox
                return OCRLine(text: top.string, x: Double(box.minX), y: Double(1 - box.midY),
                               width: Double(box.width), height: Double(box.height),
                               confidence: Double(top.confidence))
            }
        }.value
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
