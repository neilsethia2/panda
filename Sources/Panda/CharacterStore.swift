import AppKit
import Combine
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// The user's own tab closer: any picture they pick, cut out from its background, trimmed
/// and saved next to the statistics. The run animation is applied to it live when it moves.
final class CharacterStore: ObservableObject {
    static let shared = CharacterStore()

    @Published private(set) var image: NSImage?
    @Published private(set) var working = false
    /// One line telling the user what happened with their last picture.
    @Published var note: String?

    static var fileURL: URL { PandaPaths.supportDir.appendingPathComponent("character.png") }

    private init() {
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: CharacterStore.fileURL) else {
            image = nil
            return
        }
        image = NSImage(data: data)
    }

    var hasImage: Bool { image != nil }

    /// Show the system file picker, then import what was chosen.
    func chooseImage(removeBackground: Bool, completion: @escaping (Bool) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a picture to use as your tab closer."
        panel.prompt = "Use this picture"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else {
            completion(false)
            return
        }
        importImage(at: url, removeBackground: removeBackground, completion: completion)
    }

    func importImage(at url: URL, removeBackground: Bool, completion: @escaping (Bool) -> Void) {
        working = true
        note = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = CharacterStore.loadAndProcess(url: url, removeBackground: removeBackground)
            var saved = false
            if let result = result {
                PandaPaths.ensureSupportDir()
                let rep = NSBitmapImageRep(cgImage: result.image)
                if let png = rep.representation(using: .png, properties: [:]) {
                    saved = (try? png.write(to: CharacterStore.fileURL, options: .atomic)) != nil
                }
            }
            DispatchQueue.main.async {
                self.working = false
                if saved, let result = result {
                    self.load()
                    if result.cutOut {
                        self.note = "Background removed. Your character is ready."
                    } else if result.hadTransparency {
                        self.note = "Your character is ready."
                    } else if removeBackground {
                        self.note = "Couldn't find a clear subject to cut out, so the whole picture is used."
                    } else {
                        self.note = "Your character is ready."
                    }
                } else {
                    self.note = "That file couldn't be read as a picture."
                }
                completion(saved)
            }
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: CharacterStore.fileURL)
        image = nil
        note = nil
    }

    // MARK: Processing (background thread)

    struct Processed {
        let image: CGImage
        let cutOut: Bool
        let hadTransparency: Bool
    }

    static func loadAndProcess(url: URL, removeBackground: Bool) -> Processed? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        // Decode at a sensible size with the photo's rotation already applied.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1024,
        ]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return process(decoded, removeBackground: removeBackground)
    }

    static func process(_ input: CGImage, removeBackground: Bool) -> Processed {
        var image = input
        var cutOut = false
        let transparent = hasTransparency(image)

        if removeBackground, !transparent {
            if #available(macOS 14.0, *), let lifted = liftSubject(image) {
                image = lifted
                cutOut = true
            }
        }
        if let trimmed = trimTransparentEdges(image) { image = trimmed }
        if let small = scaled(image, maxSide: 400) { image = small }
        return Processed(image: image, cutOut: cutOut, hadTransparency: transparent)
    }

    /// Uses the same subject detection as "lift subject from background" in Photos.
    @available(macOS 14.0, *)
    static func liftSubject(_ image: CGImage) -> CGImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
            guard let observation = request.results?.first, !observation.allInstances.isEmpty else { return nil }
            let buffer = try observation.generateMaskedImage(
                ofInstances: observation.allInstances,
                from: handler,
                croppedToInstancesExtent: true
            )
            let ciImage = CIImage(cvPixelBuffer: buffer)
            return CIContext().createCGImage(ciImage, from: ciImage.extent)
        } catch {
            return nil
        }
    }

    private static func pixels(of image: CGImage, width: Int, height: Int) -> [UInt8]? {
        guard width > 0, height > 0 else { return nil }
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? data : nil
    }

    static func hasTransparency(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        default:
            break
        }
        // Sample a small copy: a picture counts as transparent if a real share of it is see-through.
        let side = 64
        guard let data = pixels(of: image, width: side, height: side) else { return false }
        var clear = 0
        for i in 0..<(side * side) where data[i * 4 + 3] < 128 { clear += 1 }
        return clear > (side * side) / 50
    }

    /// Crop away empty margins so the character's feet sit on the bottom edge.
    static func trimTransparentEdges(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard let data = pixels(of: image, width: width, height: height) else { return nil }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * width * 4
            for x in 0..<width where data[row + x * 4 + 3] > 20 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let rect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        if rect.width >= CGFloat(width) && rect.height >= CGFloat(height) { return nil }
        return image.cropping(to: rect)
    }

    static func scaled(_ image: CGImage, maxSide: Int) -> CGImage? {
        let longest = max(image.width, image.height)
        guard longest > maxSide else { return nil }
        let ratio = CGFloat(maxSide) / CGFloat(longest)
        let width = max(1, Int(CGFloat(image.width) * ratio))
        let height = max(1, Int(CGFloat(image.height) * ratio))
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
