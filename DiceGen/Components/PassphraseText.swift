//
//  PassphraseText.swift
//  DiceGen
//
//  Created by Daniel Byon on 4/4/20.
//  Copyright © 2020 Daniel Byon. All rights reserved.
//

import SwiftUI

struct PassphraseText: View {

    let text: String

    var body: some View {
        HStack(spacing: 0) {
            Text(text)
                .font(.system(.title, design: .monospaced))
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(.vertical)
    }

}

struct PassphraseText_Previews: PreviewProvider {
    static var previews: some View {
        PassphraseText(text: "correct battery horse staple")
    }
}
