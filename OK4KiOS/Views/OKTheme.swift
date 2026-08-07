import SwiftUI

enum OKTheme {
    static let accent = Color(red: 0.94, green: 0.16, blue: 0.23)
    static let background = Color(uiColor: .systemBackground)
    static let card = Color(uiColor: .secondarySystemBackground)
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 44)).foregroundColor(OKTheme.accent)
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .padding(28)
    }
}

struct PosterPlaceholder: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.gray.opacity(0.22), Color.gray.opacity(0.08)], startPoint: .top, endPoint: .bottom)
            Image(systemName: "film.fill").font(.largeTitle).foregroundColor(.secondary)
        }
    }
}
