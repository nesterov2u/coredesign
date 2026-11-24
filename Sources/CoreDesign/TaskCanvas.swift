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

struct TaskCanvas: View {
    @Environment(\.design) private var design
    let store: ProjectStore
    let item: WorkItem
    let back: () -> Void

    @ViewState private var frameID: UUID?
    @ViewState private var layerID: UUID?
    @ViewState private var zoom: CGFloat?
    @GestureState private var magnification: CGFloat = 1
    @FocusState private var boardFocused: Bool
    @Environment(\.undoManager) private var undoManager
    @ViewState private var collapsed: Set<UUID> = []
    @ViewState private var importFrameID: UUID?
    @ViewState private var importing = false
    @ViewState private var removingFrame = false

    private var frames: [CanvasFrame] { item.canvasFrames ?? [] }
    private var frame: CanvasFrame? { frames.first { $0.id == frameID } ?? frames.first }
    private var layer: CanvasLayer? { frame?.layers.first { $0.id == layerID } }

    var body: some View {
        HStack(spacing: 0) {
            hierarchy
            Divider()
            board
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
                    selectLayer(id, in: importFrameID)
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
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Space.sm) {
                ChipButton(title: "Назад", compact: true, icon: "arrow.left", action: back)
                Text(item.title).font(design.heading(14)).lineLimit(2)
            }
            .padding(Space.md)
            Divider()
            HStack {
                sectionTitle("Слои")
                Spacer()
                tool("Создать фрейм", icon: "plus", action: addFrame)
            }
            .padding(.leading, Space.md)
            .padding(.trailing, Space.xxs)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(frames) { entry in
                        HStack(spacing: 0) {
                            tool(collapsed.contains(entry.id) ? "Развернуть слои" : "Свернуть слои",
                                 icon: collapsed.contains(entry.id) ? "chevron.right" : "chevron.down", width: 22) {
                                if collapsed.remove(entry.id) == nil { collapsed.insert(entry.id) }
                            }
                            .opacity(entry.layers.isEmpty ? 0 : 1)
                            .disabled(entry.layers.isEmpty)
                            entryButton(entry.name, icon: "rectangle", selected: frame?.id == entry.id && layer == nil) {
                                frameID = entry.id
                                layerID = nil
                            }
                        }
                        if !collapsed.contains(entry.id) {
                            ForEach(entry.layers.reversed()) { child in
                                entryButton(child.name, icon: child.icon, selected: layerID == child.id) {
                                    selectLayer(child.id, in: entry.id)
                                }
                                .padding(.leading, 22)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        removeLayer(child.id, in: entry.id)
                                    } label: {
                                        Label("Удалить слой", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Space.xs)
            }
        }
        .frame(width: 188)
        .background(design.surface)
    }

    private func entryButton(_ name: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                Image(systemName: icon).frame(width: 14)
                    .foregroundStyle(selected ? design.accent : design.muted)
                    .accessibilityHidden(true)
                Text(name).lineLimit(1)
            }
            .font(design.ui(12, bold: selected))
            .foregroundStyle(design.ink)
            .padding(.horizontal, Space.xs)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .background(selected ? design.tint : Color.clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(name)
    }

    private var board: some View {
        GeometryReader { viewport in
            if let frame {
                let fit = min(max(1, viewport.size.width - 56) / CGFloat(frame.width),
                              max(1, viewport.size.height - 116) / CGFloat(frame.height), 1)
                let base = zoom ?? fit
                let scale = boundedZoom(base * magnification)
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("\(frame.name) · \(frame.width) × \(frame.height)")
                            .font(design.ui(12))
                            .foregroundStyle(layer == nil ? design.accent : design.muted)
                            .lineLimit(1)
                            .frame(maxWidth: max(136, CGFloat(frame.width) * scale), alignment: .leading)
                        CanvasArtboard(frame: frame, selection: Binding(
                            get: { layerID }, set: { selectLayer($0, in: frame.id) }
                        ), scale: scale, file: store.file) { change in
                            editFrame(frame.id, change)
                        }
                    }
                    .padding(.top, 32)
                    .padding(.bottom, 68)
                    .padding(.horizontal, 28)
                    .frame(minWidth: viewport.size.width, minHeight: viewport.size.height)
                }
                .id(frame.id)
                .focusable()
                .focused($boardFocused)
                .focusEffectDisabled()
                .onDeleteCommand {
                    if let layerID { removeLayer(layerID, in: frame.id) }
                }
                .background {
                    CanvasScrollZoom { delta in
                        zoom = boundedZoom((zoom ?? fit) * exp(delta * 0.02))
                    }
                    .allowsHitTesting(false)
                }
                .simultaneousGesture(MagnifyGesture(minimumScaleDelta: 0)
                    .updating($magnification) { value, state, _ in state = value.magnification }
                    .onEnded { zoom = boundedZoom(base * $0.magnification) })
                .overlay(alignment: .topTrailing) {
                    zoomMenu(scale: scale).padding(Space.md)
                }
            } else {
                VStack(spacing: Space.md) {
                    Image(systemName: "rectangle.dashed").font(.system(size: 28)).foregroundStyle(design.muted)
                        .accessibilityHidden(true)
                    Text("На холсте пока пусто").font(design.heading(17))
                    ChipButton(title: "Создать фрейм", style: .primary, compact: true, icon: "plus", action: addFrame)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(design.field)
        .overlay(alignment: .bottom) {
            tools.padding(.bottom, Space.lg)
        }
    }

    private func zoomMenu(scale: CGFloat) -> some View {
        let percentage = max(1, Int((scale * 100).rounded()))
        return Menu {
            Button("Увеличить") { zoom = boundedZoom(scale * 1.25) }
            Button("Уменьшить") { zoom = boundedZoom(scale / 1.25) }
            Divider()
            Button("Вписать фрейм") { zoom = nil }
            ForEach([25, 50, 100, 200, 400], id: \.self) { value in
                Button("\(value)%") { zoom = CGFloat(value) / 100 }
            }
        } label: {
            Text("\(percentage)%").monospacedDigit().font(design.ui(12))
                .padding(.leading, Space.xs)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(Space.xxs)
        .background(design.surface, in: RoundedRectangle(cornerRadius: 7))
        .hoverFeedback(cornerRadius: 7)
        .accessibilityLabel("Масштаб холста")
        .accessibilityValue("\(percentage)%")
        .help("Масштаб: щипок или ⌘ + свайп двумя пальцами")
    }

    private var tools: some View {
        HStack(spacing: Space.xxs) {
            tool("Выбрать фрейм", icon: "cursorarrow", active: frame != nil && layer == nil) {
                layerID = nil
                boardFocused = true
            }
            .disabled(frame == nil)
            Divider().frame(height: 20)
            tool("Фрейм", icon: "rectangle.badge.plus", action: addFrame)
            tool("Текст", icon: "textformat", action: addText).disabled(frame == nil)
            tool("Изображение", icon: "photo") {
                importFrameID = frame?.id
                importing = importFrameID != nil
            }
            .disabled(frame == nil)
            Divider().frame(height: 20)
            tool("Удалить слой", icon: "trash") {
                if let frame, let layerID { removeLayer(layerID, in: frame.id) }
            }
            .disabled(layer == nil)
        }
        .padding(Space.xs)
        .background(design.surface, in: RoundedRectangle(cornerRadius: 11))
        .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(design.line).allowsHitTesting(false) }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Инструменты холста")
    }

    private func tool(_ title: String, icon: String, width: CGFloat = 32, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: width == 22 ? 10 : 14, weight: .medium))
                .frame(width: width, height: 30)
                .foregroundStyle(active ? design.accent : design.ink)
                .background(active ? design.tint : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(title)
        .help(title)
    }

    private func inspector(_ frame: CanvasFrame) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                if let layer {
                    HStack {
                        sectionTitle(layer.material == nil ? "Текстовый слой" : "Изображение")
                        Spacer()
                        tool("Выше", icon: "arrow.up", width: 22) { moveLayer(layer.id, in: frame.id, by: 1) }
                            .disabled(frame.layers.last?.id == layer.id)
                        tool("Ниже", icon: "arrow.down", width: 22) { moveLayer(layer.id, in: frame.id, by: -1) }
                            .disabled(frame.layers.first?.id == layer.id)
                    }
                    TextField("Название слоя", text: layerValue(layer, \.name))
                    Divider()
                    sectionTitle("Положение")
                    HStack {
                        number("X", value: layerValue(layer, \.x), range: -8192...8192)
                        number("Y", value: layerValue(layer, \.y), range: -8192...8192)
                    }
                    sectionTitle("Размер")
                    HStack {
                        number("Ширина", mark: "Ш", value: layerValue(layer, \.width), range: 1...8192)
                        number("Высота", mark: "В", value: layerValue(layer, \.height), range: 1...8192)
                    }
                    if layer.material == nil {
                        Divider()
                        sectionTitle("Текст")
                        TextField("Содержимое текста", text: layerValue(layer, \.text), axis: .vertical)
                            .lineLimit(2...5)
                        number("Кегль", value: layerValue(layer, \.fontSize), range: 1...1024)
                        ColorPicker("Цвет текста", selection: color(layerValue(layer, \.fill)), supportsOpacity: false)
                    }
                } else {
                    sectionTitle("Фрейм")
                    TextField("Имя фрейма", text: frameValue(frame, \.name))
                    Divider()
                    sectionTitle("Размер")
                    HStack {
                        number("Ширина", mark: "Ш", value: frameValue(frame, \.width), range: 1...8192)
                        number("Высота", mark: "В", value: frameValue(frame, \.height), range: 1...8192)
                    }
                    Menu("Формат фрейма") {
                        ForEach(CanvasFrame.sizes, id: \.0) { name, width, height in
                            Button("\(name) · \(width) × \(height)") {
                                editFrame(frame.id) { $0.width = width; $0.height = height }
                            }
                        }
                    }
                    Divider()
                    sectionTitle("Заливка")
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
        .frame(width: 194)
        .background(design.surface)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(design.ui(12)).foregroundStyle(design.muted)
            .accessibilityAddTraits(.isHeader)
    }

    private func number(_ title: String, mark: String? = nil, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        let bounded = Binding(get: { value.wrappedValue }, set: { value.wrappedValue = min(max($0, range.lowerBound), range.upperBound) })
        return HStack(spacing: Space.xxs) {
            Text(mark ?? title).font(design.ui(11)).foregroundStyle(design.muted).accessibilityHidden(true)
            TextField(title, value: bounded, format: .number.grouping(.never))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
        .padding(.horizontal, Space.sm)
        .frame(height: 28)
        .background(design.field, in: RoundedRectangle(cornerRadius: 6))
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
        selectLayer(layer.id, in: frame.id)
    }

    private func selectLayer(_ id: UUID?, in frame: UUID) {
        frameID = frame
        layerID = id
        if id != nil { collapsed.remove(frame) }
        boardFocused = true
    }

    private func removeLayer(_ id: UUID, in frameID: UUID) {
        guard let frame = frames.first(where: { $0.id == frameID }),
              let index = frame.layers.firstIndex(where: { $0.id == id }) else { return }
        let removed = frame.layers[index]
        editFrame(frameID) { $0.layers.removeAll { $0.id == id } }
        let workID = item.id
        guard store.items.first(where: { $0.id == workID })?.canvasFrames?
            .first(where: { $0.id == frameID })?.layers.contains(where: { $0.id == id }) == false else { return }
        if layerID == id { layerID = nil }
        undoManager?.registerUndo(withTarget: store) { store in
            store.update(workID) { work in
                guard let frameIndex = work.canvasFrames?.firstIndex(where: { $0.id == frameID }),
                      var frame = work.canvasFrames?[frameIndex],
                      !frame.layers.contains(where: { $0.id == id }) else { return }
                frame.layers.insert(removed, at: min(index, frame.layers.count))
                work.canvasFrames?[frameIndex] = frame
            }
        }
        undoManager?.setActionName("Удаление слоя")
    }

    private func moveLayer(_ id: UUID, in frameID: UUID, by distance: Int) {
        editFrame(frameID) { frame in
            guard let index = frame.layers.firstIndex(where: { $0.id == id }),
                  frame.layers.indices.contains(index + distance) else { return }
            frame.layers.swapAt(index, index + distance)
        }
    }
}

private struct CanvasScrollZoom: NSViewRepresentable {
    var zoom: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollMonitor { ScrollMonitor() }
    func updateNSView(_ view: ScrollMonitor, context: Context) { view.zoom = zoom }

    final class ScrollMonitor: NSView {
        var zoom: (CGFloat) -> Void = { _ in }
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window, event.window == window, event.hasPreciseScrollingDeltas,
                      event.modifierFlags.contains(.command),
                      bounds.contains(convert(event.locationInWindow, from: nil)) else { return event }
                if event.momentumPhase.isEmpty, event.scrollingDeltaY != 0 {
                    zoom(event.scrollingDeltaY)
                }
                return nil
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
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

private func boundedZoom(_ scale: CGFloat) -> CGFloat { min(max(scale, 0.01), 8) }

private func canvasColor(_ rgb: Int) -> Color {
    Color(red: Double((rgb >> 16) & 255) / 255,
          green: Double((rgb >> 8) & 255) / 255,
          blue: Double(rgb & 255) / 255)
}
