import Foundation

protocol DeepTutorToolLookup: Sendable {
    func tool(named name: String) -> (any DeepTutorTool)?
}

