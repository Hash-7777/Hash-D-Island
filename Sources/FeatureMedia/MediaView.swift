import SwiftUI
import AppKit
import HashNotchKit

/// Leading compact-live: album artwork to the left of the notch.
/// The compact strip shows only while audio is actually playing.
struct MediaArtworkView: View {
    @ObservedObject var monitor: MediaMonitor
    let theme: Theme

    var body: some View {
        if let media = monitor.nowPlaying, media.isPlaying {
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
        if let media = monitor.nowPlaying, media.isPlaying {
            HStack(spacing: 7) {
                MarqueeText(media.title)
                    .foregroundStyle(theme.textColor)
                AudioBarsView(isActive: media.isPlaying, tint: theme.accent)
            }
            .frame(maxWidth: 158, alignment: .leading)
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

                if media.source != .other {
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
