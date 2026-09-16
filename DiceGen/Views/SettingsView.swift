//
//  SettingsView.swift
//  DiceGen
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var historyVault: HistoryVault

    private let urls: [(title: String, url: URL)] = [
        ("Write a review", URL(string: "itms-apps://itunes.apple.com/WebObjects/MZStore.woa/wa/viewContentsUserReviews?id=980521593&onlyLatestVersion=true&pageNumber=0&sortOrdering=1&type=Purple+Software ")!),
        ("See more apps", URL(string: "https://apps.apple.com/us/developer/daniel-byon/id309681721")!)
    ]

    private let emails: [(title: String, emailAddress: String, subject: String)] = [
        ("Report a bug", "bugreport@danielbyon.com", "DiceGen Bug Report" + Self.emailSubjectSuffix),
        ("Request a feature", "featurerequest@danielbyon.com", "DiceGen Feature Request" + Self.emailSubjectSuffix),
        ("General feedback", "contact@danielbyon.com", "DiceGen Feedback" + Self.emailSubjectSuffix)
    ]

    private static var emailSubjectSuffix: String {
        guard let version = DiceGenConstants.appVersion else { return "" }
        return ": v\(version)"
    }

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    HistorySettingsView()
                } label: {
                    HStack {
                        Text("History")
                        Spacer()
                        Text(historyStatus)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                ForEach(emails, id: \.title) {
                    SettingsEmailButton(title: $0.title, emailAddress: $0.emailAddress, subject: $0.subject)
                }
            }
            Section {
                ForEach(urls, id: \.title) {
                    SettingsLinkButton(title: $0.title, url: $0.url)
                }
            }
            Section(footer: AppInfo()) {
                NavigationLink("Why are there no ads in this app?") {
                    TipJarView()
                }
                NavigationLink("Acknowledgements") {
                    AcknowledgementsView()
                }
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
                .bold()
            }
        }
    }

    private var historyStatus: String {
        switch historyVault.state {
        case .disabled:
            return "Off"
        case .setupRequired:
            return "Setup Required"
        case .locked, .unlocked:
            return "On"
        case .initializing:
            return "Setup Required"
        case .failed:
            return "Needs Reset"
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            SettingsView()
        }
        .environmentObject(TipStore(client: StoreKitClient(), startTransactionListener: false))
        .environmentObject(HistoryVault.preview())
    }
}

struct AppInfo: View {
    private var buildInfo: String {
        var string = ""
        if let appName = DiceGenConstants.appName { string += appName }
        if let appVersion = DiceGenConstants.appVersion { string += " \(appVersion)" }
        if let buildVersion = DiceGenConstants.buildVersion { string += " (Build \(buildVersion))" }
        return string
    }

    private var copyright: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return "Copyright © \(formatter.string(from: Date())) Daniel Byon"
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text(buildInfo)
            Text(copyright)
        }
    }
}
