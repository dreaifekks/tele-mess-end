import SwiftUI

struct SidebarView: View {
    @Binding var selection: AppSection
    var sections: [AppSection] = AppSection.allCases

    var body: some View {
        List(selection: $selection) {
            Section("Core") {
                ForEach(sections) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Tele Mess")
    }
}
