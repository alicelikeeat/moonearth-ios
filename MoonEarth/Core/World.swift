import Foundation

public struct Grid: Codable, Hashable, Sendable {
    public var x: Int
    public var z: Int
    public init(_ x: Int, _ z: Int) { self.x = x; self.z = z }
    public var neighbors: [Grid] { [Grid(x-1,z), Grid(x+1,z), Grid(x,z-1), Grid(x,z+1)] }
}

public enum Surface: String, Codable, CaseIterable, Sendable {
    case grass, earth, sand, stone, snow, road, water, brick
    public var name: String {
        switch self {
        case .grass: "草地"; case .earth: "泥土"; case .sand: "沙地"; case .stone: "岩石"
        case .snow: "雪地"; case .road: "道路"; case .water: "水域"; case .brick: "砖地"
        }
    }
    public var color: UInt32 {
        switch self {
        case .grass: 0x8CA96C; case .earth: 0x977255; case .sand: 0xDDCBA3; case .stone: 0x929997
        case .snow: 0xEEF0EB; case .road: 0x637077; case .water: 0x69ADB8; case .brick: 0xBA8F74
        }
    }
}

public struct Tile: Codable, Equatable, Sendable {
    public var position: Grid
    public var height: Int
    public var surface: Surface
    public init(_ position: Grid, height: Int = 0, surface: Surface = .grass) {
        self.position = position; self.height = height; self.surface = surface
    }
}

public struct Room: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var floor: Int
    /// All interior dimensions use quarter-metre cells, never terrain cells.
    public var x: Int
    public var z: Int
    public var width: Int
    public var depth: Int
    public init(name: String, floor: Int = 0, x: Int, z: Int, width: Int, depth: Int) {
        self.name = name; self.floor = floor; self.x = x; self.z = z
        self.width = width; self.depth = depth
    }
    public var squareMetres: Double { Double(width * depth) / 16 }
}

public struct Prop: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var asset: String
    public var x: Float
    public var y: Float
    public var z: Float
    public var turns: Int = 0
    public var locked = false
    public init(asset: String, x: Float, y: Float = 0, z: Float) {
        self.asset = asset; self.x = x; self.y = y; self.z = z
    }
}

public struct VoxelEdit: Codable, Equatable, Sendable {
    public var x: Int
    public var y: Int
    public var z: Int
    /// nil carves an opening. Values index the shared voxel palette.
    public var material: Int?
    public init(x: Int, y: Int, z: Int, material: Int?) {
        self.x = x; self.y = y; self.z = z; self.material = material
    }
}

public struct Building: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String = "新房屋"
    public var origin: Grid
    public var elevation: Int = 1
    public var width: Int = 32
    public var depth: Int = 32
    public var floors: Int = 2
    public var turns: Int = 0
    public var locked = false
    public var rooms: [Room] = []
    public var furniture: [Prop] = []
    public var edits: [VoxelEdit] = []
    public init(origin: Grid) { self.origin = origin }
    public var footprint: (width: Int, depth: Int) {
        let w = (width + 3) / 4, d = (depth + 3) / 4
        return turns % 2 == 0 ? (w, d) : (d, w)
    }
    public func contains(_ p: Grid) -> Bool {
        let f = footprint
        return p.x >= origin.x && p.z >= origin.z && p.x < origin.x + f.width && p.z < origin.z + f.depth
    }
    /// Positive rotations around Y, translated so origin remains the minimum corner.
    public func worldPoint(x: Float, y: Float, z: Float) -> SIMD3<Float> {
        let w = Float(width) / 4, d = Float(depth) / 4
        let q: SIMD3<Float>
        switch turns {
        case 1: q = [z, y, w-x]
        case 2: q = [w-x, y, d-z]
        case 3: q = [d-z, y, x]
        default: q = [x, y, z]
        }
        return q + SIMD3(Float(origin.x), Float(elevation), Float(origin.z))
    }
    public func localPoint(_ p: SIMD3<Float>) -> SIMD3<Float> {
        let v = p - SIMD3(Float(origin.x), Float(elevation), Float(origin.z))
        let w = Float(width)/4, d = Float(depth)/4
        switch turns {
        case 1: return [w-v.z, v.y, v.x]
        case 2: return [w-v.x, v.y, d-v.z]
        case 3: return [v.z, v.y, d-v.x]
        default: return v
        }
    }
}

public struct GenerationRecord: Codable, Equatable, Sendable {
    public var prompt: String
    public var engine: String
    public var seed: UInt64
    public var date: Date
}

public struct World: Codable, Equatable, Identifiable, Sendable {
    public var version = 1
    public var id = UUID()
    public var name = "未命名世界"
    public var size = 128
    public var seed: UInt64 = 42
    public var tiles: [Tile] = []
    public var buildings: [Building] = []
    public var props: [Prop] = []
    public var generations: [GenerationRecord] = []
    /// Opaque extension bytes survive an unmodified import/export round trip.
    public var extensions: [String: Data] = [:]
    public init() {}
    public func contains(_ p: Grid) -> Bool { p.x >= 0 && p.z >= 0 && p.x < size && p.z < size }
    public func tile(at p: Grid) -> Tile { tiles.first { $0.position == p } ?? Tile(p) }
    public mutating func setTile(_ tile: Tile) {
        if let i = tiles.firstIndex(where: { $0.position == tile.position }) { tiles[i] = tile }
        else { tiles.append(tile) }
    }
    public func validated() throws -> World {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw WorldError.invalid(message) }
        }
        try require(version == 1, "不支持的地图版本：\(version)")
        try require((16...512).contains(size), "地图尺寸必须为 16…512")
        try require(name.count <= 100, "项目名称过长")
        try require(tiles.count <= size*size && buildings.count <= 256 && props.count <= 10000, "地图元素超出安全上限")
        try require(Set(tiles.map(\.position)).count == tiles.count, "存在重复地形坐标")
        let ids = buildings.map(\.id) + props.map(\.id) + buildings.flatMap { $0.furniture.map(\.id) + $0.rooms.map(\.id) }
        try require(Set(ids).count == ids.count, "存在重复对象 ID")
        for t in tiles { try require(contains(t.position) && (0...96).contains(t.height), "地形越界") }
        for b in buildings {
            try require((16...96).contains(b.width) && (16...96).contains(b.depth), "建筑尺寸必须为 4…24 米")
            try require((1...6).contains(b.floors) && (0...3).contains(b.turns), "建筑楼层或旋转无效")
            try require((0...97).contains(b.elevation), "建筑高度无效")
            let f = b.footprint
            try require(contains(b.origin) && contains(Grid(b.origin.x+f.width-1, b.origin.z+f.depth-1)), "建筑超出地图")
            try require(b.rooms.count <= 96 && b.furniture.count <= 512 && b.edits.count <= 100000, "室内元素超出上限")
            for r in b.rooms {
                try require(r.floor >= 0 && r.floor < b.floors && r.x >= 1 && r.z >= 1, "房间楼层或起点无效")
                try require(r.width >= 4 && r.depth >= 4 && r.width < 96 && r.depth < 96, "房间尺寸无效")
                try require(r.x < 96 && r.z < 96 && r.x+r.width < b.width && r.z+r.depth < b.depth, "房间超出建筑")
            }
            for e in b.edits {
                try require(e.x >= 0 && e.x < b.width && e.z >= 0 && e.z < b.depth && e.y >= 0 && e.y <= b.floors*12+6, "体素编辑越界")
                try require(e.material == nil || (0...6).contains(e.material!), "无效体素材质")
            }
            for p in b.furniture {
                try validateProp(p)
                try require(p.x >= 0 && p.x < Float(b.width)/4 && p.z >= 0 && p.z < Float(b.depth)/4 && p.y >= 0 && p.y < Float(b.floors*3), "家具位置越界")
            }
        }
        for p in props {
            try validateProp(p)
            try require(p.x >= 0 && p.x < Float(size) && p.z >= 0 && p.z < Float(size) && p.y >= 0 && p.y <= 128, "物件越界")
        }
        try require(extensions.values.reduce(0) { $0 + $1.count } <= 8_000_000, "扩展数据过大")
        try require(generations.count <= 1000, "生成记录过多")
        return self
    }
    private func validateProp(_ p: Prop) throws {
        guard p.x.isFinite && p.y.isFinite && p.z.isFinite && (0...3).contains(p.turns) && p.asset.count <= 100 else {
            throw WorldError.invalid("物件坐标或素材标识无效")
        }
    }
}

public enum WorldError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(message) = self { message } else { nil } }
}

public struct History: Sendable {
    private var past: [World] = []
    private var future: [World] = []
    public init() {}
    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }
    public mutating func commit(previous: World) {
        past.append(previous); future.removeAll()
        // Bound retained snapshot data, including opaque extensions.
        while past.count > 30 || (past.count > 1 && estimatedBytes > 24_000_000) { past.removeFirst() }
    }
    private var estimatedBytes: Int {
        past.reduce(0) { total, w in total + w.tiles.count*48 + w.props.count*160 + w.buildings.reduce(0) { $0 + $1.edits.count*40 + $1.furniture.count*160 + $1.rooms.count*128 } + w.extensions.values.reduce(0) { $0 + $1.count } }
    }
    public mutating func undo(_ current: World) -> World? {
        guard let old = past.popLast() else { return nil }; future.append(current); return old
    }
    public mutating func redo(_ current: World) -> World? {
        guard let next = future.popLast() else { return nil }; past.append(current); return next
    }
}
