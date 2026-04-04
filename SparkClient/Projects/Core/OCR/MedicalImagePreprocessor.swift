import CoreImage
import UIKit

final class SparkMedicalImagePreprocessor {
    struct Config: Sendable {
        var contrastFactor: Double = 1.1
        var brightnessFactor: Double = 0.02
        var sharpnessFactor: Double = 0.3
        var enableNoiseReduction: Bool = true
        var enhanceEdges: Bool = false

        static let balanced = Config()
    }

    static let shared = SparkMedicalImagePreprocessor()

    private let context: CIContext

    init() {
        if let device = MTLCreateSystemDefaultDevice() {
            self.context = CIContext(mtlDevice: device)
        } else {
            self.context = CIContext()
        }
    }

    func preprocess(_ image: UIImage, config: Config = .balanced) -> UIImage {
        guard let ciImage = CIImage(image: image) else { return image }

        var output = applyGrayscale(ciImage)
        if config.enableNoiseReduction {
            output = applyNoiseReduction(output)
        }
        output = applyContrastAndBrightness(output, contrast: config.contrastFactor, brightness: config.brightnessFactor)
        if config.enhanceEdges {
            output = applyEdgeEnhancement(output)
        }
        output = applySharpen(output, intensity: config.sharpnessFactor)

        guard let cgImage = context.createCGImage(output, from: output.extent) else { return image }
        return UIImage(cgImage: cgImage)
    }

    private func applyGrayscale(_ image: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CIPhotoEffectMono") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        return filter.outputImage ?? image
    }

    private func applyNoiseReduction(_ image: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CINoiseReduction") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(0.02, forKey: "inputNoiseLevel")
        filter.setValue(0.4, forKey: kCIInputSharpnessKey)
        return filter.outputImage ?? image
    }

    private func applyContrastAndBrightness(_ image: CIImage, contrast: Double, brightness: Double) -> CIImage {
        guard let filter = CIFilter(name: "CIColorControls") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(contrast, forKey: kCIInputContrastKey)
        filter.setValue(brightness, forKey: kCIInputBrightnessKey)
        filter.setValue(0.0, forKey: kCIInputSaturationKey)
        return filter.outputImage ?? image
    }

    private func applyEdgeEnhancement(_ image: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CISharpenLuminance") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(0.4, forKey: kCIInputSharpnessKey)
        return filter.outputImage ?? image
    }

    private func applySharpen(_ image: CIImage, intensity: Double) -> CIImage {
        guard let filter = CIFilter(name: "CIUnsharpMask") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(2.5, forKey: kCIInputRadiusKey)
        filter.setValue(intensity, forKey: kCIInputIntensityKey)
        return filter.outputImage ?? image
    }
}
