import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct CanvasFrame: Codable, Identifiable {
    var id = UUID()
    var name: String
    var width = 1080
    var height = 1080
    var fill = 0xFFFFFF
    var layers: [CanvasLayer] = []

    static let sizes = [
        ("Квадрат", 1080, 1080),
        ("Соотношение 16:9", 1920, 1080),
        ("Соотношение 9:16", 1080, 1920)
    ]

    func imageLayer(material: Material, size: CGSize) -> CanvasLayer {
        let scale = min(CGFloat(width) / size.width, CGFloat(height) / size.height, 1)
        let w = max(1, Int((size.width * scale).rounded(.down)))
        let h = max(1, Int((size.height * scale).rounded(.down)))
        return CanvasLayer(name: material.title, x: (width - w) / 2, y: (height - h) / 2, width: w, height: h, material: material)
    }
}

struct CanvasLayer: Codable, Identifiable {
    var id = UUID()
    var name = "Текст"
    var x: Int
    var y: Int
    var width: Int
    var height: Int
    var text = "Текст"
    var fontSize = 64
    var fill = 0x202536
    var material: Material?

    var icon: String { material == nil ? "textformat" : "photo" }
}

struct TaskCanvas<TaskListContent: View>: View {
    @Environment(\.design) private var design
    let store: ProjectStore
    let item: WorkItem
    let back: () -> Void
    @ViewBuilder var tasks: () -> TaskListContent

    @ViewState private var frameID: UUID?
    @ViewState private var layerID: UUID?
    @ViewState private var zoom: Int?
    @ViewState private var importFrameID: UUID?
    @ViewState private var importing = false
    @ViewState private var removingFrame = false
    @ViewState private var showsTasks = false

    private var frames: [CanvasFrame] { item.canvasFrames ?? [] }
    private var frame: CanvasFrame? { frames.first { $0.id == frameID } ?? frames.first }
    private var layer: CanvasLayer? { frame?.layers.first { $0.id == layerID } }

    var body: some View {
        HStack(spacing: 0) {
            hierarchy
            Divider()
            VStack(spacing: 0) {
                board
                Divider()
                tools
            }
            if let frame {
                Divider()
                inspector(frame)
            }
        }
        .background(design.surface)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            guard let importFrameID else { return }
            switch result {
            case .success(let files):
                if let id = store.attach(files, to: item.id, canvasFrame: importFrameID).last {
                    frameID = importFrameID
                    layerID = id
                }
            case .failure(let error):
                store.issue = error.localizedDescription
            }
        }
        .confirmationDialog("Удалить фрейм и его слои?", isPresented: $removingFrame, titleVisibility: .visible) {
            Button("Удалить фрейм", role: .destructive) {
                guard let id = frame?.id else { return }
                store.update(item.id) { $0.canvasFrames?.removeAll { $0.id == id } }
                frameID = nil
                layerID = nil
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    private var hierarchy: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                ChipButton(title: "Назад", compact: true, icon: "arrow.left", action: back)
                Text(item.title).font(design.heading(15)).lineLimit(2)
                Picker("Боковая панель", selection: $showsTasks) {
                    Text("Задачи").tag(true)
                    Text("Слои").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if showsTasks {
                    tasks()
                } else {
                    sectionTitle("Фреймы")
                    ForEach(frames) { entry in
                        entryButton(entry.name, icon: "rectangle", selected: frame?.id == entry.id && layer == nil) {
                            frameID = entry.id
                            layerID = nil
                        }
                    }
                    if let frame {
                        Divider()
                        sectionTitle("Слои")
                        ForEach(frame.layers.reversed()) { entry in
                            entryButton(entry.name, icon: entry.icon, selected: layerID == entry.id) { layerID = entry.id }
                        }
                        if frame.layers.isEmpty {
                            Text("Слоёв пока нет").font(design.body(12)).foregroundStyle(design.muted)
                        }
                    }
                }
            }
            .padding(Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 172)
        .background(design.field)
    }

    private func entryButton(_ name: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(name, systemImage: icon)
                .labelStyle(.titleAndIcon)
                .font(design.ui(12, bold: selected))
                .lineLimit(1)
                .foregroundStyle(selected ? design.accent : design.ink)
                .padding(.horizontal, Space.sm)
                .frame(maxWidth: .infinity, minHeight: 29, alignment: .leading)
                .background(selected ? design.tint : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(name)
    }

    @ViewBuilder private var board: some View {
        if let frame {
            GeometryReader { viewport in
                let fit = min(max(1, viewport.size.width - 48) / CGFloat(frame.width),
                              max(1, viewport.size.height - 64) / CGFloat(frame.height), 1)
                let scale = zoom.map { CGFloat($0) / 100 } ?? fit
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("\(frame.name) · \(frame.width) × \(frame.height)")
                            .font(design.ui(12))
                            .foregroundStyle(design.muted)
                            .lineLimit(1)
                            .frame(maxWidth: max(140, CGFloat(frame.width) * scale), alignment: .leading)
                        CanvasArtboard(frame: frame, selection: $layerID, scale: scale, file: store.file) { change in
                            editFrame(frame.id, change)
                        }
                    }
                    .id(frame.id)
                    .padding(24)
                    .frame(minWidth: viewport.size.width, minHeight: viewport.size.height)
                }
            }
        } else {
            VStack(spacing: Space.md) {
                Image(systemName: "rectangle.dashed").font(.system(size: 28)).foregroundStyle(design.muted)
                    .accessibilityHidden(true)
                Text("На холсте пока пусто").font(design.heading(17))
                ChipButton(title: "Создать фрейм", style: .primary, compact: true, icon: "plus", action: addFrame)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(Space.md)
        }
    }

    private var tools: some View {
        ViewThatFits(in: .horizontal) {
            toolStrip(compact: false)
            toolStrip(compact: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.sm)
        .background(design.surface)
    }

    private func toolStrip(compact: Bool) -> some View {
        HStack(spacing: Space.xxs) {
            tool("Фрейм", icon: "rectangle.badge.plus", compact: compact, action: addFrame)
            tool("Текст", icon: "textformat", compact: compact, action: addText).disabled(frame == nil)
            tool("Изображение", icon: "photo", compact: compact) {
                importFrameID = frame?.id
                importing = importFrameID != nil
            }
            .disabled(frame == nil)
            Divider().frame(height: 20)
            Menu {
                Button("По размеру окна") { zoom = nil }
                ForEach([25, 50, 75, 100, 150, 200], id: \.self) { value in
                    Button("\(value)%") { zoom = value }
                }
            } label: {
                Text(zoom.map { "\($0)%" } ?? "Вписать")
                    .font(design.ui(12))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .hoverFeedback()
            .accessibilityLabel("Масштаб холста")
            .disabled(frame == nil)
        }
    }

    @ViewBuilder
    private func tool(_ title: String, icon: String, compact: Bool, action: @escaping () -> Void) -> some View {
        if compact {
            Button(action: action) {
                Image(systemName: icon)
                    .frame(width: 30, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(title)
            .help(title)
        } else {
            ChipButton(title: title, compact: true, icon: icon, action: action)
        }
    }

    private func inspector(_ frame: CanvasFrame) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                if let layer {
                    sectionTitle("Слой")
                    TextField("Название слоя", text: layerValue(layer, \.name))
                    HStack {
                        number("X", value: layerValue(layer, \.x), range: -8192...8192)
                        number("Y", value: layerValue(layer, \.y), range: -8192...8192)
                    }
                    HStack {
                        number("Ширина", value: layerValue(layer, \.width), range: 1...8192)
                        number("Высота", value: layerValue(layer, \.height), range: 1...8192)
                    }
                    if layer.material == nil {
                        Divider()
                        sectionTitle("Текст")
                        TextField("Содержимое текста", text: layerValue(layer, \.text), axis: .vertical)
                            .lineLimit(2...5)
                        number("Кегль", value: layerValue(layer, \.fontSize), range: 1...1024)
                        ColorPicker("Цвет текста", selection: color(layerValue(layer, \.fill)), supportsOpacity: false)
                    } else {
                        Text("Изображение вписывается в границы слоя с сохранением пропорций.")
                            .foregroundStyle(design.muted)
                    }
                    Divider()
                    layerActions(frame, layer)
                } else {
                    sectionTitle("Фрейм")
                    TextField("Имя фрейма", text: frameValue(frame, \.name))
                    HStack {
                        number("Ширина", value: frameValue(frame, \.width), range: 1...8192)
                        number("Высота", value: frameValue(frame, \.height), range: 1...8192)
                    }
                    Menu("Формат фрейма") {
                        ForEach(CanvasFrame.sizes, id: \.0) { name, width, height in
                            Button("\(name) · \(width) × \(height)") {
                                editFrame(frame.id) { $0.width = width; $0.height = height }
                            }
                        }
                    }
                    ColorPicker("Фон фрейма", selection: color(frameValue(frame, \.fill)), supportsOpacity: false)
                    ChipButton(title: "Удалить фрейм", compact: true, icon: "trash") { removingFrame = true }
                }
            }
            .textFieldStyle(.roundedBorder)
            .font(design.ui(12, bold: false))
            .padding(Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(layer?.id ?? frame.id)
        }
        .frame(width: 182)
        .background(design.surface)
    }

    private func layerActions(_ frame: CanvasFrame, _ layer: CanvasLayer) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                tool("Выше", icon: "arrow.up", compact: true) { moveLayer(layer.id, in: frame.id, by: 1) }
                    .disabled(frame.layers.last?.id == layer.id)
                tool("Ниже", icon: "arrow.down", compact: true) { moveLayer(layer.id, in: frame.id, by: -1) }
                    .disabled(frame.layers.first?.id == layer.id)
            }
            ChipButton(title: "Удалить слой", compact: true, icon: "trash") {
                editFrame(frame.id) { $0.layers.removeAll { $0.id == layer.id } }
                layerID = nil
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(design.ui(12)).foregroundStyle(design.muted)
            .accessibilityAddTraits(.isHeader)
    }

    private func number(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        let bounded = Binding(get: { value.wrappedValue }, set: { value.wrappedValue = min(max($0, range.lowerBound), range.upperBound) })
        return VStack(alignment: .leading, spacing: Space.xxs) {
            Text(title).font(design.ui(11)).foregroundStyle(design.muted).accessibilityHidden(true)
            TextField(title, value: bounded, format: .number.grouping(.never))
                .multilineTextAlignment(.trailing)
        }
    }

    private func color(_ value: Binding<Int>) -> Binding<Color> {
        Binding(get: { canvasColor(value.wrappedValue) }, set: { chosen in
            guard let rgb = NSColor(chosen).usingColorSpace(.sRGB) else { return }
            let r = Int((max(0, min(1, rgb.redComponent)) * 255).rounded())
            let g = Int((max(0, min(1, rgb.greenComponent)) * 255).rounded())
            let b = Int((max(0, min(1, rgb.blueComponent)) * 255).rounded())
            value.wrappedValue = (r << 16) | (g << 8) | b
        })
    }

    private func frameValue<Value>(_ frame: CanvasFrame, _ key: WritableKeyPath<CanvasFrame, Value>) -> Binding<Value> {
        Binding(get: { frame[keyPath: key] }, set: { value in editFrame(frame.id) { $0[keyPath: key] = value } })
    }

    private func layerValue<Value>(_ layer: CanvasLayer, _ key: WritableKeyPath<CanvasLayer, Value>) -> Binding<Value> {
        Binding(get: { layer[keyPath: key] }, set: { value in
            guard let frame else { return }
            editFrame(frame.id) { frame in
                guard let index = frame.layers.firstIndex(where: { $0.id == layer.id }) else { return }
                frame.layers[index][keyPath: key] = value
            }
        })
    }

    private func editFrame(_ id: UUID, _ change: (inout CanvasFrame) -> Void) {
        store.update(item.id) { work in
            guard let index = work.canvasFrames?.firstIndex(where: { $0.id == id }) else { return }
            if var frames = work.canvasFrames {
                change(&frames[index])
                work.canvasFrames = frames
            }
        }
    }

    private func addFrame() {
        var number = frames.count + 1
        while frames.contains(where: { $0.name == "Фрейм \(number)" }) { number += 1 }
        let newFrame = CanvasFrame(name: "Фрейм \(number)")
        store.update(item.id) { $0.canvasFrames = ($0.canvasFrames ?? []) + [newFrame] }
        frameID = newFrame.id
        layerID = nil
        zoom = nil
    }

    private func addText() {
        guard let frame else { return }
        let layer = CanvasLayer(
            x: frame.width / 12, y: frame.height / 12,
            width: max(1, frame.width * 5 / 6), height: max(1, frame.height / 3),
            fontSize: min(64, max(1, frame.height / 6))
        )
        editFrame(frame.id) { $0.layers.append(layer) }
        layerID = layer.id
    }

    private func moveLayer(_ id: UUID, in frameID: UUID, by distance: Int) {
        editFrame(frameID) { frame in
            guard let index = frame.layers.firstIndex(where: { $0.id == id }),
                  frame.layers.indices.contains(index + distance) else { return }
            frame.layers.swapAt(index, index + distance)
        }
    }
}

private struct CanvasArtboard: View {
    @Environment(\.design) private var design
    let frame: CanvasFrame
    @Binding var selection: UUID?
    let scale: CGFloat
    let file: (Material) -> URL?
    let edit: ((inout CanvasFrame) -> Void) -> Void
    @GestureState private var resizing: CGSize = .zero

    var body: some View {
        let size = dimensions(resizing)
        ZStack(alignment: .topLeading) {
            canvasColor(frame.fill)
                .onTapGesture { selection = nil }
            ForEach(frame.layers) { layer in
                CanvasLayerView(layer: layer, selected: layer.id == selection, scale: scale,
                                url: layer.material.flatMap(file), select: { selection = layer.id }) { x, y in
                    edit { frame in
                        guard let index = frame.layers.firstIndex(where: { $0.id == layer.id }) else { return }
                        frame.layers[index].x = x
                        frame.layers[index].y = y
                    }
                }
            }
        }
        .frame(width: CGFloat(size.width) * scale, height: CGFloat(size.height) * scale)
        .clipped()
        .contentShape(Rectangle())
        .overlay {
            Rectangle().strokeBorder(selection == nil ? design.accent : design.line)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomTrailing) {
            if selection == nil {
                Rectangle()
                    .fill(design.accent)
                    .frame(width: 8, height: 8)
                    .padding(5)
                    .contentShape(Rectangle())
                    .offset(x: 9, y: 9)
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .updating($resizing) { event, state, _ in state = event.translation }
                        .onEnded { event in
                            let updated = dimensions(event.translation)
                            edit { $0.width = updated.width; $0.height = updated.height }
                        })
                    .help("Изменить размер фрейма")
                    .accessibilityHidden(true)
            }
        }
    }

    private func dimensions(_ offset: CGSize) -> (width: Int, height: Int) {
        (boundedCanvasValue(CGFloat(frame.width) + offset.width / scale, in: 1...8192),
         boundedCanvasValue(CGFloat(frame.height) + offset.height / scale, in: 1...8192))
    }
}

private struct CanvasLayerView: View {
    @Environment(\.design) private var design
    let layer: CanvasLayer
    let selected: Bool
    let scale: CGFloat
    let url: URL?
    let select: () -> Void
    let move: (Int, Int) -> Void
    @GestureState private var drag: CGSize = .zero

    var body: some View {
        Group {
            if layer.material != nil {
                CanvasImage(url: url)
            } else {
                Text(layer.text)
                    .font(.system(size: max(1, CGFloat(layer.fontSize) * scale), weight: .medium))
                    .foregroundStyle(canvasColor(layer.fill))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: CGFloat(layer.width) * scale, height: CGFloat(layer.height) * scale)
        .clipped()
        .contentShape(Rectangle())
        .overlay {
            if selected {
                Rectangle().strokeBorder(design.accent)
                    .allowsHitTesting(false)
            }
        }
        .onTapGesture(perform: select)
        .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .updating($drag) { event, state, _ in state = event.translation }
            .onEnded { event in
                select()
                move(boundedCanvasValue(CGFloat(layer.x) + event.translation.width / scale, in: -8192...8192),
                     boundedCanvasValue(CGFloat(layer.y) + event.translation.height / scale, in: -8192...8192))
            })
        .offset(x: CGFloat(layer.x) * scale + drag.width, y: CGFloat(layer.y) * scale + drag.height)
        .accessibilityHidden(true)
    }
}

private struct CanvasImage: View {
    let url: URL?
    @ViewState private var preview: CGImage?

    var body: some View {
        Group {
            if let preview {
                Image(decorative: preview, scale: 1).resizable().scaledToFit()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: url) {
            guard let url else { return }
            let image = await Task.detached(priority: .utility) { Self.thumbnail(at: url) }.value
            if !Task.isCancelled { preview = image }
        }
    }

    nonisolated private static func thumbnail(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways as String: true,
            kCGImageSourceCreateThumbnailWithTransform as String: true,
            kCGImageSourceThumbnailMaxPixelSize as String: 2048
        ] as [String: Any]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

private func boundedCanvasValue(_ value: CGFloat, in range: ClosedRange<Int>) -> Int {
    Int(min(max(value.rounded(), CGFloat(range.lowerBound)), CGFloat(range.upperBound)))
}

private func canvasColor(_ rgb: Int) -> Color {
    Color(red: Double((rgb >> 16) & 255) / 255,
          green: Double((rgb >> 8) & 255) / 255,
          blue: Double(rgb & 255) / 255)
}
