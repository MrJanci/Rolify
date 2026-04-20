import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            Color(red: 0.071, green: 0.071, blue: 0.071).ignoresSafeArea()

            VStack(spacing: 12) {
                Text("Rolify")
                    .font(.system(size: 56, weight: .black, design: .default))
                    .foregroundStyle(Color(red: 0.118, green: 0.843, blue: 0.376))

                Text("v0.0.1-alpha · skeleton")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    ContentView().preferredColorScheme(.dark)
}
