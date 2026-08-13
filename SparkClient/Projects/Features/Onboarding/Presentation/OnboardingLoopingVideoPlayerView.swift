import AVFoundation
import SwiftUI
import UIKit

struct OnboardingLoopingVideoPlayerView: UIViewRepresentable {
    let url: URL
    let videoGravity: AVLayerVideoGravity

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> OnboardingPlayerContainerView {
        let view = OnboardingPlayerContainerView()
        view.playerLayer.videoGravity = videoGravity
        context.coordinator.attach(to: view, url: url)
        return view
    }

    func updateUIView(_ uiView: OnboardingPlayerContainerView, context: Context) {
        uiView.playerLayer.videoGravity = videoGravity
        context.coordinator.attach(to: uiView, url: url)
    }

    static func dismantleUIView(_ uiView: OnboardingPlayerContainerView, coordinator: Coordinator) {
        coordinator.detach(from: uiView)
    }

    final class Coordinator {
        private let player = AVQueuePlayer()
        private var looper: AVPlayerLooper?
        private var currentURL: URL?

        func attach(to view: OnboardingPlayerContainerView, url: URL) {
            view.playerLayer.player = player

            guard currentURL != url else {
                if player.timeControlStatus != .playing {
                    player.play()
                }
                return
            }

            currentURL = url
            player.removeAllItems()
            player.isMuted = true
            player.actionAtItemEnd = .none

            let item = AVPlayerItem(url: url)
            looper = AVPlayerLooper(player: player, templateItem: item)
            player.play()
        }

        func detach(from view: OnboardingPlayerContainerView) {
            player.pause()
            view.playerLayer.player = nil
        }
    }
}

final class OnboardingPlayerContainerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        guard let layer = layer as? AVPlayerLayer else {
            fatalError("Expected AVPlayerLayer")
        }
        return layer
    }
}
