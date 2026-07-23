import SwiftUI
import AppKit
import HashDIslandKit

/// Leading compact-live: album artwork to the left of the notch.
/// Shows while a track is present — playing or paused — so the artwork stays
/// on the notch after you pause, until the player quits or the tab closes.
struct MediaArtworkView: View {
    @ObservedObject var monitor: MediaMonitor
    let theme: Theme

    var body: some View {
        if let media = monitor.nowPlaying {
            artwork(media)
                .transition(.scale.combined(with: .opacity))
        }
    }

    @ViewBuilder
    private func artwork(_ media: NowPlaying) -> some View {
        let size: CGFloat = 26
        Group {
            if let data = media.artwork, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(theme.subtitleColor)
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
    }
}

/// Trailing compact-live: the track title to the right of the notch — long
/// titles scroll like on the iPhone — with the audio bars at the far end,
/// away from the notch so the text never disappears under it.
struct MediaTitleView: View {
    @ObservedObject var monitor: MediaMonitor
    let theme: Theme

    var body: some View {
        if let media = monitor.nowPlaying {
            HStack(spacing: 7) {
                // The title scrolls only while playing, for the same reason the
                // bars only dance then: a paused track sits at the notch for as
                // long as you leave it, and neither should be animating there.
                MarqueeText(media.title, scrolls: media.isPlaying)
                    .foregroundStyle(theme.textColor)
                // Bars dance only while playing; they rest as dots when paused.
                AudioBarsView(isActive: media.isPlaying, tint: theme.accent)
            }
            .frame(maxWidth: 140, alignment: .leading)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
}

/// Expanded detail: the iPhone-island media card — artwork, scrolling title,
/// artist, audio bars, a live progress bar, and play/skip controls for the
/// players we can script (Spotify, Music).
struct MediaDetailView: View {
    @ObservedObject var monitor: MediaMonitor
    let theme: Theme

    var body: some View {
        if let media = monitor.nowPlaying {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    artwork(media)
                    VStack(alignment: .leading, spacing: 3) {
                        // Unlike the strip, this title keeps scrolling while
                        // paused. The panel only exists while you are hovering
                        // it, so the animation is bounded by your attention —
                        // and being able to read the whole of a long title is
                        // worth more here than the second or two of motion.
                        MarqueeText(media.title)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(theme.textColor)
                        if let artist = media.artist {
                            Text(artist)
                                .font(.system(size: 10))
                                .foregroundStyle(theme.subtitleColor)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    AudioBarsView(isActive: media.isPlaying, tint: theme.accent)
                }

                if let progress = monitor.progress {
                    progressBar(progress)
                }

                // Controls work for every source: Spotify/Music via their own
                // scripting, everything else through the system media channel.
                HStack(spacing: 26) {
                    MediaControlButton(symbol: "backward.fill", size: 12, theme: theme) {
                        monitor.previous()
                    }
                    MediaControlButton(
                        symbol: media.isPlaying ? "pause.fill" : "play.fill",
                        size: 17,
                        theme: theme
                    ) {
                        monitor.togglePlayPause()
                    }
                    MediaControlButton(symbol: "forward.fill", size: 12, theme: theme) {
                        monitor.next()
                    }
                }
                .frame(maxWidth: .infinity)

                if let volume = monitor.systemVolume {
                    HStack(spacing: 9) {
                        Image(systemName: "speaker.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(theme.subtitleColor)
                        PremiumVolumeSlider(value: volume) { monitor.setVolume($0) }
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(theme.subtitleColor)
                    }
                }
            }
            .frame(width: Panel.rowWidth, alignment: .leading)
        }
    }

    private func progressBar(_ progress: MediaProgress) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let current = progress.current(now: context.date)
            let fraction = progress.duration > 0 ? current / progress.duration : 0
            VStack(spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.16))
                        Capsule()
                            .fill(theme.textColor)
                            .frame(width: max(3, geo.size.width * CGFloat(fraction)))
                    }
                }
                .frame(height: 3)
                HStack {
                    Text(timeText(current))
                    Spacer()
                    Text("-" + timeText(max(0, progress.duration - current)))
                }
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(theme.subtitleColor)
            }
        }
        .frame(height: 18)
    }

    private func timeText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    @ViewBuilder
    private func artwork(_ media: NowPlaying) -> some View {
        let size: CGFloat = 46
        Group {
            if let data = media.artwork, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 16))
                            .foregroundStyle(theme.subtitleColor)
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
    }
}

/// An iPhone-style volume slider: thin capsule track, white fill, and a knob
/// that grows under the pointer. Values apply on every drag tick — the
/// backing call is direct CoreAudio, so movement is instant.
private struct PremiumVolumeSlider: View {
    let value: Int
    let onChange: (Int) -> Void

    @State private var dragging = false
    @State private var hovering = false

    private var knobSize: CGFloat { dragging ? 17 : (hovering ? 14 : 11) }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let fraction = CGFloat(min(max(value, 0), 100)) / 100
            let knob = knobSize
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.18))
                    .frame(height: 4)
                Capsule(style: .continuous)
                    .fill(Color.white)
                    .frame(width: max(4, width * fraction), height: 4)
                Circle()
                    .fill(Color.white)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
                    .offset(x: min(max(width * fraction - knob / 2, 0), width - knob))
            }
            .frame(width: width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        dragging = true
                        let fraction = min(max(gesture.location.x / width, 0), 1)
                        onChange(Int((fraction * 100).rounded()))
                    }
                    .onEnded { _ in dragging = false }
            )
        }
        .frame(height: 20)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: knobSize)
    }
}

/// One round media control: a plain white symbol with a soft circular
/// highlight on hover, sized for an easy click target.
private struct MediaControlButton: View {
    let symbol: String
    let size: CGFloat
    let theme: Theme
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(theme.textColor)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.16 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
