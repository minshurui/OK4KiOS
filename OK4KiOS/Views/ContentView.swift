import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationView {
            List {
                NavigationLink("点播") { VodHomeView() }
                NavigationLink("直播") { LiveView() }
                NavigationLink("收藏与历史") { LibraryView() }
                NavigationLink("设置") { SettingsView() }
            }
            .navigationTitle("OK影视4K")
        }
        .navigationViewStyle(.stack)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
