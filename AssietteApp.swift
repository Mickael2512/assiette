import SwiftUI

@main
struct AssietteApp: App {
    @State private var store = Store()
    var body: some Scene {
        WindowGroup { RootView().environment(store).tint(.green) }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            TodayView().tabItem { Label("Aujourd’hui", systemImage: "chart.pie.fill") }
            RecipesView().tabItem { Label("Recettes", systemImage: "book.closed.fill") }
            HistoryView().tabItem { Label("Historique", systemImage: "clock.fill") }
            SettingsView().tabItem { Label("Réglages", systemImage: "gearshape.fill") }
        }
    }
}
