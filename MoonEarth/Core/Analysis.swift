import Foundation

public struct Finding: Identifiable, Sendable {
    public var id = UUID()
    public var message: String
    public var position: Grid
    public var buildingID: UUID?
    public init(_ message: String, at position: Grid, buildingID: UUID? = nil) {
        self.message = message; self.position = position; self.buildingID = buildingID
    }
}
public struct AnalysisReport: Sendable {
    public var roadComponents: Int = 0
    public var waterArea: Int = 0
    public var buildingArea: Int = 0
    public var findings: [Finding] = []
}

public enum Analyzer {
    public static func analyze(_ world: World) -> AnalysisReport {
        var result = AnalysisReport()
        let tiles = Dictionary(uniqueKeysWithValues: world.tiles.map { ($0.position,$0) })
        let roads = Set(world.tiles.filter { $0.surface == .road }.map(\.position))
        var unseen = roads
        while let start = unseen.first {
            result.roadComponents += 1
            var queue = [start]; unseen.remove(start); var cursor = 0
            while cursor < queue.count {
                let p = queue[cursor]; cursor += 1
                for n in p.neighbors where unseen.contains(n) && abs((tiles[n]?.height ?? 0)-(tiles[p]?.height ?? 0)) <= 1 {
                    unseen.remove(n); queue.append(n)
                }
            }
            if queue.count < 4 { result.findings.append(Finding("孤立的短道路",at:start)) }
        }
        result.waterArea = world.tiles.filter { $0.surface == .water }.count
        var occupied = Set<Grid>()
        for b in world.buildings {
            let f = b.footprint
            for x in b.origin.x..<(b.origin.x+f.width) { for z in b.origin.z..<(b.origin.z+f.depth) {
                let p = Grid(x,z)
                if !occupied.insert(p).inserted { result.findings.append(Finding("建筑占地重叠",at:p,buildingID:b.id)) }
            } }
            let e = b.worldPoint(x:Float(b.width)/8,y:0,z:Float(b.depth)/4+0.5)
            let entry = Grid(Int(floor(e.x)),Int(floor(e.z)))
            if !roads.contains(entry) && !entry.neighbors.contains(where:roads.contains) { result.findings.append(Finding("\(b.name)：入口未直接连接道路",at:b.origin,buildingID:b.id)) }
            if world.tile(at:b.origin).surface == .water { result.findings.append(Finding("\(b.name)：建筑落在水域",at:b.origin,buildingID:b.id)) }
            for p in b.furniture where Catalog.asset(p.asset) == nil { result.findings.append(Finding("缺少素材 \(p.asset)，已保留原始记录",at:b.origin,buildingID:b.id)) }
            for f in 0..<b.floors {
                // Quarter-metre flood fill at floor level with a 0.5m-wide agent.
                let cells = BuildingGeometry.cells(b,visibleFloor:f,roof:false)
                let base = f*12+1
                var blocked = Set<Grid>()
                for x in 0..<b.width { for z in 0..<b.depth {
                    if (base..<(base+7)).contains(where: { cells[Cell(x,$0,z)] != nil }) { blocked.insert(Grid(x,z)) }
                } }
                for p in b.furniture where Int(p.y/3) == f {
                    for part in Catalog.asset(p.asset)?.parts ?? Catalog.placeholder {
                        // Conservative footprint, respecting furniture quarter turns.
                        let minP = part.center-part.size/2, maxP = part.center+part.size/2
                        let corners = [SIMD2(minP.x,minP.z),SIMD2(maxP.x,minP.z),SIMD2(minP.x,maxP.z),SIMD2(maxP.x,maxP.z)].map { point -> SIMD2<Float> in
                            switch p.turns { case 1: return [point.y,-point.x]; case 2: return [-point.x,-point.y]; case 3: return [-point.y,point.x]; default: return point }
                        }
                        let x0 = Int(floor((p.x+corners.map(\.x).min()!)*4)), x1 = Int(ceil((p.x+corners.map(\.x).max()!)*4))
                        let z0 = Int(floor((p.z+corners.map(\.y).min()!)*4)), z1 = Int(ceil((p.z+corners.map(\.y).max()!)*4))
                        for x in x0..<x1 { for z in z0..<z1 { blocked.insert(Grid(x,z)) } }
                    }
                }
                func clear(_ p: Grid) -> Bool {
                    p.x > 0 && p.z > 0 && p.x+1 < b.width && p.z+1 < b.depth &&
                    ![p,Grid(p.x+1,p.z),Grid(p.x,p.z+1),Grid(p.x+1,p.z+1)].contains(where:blocked.contains)
                }
                let start = f == 0 ? Grid(b.width/2-1,b.depth-2) : Grid(b.width-6,14)
                var reached = Set<Grid>(), queue: [Grid] = []; var cursor = 0
                if clear(start) { reached.insert(start); queue.append(start) }
                while cursor < queue.count {
                    let p = queue[cursor]; cursor += 1
                    for n in p.neighbors where !reached.contains(n) && clear(n) { reached.insert(n); queue.append(n) }
                }
                for room in b.rooms where room.floor == f {
                    let center = Grid(room.x+room.width/2,room.z+room.depth/2)
                    if !reached.contains(center) { result.findings.append(Finding("\(f+1) 楼「\(room.name)」中心不可达（0.5m 通行模型）",at:b.origin,buildingID:b.id)) }
                }
            }
        }
        result.buildingArea = occupied.count
        // Prevent enormous overlapping maps from overwhelming the UI.
        result.findings = Array(result.findings.prefix(200))
        return result
    }
}
