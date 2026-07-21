import SwiftUI
import AppKit
import HashNotchKit

/// Compact-live view: a music glyph and the track title in the slim strip.
struct MediaCompactView: View {
    @ObservedObject var monitor: MediaMonitor
    let theme: Theme

    var body: some View {
        if let media = monitor.nowPlaying {
            HStack(spacing: 6) {
                Image(systemName: media.isPlaying ? "music.note" : "pause.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.accent)
                Text(media.title)
                    .foregroundStyle(theme.textColor)
                    .lineLimit(1)
            }
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
                Image(systemName: media.isPlaying ? "play.fill" : "pause.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.subtitleColor)
            }
            .frame(width: 240, alignment: .leading)
        }
    }

    @ViewBuilder
    private func artwork(_ media: NowPlaying) -> some View {
        if let data = media.artwork, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.subtitleColor)
                )
        }
    }
}
