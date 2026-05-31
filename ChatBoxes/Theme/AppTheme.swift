import SwiftUI

extension Animation {
    static let chatBoxSmooth = Animation.smooth(duration: 0.32)
    static let chatBoxQuick = Animation.smooth(duration: 0.22)
}

enum AppLayout {
    static let sidebarIdealWidth: CGFloat = 260
    static let sidebarMinWidth: CGFloat = 240
    static let sidebarMaxWidth: CGFloat = 300
    static let messageSpacing: CGFloat = 24
    /// 与窗口 toolbar（模型切换 / 分享复制）左右边缘对齐的内容边距
    static let toolbarContentHorizontalInset: CGFloat = 20
    static let sidebarContentHorizontalInset: CGFloat = 12
    static let sidebarSelectionCornerRadius: CGFloat = 12
    static let listSelectionCornerRadius: CGFloat = 6
    static let listRowVerticalInset: CGFloat = 2
    static let listRowHorizontalInset: CGFloat = 6
    static let composerCornerRadius: CGFloat = 20
    static let composerHorizontalInset: CGFloat = 16
    static let composerBottomInset: CGFloat = 14
    static let composerMessageGap: CGFloat = 20
    /// 输入区上方渐变毛玻璃过渡高度
    static let composerDockFadeHeight: CGFloat = 36
    /// 为底部悬浮输入区预留的滚动空间（含毛玻璃过渡）
    static var composerDockReservedHeight: CGFloat {
        composerMaxHeight + composerDockFadeHeight + composerBottomInset + composerMessageGap
    }
    static let composerInnerHorizontalPadding: CGFloat = 14
    static let composerInnerTopPadding: CGFloat = 12
    static let composerInnerBottomPadding: CGFloat = 8
    static let composerToolbarHeight: CGFloat = 36
    static let composerVoicePanelHeight: CGFloat = 56
    static let composerMinHeight: CGFloat = 96
    static let composerDefaultHeight: CGFloat = 96
    static let composerMaxHeight: CGFloat = 220
    static let composerDefaultTextHeight: CGFloat = 22
    static let composerTextMaxHeight: CGFloat = 156
    static let composerLineHeight: CGFloat = 22
    static let composerToolSize: CGFloat = 32
    /// 工具栏 SF Symbol / 自定义图标绘制尺寸（+、麦克风、地球等保持一致）
    static let composerToolbarIconContentSize: CGFloat = 18
    static let composerSendSize: CGFloat = 32
    static let composerToolbarFontSize: CGFloat = 13
    static let bodySize: CGFloat = 15
    static let sidebarRecentHeaderSize: CGFloat = 11
    static let sidebarSessionTitleSize: CGFloat = 13
    static let captionSize: CGFloat = 12
    static let codeSize: CGFloat = 13
}

struct GlassIntensityKey: EnvironmentKey {
    static let defaultValue: AppGlassIntensity = .standard
}

extension EnvironmentValues {
    var glassIntensity: AppGlassIntensity {
        get { self[GlassIntensityKey.self] }
        set { self[GlassIntensityKey.self] = newValue }
    }
}

extension Color {
    static let chatBoxCanvas = Color(nsColor: .windowBackgroundColor)
    static let chatBoxGroupedBackground = Color(nsColor: .controlBackgroundColor)
    static let chatBoxTextPrimary = Color.primary
    static let chatBoxTextSecondary = Color.secondary
    static let chatBoxSurface = Color(nsColor: .controlBackgroundColor).opacity(0.55)
    static let chatBoxSurfaceSolid = Color(nsColor: .controlBackgroundColor)
    static let chatBoxLine = Color(nsColor: .separatorColor)
    static let chatBoxUserBubble = Color(nsColor: .separatorColor).opacity(0.35)
    static let chatBoxAccent = Color.accentColor
    /// 列表选中行背景（浅灰胶囊，对齐系统侧栏样式）
    static let chatBoxListSelection = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.08)
            : NSColor(srgbRed: 235 / 255, green: 235 / 255, blue: 235 / 255, alpha: 1)
    })
    static let chatBoxComposerSurface = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.controlBackgroundColor
            : NSColor.white
    })
    static let chatBoxComposerBorder = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.separatorColor
            : NSColor(calibratedWhite: 0.88, alpha: 1)
    })
    static let chatBoxComposerTool = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.secondaryLabelColor
            : NSColor(calibratedWhite: 0.45, alpha: 1)
    })
    static let chatBoxComposerToolActive = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.labelColor
            : NSColor(calibratedWhite: 0.18, alpha: 1)
    })
    static let chatBoxComposerSendDisabled = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.28, alpha: 1)
            : NSColor(calibratedWhite: 0.82, alpha: 1)
    })
    static let chatBoxComposerSendEnabled = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.88, alpha: 1)
            : NSColor(calibratedWhite: 0.12, alpha: 1)
    })
}

private struct LiquidGlassSurfaceModifier: ViewModifier {
    @Environment(\.glassIntensity) private var glassIntensity

    let cornerRadius: CGFloat
    let interactive: Bool

    func body(content: Content) -> some View {
        content.glassEffect(
            glassIntensity.liquidGlass(interactive: interactive),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }
}

extension View {
    func chatBoxLiquidGlass(cornerRadius: CGFloat = AppLayout.composerCornerRadius, interactive: Bool = false) -> some View {
        modifier(LiquidGlassSurfaceModifier(cornerRadius: cornerRadius, interactive: interactive))
    }

    func chatBoxGlassCard(cornerRadius: CGFloat = AppLayout.composerCornerRadius, interactive: Bool = false) -> some View {
        chatBoxLiquidGlass(cornerRadius: cornerRadius, interactive: interactive)
    }

    func chatBoxCenteredContent() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppLayout.toolbarContentHorizontalInset)
    }

    func chatBoxListRowBackground(isSelected: Bool) -> some View {
        listRowBackground(
            Group {
                if isSelected {
                    RoundedRectangle(
                        cornerRadius: AppLayout.listSelectionCornerRadius,
                        style: .continuous
                    )
                    .fill(Color.chatBoxListSelection)
                } else {
                    Color.clear
                }
            }
        )
        .listRowInsets(
            EdgeInsets(
                top: AppLayout.listRowVerticalInset,
                leading: AppLayout.listRowHorizontalInset,
                bottom: AppLayout.listRowVerticalInset,
                trailing: AppLayout.listRowHorizontalInset
            )
        )
    }

    /// 侧栏列表行：与搜索框同宽（12pt 边距），选中灰底 + 主色文字
    func chatBoxSidebarListRow(isSelected: Bool) -> some View {
        foregroundStyle(Color.primary)
            .listRowBackground(Color.clear)
            .listRowInsets(
                EdgeInsets(
                    top: AppLayout.listRowVerticalInset,
                    leading: AppLayout.sidebarContentHorizontalInset,
                    bottom: AppLayout.listRowVerticalInset,
                    trailing: AppLayout.sidebarContentHorizontalInset
                )
            )
    }

}

extension View {
    /// 悬浮输入卡片：Liquid Glass / 材质 + 轻阴影。
    func chatBoxFloatingComposerChrome() -> some View {
        chatBoxLiquidGlass(cornerRadius: AppLayout.composerCornerRadius, interactive: true)
            .shadow(color: .black.opacity(0.08), radius: 14, y: 5)
            .overlay {
                RoundedRectangle(cornerRadius: AppLayout.composerCornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
            }
    }

    func chatBoxFloatingComposerLayout() -> some View {
        frame(maxWidth: .infinity)
            .padding(.horizontal, AppLayout.composerHorizontalInset)
    }

    /// 底部整条毛玻璃衬底，消息滚动到输入框下方时会透过模糊显示。
    func chatBoxComposerDock() -> some View {
        padding(.top, AppLayout.composerDockFadeHeight)
            .padding(.bottom, AppLayout.composerBottomInset)
            .background {
                ComposerDockFrostedBackground()
                    .allowsHitTesting(false)
            }
    }

    func thinkingShimmer(active: Bool) -> some View {
        overlay {
            if active {
                ThinkingShimmerOverlay()
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct ComposerDockFrostedBackground: View {
    @Environment(\.glassIntensity) private var glassIntensity

    var body: some View {
        Rectangle()
            .fill(material)
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [.clear, .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: AppLayout.composerDockFadeHeight + 28)
                    Color.black
                }
            }
    }

    private var material: Material {
        switch glassIntensity {
        case .subtle: .ultraThinMaterial
        case .standard: .thinMaterial
        case .strong: .regularMaterial
        }
    }
}

/// 思考进行中的表面流光，对齐 ChatGPT macOS 的 shimmer 效果。
struct ThinkingShimmerOverlay: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 1.6) / 1.6

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Color.primary.opacity(0.04), location: 0.38),
                    .init(color: Color.primary.opacity(0.14), location: 0.5),
                    .init(color: Color.primary.opacity(0.04), location: 0.62),
                    .init(color: .clear, location: 1),
                ],
                startPoint: UnitPoint(x: phase * 2.2 - 0.6, y: 0.5),
                endPoint: UnitPoint(x: phase * 2.2 + 0.6, y: 0.5)
            )
            .blendMode(.plusLighter)
        }
    }
}

/// 助手消息区的思考状态标签，对齐 ChatGPT macOS：灰色文字 + 流光，无胶囊底。
struct ThinkingStatusLabel: View {
    let text: String
    var isShimmerActive: Bool = false
    var showsChevron: Bool = false
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 2) {
                if isShimmerActive {
                    ThinkingShimmerText(text: text, font: .system(size: 14))
                } else {
                    Text(text)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }

                if showsChevron {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
    }
}

struct ThinkingShimmerText: View {
    let text: String
    var font: Font = .system(size: 13)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 1.6) / 1.6
            let center = min(1, max(0, phase * 1.4))
            let leading = min(center, max(0, center - 0.15))
            let trailing = max(center, min(1, center + 0.15))

            Text(text)
                .font(font)
                .foregroundStyle(.clear)
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: Color.secondary.opacity(0.55), location: 0),
                            .init(color: Color.secondary.opacity(0.55), location: leading),
                            .init(color: Color.primary.opacity(0.92), location: center),
                            .init(color: Color.secondary.opacity(0.55), location: trailing),
                            .init(color: Color.secondary.opacity(0.55), location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .mask {
                        Text(text).font(font)
                    }
                }
        }
    }
}
