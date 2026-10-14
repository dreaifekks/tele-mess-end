import SwiftUI

/// Keep the list and inspector inside the available content width.
struct AdaptiveDetailLayout<ListContent: View, Detail: View>: View {
    var hasDetail: Bool
    @ViewBuilder var list: () -> ListContent
    @ViewBuilder var detail: () -> Detail

    var body: some View {
        GeometryReader { proxy in
            if !hasDetail {
                list()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if proxy.size.width >= 1100 {
                HSplitView {
                    list().frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                    detail().frame(width: 400)
                }
            } else {
                VSplitView {
                    list().frame(minWidth: 0, maxWidth: .infinity, minHeight: 140, maxHeight: .infinity)
                    detail().frame(maxWidth: .infinity, minHeight: 180, maxHeight: .infinity)
                }
            }
        }
    }
}
