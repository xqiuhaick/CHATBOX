import SwiftUI

enum ModelPickerStyle {
    case inline
    case pill
}

struct ModelPickerMenu: View {
    @Environment(ChatStore.self) private var store
    @Binding var isPresented: Bool

    var style: ModelPickerStyle = .pill

    init(
        isPresented: Binding<Bool>,
        style: ModelPickerStyle = .pill
    ) {
        _isPresented = isPresented
        self.style = style
    }

    private var modelName: String {
        modelShortName(store.settings.model)
    }

    var body: some View {
        switch style {
        case .inline:
            inlineControl
        case .pill:
            pillControl
        }
    }

    private var inlineControl: some View {
        modelPickerButton {
            inlineLabel
        }
    }

    private var pillControl: some View {
        modelPickerButton {
            pillLabel
        }
    }

    private func modelPickerButton<LabelContent: View>(@ViewBuilder label: () -> LabelContent) -> some View {
        Button {
            isPresented.toggle()
        } label: {
            label()
                .contentShape(Rectangle())
        }
        .buttonStyle(.automatic)
        .help("切换模型")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ModelPickerPanel(isPresented: $isPresented)
        }
    }

    private var inlineLabel: some View {
        Text(modelName)
            .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(Color.primary)
        .lineLimit(1)
    }

    private var pillLabel: some View {
        inlineLabel
            .padding(.horizontal, 14)
    }
}

extension View {
    func modelPickerPopoverChrome() -> some View {
        background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        }
    }
}

struct ModelPickerPanel: View {
    @Environment(ChatStore.self) private var store
    @Binding var isPresented: Bool

    private var providerSections: [ModelPickerSection] {
        store.favoriteModelsByProvider()
            .map { ModelPickerSection(provider: $0.key, models: $0.value.sorted()) }
            .filter { !$0.models.isEmpty }
            .sorted { $0.provider.title.localizedCaseInsensitiveCompare($1.provider.title) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if providerSections.isEmpty {
                    Text("请先在设置中收藏模型")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(Array(providerSections.enumerated()), id: \.element.id) { index, section in
                        providerSection(section, topInset: index == 0 ? 0 : 10)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .frame(width: 268)
        .frame(maxHeight: 420)
        .modelPickerPopoverChrome()
    }

    private func providerSection(_ section: ModelPickerSection, topInset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(section.provider.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, topInset)
                .padding(.bottom, 2)

            ForEach(section.models, id: \.self) { model in
                modelRow(providerID: section.provider.id, model: model)
            }
        }
    }

    private func modelRow(providerID: String, model: String) -> some View {
        let isSelected = store.settings.model == model && store.settings.provider == providerID

        return Button {
            store.applyModel(provider: providerID, model: model)
            isPresented = false
        } label: {
            HStack(spacing: 8) {
                Text(modelShortName(model))
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(store.favoriteModels(for: providerID).contains(model) ? "取消收藏" : "收藏") {
                store.toggleFavorite(model: model, provider: providerID)
            }
        }
    }
}

private struct ModelPickerSection: Identifiable {
    let provider: ProviderMeta
    let models: [String]

    var id: String { provider.id }
}

func modelDisplayTitle(model: String) -> String {
    modelShortName(model)
}

func modelShortName(_ model: String) -> String {
    model.components(separatedBy: "/").last ?? model
}

func modelSubtitle(provider: String, model: String) -> String {
    let providerName = providerTitle(for: provider)
    let normalized = model.lowercased()
    if normalized.contains("reasoner") || normalized.contains("reasoning") || normalized.contains("thinking") {
        return "\(providerName) · 深度推理"
    }
    if normalized.contains("vision") || normalized.contains("image") {
        return "\(providerName) · 视觉理解"
    }
    return providerName
}
