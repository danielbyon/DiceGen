//
//  SettingsView.swift
//  DiceGen
//
//  Created by Daniel Byon on 3/30/20.
//  Copyright © 2020 Daniel Byon. All rights reserved.
//

import SwiftUI

struct SettingsView: View {

    @Environment(\.presentationMode) var presentation
    @EnvironmentObject var historyStorage: HistoryStorage
    @EnvironmentObject var userSettings: UserSettings

    private let urls: [(title: String, url: URL)] = [
        ("Write a review", URL(string: "https://www.example.com")!),
        ("See more apps", URL(string: "https://www.example.com")!)
    ]

    private let emails: [(title: String, emailAddress: String, subject: String)] = [
        ("Report a bug", "bugreport@example.com", "DiceGen Bug Report" + Self.emailSubjectSuffix),
        ("Request a feature", "featurerequest@example.com", "DiceGen Feature Request" + Self.emailSubjectSuffix),
        ("General feedback", "contact@example.com", "DiceGen Feedback" + Self.emailSubjectSuffix)
    ]

    private static var emailSubjectSuffix: String {
        guard let version = DiceGenConstants.appVersion else {
            return ""
        }
        return ": v\(version)"
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $historyStorage.shouldSaveItems) {
                    Text("Save copied passphrases/passwords")
                }
                if !historyStorage.isEmpty {
                    Button(action: {
                        self.historyStorage.savedItems = []
                    }) {
                        Text("Clear passphrase/password history")
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
                NavigationLink(destination: TipJarView()) {
                    Text("Why are there no ads in this app?")
                }
                NavigationLink(destination: AcknowledgementsView()) {
                    Text("Acknowledgements")
                }
            }
        }
        .navigationBarTitle("Settings")
        .navigationBarItems(leading: Button(action: {
            self.presentation.wrappedValue.dismiss()
        }, label: {
            Text("Done")
                .bold()
                .padding([.trailing, .vertical])
        }))
    }

}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SettingsView()
                .environmentObject(HistoryStorage())
                .environmentObject(UserSettings())
        }
    }
}

struct AppInfo: View {

    private var buildInfo: String {
        var string = ""
        if let appName = DiceGenConstants.appName {
            string += appName
        }
        if let appVersion = DiceGenConstants.appVersion {
            string += " \(appVersion)"
        }
        if let buildVersion = DiceGenConstants.buildVersion {
            string += " (Build \(buildVersion))"
        }
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
