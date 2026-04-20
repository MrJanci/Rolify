import SwiftUI

struct SectionHeader: View {
    let title: String
    var showMore: Bool = false
    var onMore: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(DS.textPrimary)
            Spacer()
            if showMore, let onMore {
                Button(action: onMore) {
                    Text("Alle")
                        .font(DS.Font.footnote)
                        .foregroundStyle(DS.textSecondary)
                }
            }
        }
        .padding(.horizontal, DS.xl)
        .padding(.top, DS.l)
        .padding(.bottom, DS.s)
    }
}
