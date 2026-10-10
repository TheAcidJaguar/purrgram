// DesktopCat — breeds/coats and moods.

import Cocoa

// MARK: - Coats

struct Coat {
    let name: String
    let fur, dark, light, outline, eye, inner, nose: NSColor
    var stripes = false, chest = false, whitePaws = false, points = false
    // breed shape traits
    var size: CGFloat = 1            // overall size
    var fluff = false                // shaggy tufted outline, lynx ear tips
    var headMul: CGFloat = 1         // head size (rounder faces)
    var earMul: CGFloat = 1          // ear height
    var bodyMul: CGFloat = 1         // body thickness
    var tailMul: CGFloat = 1         // tail thickness
    var spots = false                // rosettes
    var wrinkles = false             // hairless forehead folds
    var wedge = false                // wedge-shaped head: high cheekbones, narrow chin, big flared bat ears (Sphynx)
}

let coats: [Coat] = [
    Coat(name: "Slate", fur: rgb(0x5C6178), dark: rgb(0x474B5F), light: rgb(0x70758E), outline: rgb(0x15151C),
         eye: rgb(0x0F0F14), inner: rgb(0x8E93AE), nose: rgb(0x2A2A35)),
    Coat(name: "Charcoal", fur: rgb(0x5E5E5E), dark: rgb(0x474747), light: rgb(0x707070), outline: rgb(0x0E0E0E),
         eye: rgb(0x0E0E0E), inner: rgb(0x8C8C8C), nose: rgb(0x303030)),
    Coat(name: "Siamese", fur: rgb(0xEADFCC), dark: rgb(0x58392D), light: rgb(0xF8F2E7), outline: rgb(0x2A1C16),
         eye: rgb(0x3A86E0), inner: rgb(0xC9A294), nose: rgb(0x24140F), points: true),
    Coat(name: "Tan Tabby", fur: rgb(0xC9A08E), dark: rgb(0xA97F6E), light: rgb(0xE2C3B4), outline: rgb(0x3A2A24),
         eye: rgb(0x2A1E1A), inner: rgb(0xE8B0B0), nose: rgb(0xFF8C9A), stripes: true),
    Coat(name: "Orange Tabby", fur: rgb(0xF0A050), dark: rgb(0xC97830), light: rgb(0xFFD8A8), outline: rgb(0x3A2210),
         eye: rgb(0x2A1A0E), inner: rgb(0xF6B3B0), nose: rgb(0xF48C8C), stripes: true),
    Coat(name: "Midnight", fur: rgb(0x2E2E36), dark: rgb(0x1C1C22), light: rgb(0x40404A), outline: rgb(0x08080A),
         eye: rgb(0xF2C94C), inner: rgb(0x6A5060), nose: rgb(0x6A5060)),
    Coat(name: "Tuxedo", fur: rgb(0x2E2E36), dark: rgb(0x1C1C22), light: rgb(0xF4F4F4), outline: rgb(0x08080A),
         eye: rgb(0xB7E36A), inner: rgb(0xD9A0A8), nose: rgb(0xE59AA5), chest: true, whitePaws: true),
    Coat(name: "Cream", fur: rgb(0xF2E2C8), dark: rgb(0xDCC29A), light: rgb(0xFFF6E8), outline: rgb(0x4A3A28),
         eye: rgb(0x2A1E1A), inner: rgb(0xF4B6B4), nose: rgb(0xF48C8C), stripes: true),
    Coat(name: "Maine Coon", fur: rgb(0x8C6A4C), dark: rgb(0x4A3322), light: rgb(0xDCC5A8), outline: rgb(0x24180E),
         eye: rgb(0x2A2210), inner: rgb(0xD9A69A), nose: rgb(0x8A4A3E), stripes: true,
         size: 1.13, fluff: true, headMul: 1.04, earMul: 1.12, bodyMul: 1.12, tailMul: 1.6),
    Coat(name: "British Shorthair", fur: rgb(0x8E99A8), dark: rgb(0x6F7988), light: rgb(0xAAB3C0), outline: rgb(0x1F232A),
         eye: rgb(0xE08A1E), inner: rgb(0xB9A3AE), nose: rgb(0x56606E),
         size: 1.02, headMul: 1.12, earMul: 0.72, bodyMul: 1.15, tailMul: 1.2),
    Coat(name: "Bengal", fur: rgb(0xD9A04E), dark: rgb(0x5E3818), light: rgb(0xF3DCAE), outline: rgb(0x2C1A0C),
         eye: rgb(0x1E2A10), inner: rgb(0xE3A18A), nose: rgb(0xB5604A),
         earMul: 0.95, bodyMul: 0.95, spots: true),
    Coat(name: "Sphynx", fur: rgb(0xE9C4B2), dark: rgb(0xC69886), light: rgb(0xF4DBCD), outline: rgb(0x4A2E26),
         eye: rgb(0x2A2A10), inner: rgb(0xF0A39C), nose: rgb(0xD98C80),
         headMul: 0.96, earMul: 1.75, bodyMul: 0.88, tailMul: 0.6, wrinkles: true, wedge: true),
]

// MARK: - Personality

/// Each cat gets a temperament that tilts how often it does things.
enum Personality: Int, CaseIterable {
    case playful, lazy, clingy, skittish, curious
    var name: String { ["Playful", "Lazy", "Clingy", "Skittish", "Curious"][rawValue] }
    var blurb: String {
        ["Zoomies, pounces, and never says no to yarn", "Loafs and naps more than anything",
         "Follows you around and loves pets", "Easily startled and loves to hide",
         "Explores and climbs everything"][rawValue]
    }
}
