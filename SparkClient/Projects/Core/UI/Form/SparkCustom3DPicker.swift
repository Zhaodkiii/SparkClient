import SwiftUI

@available(iOS 17.0, *)
struct SparkCustom3DPickerConfig {
    var text: String
    var show = false
    var sourceFrame: CGRect = .zero
}

@available(iOS 17.0, *)
extension View {
    @ViewBuilder
    func sparkCustom3DPicker(_ config: Binding<SparkCustom3DPickerConfig>, items: [String]) -> some View {
        overlay {
            if config.wrappedValue.show {
                SparkCustom3DPickerOverlay(texts: items, config: config)
                    .transition(.identity)
            }
        }
    }
}

@available(iOS 17.0, *)
struct SparkCustom3DPickerSourceView: View {
    @Binding var config: SparkCustom3DPickerConfig

    var body: some View {
        Text(config.text)
            .foregroundStyle(.blue)
            .frame(height: 20)
            .opacity(config.show ? 0 : 1)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { newValue in
                config.sourceFrame = newValue
            }
    }
}

@available(iOS 17.0, *)
private struct SparkCustom3DPickerOverlay: View {
    var texts: [String]
    @Binding var config: SparkCustom3DPickerConfig

    @State private var activeText: String?
    @State private var showContents = false
    @State private var showScrollView = false
    @State private var expandItems = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(showContents ? 1 : 0)
                .ignoresSafeArea()

            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(texts, id: \.self) { text in
                        cardView(text, size: size)
                    }
                }
                .scrollTargetLayout()
            }
            .safeAreaPadding(.top, (size.height * 0.5) - 20)
            .safeAreaPadding(.bottom, size.height * 0.5)
            .scrollPosition(id: $activeText, anchor: .center)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            .scrollIndicators(.hidden)
            .opacity(showScrollView ? 1 : 0)
            .allowsHitTesting(expandItems && showScrollView)

            let offset: CGSize = .init(
                width: showContents ? size.width * -0.3 : config.sourceFrame.minX,
                height: showContents ? -10 : config.sourceFrame.minY
            )

            Text(config.text)
                .fontWeight(showContents ? .semibold : .regular)
                .foregroundStyle(.blue)
                .frame(height: 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: showContents ? .trailing : .topLeading)
                .offset(offset)
                .opacity(showScrollView ? 0 : 1)
                .ignoresSafeArea(.all, edges: showContents ? [] : .all)

            closeButton
        }
        .task {
            guard activeText == nil else { return }
            activeText = config.text

            withAnimation(.easeInOut(duration: 0.3)) {
                showContents = true
            }

            try? await Task.sleep(for: .seconds(0.3))
            showScrollView = true

            withAnimation(.snappy(duration: 0.3, extraBounce: 0)) {
                expandItems = true
            }
        }
        .onChange(of: activeText) { _, newValue in
            guard let newValue else { return }
            config.text = newValue
        }
    }

    private var closeButton: some View {
        Button {
            Task {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandItems = false
                }

                try? await Task.sleep(for: .seconds(0.2))
                showScrollView = false

                withAnimation(.easeInOut(duration: 0.2)) {
                    showContents = false
                }

                try? await Task.sleep(for: .seconds(0.2))
                config.show = false
            }
        } label: {
            Image(systemName: "xmark")
                .font(.title2)
                .foregroundStyle(Color.primary)
                .frame(width: 45, height: 45)
                .contentShape(.rect)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .offset(x: showContents ? -50 : -20, y: -10)
        .opacity(showContents ? 1 : 0)
        .blur(radius: showContents ? 0 : 5)
    }

    private func cardView(_ text: String, size: CGSize) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            Text(text)
                .fontWeight(.semibold)
                .foregroundStyle(config.text == text ? .blue : .gray)
                .blur(radius: expandItems ? 0 : config.text == text ? 0 : 5)
                .offset(y: offset(proxy))
                .clipped()
                .offset(x: -width * 0.3)
                .rotationEffect(.degrees(expandItems ? -rotation(proxy, size) : .zero), anchor: .topTrailing)
                .opacity(opacity(proxy, size))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .frame(height: 20)
        .lineLimit(1)
        .zIndex(config.text == text ? 1000 : 0)
    }

    private func offset(_ proxy: GeometryProxy) -> CGFloat {
        let minY = proxy.frame(in: .scrollView(axis: .vertical)).minY
        return expandItems ? 0 : -minY
    }

    private func rotation(_ proxy: GeometryProxy, _ size: CGSize) -> CGFloat {
        let height = size.height * 0.5
        let minY = proxy.frame(in: .scrollView(axis: .vertical)).minY
        let maxRotation: CGFloat = 220
        let progress = minY / height
        return progress * maxRotation
    }

    private func opacity(_ proxy: GeometryProxy, _ size: CGSize) -> CGFloat {
        let minY = proxy.frame(in: .scrollView(axis: .vertical)).minY
        let height = size.height * 0.5
        let progress = (minY / height) * 2.8
        return progress < 0 ? 1 + progress : 1 - progress
    }
}
