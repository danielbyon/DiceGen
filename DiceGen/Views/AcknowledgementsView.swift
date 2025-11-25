//
//  AcknowledgementsView.swift
//  DiceGen
//
//  Created by Daniel Byon on 3/31/20.
//  Copyright © 2020 Daniel Byon. All rights reserved.
//

import SwiftUI

struct AcknowledgementsView: View {

    private let items: [(title: String, url: URL)] = [
        ("Diceware algorithm & word lists", URL(string: "http://world.std.com/~reinhold/diceware.html")!),
        ("Catalan word list", URL(string: "https://github.com/1ma/diceware-cat")!),
        ("Chinese word list", URL(string: "https://github.com/cfbao/chinese-diceware")!),
        ("French word list", URL(string: "https://github.com/chmduquesne/diceware-fr")!),
        ("EFF word lists", URL(string: "https://www.eff.org/deeplinks/2016/07/new-wordlists-random-passphrases")!),
        ("Esperanto word list", URL(string: "https://esperantajxo.blogspot.com/2014/07/dajsvaro.html")!),
        ("Finnish word list", URL(string: "http://users.ics.aalto.fi/kaip/noppaware/")!),
        ("Hungarian word list", URL(string: "https://github.com/luczsoma/HungarianDiceware")!),
        ("Italian word list", URL(string: "https://www.taringamberini.com/it/diceware_it_IT/lista-di-parole-diceware-in-italiano/")!),
        ("Slovak word list", URL(string: "https://github.com/jtomori/diceware_slovak")!),
        ("Spanish word list", URL(string: "http://world.std.com/%7Ereinhold/diceware_en_espanolA.htm")!)
    ]

    var body: some View {
        List {
            ForEach(items, id: \.title) {
                SettingsLinkButton(title: $0.title, url: $0.url)
            }
        }
        .navigationBarTitle("Acknowledgements")
    }

}

struct AcknowledgementsView_Previews: PreviewProvider {
    static var previews: some View {
        AcknowledgementsView()
    }
}
