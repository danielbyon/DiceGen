//
//  View+Centered.swift
//  DiceGen
//
//  Created by Daniel Byon on 3/30/20.
//  Copyright © 2020 Daniel Byon. All rights reserved.
//

import SwiftUI

extension View {

    func centered() -> some View {
        frame(minWidth: 0, maxWidth: .infinity, alignment: .center)
    }

}
