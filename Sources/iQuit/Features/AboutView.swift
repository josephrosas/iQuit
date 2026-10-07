import AppKit
import SwiftUI

struct AboutView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                BrandLogo(size: 64, shadowed: true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("iQuit")
                        .font(.title2.weight(.semibold))
                    Text("A fresh start without a restart")
                        .font(.callout)
                        .foregroundStyle(iQuitTheme.muted)
                }
            }

            LabeledContent("Version", value: appModel.versionText)
            LabeledContent("Control", value: "Menu bar, Shortcuts, or iquit://")

            Text("iQuit will not quit Finder, Dock, or other protected system processes. Some background apps may relaunch themselves. Force quit skips save prompts.")
                .font(.caption)
                .foregroundStyle(iQuitTheme.muted)

            Spacer(minLength: 0)

            R6Footer(showsProductName: false)
        }
        .padding(28)
        .frame(width: 420, height: 320, alignment: .topLeading)
        .background(iQuitTheme.page)
        .preferredColorScheme(appModel.appearance.colorScheme)
        .onAppear {
            BrandAppearance.applyAppIcon()
        }
    }
}
