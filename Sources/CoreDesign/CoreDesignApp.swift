import AppKit
import Sparkle
import SwiftUI
import UniformTypeIdentifiers

// Use the property wrapper on toolchains without the Xcode SwiftUI macros.
typealias ViewState<Value> = SwiftUI.State<Value>

@main
struct CoreDesignApp: App {
    @ViewState private var store = ProjectStore()
    @StateObject private var updates = AppUpdates()

    var body: some Scene {
        Window("", id: "core-design") {
            Workspace(store: store)
                .frame(minWidth: 980, minHeight: 620)
        }
        .defaultSize(width: 1280, height: 810)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Проверить обновления…") { updates.check() }
                    .disabled(!updates.canCheck)
            }
        }
        Settings {
            CoreDesignSettings(updates: updates)
        }
    }
}

@MainActor
private final class AppUpdates: ObservableObject {
    @Published private(set) var canCheck = false
    @Published private(set) var automaticallyChecks = true
    private let controller: SPUStandardUpdaterController
    private var observation: NSKeyValueObservation?
    private var automaticCheckObservation: NSKeyValueObservation?

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let available = updater.canCheckForUpdates
            Task { @MainActor in self?.canCheck = available }
        }
        automaticCheckObservation = controller.updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let enabled = updater.automaticallyChecksForUpdates
            Task { @MainActor in self?.automaticallyChecks = enabled }
        }
    }

    func check() {
        guard canCheck else { return }
        controller.checkForUpdates(nil)
    }

    func setAutomaticChecks(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
    }
}

private struct CoreDesignSettings: View {
    @AppStorage("darkMode") private var dark = false
    @ObservedObject var updates: AppUpdates

    var body: some View {
        Form {
            Section("Оформление") {
                Picker("Тема", selection: $dark) {
                    Text("Светлая").tag(false)
                    Text("Тёмная").tag(true)
                }
            }
            Section("Обновления") {
                Toggle("Проверять автоматически", isOn: Binding(
                    get: { updates.automaticallyChecks }, set: updates.setAutomaticChecks
                ))
                LabeledContent("Версия", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                Button("Проверить обновления…", action: updates.check)
                    .disabled(!updates.canCheck)
            }
            Section("Подключения") {
                LabeledContent("Figma", value: "Демонстрационный режим")
                LabeledContent("Magnific", value: "Демонстрационный режим")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .preferredColorScheme(dark ? .dark : .light)
    }
}

enum TaskList: String, CaseIterable {
    case today = "Сегодня"
    case all = "Все задачи"
    var heading: String { self == .today ? "Задачи на сегодня" : rawValue }
}

enum CreateStep { case none, templates, title }

struct Workspace: View {
    @Bindable var store: ProjectStore
    @AppStorage("darkMode") private var dark = false
    @ViewState private var selected: UUID?
    @ViewState private var list: TaskList = .today
    @ViewState private var step = CreateStep.none
    @ViewState private var template: String?
    @ViewState private var title = ""
    @FocusState private var titleFocused: Bool
    @FocusState private var briefFocused: Bool
    @ViewState private var briefHovered = false
    @ViewState private var importer = false
    @ViewState private var importingFor: UUID?
    @ViewState private var preview: Material?

    private var design: Design { Design(dark: dark) }
    private let templates = ["SMM-баннер", "Обложка YouTube"]

    private var statuses: [WorkStatus] {
        list == .today ? [.active, .planned] : WorkStatus.allCases
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let item = store.items.first(where: { $0.id == selected }) {
                task(item)
            } else {
                overview
            }
        }
        .background(design.canvas)
        .foregroundStyle(design.ink)
        .environment(\.design, design)
        .preferredColorScheme(dark ? .dark : .light)
        .fileImporter(isPresented: $importer, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            guard let id = importingFor else { return }
            switch result {
            case .success(let files): _ = store.attach(files, to: id)
            case .failure(let error): store.issue = error.localizedDescription
            }
        }
        .sheet(item: $preview) { material in
            PreviewSheet(title: material.title, text: material.preview ?? "")
                .environment(\.design, design)
        }
        .alert("CoreDesign", isPresented: Binding(get: { store.issue != nil }, set: { if !$0 { store.issue = nil } })) {
            Button("ОК") { store.issue = nil }
        } message: {
            Text(store.issue ?? "")
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .help("Настройки")
                .accessibilityLabel("Настройки")
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    dark.toggle()
                } label: {
                    Image(systemName: dark ? "sun.max" : "moon")
                        .hoverFeedback()
                }
                .help(dark ? "Светлая тема" : "Тёмная тема")
                .accessibilityLabel(dark ? "Светлая тема" : "Тёмная тема")
            }
        }
    }

    private var header: some View {
        HStack(spacing: Space.lg) {
            Button {
                navigate(.today)
            } label: {
                BrandLogo(dark: design.dark)
            }
            .buttonStyle(PressStyle())
            .focusEffectDisabled()
            .accessibilityLabel("CoreDesign")
            .accessibilityHint("Вернуться к задачам на сегодня")
            Text("/").font(design.body(17)).foregroundStyle(design.muted)
            Menu {
                Button { navigate(.today) } label: { Label("Сегодня", systemImage: "calendar") }
                Button { navigate(.all) } label: { Label("Все задачи", systemImage: "list.bullet") }
            } label: {
                Text("1Ci").font(design.ui(15)).foregroundStyle(design.ink)
            }
            .fixedSize()
            .menuStyle(.borderlessButton)
            .hoverFeedback()
            .help("Проект 1Ci")
            Spacer()
            Text("Figma   ·   Magnific")
                .font(design.ui(13, bold: false))
                .foregroundStyle(design.muted)
                .help("Демонстрационные сервисы")
        }
        .padding(.horizontal, Space.lg)
        .frame(height: 64)
        .background(design.surface)
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                Text("Рабочее пространство").font(design.ui(13, bold: false)).foregroundStyle(design.muted)
                Text(list.heading)
                    .font(design.heading(32))
                    .accessibilityAddTraits(.isHeader)
                ChipButton(title: "Новая задача", style: .primary, icon: "plus", disclosure: true) {
                    if step == .none { step = .templates }
                    else { cancelCreation() }
                }
                .keyboardShortcut("n", modifiers: .command)
                listPicker
                createForm
                let items = statuses.flatMap { store.sorted($0) }
                if items.isEmpty {
                    Text("Пока нет задач").foregroundStyle(design.muted)
                        .padding(.vertical, Space.xl)
                } else {
                    VStack(spacing: 0) {
                        ForEach(items) { item in
                            taskRow(item)
                            if item.id != items.last?.id {
                                design.line.frame(height: 1)
                            }
                        }
                    }
                    .background(design.surface)
                    .overlay {
                        Rectangle().strokeBorder(design.line)
                            .allowsHitTesting(false)
                    }
                }
            }
            .padding(Space.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var listPicker: some View {
        HStack(spacing: Space.sm) {
            ForEach(TaskList.allCases, id: \.self) { option in
                ChipButton(title: option.rawValue, style: list == option ? .selected : .plain) {
                    list = option
                }
            }
        }
    }

    @ViewBuilder private var createForm: some View {
        switch step {
        case .none:
            EmptyView()
        case .templates:
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("Из шаблона проекта").font(design.ui(13, bold: false)).foregroundStyle(design.muted)
                ForEach(templates, id: \.self) { name in
                    ChipButton(title: name, style: name == templates.first ? .selected : .plain, icon: "square.on.square") {
                        prepareTask(name)
                    }
                }
                HStack(spacing: Space.sm) {
                    ChipButton(title: "Пустая задача", icon: "doc") { prepareTask(nil) }
                    Spacer()
                    cancelCreationButton
                }
            }
            .padding(Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(design.field, in: RoundedRectangle(cornerRadius: 8))
        case .title:
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("Новая задача").font(design.heading(20))
                if let template { Chip(title: "Шаблон · \(template)", style: .selected, compact: true) }
                Text("Название").font(design.ui(13, bold: false)).foregroundStyle(design.muted)
                HStack(spacing: Space.sm) {
                    TextField("Название задачи", text: $title)
                        .labelsHidden()
                        .textFieldStyle(.plain)
                        .padding(Space.sm)
                        .frame(width: 236, height: 42)
                        .background(design.surface, in: RoundedRectangle(cornerRadius: 6))
                        .hoverFeedback(cornerRadius: 6)
                        .focused($titleFocused)
                        .onSubmit(createTask)
                        .onExitCommand(perform: cancelCreation)
                    cancelCreationButton
                    ChipButton(title: "Создать задачу", style: .primary, icon: "plus", action: createTask)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(design.field, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var cancelCreationButton: some View {
        ChipButton(title: "Отмена", icon: "xmark", action: cancelCreation)
            .keyboardShortcut(.cancelAction)
    }

    private func cancelCreation() {
        titleFocused = false
        title = ""
        template = nil
        step = .none
    }

    private func prepareTask(_ selectedTemplate: String?) {
        template = selectedTemplate
        title = ""
        step = .title
        titleFocused = true
    }

    private func createTask() {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let id = store.create(title: name, template: template) else { return }
        list = .today
        open(id)
    }

    private func navigate(_ destination: TaskList) {
        selected = nil
        list = destination
        step = .none
    }

    private func open(_ id: UUID) {
        step = .none
        selected = id
    }

    private func taskRow(_ item: WorkItem) -> some View {
        HStack(spacing: Space.xl) {
            Button { open(item.id) } label: {
                Text(item.title)
                    .font(design.body(15, bold: true))
                    .foregroundStyle(design.ink)
                    .frame(maxWidth: .infinity, minHeight: 53, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            statusMenu(item)
                .frame(width: 152, alignment: .leading)
            deadlineMenu(item)
                .frame(width: 100, alignment: .leading)
        }
        .padding(.horizontal, Space.lg)
        .contentShape(Rectangle())
        .hoverFeedback(cornerRadius: 0)
    }

    private func statusMenu(_ item: WorkItem, asField: Bool = false) -> some View {
        Menu {
            ForEach(WorkStatus.allCases) { status in
                Button {
                    store.update(item.id) { $0.status = status }
                } label: {
                    if item.status == status { Label(status.rawValue, systemImage: "checkmark") }
                    else { Text(status.rawValue) }
                }
            }
        } label: {
            if asField {
                Text(item.status.rawValue)
                    .font(design.ui(12))
                    .foregroundStyle(design.statusInk)
            } else {
                Text(item.status.rawValue)
                    .font(design.ui(13, bold: false))
                    .foregroundStyle(item.status == .finished ? design.positive : design.accent)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(asField ? .visible : .hidden)
        .fixedSize()
        .padding(.horizontal, asField ? Space.md : 0)
        .padding(.vertical, asField ? Space.sm : 0)
        .background(asField ? design.surface : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            if asField {
                RoundedRectangle(cornerRadius: 8).strokeBorder(design.line)
                    .allowsHitTesting(false)
            }
        }
        .hoverFeedback()
        .help("Изменить статус")
    }

    private func deadlineMenu(_ item: WorkItem) -> some View {
        DeadlineControl(date: item.deadline) { date in store.update(item.id) { $0.deadline = date } }
    }

    private func task(_ item: WorkItem) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if item.tab == .notes { taskSidebar(item) }
            VStack(spacing: 0) {
                taskToolbar(item)
                taskBody(item)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func taskToolbar(_ item: WorkItem) -> some View {
        HStack(spacing: Space.lg) {
            HStack(spacing: Space.lg) {
                ForEach(WorkTab.allCases, id: \.self) { tab in
                    let selected = item.tab == tab
                    Button {
                        store.update(item.id) { $0.tab = tab }
                    } label: {
                        Text(tab.rawValue)
                            .font(design.ui(16))
                            .foregroundStyle(selected ? design.accent : design.muted)
                            .padding(.horizontal, Space.lg)
                            .frame(minHeight: 56)
                            .contentShape(Rectangle())
                            .overlay(alignment: .bottom) {
                                if selected { design.accent.frame(height: 2) }
                            }
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Вкладки задачи")
            Spacer()
            Button {
                store.update(item.id) { $0.chatOpen.toggle() }
            } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(item.chatOpen ? design.accent : design.muted)
                    .frame(width: 34, height: 34)
                    .background(item.chatOpen ? design.tint : design.field, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("ИИ-чат")
            .accessibilityValue(item.chatOpen ? "Открыт" : "Закрыт")
            .help(item.chatOpen ? "Скрыть ИИ-чат" : "Открыть ИИ-чат")
        }
        .padding(.horizontal, Space.xl)
        .background(alignment: .bottom) { design.line.frame(height: 1) }
        .background(design.canvas)
    }

    private func taskBody(_ item: WorkItem) -> some View {
        HStack(alignment: .top, spacing: 0) {
            switch item.tab {
            case .notes:
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.lg) {
                        ChipButton(title: "Назад", compact: true, icon: "arrow.left") {
                            navigate(list)
                        }
                        .help("Вернуться к списку задач")
                        Text(item.title).font(design.heading(28)).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: Space.md) {
                            statusMenu(item, asField: true)
                            if let template = item.template {
                                TemplateControl(template: template)
                            }
                        }
                        notes(item)
                    }
                    .padding(Space.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .canvas:
                TaskCanvas(store: store, item: item, back: { navigate(list) }) {
                    Picker("Список задач", selection: $list) {
                        ForEach(TaskList.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .labelsHidden()
                    taskGroups(item)
                }
                .id(item.id)
            }
            if item.chatOpen {
                TaskChat(store: store, item: item, onResult: { label in
                    preview = Material(title: label, preview: "Демонстрационный результат для задачи «\(item.title)».")
                })
                .id(item.id)
                .frame(width: item.tab == .canvas ? 320 : 400)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func taskSidebar(_ item: WorkItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                Text("Задачи").font(design.heading(20))
                listPicker
                taskGroups(item)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.lg)
        }
        .frame(width: 244)
        .background(design.field)
    }

    private func taskGroups(_ item: WorkItem) -> some View {
        ForEach(statuses) { status in
            let group = store.sorted(status)
            if !group.isEmpty {
                Text(status.rawValue).font(design.ui(13)).foregroundStyle(design.muted)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    ForEach(group) { entry in
                        Button { open(entry.id) } label: {
                            Text(entry.title)
                                .font(design.body(14))
                                .foregroundStyle(entry.id == item.id ? design.accent : design.ink)
                                .lineLimit(2)
                                .padding(.horizontal, Space.sm)
                                .frame(minHeight: 33, alignment: .leading)
                                .background(entry.id == item.id ? design.tint : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(PressStyle())
                    }
                }
            }
        }
    }

    private func notes(_ item: WorkItem) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("Бриф").font(design.heading(20))
            TextField(
                "Бриф",
                text: Binding(get: { item.brief }, set: { value in store.update(item.id) { $0.brief = value } }),
                prompt: Text("Вставьте бриф или начните писать…").foregroundStyle(design.muted),
                axis: .vertical
            )
                .textFieldStyle(.plain)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .font(design.body())
                .foregroundStyle(design.ink)
                .focused($briefFocused)
                .padding(Space.sm)
                .frame(maxWidth: .infinity, minHeight: 144, alignment: .topLeading)
                .containerRelativeFrame(.horizontal, alignment: .leading) { columnWidth, _ in
                    max(0, columnWidth - 2 * Space.xl) * 0.6
                }
                .background {
                    RoundedRectangle(cornerRadius: 8).fill(design.surface)
                        .onTapGesture { briefFocused = true }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(briefFocused ? design.accent : (briefHovered ? design.line : Color.clear))
                        .allowsHitTesting(false)
                }
                .onHover { briefHovered = $0 }
            Text("Материалы").font(design.heading(20))
            ForEach(item.materials) { material in
                ChipButton(title: material.title, compact: true, icon: "doc") {
                    if let file = store.file(for: material) {
                        if !NSWorkspace.shared.open(file) { store.issue = "Не удалось открыть файл «\(material.title)»." }
                    } else {
                        preview = material
                    }
                }
                .contextMenu {
                    Button(role: .destructive) {
                        store.update(item.id) { $0.materials.removeAll { $0.id == material.id } }
                    } label: {
                        Label("Убрать из задачи", systemImage: "trash")
                    }
                }
            }
            ChipButton(title: "Добавить файл", compact: true, icon: "paperclip") {
                importingFor = item.id
                importer = true
            }
        }
        .id(item.id)
    }
}

private struct BrandLogo: View {
    let dark: Bool

    private static let lightImage = load("Logo-CoreDesign-Light")
    private static let darkImage = load("Logo-CoreDesign-Dark")

    var body: some View {
        if let image = dark ? Self.darkImage : Self.lightImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: image.size.width, height: image.size.height)
        } else {
            Text("CoreDesign").font(.system(size: 25, weight: .semibold))
        }
    }

    private static func load(_ name: String) -> NSImage? {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: name, withExtension: "svg", subdirectory: "Brand") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

struct TemplateControl: View {
    @Environment(\.design) private var design
    @ViewState private var opened = false
    let template: String

    var body: some View {
        ChipButton(title: "Шаблон · \(template)", compact: true, icon: "square.on.square") { opened.toggle() }
            .popover(isPresented: $opened, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text(template).font(design.heading(17))
                    Text(template == "SMM-баннер" ? "Формат · Customer Story" : "Формат · YouTube Thumbnail")
                    Text("Демонстрационный шаблон").foregroundStyle(design.muted)
                }
                .padding(Space.lg)
            }
    }
}

struct DeadlineControl: View {
    @Environment(\.design) private var design
    @ViewState private var opened = false
    let date: Date?
    let onChange: (Date?) -> Void

    var body: some View {
        Button {
            opened.toggle()
        } label: {
            Text(date?.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "ru_RU"))) ?? "—")
                .font(design.ui(13, bold: false))
                .foregroundStyle(design.muted)
        }
        .buttonStyle(PressStyle())
        .help("Установить срок")
        .popover(isPresented: $opened, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: Space.md) {
                DatePicker("Срок", selection: Binding(get: { date ?? Date() }, set: { onChange($0) }), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                HStack {
                    ChipButton(title: "Сбросить", compact: true, icon: "arrow.counterclockwise") {
                        onChange(nil); opened = false
                    }.disabled(date == nil)
                    Spacer()
                    ChipButton(title: "Готово", compact: true, icon: "checkmark") {
                        if date == nil { onChange(Date()) }; opened = false
                    }
                }
            }
            .frame(width: 235)
            .padding(Space.lg)
            .environment(\.locale, Locale(identifier: "ru_RU"))
        }
    }
}

struct PreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.design) private var design
    let title: String
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text(title).font(design.heading(24))
            Text(text).font(design.body())
            ChipButton(title: "Закрыть", style: .selected, icon: "xmark") { dismiss() }
        }
        .frame(minWidth: 360, alignment: .leading)
        .padding(Space.xl)
    }
}
