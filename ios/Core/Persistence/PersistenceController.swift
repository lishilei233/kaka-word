import Foundation
import SwiftData

enum PersistenceController {
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        let schema = Schema(versionedSchema: PictureWordSchemaV2.self)
        return try ModelContainer(
            for: schema,
            migrationPlan: PictureWordMigrationPlan.self,
            configurations: configuration
        )
    }
}
