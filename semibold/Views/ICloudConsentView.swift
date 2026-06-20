import SwiftUI

/// First-launch prompt asking whether to sync documents through iCloud
/// (NO-002 §3.1/§5.1, `iOS_ICloudConsent` wireframe).
///
/// Placeholder for now — only stands in so `RootLaunchState`'s
/// show/hide branching has something concrete to present. The real
/// layout (☁ icon, title, body copy, "동기화 사용"/"나중에" buttons, dim
/// overlay) and the buttons' `sync_mode` + container wiring land in this
/// same feature brief's next acceptance-criteria items.
struct ICloudConsentView: View {
    var body: some View {
        Text("iCloud Consent Placeholder")
    }
}

#Preview {
    ICloudConsentView()
}
