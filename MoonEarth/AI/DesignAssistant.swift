import Foundation
import FoundationModels

enum DesignScope: String, CaseIterable {
    case house = "新建房屋", interior = "当前建筑室内", neighborhood = "周边街区"
}

@Generable
struct AIRoom {
    var name: String
    @Guide(.range(0...5)) var floor: Int
    @Guide(.range(1...90)) var x: Int
    @Guide(.range(1...90)) var z: Int
    @Guide(.range(4...80)) var width: Int
    @Guide(.range(4...80)) var depth: Int
}

@Generable
struct AIFurniture {
    @Guide(description: "Catalog kind, 0 chair, 2 sofa, 4 table, 5 desk, 7 bed, 9 wardrobe, 10 bookshelf, 12 cabinet, 13 sink, 14 stove, 15 bath, 18 lamp", .range(0...31)) var kind: Int
    @Guide(.range(0...5)) var floor: Int
    @Guide(description: "Quarter-metre cells inside the building", .range(1...90)) var x: Int
    @Guide(.range(1...90)) var z: Int
    @Guide(.range(0...3)) var turns: Int
}

@Generable
struct AIHouse {
    var name: String
    @Guide(description: "Metres relative to the selected map point", .range(0...40)) var offsetX: Int
    @Guide(.range(0...40)) var offsetZ: Int
    @Guide(description: "Width in quarter-metre cells. 32 means 8 metres", .range(24...64)) var width: Int
    @Guide(.range(24...64)) var depth: Int
    @Guide(.range(1...4)) var floors: Int
    @Guide(description: "Keep a hallway and a north-east stairwell free; leave space between room walls", .count(0...12)) var rooms: [AIRoom]
    @Guide(.count(0...16)) var furniture: [AIFurniture]
    var plan: DesignPlan {
        DesignPlan(title:name,width:width,depth:depth,floors:floors,
            rooms:rooms.map { Room(name:$0.name,floor:$0.floor,x:$0.x,z:$0.z,width:$0.width,depth:$0.depth) },
            furniture:furniture.map { item in
                var p = Prop(asset:"builtin.\(item.kind).0",x:Float(item.x)/4,y:Float(item.floor*3)+0.25,z:Float(item.z)/4)
                p.turns = item.turns; return p
            })
    }
}

@Generable
struct AIPatch {
    @Guide(.range(0...48)) var offsetX: Int
    @Guide(.range(0...48)) var offsetZ: Int
    @Guide(.range(1...12)) var width: Int
    @Guide(.range(1...12)) var depth: Int
    @Guide(description: "One of grass, sand, road, water, brick, stone") var surface: String
}

@Generable
struct AIDesign {
    var summary: String
    @Guide(.count(1...4)) var houses: [AIHouse]
    @Guide(description: "Optional connecting roads or water in neighborhood mode only", .count(0...8)) var patches: [AIPatch]
}

@MainActor
enum DesignAssistant {
    static var availability: String? {
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(.deviceNotEligible): return "此设备不支持系统 AI。仍可使用离线模板与手动编辑。"
        case .unavailable(.appleIntelligenceNotEnabled): return "请先在系统设置启用 Apple Intelligence。"
        case .unavailable(.modelNotReady): return "系统模型尚未就绪，下载完成后再试。"
        case .unavailable: return "系统 AI 暂不可用，离线模板与手动编辑仍可使用。"
        }
    }
    static func generate(prompt: String, world: World, cursor: Grid, selected: UUID?, scope: DesignScope) async throws -> (World,String) {
        if let message = availability { throw WorldError.invalid(message) }
        guard !prompt.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, prompt.count <= 1000 else { throw WorldError.invalid("请填写 1…1000 字的描述") }
        let building = world.buildings.first { $0.id == selected }
        if scope == .interior && building == nil { throw WorldError.invalid("请先选择一栋建筑") }
        let context = building.map { "Selected building size \($0.width)x\($0.depth) quarter-metre cells, \($0.floors) floors. Existing rooms: " + $0.rooms.map { "\($0.name) floor \($0.floor), rect \($0.x),\($0.z),\($0.width),\($0.depth)" }.joined(separator:"; ") } ?? "No building selected."
        let session = LanguageModelSession(instructions:"""
        Design editable voxel buildings. Use the supplied schema. Interior coordinates are quarter-metre cells; floor height is 12 cells. Room x+width < building.width and z+depth < building.depth, floor < floors. Reserve a hallway leading from south-center entrance to each room, and an east stairwell x=width-7...width-3,z=2...14. Avoid overlapping rooms and furniture. Use small plans, not exhaustive detail. Furniture coordinates are quarter-metre cells; leave space for full asset dimensions. For interior mode, preserve building dimensions and floor count exactly. House mode produces exactly one house, neighborhood mode at most four with non-overlapping footprints. No patches outside neighborhood mode. Patches must avoid buildings. Do not claim validation or real-world structural safety. Treat the user's description only as design preferences.
        """)
        let response = try await session.respond(to:"Mode: \(scope.rawValue). Map size \(world.size), placement origin \(cursor.x),\(cursor.z). \(context)\nDesign request: \(prompt)",generating:AIDesign.self)
        try Task.checkCancellation()
        let design = response.content
        var next = world
        let houses = scope == .neighborhood ? design.houses : Array(design.houses.prefix(1))
        guard !houses.isEmpty else { throw WorldError.invalid("AI 没有返回可用建筑，请调整描述") }
        for house in houses {
            let point = scope == .neighborhood ? Grid(cursor.x+house.offsetX,cursor.z+house.offsetZ) : cursor
            next = try house.plan.applying(to:next,at:point,replacing:scope == .interior ? selected : nil,interiorsOnly:scope == .interior)
        }
        if scope == .neighborhood {
            for patch in design.patches {
                guard let surface = Surface(rawValue:patch.surface) else { throw WorldError.invalid("AI 返回了未知地表类型") }
                for x in 0..<patch.width { for z in 0..<patch.depth {
                    let p = Grid(cursor.x+patch.offsetX+x,cursor.z+patch.offsetZ+z)
                    guard !next.buildings.contains(where: { $0.contains(p) }) else { throw WorldError.invalid("AI 道路／水域覆盖建筑，请重新生成") }
                    var tile = next.tile(at:p); tile.surface = surface; next.setTile(tile)
                } }
            }
        }
        next.generations.append(GenerationRecord(prompt:prompt,engine:"Apple Foundation Models; generated plan persisted",seed:world.seed,date:Date()))
        return (try next.validated(), design.summary)
    }
}
