// swift-tools-version: 6.0
// ─────────────────────────────────────────────────────────────────────────────
// InkyMLX — modèles de langage locaux (Mistral, Llama, Qwen, Gemma, Phi…) via
// MLX, le moteur d'apprentissage automatique d'Apple pour Apple Silicon.
//
// Pourquoi un package séparé d'InkyKit ? MLX compile des « shaders » Metal (le
// code qui tourne sur le GPU) : il faut Xcode (`xcodebuild`), `swift test` ne
// suffit pas. En l'isolant ici, les tests d'InkyKit restent simples à lancer.
// ─────────────────────────────────────────────────────────────────────────────
import PackageDescription

let package = Package(
    name: "InkyMLX",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "InkyMLX", targets: ["InkyMLX"]),
    ],
    dependencies: [
        .package(path: "../InkyKit"),
        // Modèles de langage sur MLX (Apple, licence MIT).
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMinor(from: "3.32.3")),
        // Tokenizers des modèles Hugging Face (licence Apache 2.0).
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
    ],
    targets: [
        .target(name: "InkyMLX", dependencies: [
            .product(name: "InkyCore", package: "InkyKit"),
            .product(name: "MLXLLM", package: "mlx-swift-lm"),
            .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            .product(name: "Tokenizers", package: "swift-transformers"),
        ]),
    ]
)
