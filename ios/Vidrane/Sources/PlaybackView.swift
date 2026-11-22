import SwiftUI
import AVKit

struct PlaybackView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("keepScreenOn") private var keepScreenOn = true
    @AppStorage("playbackRate") private var playbackRate = 1.0
    let request: PlaybackRequest
    @State private var player = AVPlayer()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(request.title).lineLimit(1).font(.subheadline)
                Spacer()
                Button("Готово") { dismiss() }
                    .foregroundStyle(VidraneStyle.accent)
            }
            .padding()
            SystemPlayer(player: player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.black)
        .onAppear {
            player.replaceCurrentItem(with: AVPlayerItem(url: request.url))
            player.play()
            if playbackRate != 1 { player.rate = Float(playbackRate) }
            UIApplication.shared.isIdleTimerDisabled = keepScreenOn
        }
        .onDisappear {
            player.pause()
            player.replaceCurrentItem(with: nil)
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
}

struct SystemPlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
}
