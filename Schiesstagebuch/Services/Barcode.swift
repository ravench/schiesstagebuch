import CoreImage.CIFilterBuiltins
import Foundation

/// Draws Code 128 barcodes, the symbology printed on the SSV membership card.
enum BarcodeRenderer {
    private static let context = CIContext()

    /// Code 128 covers printable ASCII; Core Image rejects anything else.
    static func canEncode(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { $0.value >= 32 && $0.value < 127 }
    }

    /// A crisp black-on-white bitmap, one module scaled to `scale` pixels; nil if the value can't be encoded.
    static func code128(_ value: String, scale: CGFloat = 4) -> CGImage? {
        guard canEncode(value) else { return nil }
        let filter = CIFilter.code128BarcodeGenerator()
        filter.message = Data(value.utf8)
        filter.quietSpace = 10
        filter.barcodeHeight = 50
        guard let output = filter.outputImage, !output.extent.isInfinite, !output.extent.isEmpty else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return context.createCGImage(scaled, from: scaled.extent)
    }

    /// Width of the Code 128 symbol in modules, quiet zones included.
    static func code128Modules(_ value: String) -> Int? {
        code128(value, scale: 1)?.width
    }

    /// Largest whole number of pixels per module so a symbol of `modules` fits into `pixels`.
    /// Whole pixels keep every bar the same width, which scanners need.
    static func moduleScale(fitting pixels: CGFloat, modules: Int) -> Int {
        guard modules > 0, pixels.isFinite else { return 1 }
        return max(1, Int(pixels) / modules)
    }
}
