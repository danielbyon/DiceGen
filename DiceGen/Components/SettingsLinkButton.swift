//
//  SettingsLinkButton.swift
//  DiceGen
//
//  Created by Daniel Byon on 3/31/20.
//  Copyright © 2020 Daniel Byon. All rights reserved.
//

import SwiftUI

struct SettingsLinkButton: View {

    let title: String
    let url: URL

    var body: some View {
        Button(action: {
            UIApplication.shared.open(self.url)
        }) {
            Text(title)
                .foregroundColor(.primary)
        }
    }

}

struct SettingsButton_Previews: PreviewProvider {
    static var previews: some View {
        SettingsLinkButton(title: "Write a review", url: URL(string: "https://www.example.com")!)
    }
}
