import SwiftUI
import MapKit
import WebKit
import UIKit

struct ChatMapLocationPayload: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let latitude: Double
    let longitude: Double

    init(id: UUID = UUID(), name: String, latitude: Double, longitude: Double) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }
}

struct ChatRoutePayload: Codable, Identifiable, Equatable {
    let id: UUID
    let summary: String
    let distance: String?
    let duration: String?
    let mode: String?

    init(
        id: UUID = UUID(),
        summary: String,
        distance: String? = nil,
        duration: String? = nil,
        mode: String? = nil
    ) {
        self.id = id
        self.summary = summary
        self.distance = distance
        self.duration = duration
        self.mode = mode
    }
}

struct ChatEventPayload: Codable, Identifiable, Equatable {
    let id: UUID
    let type: String
    let title: String
    let dateText: String?
    let location: String?
    let notes: String?

    init(
        id: UUID = UUID(),
        type: String,
        title: String,
        dateText: String? = nil,
        location: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.dateText = dateText
        self.location = location
        self.notes = notes
    }
}

struct ChatHealthCardPayload: Codable, Identifiable, Equatable {
    let id: UUID
    let title: String
    let energyKilocalories: Double?
    let proteinGrams: Double?
    let carbohydratesGrams: Double?
    let fatGrams: Double?
    let dateText: String?

    init(
        id: UUID = UUID(),
        title: String,
        energyKilocalories: Double? = nil,
        proteinGrams: Double? = nil,
        carbohydratesGrams: Double? = nil,
        fatGrams: Double? = nil,
        dateText: String? = nil
    ) {
        self.id = id
        self.title = title
        self.energyKilocalories = energyKilocalories
        self.proteinGrams = proteinGrams
        self.carbohydratesGrams = carbohydratesGrams
        self.fatGrams = fatGrams
        self.dateText = dateText
    }
}

struct ChatTranslatedBlockView: View {
    let text: String
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack {
                    Text(L10n.text("chat.bubble.translate.title"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            if expanded {
                Markdown(text)
                    .markdownTheme(.chatBubble(foreground: .primary))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
        )
    }
}

struct ChatEventsCardListView: View {
    let events: [ChatEventPayload]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(events) { event in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: event.type.lowercased() == "calendar" ? "calendar" : "list.bullet")
                            .foregroundStyle(.secondary)
                        Text(event.title)
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 0)
                    }
                    if let dateText = event.dateText, dateText.isEmpty == false {
                        Text(dateText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let location = event.location, location.isEmpty == false {
                        Text(location)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let notes = event.notes, notes.isEmpty == false {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                )
            }
        }
    }
}

struct ChatHealthCardListView: View {
    let cards: [ChatHealthCardPayload]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(cards) { card in
                VStack(alignment: .leading, spacing: 6) {
                    Text(card.title)
                        .font(.subheadline.weight(.semibold))
                    HStack {
                        nutrient("kcal", card.energyKilocalories)
                        nutrient("P", card.proteinGrams)
                        nutrient("C", card.carbohydratesGrams)
                        nutrient("F", card.fatGrams)
                    }
                    if let dateText = card.dateText, dateText.isEmpty == false {
                        Text(dateText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                )
            }
        }
    }

    private func nutrient(_ key: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value.map { String(format: "%.1f", $0) } ?? "--")
                .font(.caption.weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ChatSleepCardView: View {
    let model: ChatHealthSleepModel

    private var sortedDays: [ChatHealthSleepModel.Day] {
        model.days.sorted { $0.date < $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("睡眠")
                .font(.subheadline.weight(.semibold))

            ForEach(sortedDays) { day in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(day.date)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(day.summary.totalSleepMinutes) 分钟")
                            .font(.caption.weight(.semibold))
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color(uiColor: .tertiarySystemFill))
                            HStack(spacing: 2) {
                                ForEach(day.timeline) { segment in
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(chatSleepStageColor(segment.stage))
                                        .frame(width: max(2, geo.size.width * max(0, segment.widthPercent)))
                                }
                            }
                        }
                    }
                    .frame(height: 12)

                    HStack(spacing: 10) {
                        stageChip(.deep, value: day.stages.deep)
                        stageChip(.core, value: day.stages.core)
                        stageChip(.rem, value: day.stages.rem)
                        if day.stages.awake > 0 {
                            stageChip(.awake, value: day.stages.awake)
                        }
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                )
            }
        }
    }

    private func stageChip(_ stage: ChatHealthSleepModel.Stage, value: Int) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(chatSleepStageColor(stage))
                .frame(width: 7, height: 7)
            Text("\(stage.displayName) \(value)m")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private func chatSleepStageColor(_ stage: ChatHealthSleepModel.Stage) -> Color {
    switch stage {
    case .deep:
        return Color(red: 30 / 255, green: 58 / 255, blue: 138 / 255)
    case .core:
        return Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255)
    case .rem:
        return Color(red: 96 / 255, green: 165 / 255, blue: 250 / 255)
    case .awake:
        return Color(red: 255 / 255, green: 107 / 255, blue: 107 / 255)
    case .unspecified:
        return Color(red: 95 / 255, green: 85 / 255, blue: 236 / 255)
    }
}

struct ChatMapRouteBlockView: View {
    let locations: [ChatMapLocationPayload]
    let routes: [ChatRoutePayload]
    @State private var mapType: MKMapType = .standard
    @State private var showFullMap = false

    private var region: MKCoordinateRegion {
        guard let first = locations.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074),
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            )
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ChatUIKitMapView(region: region, locations: locations, mapType: mapType)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 10) {
                Button {
                    mapType = mapType == .standard ? .hybridFlyover : .standard
                } label: {
                    Label(L10n.text("chat.bubble.map.style"), systemImage: "map")
                        .font(.caption)
                }
                Button {
                    showFullMap = true
                } label: {
                    Label(L10n.text("chat.bubble.map.fullscreen"), systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.caption)
                }
                if let first = locations.first {
                    Button {
                        let name = first.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Destination"
                        if let url = URL(string: "http://maps.apple.com/?daddr=\(first.latitude),\(first.longitude)&q=\(name)") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label(L10n.text("chat.bubble.map.navigate"), systemImage: "location.north.line")
                            .font(.caption)
                    }
                }
            }

            if routes.isEmpty == false {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(routes) { route in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(route.summary)
                                .font(.caption.weight(.medium))
                            Text([route.distance, route.duration, route.mode]
                                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { $0.isEmpty == false }
                                .joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showFullMap) {
            ChatUIKitMapView(region: region, locations: locations, mapType: mapType)
                .ignoresSafeArea()
        }
    }
}

struct ChatHTMLPreviewBlockView: View {
    let htmlContent: String
    @State private var showFull = false
    @State private var showSource = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ChatHTMLWebView(htmlContent: htmlContent)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 8) {
                Button {
                    showSource = true
                } label: {
                    Image(systemName: "chevron.left.slash.chevron.right")
                }
                Button {
                    showFull = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
            }
            .font(.caption)
            .padding(8)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(8)
        }
        .sheet(isPresented: $showSource) {
            NavigationView {
                ScrollView {
                    Text(htmlContent)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle(L10n.text("chat.bubble.web.source"))
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(L10n.text("chat.bubble.action.copy")) {
                            UIPasteboard.general.string = htmlContent
                        }
                    }
                }
            }
            .navigationViewStyle(.stack)
        }
        .fullScreenCover(isPresented: $showFull) {
            NavigationView {
                ChatHTMLWebView(htmlContent: htmlContent)
                    .ignoresSafeArea()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(L10n.text("common.close")) {
                                showFull = false
                            }
                        }
                    }
            }
            .navigationViewStyle(.stack)
        }
    }
}

struct ChatImagePayload: Identifiable, Equatable {
    let id: UUID
    let url: URL?
    let image: UIImage?
}

struct ChatImageGalleryBlockView: View {
    let images: [ChatImagePayload]
    @State private var selectedImage: UIImage?
    @State private var selectedURL: URL?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(images) { payload in
                    ZStack {
                        if let image = payload.image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else if let url = payload.url {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView()
                                case .success(let image):
                                    image.resizable().scaledToFill()
                                case .failure:
                                    Image(systemName: "photo")
                                @unknown default:
                                    Image(systemName: "photo")
                                }
                            }
                        } else {
                            Image(systemName: "photo")
                        }
                    }
                    .frame(width: 180, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contextMenu {
                        if let image = payload.image {
                            Button(L10n.text("chat.bubble.image.copy"), systemImage: "square.on.square") {
                                UIPasteboard.general.image = image
                            }
                            Button(L10n.text("chat.bubble.image.save"), systemImage: "square.and.arrow.down") {
                                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                            }
                        }
                    }
                    .onTapGesture {
                        selectedImage = payload.image
                        selectedURL = payload.url
                    }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { selectedImage != nil || selectedURL != nil },
            set: { if !$0 { selectedImage = nil; selectedURL = nil } }
        )) {
            ZStack {
                Color.black.ignoresSafeArea()
                if let selectedImage {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .scaledToFit()
                        .padding()
                } else if let selectedURL {
                    AsyncImage(url: selectedURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView().tint(.white)
                        case .success(let image):
                            image.resizable().scaledToFit().padding()
                        case .failure:
                            Image(systemName: "photo")
                                .foregroundStyle(.white)
                        @unknown default:
                            Image(systemName: "photo")
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
        }
    }
}

private struct ChatUIKitMapView: UIViewRepresentable {
    let region: MKCoordinateRegion
    let locations: [ChatMapLocationPayload]
    let mapType: MKMapType

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.showsCompass = true
        return map
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.mapType = mapType
        mapView.setRegion(region, animated: true)
        mapView.removeAnnotations(mapView.annotations)
        let annotations = locations.map { location -> MKPointAnnotation in
            let a = MKPointAnnotation()
            a.title = location.name
            a.coordinate = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
            return a
        }
        mapView.addAnnotations(annotations)
    }
}

private struct ChatHTMLWebView: UIViewRepresentable {
    let htmlContent: String

    func makeUIView(context: Context) -> WKWebView {
        WKWebView()
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.loadHTMLString(htmlContent, baseURL: nil)
    }
}
