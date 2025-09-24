//
//  Color.swift
//  Aura
//
//  Created by Mac Mini on 10/09/2025.
//

import SwiftUI

extension Color {
    // Brand Colors
    static let emerald = Color(red: 84/255, green: 187/255, blue: 116/255)
    static let eton = Color(red: 147/255, green: 207/255, blue: 162/255)
    static let charlestonGreen = Color(red: 23/255, green: 29/255, blue: 30/255)
    static let alabaster = Color(red: 243/255, green: 235/255, blue: 226/255)
    
    
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    static let darkRed = Color(hex: "ff0000")   // #8B0000
    static let darkGreen = Color(hex: "00ff00")  // #006400
    static let darkBlue = Color(hex: "0000ff")   // #00008B
    
    static let orange     = Color(hex: "FFA500")
    static let yellow     = Color(hex: "FFFF00")
    static let indigo     = Color(hex: "4B0082")
    static let purple     = Color(hex: "800080")
    static let pink       = Color(hex: "FFC0CB")

    static let darkGray = Color(red: 0.3, green: 0.3, blue: 0.3)
    static let darkBrown = Color(red: 0.4, green: 0.25, blue: 0.2)
    // UI Colors
    static let backgroundColor = Color.alabaster
    static let cardColor = Color.white
    static let primaryAccent = Color.emerald
    static let secondaryAccent = Color.eton
    
    static let verticalGradient = LinearGradient(
        gradient: Gradient(colors: [eton.opacity(0.4), emerald]),
        startPoint: .top,
        endPoint: .bottom
    )
    
    func toHex() -> String {
        let uiColor = UIColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 1
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02lX%02lX%02lX",
                      lroundf(Float(r * 255)),
                      lroundf(Float(g * 255)),
                      lroundf(Float(b * 255)))
    }
}

