import SwiftUI

/// Компактная стеклянная карточка с 10-полосным эквалайзером, выбором пресетов и предусилением.
public struct EqualizerPopoverView: View {
    @UIState private var eqSettings = EqualizerSettings.shared
    @UIState private var coordinator = NavigationCoordinator.shared
    @UIState private var windowState = WindowState.shared

    public init() {}

    public var body: some View {
        let cardWidth = min(404, max(320, windowState.windowSize.width - 24))

        VStack(alignment: .leading, spacing: 14) {
            // Верхняя панель: заголовок, переключатель Вкл/Выкл, пресеты и сброс
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "slider.vertical.3")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(eqSettings.isEnabled ? YMTheme.accent : YMTheme.fg60)

                    Text("Эквалайзер")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(YMTheme.fg)
                }

                Toggle("", isOn: $eqSettings.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(YMTheme.accent)

                Spacer()

                Menu {
                    ForEach(YMEqualizerPreset.allCases) { preset in
                        Button {
                            eqSettings.selectPreset(preset)
                        } label: {
                            HStack {
                                Text(preset.title)
                                if eqSettings.selectedPreset == preset {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(eqSettings.selectedPreset.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(YMTheme.fg)
                            .lineLimit(1)

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(YMTheme.fg40)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(YMTheme.surfaceComponent)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(YMTheme.border, lineWidth: 1)
                            )
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        eqSettings.reset()
                    }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(YMTheme.fg60)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(YMTheme.surfaceComponent))
                }
                .buttonStyle(.plain)
                .help("Сбросить все полосы в 0 дБ")

                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.86)) {
                        coordinator.isEqualizerPresented = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(YMTheme.fg60)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(YMTheme.surfaceComponent))
                }
                .buttonStyle(.plain)
                .help("Закрыть эквалайзер (Esc)")
            }

            // Строка предусиления (Preamp: -6...+6 дБ)
            HStack(spacing: 10) {
                Text("Предусиление")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(YMTheme.fg60)

                YMSlider(
                    value: Binding(
                        get: { Double(eqSettings.preampDb) },
                        set: { eqSettings.setPreamp(Float($0)) }
                    ),
                    in: -6...6,
                    activeColor: eqSettings.isEnabled ? YMTheme.accent : YMTheme.fg40,
                    trackColor: YMTheme.surfaceComponentHover,
                    height: 3
                )

                Text(formatDb(eqSettings.preampDb))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(YMTheme.fg60)
                    .frame(width: 48, alignment: .trailing)
            }
            .opacity(eqSettings.isEnabled ? 1.0 : 0.5)

            Divider()
                .overlay(YMTheme.border)

            // 10 вертикальных ползунков частот
            HStack(alignment: .center, spacing: 6) {
                // Шкала дБ слева
                VStack {
                    Text("+12")
                    Spacer()
                    Text("0")
                    Spacer()
                    Text("-12")
                }
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(YMTheme.fg40)
                .frame(width: 22, height: 132)
                .padding(.bottom, 18)

                ForEach(0..<10, id: \.self) { index in
                    VerticalEQBandControl(
                        label: EqualizerSettings.bandLabels[index],
                        gainDb: eqSettings.bandGains[index],
                        isEnabled: eqSettings.isEnabled,
                        onChange: { newGain in
                            eqSettings.setBandGain(index: index, gain: newGain)
                        }
                    )
                }
            }
            .opacity(eqSettings.isEnabled ? 1.0 : 0.45)
        }
        .padding(16)
        .frame(width: cardWidth)
        .background {
            ZStack {
                VisualEffectBlur(material: .popover, blendingMode: .withinWindow)
                YMTheme.surface.opacity(YMTheme.isLight ? 0.86 : 0.82)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(YMTheme.borderHover, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(YMTheme.isLight ? 0.14 : 0.42), radius: 22, x: 0, y: 10)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {}
    }

    private func formatDb(_ val: Float) -> String {
        if abs(val) < 0.05 { return "0.0 дБ" }
        return String(format: "%+.1f дБ", val)
    }
}

/// Отдельный вертикальный ползунок частотной полосы с поддержкой двойного клика для сброса в 0 дБ.
private struct VerticalEQBandControl: View {
    let label: String
    let gainDb: Float
    let isEnabled: Bool
    let onChange: (Float) -> Void

    @UIState private var isDragging = false

    private let trackHeight: CGFloat = 132

    private var normalizedRatio: CGFloat {
        let span = EqualizerSettings.maxGainDb - EqualizerSettings.minGainDb
        guard span > 0 else { return 0.5 }
        return CGFloat((gainDb - EqualizerSettings.minGainDb) / span)
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let h = geo.size.height
                let midY = h * 0.5
                let knobY = h * (1.0 - normalizedRatio)
                let fillTop = min(midY, knobY)
                let fillHeight = abs(knobY - midY)

                ZStack(alignment: .top) {
                    // Центральная метка 0 дБ
                    Rectangle()
                        .fill(YMTheme.borderHover)
                        .frame(width: 14, height: 1)
                        .offset(y: midY)

                    // Фоновая дорожка
                    Capsule()
                        .fill(YMTheme.surfaceComponentHover)
                        .frame(width: 4, height: h)

                    // Активная заливка от центра (0 дБ) до текущего значения
                    Capsule()
                        .fill(isEnabled ? YMTheme.accent : YMTheme.fg40)
                        .frame(width: 4, height: max(2, fillHeight))
                        .offset(y: fillTop)

                    // Бегунок
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().strokeBorder(YMTheme.borderHover, lineWidth: 0.5))
                        .frame(width: isDragging ? 13 : 11, height: isDragging ? 13 : 11)
                        .shadow(color: YMTheme.shadowColor, radius: 3, y: 1)
                        .offset(y: max(0, min(h - 11, knobY - 5.5)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            let clampedY = min(max(value.location.y, 0), h)
                            let ratio = 1.0 - Float(clampedY / h)
                            let span = EqualizerSettings.maxGainDb - EqualizerSettings.minGainDb
                            let rawGain = EqualizerSettings.minGainDb + ratio * span
                            let snapped = (rawGain * 2).rounded() / 2
                            onChange(snapped)
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )
                .onTapGesture(count: 2) {
                    onChange(0.0)
                }
            }
            .frame(height: trackHeight)

            Text(label)
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(abs(gainDb) > 0.1 && isEnabled ? YMTheme.accent : YMTheme.fg60)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .help("\(label) Гц: \(String(format: "%+.1f дБ", gainDb)) (двойной клик — сброс)")
    }
}
