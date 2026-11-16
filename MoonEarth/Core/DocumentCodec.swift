import Foundation

public enum PackageKind: String, Codable, Sendable { case world, region, building }
private struct Envelope: Codable {
    var format = "earth.moon.document"
    var version = 1
    var kind: PackageKind
    var checksum: String
    var payload: Data
}

public enum DocumentCodec {
    public static let maximumBytes = 32_000_000
    /// FNV-1a detects accidental corruption; it is not an authenticity signature.
    public static func checksum(_ bytes: Data) -> String {
        var hash: UInt64 = 14695981039346656037
        for byte in bytes { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return String(hash,radix:16)
    }
    public static func encode(_ world: World, kind: PackageKind = .world) throws -> Data {
        _ = try world.validated()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(world)
        let data = try encoder.encode(Envelope(kind:kind,checksum:checksum(payload),payload:payload))
        guard data.count <= maximumBytes else { throw WorldError.invalid("文件超过 32 MB 上限") }
        return data
    }
    public static func decode(_ data: Data) throws -> (World, PackageKind) {
        guard data.count <= maximumBytes else { throw WorldError.invalid("文件超过 32 MB 上限") }
        let envelope = try JSONDecoder().decode(Envelope.self,from:data)
        guard envelope.format == "earth.moon.document", envelope.version == 1 else { throw WorldError.invalid("不是支持的 Moon Earth 文档") }
        guard checksum(envelope.payload) == envelope.checksum else { throw WorldError.invalid("文件校验失败，原项目未被修改") }
        let world = try JSONDecoder().decode(World.self,from:envelope.payload).validated()
        guard envelope.kind != .building || world.buildings.count == 1 else { throw WorldError.invalid("建筑包必须包含一栋建筑") }
        return (world,envelope.kind)
    }
    public static func building(_ b: Building) throws -> World {
        var w = World(); w.name = b.name; w.size = 32
        var copy = b; copy.origin = Grid(0,0); copy.elevation = 1
        w.buildings = [copy]; return try w.validated()
    }
    public static func region(_ world: World, from start: Grid, to end: Grid) throws -> World {
        let minX = min(start.x,end.x), minZ = min(start.z,end.z), maxX = max(start.x,end.x), maxZ = max(start.z,end.z)
        guard world.contains(Grid(minX,minZ)), world.contains(Grid(maxX,maxZ)) else { throw WorldError.invalid("选区超出地图") }
        var out = World(); out.name = world.name + " · 区域"; out.size = max(16,max(maxX-minX+1,maxZ-minZ+1))
        let lookup = Dictionary(uniqueKeysWithValues:world.tiles.map { ($0.position,$0) })
        // Include implicit default ground: importing an empty plain must replace old terrain too.
        for x in minX...maxX { for z in minZ...maxZ {
            let t = lookup[Grid(x,z)] ?? Tile(Grid(x,z))
            out.tiles.append(Tile(Grid(x-minX,z-minZ),height:t.height,surface:t.surface))
        } }
        for b in world.buildings {
            let f = b.footprint
            let intersects = b.origin.x <= maxX && b.origin.z <= maxZ && b.origin.x+f.width > minX && b.origin.z+f.depth > minZ
            guard !intersects || (b.origin.x >= minX && b.origin.z >= minZ && b.origin.x+f.width-1 <= maxX && b.origin.z+f.depth-1 <= maxZ) else { throw WorldError.invalid("选区切穿了建筑，请扩大选区") }
            if intersects { var b = b; b.origin = Grid(b.origin.x-minX,b.origin.z-minZ); out.buildings.append(b) }
        }
        out.props = world.props.filter { $0.x >= Float(minX) && $0.x < Float(maxX+1) && $0.z >= Float(minZ) && $0.z < Float(maxZ+1) }.map { p in var p = p; p.x -= Float(minX); p.z -= Float(minZ); return p }
        return try out.validated()
    }
    public static func merge(_ incoming: World, into world: World, at offset: Grid) throws -> World {
        var next = world
        for tile in incoming.tiles {
            let p = Grid(tile.position.x+offset.x,tile.position.z+offset.z)
            guard next.contains(p) else { throw WorldError.invalid("导入区域超出地图") }
            if next.buildings.contains(where: { $0.locked && $0.contains(p) }) { throw WorldError.invalid("导入范围包含锁定建筑") }
            next.setTile(Tile(p,height:tile.height,surface:tile.surface))
        }
        for var b in incoming.buildings {
            b.id = UUID(); b.origin = Grid(b.origin.x+offset.x,b.origin.z+offset.z)
            b.rooms = b.rooms.map { r in var r = r; r.id = UUID(); return r }
            b.furniture = b.furniture.map { p in var p = p; p.id = UUID(); return p }
            let f = b.footprint
            guard !next.buildings.contains(where: { other in
                let o = other.footprint
                return b.origin.x < other.origin.x+o.width && other.origin.x < b.origin.x+f.width && b.origin.z < other.origin.z+o.depth && other.origin.z < b.origin.z+f.depth
            }) else { throw WorldError.invalid("导入建筑与现有建筑重叠") }
            next.buildings.append(b)
        }
        for var p in incoming.props { p.id = UUID(); p.x += Float(offset.x); p.z += Float(offset.z); next.props.append(p) }
        // Never silently merge opaque extension references into another ID space.
        guard incoming.extensions.isEmpty else { throw WorldError.invalid("区域含未知扩展，无法安全合并；请作为独立世界打开") }
        return try next.validated()
    }
}

public actor ProjectRepository {
    private let directory: URL
    public init(directory: URL) { self.directory = directory }
    private func prepare() throws { try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true) }
    public func save(_ world: World) throws {
        try prepare()
        let path = directory.appendingPathComponent(world.id.uuidString).appendingPathExtension("pxworld")
        let data = try DocumentCodec.encode(world)
        if FileManager.default.fileExists(atPath:path.path) {
            let old = try Data(contentsOf:path)
            _ = try DocumentCodec.decode(old)
            try old.write(to:path.appendingPathExtension("backup"),options:.atomic)
        }
        try data.write(to:path,options:.atomic)
    }
    public func list() throws -> [(world: World, recovered: Bool)] {
        try prepare()
        let paths = try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil).filter { $0.pathExtension == "pxworld" }
        return try paths.map { path in
            do { return (try DocumentCodec.decode(Data(contentsOf:path)).0,false) }
            catch {
                let backup = try Data(contentsOf:path.appendingPathExtension("backup"))
                let world = try DocumentCodec.decode(backup).0
                // Restore valid bytes so subsequent saves can proceed.
                try backup.write(to:path,options:.atomic)
                return (world,true)
            }
        }.sorted { $0.world.name < $1.world.name }
    }
    public func trash(_ id: UUID) throws {
        let path = directory.appendingPathComponent(id.uuidString).appendingPathExtension("pxworld")
        let trash = directory.appendingPathComponent("Trash",isDirectory:true)
        try FileManager.default.createDirectory(at:trash,withIntermediateDirectories:true)
        let target = trash.appendingPathComponent(id.uuidString+"-"+UUID().uuidString+".pxworld")
        try FileManager.default.moveItem(at:path,to:target)
    }
    public func restoreAll() throws {
        let trash = directory.appendingPathComponent("Trash",isDirectory:true)
        guard FileManager.default.fileExists(atPath:trash.path) else { return }
        for path in try FileManager.default.contentsOfDirectory(at:trash,includingPropertiesForKeys:nil) where path.pathExtension == "pxworld" {
            var w = try DocumentCodec.decode(Data(contentsOf:path)).0; w.id = UUID(); w.name += " · 恢复"
            try save(w); try FileManager.default.removeItem(at:path)
        }
    }
}
