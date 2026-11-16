import Foundation

public enum WorldTemplate: String, CaseIterable, Sendable {
    case blank = "空白", plain = "平原", island = "岛屿", valley = "山谷"
}

public struct SeededRandom: Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var x = state
        x = (x ^ (x >> 30)) &* 0xBF58476D1CE4E5B9
        x = (x ^ (x >> 27)) &* 0x94D049BB133111EB
        return x ^ (x >> 31)
    }
}

public enum Generator {
    public static func world(template: WorldTemplate, size: Int = 128, seed: UInt64 = 42) -> World {
        var w = World(); w.size = min(512,max(16,size)); w.seed = seed; w.name = template.rawValue + "世界"
        guard template != .blank else { return w }
        var rng = SeededRandom(seed: seed)
        let phase = Double(rng.next()%1000)/100
        for x in 0..<w.size { for z in 0..<w.size {
            let nx = Double(x)/Double(w.size)-0.5, nz = Double(z)/Double(w.size)-0.5
            let noise = sin(Double(x)*0.16+phase)*cos(Double(z)*0.12+phase)
            var h = 0; var surface: Surface = .grass
            if template == .island {
                let radius = sqrt(nx*nx+nz*nz)
                h = max(0,Int((0.42-radius)*22+noise))
                surface = h == 0 ? .water : h < 2 ? .sand : .grass
            } else if template == .valley {
                h = max(0,Int(abs(nx)*22+noise)); surface = abs(nx)<0.035 ? .water : h>7 ? .stone : .grass
            } else { h = max(0,Int(noise+0.4)) }
            if h != 0 || surface != .grass { w.tiles.append(Tile(Grid(x,z),height:h,surface:surface)) }
        } }
        return w
    }
    public static func house(at point: Grid, elevation: Int = 1, variant: Int = 0) -> Building {
        var b = Building(origin: point); b.elevation = elevation
        b.name = ["林间小屋","河畔住宅","双层别墅","城市公寓","庭院楼","小商店","工作室","图书馆","旅店","农舍","仓库","塔楼"][abs(variant)%12]
        b.width = 32 + (abs(variant)%3)*8; b.depth = 32 + (abs(variant)%2)*8
        b.floors = 1 + abs(variant)%3
        for floor in 0..<b.floors {
            b.rooms.append(Room(name: floor == 0 ? "起居室" : "卧室", floor: floor, x: 1,z: 1,width: 12,depth: 12))
            var p = Prop(asset: floor == 0 ? "builtin.2.0" : "builtin.7.0", x: 0.75,y: Float(floor*3)+0.25,z: 0.75)
            p.turns = 0; b.furniture.append(p)
        }
        return b
    }
    public static func demo() -> World {
        var w = world(template: .plain, size: 128); w.name = "河畔工坊"
        for x in 0..<48 { for z in 30...32 { w.setTile(Tile(Grid(x,z),surface:.road)) } }
        for z in 0..<64 { for x in 45...48 { w.setTile(Tile(Grid(x,z),surface:.water)) } }
        for x in 43...50 { w.setTile(Tile(Grid(x,31),height:1,surface:.road)) }
        for (i,p) in [Grid(18,20),Grid(30,20),Grid(18,35)].enumerated() {
            let b = house(at:p,variant:i)
            for x in p.x..<(p.x+b.footprint.width) { for z in p.z..<(p.z+b.footprint.depth) { w.setTile(Tile(Grid(x,z))) } }
            w.buildings.append(b)
        }
        var rng = SeededRandom(seed:42)
        for _ in 0..<32 {
            let x = Int(rng.next()%48)+8, z = Int(rng.next()%44)+8, p = Grid(x,z)
            guard !w.buildings.contains(where: { $0.contains(p) }), w.tile(at:p).surface != .water, w.tile(at:p).surface != .road else { continue }
            w.props.append(Prop(asset:"builtin.21.0", x:Float(x), y:Float(w.tile(at:p).height+1), z:Float(z)))
        }
        return w
    }
}

/// A bounded building plan shared by on-device AI, imported plans and template generation.
public struct DesignPlan: Codable, Sendable {
    public var title: String
    public var width: Int
    public var depth: Int
    public var floors: Int
    public var rooms: [Room]
    public var furniture: [Prop]
    public init(title: String, width: Int, depth: Int, floors: Int, rooms: [Room], furniture: [Prop]) {
        self.title = title; self.width = width; self.depth = depth; self.floors = floors; self.rooms = rooms; self.furniture = furniture
    }
    public func applying(to world: World, at point: Grid, replacing id: UUID? = nil, interiorsOnly: Bool = false) throws -> World {
        var next = world
        let index = id.flatMap { id in next.buildings.firstIndex { $0.id == id } }
        if id != nil && index == nil { throw WorldError.invalid("目标建筑已不存在") }
        if let index, next.buildings[index].locked { throw WorldError.invalid("建筑已锁定") }
        var b = index.map { next.buildings[$0] } ?? Building(origin: point)
        if !interiorsOnly { b.name = String(title.prefix(100)); b.width = width; b.depth = depth; b.floors = floors }
        if index == nil { b.elevation = world.tile(at:point).height+1 }
        // Locked furniture survives every generation. AI cannot replace locked content.
        let locked = b.furniture.filter(\.locked)
        b.rooms = rooms.map { r in var r = r; r.id = UUID(); return r }
        b.furniture = locked + furniture.map { p in var p = p; p.id = UUID(); p.locked = false; return p }
        if !interiorsOnly { b.edits = [] }
        if let index { next.buildings[index] = b } else { next.buildings.append(b) }
        _ = try next.validated()
        for other in next.buildings where other.id != b.id {
            let a = b.footprint, o = other.footprint
            if b.origin.x < other.origin.x+o.width && other.origin.x < b.origin.x+a.width && b.origin.z < other.origin.z+o.depth && other.origin.z < b.origin.z+a.depth {
                throw WorldError.invalid("生成建筑与「\(other.name)」重叠，请移动放置位置")
            }
        }
        return next
    }
}
