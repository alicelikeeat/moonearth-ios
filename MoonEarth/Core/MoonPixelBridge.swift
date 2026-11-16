import Foundation

public enum MoonPixelBridge {
    public static let referenceCommit = "e0bf6b40db63c4a70d8518060b433f83c08af90a"
    public static let status = "已核对 MoonPixel 开发分支：32×32 分块、四层 UInt8 tile ID、format 3 事务存档。它没有 Moon Earth 文件导入入口；本版不宣称完整双向互通。建筑室内、体素高度和家具无法直接映射，需双方接入协议。完整作品请使用原生 .pxworld 保存。"
    public struct ChunkData: Codable, Sendable {
        public var v: Int
        public var cx: Int
        public var cy: Int
        public var l0: Data
        public var l1: Data
        public var l2: Data
        public var l3: Data
        public var revision: Int
        public init(v: Int = 1,cx: Int,cy: Int,l0: Data,l1: Data,l2: Data,l3: Data,revision: Int = 0) {
            self.v = v; self.cx = cx; self.cy = cy; self.l0 = l0; self.l1 = l1; self.l2 = l2; self.l3 = l3; self.revision = revision
        }
    }
    /// Explicit mapping is required; never infer tile IDs from ordinal values.
    /// Retain original source bytes, including timers/props and future fields.
    public static func importTerrainChunk(_ data: Data, mapping: [UInt8:Surface]) throws -> World {
        guard data.count <= DocumentCodec.maximumBytes else { throw WorldError.invalid("MoonPixel 分块过大") }
        let chunk = try JSONDecoder().decode(ChunkData.self,from:data)
        guard chunk.v == 1, [chunk.l0,chunk.l1,chunk.l2,chunk.l3].allSatisfy({ $0.count == 1024 }) else { throw WorldError.invalid("无效 MoonPixel 分块") }
        var w = World(); w.size = 32; w.name = "MoonPixel 分块 \(chunk.cx),\(chunk.cy)"
        for (i,tile) in chunk.l0.enumerated() {
            guard let surface = mapping[tile] else { throw WorldError.invalid("缺少 MoonPixel tile ID \(tile) 的显式映射") }
            w.tiles.append(Tile(Grid(i%32,i/32),surface:surface))
        }
        w.extensions["moonpixel.originalChunk"] = data
        w.extensions["moonpixel.importedTerrainChecksum"] = Data(try terrainFingerprint(w).utf8)
        return try w.validated()
    }
    /// Only unchanged-source pass-through is safe. Changed terrain requires a complete store writer.
    public static func originalChunk(from world: World) throws -> Data {
        guard let data = world.extensions["moonpixel.originalChunk"], let fingerprint = world.extensions["moonpixel.importedTerrainChecksum"],
              Data(try terrainFingerprint(world).utf8) == fingerprint, world.buildings.isEmpty, world.props.isEmpty else {
            throw WorldError.invalid("修改后的世界无法安全写回 MoonPixel 存档；请导出 Moon Earth 原生文件")
        }
        return data
    }
    private static func terrainFingerprint(_ world: World) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let tiles = world.tiles.sorted { $0.position.z == $1.position.z ? $0.position.x < $1.position.x : $0.position.z < $1.position.z }
        return DocumentCodec.checksum(try encoder.encode(tiles)) + "/\(world.size)"
    }
}
