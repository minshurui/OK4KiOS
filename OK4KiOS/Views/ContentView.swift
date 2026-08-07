import SwiftUI

struct ContentView: View {
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            NavigationView { VodHomeView() }
                .navigationViewStyle(.stack)
                .tabItem { Label("点播", systemImage: "film.fill") }
                .tag(0)

            NavigationView { LiveView() }
                .navigationViewStyle(.stack)
                .tabItem { Label("直播", systemImage: "play.tv.fill") }
                .tag(1)

            NavigationView { LibraryView() }
                .navigationViewStyle(.stack)
                .tabItem { Label("收藏", systemImage: "heart.fill") }
                .tag(2)

            NavigationView { SettingsView() }
                .navigationViewStyle(.stack)
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
                .tag(3)
        }
        .accentColor(OKTheme.accent)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}
