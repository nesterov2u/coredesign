import AppKit
import Foundation
import ImageIO

enum WorkStatus: String, Codable, CaseIterable, Identifiable {
    case active = "В работе"
    case planned = "Запланирована"
    case finished = "Завершена"
    var id: Self { self }
}

enum WorkTab: String, Codable, CaseIterable {
    case notes = "Заметки"
    case canvas = "Холст"
}

enum Service: String, CaseIterable, Identifiable {
    case automatic = "Автоматически"
    case figma = "Figma"
    case magnific = "Magnific"
    var id: Self { self }
    var detail: String {
        switch self {
        case .automatic: "Подобрать сервис по поручению"
        case .figma: "Создание и правка макетов"
        case .magnific: "Изображения и видео"
        }
    }
}

struct Material: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var storedName: String?
    var preview: String?
}

struct ChatMessage: Codable, Identifiable {
    var id = UUID()
    var author: String
    var text: String
    var context: [String] = []
    var results: [String] = []
}

struct WorkItem: Codable, Identifiable {
    var id = UUID()
    var title: String
    var status: WorkStatus = .planned
    var created = Date()
    var deadline: Date?
    var template: String?
    var brief = ""
    var materials: [Material] = []
    var tab: WorkTab = .notes
    var chatOpen = false
    var messages: [ChatMessage] = []
    var pendingGeneration = false
    var canvasFrames: [CanvasFrame]?

    static var demo: [WorkItem] {
        let calendar = Calendar.current
        func due(_ month: Int, _ day: Int) -> Date? {
            calendar.date(from: DateComponents(year: 2026, month: month, day: day))
        }
        let base = Date(timeIntervalSince1970: 1_795_478_400)
        return [
            WorkItem(title: "Обложка вебинара", status: .active, created: base, deadline: due(11, 27)),
            WorkItem(title: "Листовка для партнёров", status: .active, created: base.addingTimeInterval(-60), deadline: due(11, 30)),
            WorkItem(
                title: "Баннер Customer Story", created: base.addingTimeInterval(-120), template: "SMM-баннер",
                brief: "Подготовить два баннера для LinkedIn.\n\nКомпания — Güçlü Elektrik\nЯзыки — английский и турецкий\nФормат — шаблон Customer Story",
                materials: [Material(title: "Тексты EN и TR.docx", preview: "Güçlü Elektrik · Customer Story\n\nДемонстрационный материал на английском и турецком языках.")]
            ),
            WorkItem(title: "Обложка YouTube", created: base.addingTimeInterval(-180), deadline: due(12, 2))
        ]
    }
}

@MainActor @Observable
final class ProjectStore {
    private let directory: URL
    private var loadFailed = false
    var issue: String?
    private(set) var items: [WorkItem] = []
    let projectMaterials = [
        Material(title: "Брендбук.pdf", preview: "Демонстрационный материал проекта 1Ci."),
        Material(title: "Логотип.svg", preview: "Демонстрационный материал проекта 1Ci.")
    ]

    init(directory: URL = URL.applicationSupportDirectory.appending(path: "CoreDesign")) {
        self.directory = directory
        do {
            let data = try Data(contentsOf: directory.appending(path: "tasks.json"))
            items = try JSONDecoder().decode([WorkItem].self, from: data)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            items = WorkItem.demo
        } catch {
            loadFailed = true
            issue = "Не удалось открыть локальные данные. Перезапустите CoreDesign после восстановления файла tasks.json."
        }
    }

    func sorted(_ status: WorkStatus) -> [WorkItem] {
        items.filter { $0.status == status }.sorted { $0.created > $1.created }
    }

    func create(title: String, template: String?) -> UUID? {
        let item = WorkItem(title: title, template: template)
        return commit(items + [item]) ? item.id : nil
    }

    func update(_ id: UUID, _ change: (inout WorkItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var revised = items
        change(&revised[index])
        _ = commit(revised)
    }

    func attach(_ sources: [URL], to id: UUID, canvasFrame frameID: UUID? = nil) -> [UUID] {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return [] }
        var revised = items
        let frames = revised[index].canvasFrames ?? []
        let frameIndex = frameID.flatMap { id in frames.firstIndex { $0.id == id } }
        guard frameID == nil || frameIndex != nil else { return [] }
        var copied: [URL] = []
        var layerIDs: [UUID] = []
        do {
            try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
            for source in sources {
                let accessing = source.startAccessingSecurityScopedResource()
                defer { if accessing { source.stopAccessingSecurityScopedResource() } }
                let geometry = try frameID.map { _ in try imageSize(at: source) }
                let name = UUID().uuidString + "-" + source.lastPathComponent
                let destination = attachments.appending(path: name)
                try FileManager.default.copyItem(at: source, to: destination)
                copied.append(destination)
                let material = Material(title: source.lastPathComponent, storedName: name)
                revised[index].materials.append(material)
                if let frameIndex, let geometry {
                    let layer = frames[frameIndex].imageLayer(material: material, size: geometry)
                    revised[index].canvasFrames?[frameIndex].layers.append(layer)
                    layerIDs.append(layer.id)
                }
            }
            if commit(revised) { return layerIDs }
        } catch {
            issue = "Не удалось добавить материалы. \(error.localizedDescription)"
        }
        for file in copied { try? FileManager.default.removeItem(at: file) }
        return []
    }

    private func imageSize(at url: URL) throws -> CGSize {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
              width > 0, height > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let orientation = properties[kCGImagePropertyOrientation as String] as? Int ?? 1
        return (5...8).contains(orientation) ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    func file(for material: Material) -> URL? {
        material.storedName.map { attachments.appending(path: $0) }
    }

    private var attachments: URL { directory.appending(path: "Attachments") }

    private func commit(_ revised: [WorkItem]) -> Bool {
        guard !loadFailed else {
            issue = "Локальные данные недоступны. Изменения не сохранены."
            return false
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(revised).write(to: directory.appending(path: "tasks.json"), options: .atomic)
            items = revised
            return true
        } catch {
            issue = "Не удалось сохранить изменения. \(error.localizedDescription)"
            return false
        }
    }
}
