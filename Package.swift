// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TradeSync",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "TradeSync",
            path: "Sources/TradeSync",
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals")
            ]
        )
    ]
)
