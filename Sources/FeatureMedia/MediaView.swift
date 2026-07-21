import SwiftUI
import AppKit
import HashNotchKit

/// Leading compact-live: album artwork to the left of the notch.
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
                MarqueeText(media.title)
                    .foregroundStyle(theme.textColor)
                AudioBarsView(isActive: media.isPlaying, tint: theme.accent)
            }
            .frame(maxWidth: 158, alignment: .leading)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
}

/// Expanded detail: artwork, title, artist, and play state.
struct MediaDetailView: View {
    @ObservedObject var monitor: MediaMonitor
    let theme: Theme

    var body: some View {
        if let media = monitor.nowPlaying {
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
            .frame(width: Panel.rowWidth, alignment: .leading)
        }
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
