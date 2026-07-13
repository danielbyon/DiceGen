//
//  SettingsEmailButton.swift
//  DiceGen
//

import MessageUI
import SwiftUI

struct SettingsEmailButton: View {
    @State private var isShowingComposeEmail = false
    @State private var isShowingComposeError = false
    @State private var composeResult: Result<MFMailComposeResult, Error>?

    let title: String
    let emailAddress: String
    let subject: String

    var body: some View {
        Button(title) {
            if MFMailComposeViewController.canSendMail() {
                isShowingComposeEmail = true
            } else {
                isShowingComposeError = true
            }
        }
        .foregroundStyle(.primary)
        .sheet(isPresented: $isShowingComposeEmail) {
            MailComposeView(
                toRecipients: [emailAddress],
                subject: subject,
                isShowing: $isShowingComposeEmail,
                result: $composeResult
            )
        }
        .alert("Can't send email", isPresented: $isShowingComposeError) {
            Button("Dismiss", role: .cancel) {}
        } message: {
            Text("Please check your email settings and try again.")
        }
    }
}

struct SettingsEmailButton_Previews: PreviewProvider {
    static var previews: some View {
        SettingsEmailButton(title: "Report a bug", emailAddress: "bugreport@example.com", subject: "Hello world")
    }
}
