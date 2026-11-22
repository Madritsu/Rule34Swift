import AVFoundation
import AVKit
import Combine
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct R34VideoPlayerView: View {
    let url: URL
    let topLeading: AnyView
    let topTrailing: AnyView

    @StateObject private var model: PlayerModel
    @State private var controlsVisible = true
    @State private var hideWorkItem: DispatchWorkItem?
    @State private var isScrubbing = false

    init(url: URL, topLeading: AnyView = AnyView(EmptyView()), topTrailing: AnyView = AnyView(EmptyView())) {
        self.url = url
        self.topLeading = topLeading
        self.topTrailing = topTrailing
        _model = StateObject(wrappedValue: PlayerModel(url: url))
    }

    var body: some View {
        ZStack {
            #if os(macOS)
            macOSPlayerView
                .ignoresSafeArea()
                .onTapGesture {
                    toggleControls()
                }
            #else
            PlayerLayerView(player: model.player)
                .ignoresSafeArea()
                .onTapGesture {
                    toggleControls()
                }
            #endif

            if model.isBuffering {
                ProgressView()
                    .tint(.orange)
                    .scaleEffect(1.15)
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.callout.weight(.medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
                    .padding()
            }

            if controlsVisible {
                VStack(spacing: 10) {
                    topBar
                    Spacer()
                    bottomBar
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: controlsVisible)
        .onAppear {
            model.play()
            scheduleAutohide()
        }
        .onDisappear {
            hideWorkItem?.cancel()
            model.pause()
        }
    }

    #if os(macOS)
    private var macOSPlayerView: some View {
        VideoPlayer(player: model.player)
            .aspectRatio(16/9, contentMode: .fit)
    }
    #endif

    private var topBar: some View {
        HStack(spacing: 10) {
            #if !os(macOS)
            AirPlayRoutePicker()
                .frame(width: 44, height: 44)
                .r34Glass(cornerRadius: 22, interactive: true)
            #endif

            topLeading

            Spacer()

            topTrailing
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.001))
        .contentShape(Rectangle())
        .padding(.top, 6)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    model.togglePlayPause()
                    scheduleAutohide()
                } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                }

                Text(model.currentTimeText)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)

                Slider(
                    value: Binding(
                        get: { model.progress },
                        set: { newValue in
                            model.progress = newValue
                        }
                    ),
                    in: 0...1,
                    onEditingChanged: { editing in
                        isScrubbing = editing
                        if editing {
                            hideWorkItem?.cancel()
                        } else {
                            model.seekToProgress()
                            scheduleAutohide()
                        }
                    }
                )
                .tint(.orange)

                Text(model.durationText)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)

                Button {
                    model.isMuted.toggle()
                    scheduleAutohide()
                } label: {
                    Image(systemName: model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .r34Glass(cornerRadius: 22, interactive: true)
        .padding(.bottom, 10)
    }

    private func toggleControls() {
        controlsVisible.toggle()
        if controlsVisible {
            scheduleAutohide()
        } else {
            hideWorkItem?.cancel()
        }
    }

    private func scheduleAutohide() {
        hideWorkItem?.cancel()
        guard model.isPlaying else { return }
        let work = DispatchWorkItem {
            if !isScrubbing {
                controlsVisible = false
            }
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8, execute: work)
    }
}

@MainActor
final class PlayerModel: ObservableObject {
    let player: AVPlayer

    @Published var isPlaying: Bool = false
    @Published private(set) var isBuffering = false
    @Published private(set) var errorMessage: String?
    @Published var isMuted: Bool {
        didSet {
            player.isMuted = isMuted
            UserDefaults.standard.set(isMuted, forKey: "videoPlayerMuted")
        }
    }

    @Published var progress: Double = 0
    @Published private(set) var currentTimeText: String = "0:00"
    @Published private(set) var durationText: String = "0:00"

    private var timeObserver: Any?
    private var isSeeking = false
    private var cancellables = Set<AnyCancellable>()

    init(url: URL) {
        let savedMuteState = UserDefaults.standard.bool(forKey: "videoPlayerMuted")
        self.isMuted = savedMuteState

        // AVPlayerItem(url:) is the most reliable path for rule34.xxx video hosts.
        // Some hosts reject or mishandle AVURLAsset requests with custom headers.
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .pause
        player.isMuted = savedMuteState
        player.automaticallyWaitsToMinimizeStalling = true

        addTimeObserver()
        NotificationCenter.default.addObserver(self, selector: #selector(didFinish), name: .AVPlayerItemDidPlayToEndTime, object: item)
        NotificationCenter.default.addObserver(self, selector: #selector(playbackStalled), name: .AVPlayerItemPlaybackStalled, object: item)
        item.publisher(for: \AVPlayerItem.status)
            .receive(on: RunLoop.main)
            .sink { [weak self] (status: AVPlayerItem.Status) in
                guard let self else { return }
                if status == .failed {
                    self.isBuffering = false
                    self.errorMessage = item.error?.localizedDescription ?? NSLocalizedString("Video could not be loaded", comment: "Video error")
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        NotificationCenter.default.removeObserver(self)
    }

    func play() {
        errorMessage = nil
        isBuffering = true
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
        isBuffering = false
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func seekToProgress() {
        guard let item = player.currentItem else { return }
        let duration = item.duration.seconds
        guard duration.isFinite, duration > 0 else { return }
        let target = duration * progress
        isSeeking = true
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                self?.isSeeking = false
            }
        }
    }

    private func addTimeObserver() {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            guard let item = self.player.currentItem else { return }

            let current = time.seconds
            let duration = item.duration.seconds

            Task { @MainActor in
                self.isBuffering = self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate && self.isPlaying
                if duration.isFinite, duration > 0 {
                    if !self.isSeeking {
                        self.progress = min(max(current / duration, 0), 1)
                    }
                    self.durationText = Self.formatTime(duration)
                }
                self.currentTimeText = Self.formatTime(current)
            }
        }
    }

    @objc private func didFinish() {
        pause()
        player.seek(to: .zero)
    }

    @objc private func playbackStalled() {
        isBuffering = isPlaying
    }

    private static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds.rounded(.down))
        let m = s / 60
        let r = s % 60
        return "\(m):" + String(format: "%02d", r)
    }
}

#if canImport(UIKit) && !os(macOS)
private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let v = PlayerContainerView()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspect
        return v
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.playerLayer.player = player
    }
}

private final class PlayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

private struct AirPlayRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.backgroundColor = .clear
        view.tintColor = UIColor.systemOrange
        view.activeTintColor = UIColor.systemOrange
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif
