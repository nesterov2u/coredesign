import AppKit
import CoreText
import SwiftUI

enum PrototypeFonts {
    private static let descriptors: [String: CTFontDescriptor] = {
        guard let directory = Bundle.main.resourceURL?.appending(path: "Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return [:] }
        var descriptors: [String: CTFontDescriptor] = [:]
        for file in files where file.pathExtension == "ttf" {
            let family = file.deletingPathExtension().lastPathComponent
            if let fonts = CTFontManagerCreateFontDescriptorsFromURL(file as CFURL) as? [CTFontDescriptor] {
                descriptors[family] = fonts.first
            }
        }
        return descriptors
    }()

    static func font(_ name: String, size: CGFloat) -> Font? {
        let parts = name.split(separator: "-", maxSplits: 1)
        guard parts.count == 2, let descriptor = descriptors[String(parts[0])] else { return nil }
        let weighted = CTFontDescriptorCreateCopyWithVariation(descriptor, 0x77676874 as NSNumber, parts[1] == "SemiBold" ? 600 : 400)
        return Font(CTFontCreateWithFontDescriptor(weighted, size, nil))
    }
}
