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
        let size: CGFloat = 22
        if let data = media.artwork, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.white.opacity(0.12))
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(theme.subtitleColor)
                )
        }
    }
}

/// Trailing compact-live: the track title to the right of the notch, with a
/// small animated playing indicator.
struct MediaTitleView: View {
    @ObservedObject var monitor: MediaMonitor
    let theme: Theme

    var body: some View {
        if let media = monitor.nowPlaying {
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(theme.accent)
                    .symbolEffect(.variableColor.iterative, isActive: media.isPlaying)
                Text(media.title)
                    .foregroundStyle(theme.textColor)
                    .lineLimit(1)
            }
            .frame(maxWidth: 150, alignment: .leading)
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
            HStack(spacing: 10) {
                artwork(media)
                VStack(alignment: .leading, spacing: 2) {
                    Text(media.title)
                        .foregroundStyle(theme.textColor)
                        .lineLimit(1)
                    if let artist = media.artist {
                        Text(artist)
                            .font(.system(size: 9))
                            .foregroundStyle(theme.subtitleColor)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "waveform")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.accent)
                    .symbolEffect(.variableColor.iterative, isActive: media.isPlaying)
            }
            .frame(width: Panel.rowWidth, alignment: .leading)
        }
    }

    @ViewBuilder
    private func artwork(_ media: NowPlaying) -> some View {
        if let data = media.artwork, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .frame(width: 38, height: 38)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.subtitleColor)
                )
        }
    }
}
