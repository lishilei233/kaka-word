export class MockVisionProvider {
    async analyze(input) {
        return {
            imageWidth: input.imageWidth,
            imageHeight: input.imageHeight,
            objects: [
                {
                    id: "obj_01",
                    english: "mug",
                    chinese: "杯子",
                    ipa: "/mʌɡ/",
                    confidence: 0.96,
                    box: { x: 0.58, y: 0.43, width: 0.22, height: 0.28 },
                    anchor: { x: 0.69, y: 0.57 },
                    example: "This is a mug.",
                },
                {
                    id: "obj_02",
                    english: "book",
                    chinese: "书",
                    ipa: "/bʊk/",
                    confidence: 0.93,
                    box: { x: 0.12, y: 0.57, width: 0.30, height: 0.20 },
                    anchor: { x: 0.27, y: 0.67 },
                    example: "I am reading a book.",
                },
                {
                    id: "obj_03",
                    english: "plant",
                    chinese: "植物",
                    ipa: "/plænt/",
                    confidence: 0.91,
                    box: { x: 0.08, y: 0.12, width: 0.22, height: 0.34 },
                    anchor: { x: 0.19, y: 0.29 },
                    example: "The plant is green.",
                },
            ],
        };
    }
}
