import SwiftUI

struct SettingsView: View {
    @State private var isDark = true
    @State private var isRegionVisible = false

    var body: some View {
        VStack(spacing: 32) {
            Toggle(isOn: $isDark) {
                EmptyView()
            }
            .labelsHidden()

            Toggle(isOn: $isRegionVisible) {
                EmptyView()
            }
            .labelsHidden()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())

    }
}
