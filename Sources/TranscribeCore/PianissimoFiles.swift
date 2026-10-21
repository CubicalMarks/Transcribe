import Foundation

// File sizes and LFS SHA-256 from the pinned Hugging Face tree, checked 2026-10-21.
extension PianissimoEngine {
    static let files: [ModelFile] = [
        .init(path: "Decoder.mlmodelc/analytics/coremldata.bin", size: 243, sha256: "71ee87b9dc76636c55797ae5ba569768bfd8d81f70760ff363380a20165faaaa"),
        .init(path: "Decoder.mlmodelc/coremldata.bin", size: 565, sha256: "44c777d0f545b07d86a2f9f764eadf3f2105930b3b9bef7a76c3a09707ec0e30"),
        .init(path: "Decoder.mlmodelc/metadata.json", size: 3429, sha256: nil),
        .init(path: "Decoder.mlmodelc/model.mil", size: 13110, sha256: nil),
        .init(path: "Decoder.mlmodelc/weights/weight.bin", size: 23604992, sha256: "9e34a5cc5da3477cf0e49126f55d4754a6a332b5df52a22812d6ddbd84af0e39"),
        .init(path: "Encoder.mlmodelc/analytics/coremldata.bin", size: 243, sha256: "5ba634cfa9d2dfe8068b1139802837fa150f6705f87626d723e155fb8e3d4868"),
        .init(path: "Encoder.mlmodelc/coremldata.bin", size: 500, sha256: "a3f2bc5cdb7fbe2490addfeab6b02d0df52c072841f5b7928d402e50278556a8"),
        .init(path: "Encoder.mlmodelc/metadata.json", size: 2937, sha256: nil),
        .init(path: "Encoder.mlmodelc/model.mil", size: 960233, sha256: nil),
        .init(path: "Encoder.mlmodelc/weights/weight.bin", size: 593445952, sha256: "adb71a2b3f7fea1c93f9f2906cd0176794388c5d635e17de4f65798bd3221af9"),
        .init(path: "JointDecisionv3.mlmodelc/analytics/coremldata.bin", size: 243, sha256: "68daea88123bb1bed958df781aed9b18829c4d29bf27db2a950ff98c03214890"),
        .init(path: "JointDecisionv3.mlmodelc/coremldata.bin", size: 597, sha256: "7497800778965aea71234f8fd329ec56279478fadc10bca5e028822d7ed31f21"),
        .init(path: "JointDecisionv3.mlmodelc/metadata.json", size: 3573, sha256: nil),
        .init(path: "JointDecisionv3.mlmodelc/model.mil", size: 11777, sha256: nil),
        .init(path: "JointDecisionv3.mlmodelc/weights/weight.bin", size: 12642764, sha256: "1f841daf3a6ce483ac136cd7a5e48d6071543e7c5eddcbba4525bda74695cb61"),
        .init(path: "Preprocessor.mlmodelc/analytics/coremldata.bin", size: 243, sha256: "c9beeb989c8d66f8be11df59bc6df277ec76cee404f6865b46243835ef562f6d"),
        .init(path: "Preprocessor.mlmodelc/coremldata.bin", size: 486, sha256: "dbde3f2300842c1fd51ef3ff948a0bcffe65ffd2dca10707f2509f32c1d65b1d"),
        .init(path: "Preprocessor.mlmodelc/metadata.json", size: 2841, sha256: nil),
        .init(path: "Preprocessor.mlmodelc/model.mil", size: 28181, sha256: nil),
        .init(path: "Preprocessor.mlmodelc/weights/weight.bin", size: 491072, sha256: "129b76e3aeafa8afa3ea76d995b964b145fe83700d579f6ff42c4c38fa0968ea"),
        .init(path: "README.md", size: 2164, sha256: nil),
        .init(path: "config.json", size: 513, sha256: nil),
        .init(path: "parakeet_vocab.json", size: 151122, sha256: nil),
    ]
}
