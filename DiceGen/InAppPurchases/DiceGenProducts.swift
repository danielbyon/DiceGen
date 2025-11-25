//
//  DiceGenProduct.swift
//  DiceGen
//
//  Created by Daniel Byon on 4/3/20.
//  Copyright © 2020 Daniel Byon. All rights reserved.
//

import Foundation

struct DiceGenProduct {

    static let smallTip: ProductIdentifier = "smallTip"
    static let mediumTip: ProductIdentifier = "mediumTip"
    static let largeTip: ProductIdentifier = "largeTip"

    static let allProducts: Set<ProductIdentifier> = [
        smallTip,
        mediumTip,
        largeTip
    ]

    static let store = StoreClient(productIdentifiers: allProducts)

}
