//
//  SettingsEmailButton.swift
//  DiceGen
//
//  Created by Daniel Byon on 3/31/20.
//  Copyright © 2020 Daniel Byon. All rights reserved.
//

import SwiftUI
import MessageUI

struct SettingsEmailButton: View {

    @State private var isShowingComposeEmail = false
    @State private var isShowingComposeError = false
    @State private var composeResult: Result<MFMailComposeResult, Error>?

    let title: String
    let emailAddress: String
    let subject: String

    var body: some View {
        Button(action: {
            debugPrint("Opening \(self.title) URL")
            if MFMailComposeViewController.canSendMail() {
                self.isShowingComposeEmail.toggle()
            } else {
                self.isShowingComposeError.toggle()
            }
        }) {
            Text(title)
                .foregroundColor(.primary)
        }
        .sheet(isPresented: $isShowingComposeEmail) {
            MailComposeView(toRecipients: [self.emailAddress], subject: self.subject, isShowing: self.$isShowingComposeEmail, result: self.$composeResult)
        }
        .alert(isPresented: $isShowingComposeError) {
            Alert(title: Text("Can't send email"), message: Text("Please check your email settings and try again."), dismissButton: nil)
        }
    }

}

struct SettingsEmailButton_Previews: PreviewProvider {
    static var previews: some View {
        SettingsEmailButton(title: "Report a bug", emailAddress: "bugreport@example.com", subject: "Hello world")
    }
}
