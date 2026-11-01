import UIKit
import Vision

/// On-device barcode detection (Vision). Nothing leaves the phone.
enum BarcodeReader {
    /// The barcodes on one photo, with retail product codes marked as such.
    static func barcodes(in image: UIImage) async -> [ScannedBarcode] {
        guard let cgImage = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await Task.detached(priority: .userInitiated) {
            let request = VNDetectBarcodesRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            try? handler.perform([request])
            return (request.results ?? []).compactMap { observation -> ScannedBarcode? in
                guard let payload = observation.payloadStringValue, !payload.isEmpty else { return nil }
                return ScannedBarcode(payload: payload, kind: kind(of: observation))
            }
        }.value
    }

    private static func kind(of observation: VNBarcodeObservation) -> ScannedBarcode.Kind {
        switch observation.symbology {
        case .ean8, .ean13, .upce, .itf14:
            return .product
        case .gs1DataBar, .gs1DataBarExpanded, .gs1DataBarLimited:
            return .gs1
        default:
            return observation.isGS1DataCarrier ? .gs1 : .other
        }
    }
}
