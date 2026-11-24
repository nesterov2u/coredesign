import SwiftUI

struct TaskChat: View {
    @Environment(\.design) private var design
    let store: ProjectStore
    let item: WorkItem
    let onResult: (String) -> Void

    @ViewState private var draft = ""
    @ViewState private var service = Service.automatic
    @ViewState private var panel = Panel.history
    @ViewState private var attached: [Material] = []
    @ViewState private var picked = Set<Material>()
    @ViewState private var projectContext = false

    enum Panel { case history, services, context }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("ИИ-чат").font(design.heading(20))
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Контекст задачи").font(design.ui(12, bold: false)).foregroundStyle(design.muted)
                HStack(spacing: Space.xs) {
                    Chip(title: "Бриф", style: .selected, compact: true)
                    if let template = item.template { Chip(title: template, style: .selected, compact: true) }
                }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.md) {
                        switch panel {
                        case .history: history
                        case .services: servicePicker
                        case .context: contextPicker
                        }
                        Color.clear.frame(height: 0).id("latest")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: item.messages.count) {
                    if panel == .history { proxy.scrollTo("latest", anchor: .bottom) }
                }
            }
            composer
        }
        .padding(Space.lg)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(design.field)
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            ForEach(item.messages) { message in
                let isUser = message.author == "Вы"
                VStack(alignment: .leading, spacing: Space.xs) {
                    if !isUser {
                        Text(message.author).font(design.ui(12)).foregroundStyle(design.muted)
                    }
                    Text(message.text).font(design.body())
                        .textSelection(.enabled)
                        .accessibilityLabel(isUser ? "Вы: \(message.text)" : message.text)
                    if !message.context.isEmpty {
                        Text(message.context.joined(separator: " · "))
                            .font(design.ui(12, bold: false))
                            .foregroundStyle(design.muted)
                    }
                    ForEach(message.results, id: \.self) { label in
                        ChipButton(title: label + " ↗", style: .selected, compact: true) { onResult(label) }
                    }
                }
                .padding(.horizontal, isUser ? Space.md : 0)
                .padding(.vertical, isUser ? Space.sm : 0)
                .background(isUser ? design.tint : Color.clear, in: RoundedRectangle(cornerRadius: 14))
                .padding(.leading, isUser ? Space.xxl : 0)
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            }
            if item.pendingGeneration { confirmation }
        }
    }

    private var servicePicker: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Сервис для сообщения").font(design.heading(16))
            ForEach(Service.allCases) { option in
                optionCard(option.rawValue, detail: option.detail, selected: option == service) {
                    service = option
                    panel = .history
                }
            }
        }
    }

    private var contextPicker: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Добавить контекст").font(design.heading(16))
            HStack(spacing: Space.xs) {
                ChipButton(title: "Из задачи", style: projectContext ? .plain : .selected, compact: true) { projectContext = false }
                ChipButton(title: "Из проекта", style: projectContext ? .selected : .plain, compact: true) { projectContext = true }
            }
            let materials = projectContext ? store.projectMaterials : item.materials
            if materials.isEmpty {
                Text("В задаче пока нет материалов.")
                    .font(design.body(13)).foregroundStyle(design.muted)
            }
            ForEach(materials) { material in
                optionCard(material.title, detail: projectContext ? "Материал проекта" : "Документ задачи", selected: picked.contains(material)) {
                    if picked.contains(material) { picked.remove(material) }
                    else { picked.insert(material) }
                }
            }
            ChipButton(title: picked.isEmpty ? "Готово" : "Прикрепить · \(picked.count)", style: .primary, compact: true) {
                attached = picked.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                panel = .history
            }
        }
    }

    private func optionCard(_ title: String, detail: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text((selected ? "✓  " : "") + title).font(design.ui(14)).foregroundStyle(design.ink)
                Text(detail).font(design.ui(12, bold: false)).foregroundStyle(design.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.md)
            .background(design.surface, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Подтвердить генерацию?").font(design.heading(17))
            Text("Magnific · 2 варианта\nДемонстрационный запуск.")
                .font(design.ui(13, bold: false)).foregroundStyle(design.muted)
            HStack(spacing: Space.sm) {
                ChipButton(title: "Отмена", compact: true) { resolveGeneration(approved: false) }
                ChipButton(title: "Запустить", style: .primary, compact: true) { resolveGeneration(approved: true) }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            if !attached.isEmpty {
                Text(attached.map(\.title).joined(separator: " · "))
                    .font(design.ui(12, bold: false)).foregroundStyle(design.muted)
                    .lineLimit(2)
            }
            TextField("Сообщение…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(design.body())
                .lineLimit(1...4)
                .disabled(item.pendingGeneration)
            HStack(spacing: Space.xs) {
                ChipButton(title: "+ Контекст", compact: true) {
                    if panel == .context { panel = .history }
                    else {
                        picked = Set(attached)
                        panel = .context
                    }
                }
                ChipButton(title: (service == .automatic ? "Авто" : service.rawValue) + " ▾", compact: true) {
                    panel = panel == .services ? .history : .services
                }
                ChipButton(title: "Отправить", style: .primary, compact: true, action: send)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || item.pendingGeneration)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(Space.md)
        .background(design.surface, in: RoundedRectangle(cornerRadius: 10))
    }

    private func send() {
        let request = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, !item.pendingGeneration else { return }
        let imageWords = ["фон", "картинк", "изображен", "иллюстрац", "видео"]
        let imageRequest = service == .magnific ||
            (service == .automatic && imageWords.contains { request.localizedCaseInsensitiveContains($0) })
        let bilingual = item.template == "SMM-баннер"
        store.update(item.id) {
            $0.messages.append(ChatMessage(author: "Вы", text: request, context: attached.map(\.title)))
            if imageRequest {
                $0.pendingGeneration = true
            } else {
                $0.messages.append(ChatMessage(
                    author: "CoreDesign · Figma",
                    text: bilingual ? "Демонстрационный ответ. Два фрейма готовы." : "Демонстрационный ответ. Фрейм готов.",
                    results: bilingual ? ["Фрейм · EN", "Фрейм · TR"] : ["Фрейм"]
                ))
            }
        }
        draft = ""
        service = .automatic
        attached = []
        panel = .history
    }

    private func resolveGeneration(approved: Bool) {
        store.update(item.id) {
            $0.pendingGeneration = false
            $0.messages.append(ChatMessage(
                author: "CoreDesign · Magnific",
                text: approved ? "Демонстрационный ответ. Подготовлены два варианта." : "Генерация отменена.",
                results: approved ? ["Вариант 1", "Вариант 2"] : []
            ))
        }
    }
}
