// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Transcribe",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Transcribe", targets: ["Transcribe"]),
        .executable(name: "transcribe-probe", targets: ["TranscribeProbe"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", exact: "1.1.1"),
        .package(url: "https://github.com/vapor/jwt-kit.git", from: "5.0.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", revision: "c79c4106b954f81205113c3343e5a7e59a1089b5", traits: []),
    ],
    targets: [
        .target(name: "TranscribeCore", dependencies: [
            .product(name: "JWTKit", package: "jwt-kit"),
            .product(name: "WhisperKit", package: "argmax-oss-swift"),
            .product(name: "SpeakerKit", package: "argmax-oss-swift"),
            .product(name: "FluidAudio", package: "FluidAudio"),
        ]),
        .executableTarget(name: "Transcribe", dependencies: ["TranscribeCore"]),
        .executableTarget(name: "TranscribeProbe", dependencies: ["TranscribeCore"]),
        .testTarget(name: "TranscribeCoreTests", dependencies: ["TranscribeCore"]),
        .testTarget(name: "TranscribeAppTests", dependencies: ["Transcribe"]),
    ]
)
