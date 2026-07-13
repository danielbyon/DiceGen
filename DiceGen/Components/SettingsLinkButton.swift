//
//  SettingsLinkButton.swift
//  DiceGen
//

import SwiftUI

struct SettingsLinkButton: View {
    @Environment(\.openURL) private var openURL

    let title: String
    let url: URL

    var body: some View {
        Button(title) {
            openURL(url)
        }
        .foregroundStyle(.primary)
    }
}

struct SettingsButton_Previews: PreviewProvider {
    static var previews: some View {
        SettingsLinkButton(title: "Write a review", url: URL(string: "https://www.example.com")!)
    }
}
