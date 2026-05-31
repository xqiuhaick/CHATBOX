import SwiftUI

struct WebSearchGlobeIcon: View {
    var body: some View {
        Image("WebSearchGlobe")
            .resizable()
            .scaledToFit()
    }
}

struct DrawIcon: View {
    var body: some View {
        Image("DrawIcon")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
    }
}
