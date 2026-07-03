import SwiftUI

struct SidebarView: View {
    @Binding var selection: AppSection

    var body: some View {
        List(selection: $selection) {
            Section("Core") {
                ForEach(AppSection.allCases) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Tele Mess")
    }
}
