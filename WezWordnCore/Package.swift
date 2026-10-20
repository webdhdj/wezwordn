// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WezWordnCore",
    products: [
        .library(name: "ExtendedLoginFields", targets: ["ExtendedLoginFields"]),
        .library(name: "LocalTOTP", targets: ["LocalTOTP"]),
        .library(name: "LocalEncryptedStorage", targets: ["LocalEncryptedStorage"]),
        .library(name: "VaultHealth", targets: ["VaultHealth"]),
        .library(name: "HIBPClient", targets: ["HIBPClient"]),
        .library(name: "EmergencyRecovery", targets: ["EmergencyRecovery"]),
        .library(name: "SecureSharing", targets: ["SecureSharing"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0")
    ],
    targets: [
        .target(name: "ExtendedLoginFields"),
        .target(name: "LocalTOTP", dependencies: [.product(name: "Crypto", package: "swift-crypto")]),
        .target(name: "LocalEncryptedStorage", dependencies: [.product(name: "Crypto", package: "swift-crypto")]),
        .target(name: "VaultHealth"),
        .target(name: "HIBPClient", dependencies: [.product(name: "Crypto", package: "swift-crypto")]),
        .target(name: "EmergencyRecovery", dependencies: [.product(name: "Crypto", package: "swift-crypto")]),
        .target(name: "SecureSharing", dependencies: [.product(name: "Crypto", package: "swift-crypto")]),
        .testTarget(name: "ExtendedLoginFieldsTests", dependencies: ["ExtendedLoginFields"]),
        .testTarget(name: "LocalTOTPTests", dependencies: ["LocalTOTP"]),
        .testTarget(name: "LocalEncryptedStorageTests", dependencies: ["LocalEncryptedStorage"]),
        .testTarget(name: "VaultHealthTests", dependencies: ["VaultHealth"]),
        .testTarget(name: "HIBPClientTests", dependencies: ["HIBPClient"]),
        .testTarget(name: "EmergencyRecoveryTests", dependencies: ["EmergencyRecovery"]),
        .testTarget(name: "SecureSharingTests", dependencies: ["SecureSharing"]),
    ]
)
