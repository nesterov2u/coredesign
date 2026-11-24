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
        Window("CoreDesign", id: "core-design") {
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
    }
}

@MainActor
private final class AppUpdates: ObservableObject {
    @Published private(set) var canCheck = false
    private let controller: SPUStandardUpdaterController
    private var observation: NSKeyValueObservation?

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let available = updater.canCheckForUpdates
            Task { @MainActor in self?.canCheck = available }
        }
    }

    func check() {
        guard canCheck else { return }
        controller.checkForUpdates(nil)
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
    @ViewState private var sidebar = true
    @ViewState private var step = CreateStep.none
    @ViewState private var template: String?
    @ViewState private var title = ""
    @FocusState private var titleFocused: Bool
    @FocusState private var briefFocused: Bool
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
            case .success(let files): store.attach(files, to: id)
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
                Button {
                    dark.toggle()
                } label: {
                    Image(systemName: dark ? "sun.max" : "moon")
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
                (Text("Core").foregroundStyle(design.dark ? design.ink : .black) +
                 Text("Design").foregroundStyle(design.wordmark))
                    .font(design.heading(28))
                    .tracking(-0.6)
            }
            .buttonStyle(.plain)
            Text("/").font(design.body(17)).foregroundStyle(design.muted)
            Menu {
                Button("Сегодня") { navigate(.today) }
                Button("Все задачи") { navigate(.all) }
            } label: {
                Text("1Ci").font(design.ui(15)).foregroundStyle(design.ink)
            }
            .fixedSize()
            .menuStyle(.borderlessButton)
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
                ChipButton(title: "Новая задача  ▾", style: .primary) {
                    step = step == .none ? .templates : .none
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
                    .overlay(Rectangle().strokeBorder(design.line))
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
                    ChipButton(title: name, style: name == templates.first ? .selected : .plain) {
                        prepareTask(name)
                    }
                }
                ChipButton(title: "Пустая задача") { prepareTask(nil) }
            }
            .padding(Space.md)
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
                        .background(design.surface, in: RoundedRectangle(cornerRadius: 6))
                        .frame(width: 236)
                        .focused($titleFocused)
                        .onSubmit(createTask)
                    ChipButton(title: "Создать задачу", style: .primary, action: createTask)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(Space.lg)
            .background(design.field, in: RoundedRectangle(cornerRadius: 8))
        }
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
        sidebar = true
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
            statusMenu(item, chip: false)
                .frame(width: 152, alignment: .leading)
            deadlineMenu(item)
                .frame(width: 100, alignment: .leading)
        }
        .padding(.horizontal, Space.lg)
    }

    private func statusMenu(_ item: WorkItem, chip: Bool) -> some View {
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
            if chip {
                Chip(title: item.status.rawValue, style: .selected, compact: true)
            } else {
                Text(item.status.rawValue)
                    .font(design.ui(13, bold: false))
                    .foregroundStyle(item.status == .finished ? design.positive : design.accent)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .background(chip ? design.tint : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .help("Изменить статус")
    }

    private func deadlineMenu(_ item: WorkItem) -> some View {
        DeadlineControl(date: item.deadline) { date in store.update(item.id) { $0.deadline = date } }
    }

    private func task(_ item: WorkItem) -> some View {
        GeometryReader { geometry in
            taskLayout(item, chatGutter: min(224, max(Space.xl, geometry.size.width - 1056)))
        }
    }

    private func taskLayout(_ item: WorkItem, chatGutter: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if sidebar { taskSidebar(item) }
            VStack(spacing: 0) {
                taskToolbar(item)
                taskBody(item, chatGutter: chatGutter)
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
                            .font(design.ui())
                            .foregroundStyle(selected ? design.accent : design.muted)
                            .padding(.horizontal, Space.xxs)
                            .frame(minHeight: 52)
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

    private func taskBody(_ item: WorkItem, chatGutter: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    HStack(spacing: Space.sm) {
                        Button {
                            sidebar.toggle()
                        } label: {
                            Image(systemName: "sidebar.left").foregroundStyle(design.muted)
                        }
                        .buttonStyle(.plain)
                        .help(sidebar ? "Свернуть список задач" : "Показать список задач")
                        Button("Задачи / \(list.rawValue)") { navigate(list) }
                            .buttonStyle(.plain)
                            .font(design.ui(13, bold: false))
                            .foregroundStyle(design.muted)
                    }
                    Text(item.title).font(design.heading(28)).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Space.md) {
                        statusMenu(item, chip: true)
                        if let template = item.template {
                            TemplateControl(template: template)
                        }
                    }
                    switch item.tab {
                    case .notes:
                        notes(item)
                    case .canvas:
                        VStack(alignment: .leading, spacing: Space.sm) {
                            Text("Холст").font(design.heading(20))
                            Text("Редактор холста пока недоступен в тестовой сборке.")
                                .font(design.body()).foregroundStyle(design.muted)
                        }
                    }
                }
                .padding(Space.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if item.chatOpen {
                TaskChat(store: store, item: item, onResult: { label in
                    preview = Material(title: label, preview: "Демонстрационный результат для задачи «\(item.title)».")
                })
                .id(item.id)
                .frame(width: 400)
                .padding(.trailing, chatGutter)
                .padding(.bottom, Space.xl)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func taskSidebar(_ item: WorkItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                Text("Задачи").font(design.heading(20))
                listPicker
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.lg)
        }
        .frame(width: 244)
        .background(design.field)
    }

    private func notes(_ item: WorkItem) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("Бриф").font(design.heading(20))
            TextEditor(text: Binding(get: { item.brief }, set: { value in store.update(item.id) { $0.brief = value } }))
                .font(design.body())
                .foregroundStyle(design.ink)
                .scrollContentBackground(.hidden)
                .focused($briefFocused)
                .padding(Space.sm)
                .frame(height: 144)
                .overlay(alignment: .topLeading) {
                    if item.brief.isEmpty {
                        Text("Вставьте бриф или начните писать…")
                            .font(design.body()).foregroundStyle(design.muted)
                            .padding(.top, Space.sm + 1).padding(.leading, Space.sm + 5)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .background(design.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(briefFocused ? design.accent : design.line)
                        .allowsHitTesting(false)
                }
                .accessibilityLabel("Бриф")
            Text("Материалы").font(design.heading(20))
            ForEach(item.materials) { material in
                ChipButton(title: material.title, compact: true) {
                    if let file = store.file(for: material) {
                        if !NSWorkspace.shared.open(file) { store.issue = "Не удалось открыть файл «\(material.title)»." }
                    } else {
                        preview = material
                    }
                }
                .contextMenu {
                    Button("Убрать из задачи", role: .destructive) {
                        store.update(item.id) { $0.materials.removeAll { $0.id == material.id } }
                    }
                }
            }
            ChipButton(title: "Добавить файл", compact: true) {
                importingFor = item.id
                importer = true
            }
        }
        .id(item.id)
    }
}

struct TemplateControl: View {
    @Environment(\.design) private var design
    @ViewState private var opened = false
    let template: String

    var body: some View {
        ChipButton(title: "Шаблон · \(template)", compact: true) { opened.toggle() }
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
        .buttonStyle(.plain)
        .help("Установить срок")
        .popover(isPresented: $opened, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: Space.md) {
                DatePicker("Срок", selection: Binding(get: { date ?? Date() }, set: { onChange($0) }), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                HStack {
                    Button("Сбросить") { onChange(nil); opened = false }.disabled(date == nil)
                    Spacer()
                    Button("Готово") { if date == nil { onChange(Date()) }; opened = false }
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
            ChipButton(title: "Закрыть", style: .selected) { dismiss() }
        }
        .frame(minWidth: 360, alignment: .leading)
        .padding(Space.xl)
    }
}
