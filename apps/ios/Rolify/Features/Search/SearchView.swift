import SwiftUI

/// Search-Tab — Placeholder fuer jetzt, echte Impl in Chunk 6.
struct SearchView: View {
    @State private var query = ""

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()

            VStack(spacing: DS.l) {
                Spacer().frame(height: 40)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 48, weight: .regular))
                    .foregroundStyle(DS.textSecondary)
                Text("Search")
                    .font(DS.Font.headline)
                    .foregroundStyle(DS.textPrimary)
                Text("Kommt in Chunk 6")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.textSecondary)
                Spacer()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Text("Suche")
                    .font(DS.Font.headline)
                    .foregroundStyle(DS.textPrimary)
            }
        }
    }
}
