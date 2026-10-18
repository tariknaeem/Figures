// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Figures",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "SheetCore", targets: ["SheetCore"]),
        .library(name: "SheetUI", targets: ["SheetUI"]),
        .executable(name: "Figures", targets: ["Figures"]),
    ],
    targets: [
        // Platform-independent spreadsheet engine: model, formulas, CSV and XLSX.
        .target(name: "SheetCore"),
        // SwiftUI views shared by the macOS and iOS apps.
        .target(name: "SheetUI", dependencies: ["SheetCore"]),
        // The app entry point, also compiled by the Xcode project in Apple/.
        .executableTarget(name: "Figures", dependencies: ["SheetUI"], path: "App"),
        // Engine checks; runs with the Command Line Tools, which lack XCTest.
        .executableTarget(name: "SheetCoreChecks", dependencies: ["SheetCore"]),
    ],
    swiftLanguageModes: [.v5]
)
