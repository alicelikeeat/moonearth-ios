import Foundation

public struct Cell: Hashable, Sendable {
    public var x: Int; public var y: Int; public var z: Int
    public init(_ x: Int, _ y: Int, _ z: Int) { self.x = x; self.y = y; self.z = z }
}

public enum BuildingGeometry {
    public static let palette: [UInt32] = [0xE5D8BF, 0xA87F5B, 0x647F89, 0xA3C7CD, 0xE1C690, 0x909997, 0x65855D]
    public static func cells(_ b: Building, visibleFloor: Int? = nil, roof: Bool = true) -> [Cell: Int] {
        var cells: [Cell: Int] = [:]
        let endFloor = min(b.floors-1, visibleFloor ?? b.floors-1)
        func put(_ x: Int, _ y: Int, _ z: Int, _ m: Int = 0) { cells[Cell(x,y,z)] = m }
        for f in 0...endFloor {
            let base = f*12
            for x in 0..<b.width { for z in 0..<b.depth {
                // Stairwell opening on upper floors; landing remains around the opening.
                if f == 0 || !(x >= b.width-7 && x < b.width-3 && z >= 2 && z < 14) { put(x,base,z,1) }
            } }
            for y in (base+1)..<(base+12) {
                for x in 0..<b.width { put(x,y,0); put(x,y,b.depth-1) }
                for z in 0..<b.depth { put(0,y,z); put(b.width-1,y,z) }
            }
            // Windows remain editable voxels.
            for x in stride(from: 4, to: b.width-4, by: 8) { for dx in 0..<4 { for y in (base+5)..<(base+9) { put(x+dx,y,0,3); put(x+dx,y,b.depth-1,3) } } }
            if f == 0 { for x in (b.width/2-2)..<(b.width/2+2) { for y in 1...8 { cells.removeValue(forKey: Cell(x,y,b.depth-1)) } } }
            for room in b.rooms where room.floor == f {
                for y in (base+1)..<(base+12) {
                    for x in room.x...(room.x+room.width) { put(x,y,room.z); put(x,y,room.z+room.depth) }
                    for z in room.z...(room.z+room.depth) { put(room.x,y,z); put(room.x+room.width,y,z) }
                }
                // Each room gets an editable doorway towards its south side.
                let door = room.x + room.width/2
                for x in (door-1)...(door+1) { for y in (base+1)...(base+8) { cells.removeValue(forKey: Cell(x,y,room.z+room.depth)) } }
            }
            if f < b.floors-1 {
                for step in 0..<12 { for x in (b.width-7)..<(b.width-3) { for y in (base+1)...(base+step+1) { put(x,y,step+2,1) } } }
            }
        }
        if roof && visibleFloor == nil {
            let y = b.floors*12
            for x in 0..<b.width { for z in 0..<b.depth { put(x,y,z,2) } }
        }
        let cap = visibleFloor.map { ($0+1)*12-1 } ?? Int.max
        for edit in b.edits where edit.y <= cap {
            let p = Cell(edit.x,edit.y,edit.z)
            if let m = edit.material { cells[p] = m } else { cells.removeValue(forKey: p) }
        }
        return cells
    }
}

public struct MeshBatch: Sendable {
    public var color: UInt32
    public var positions: [SIMD3<Float>] = []
    public var normals: [SIMD3<Float>] = []
    public var indices: [UInt32] = []
    public init(color: UInt32) { self.color = color }
    public mutating func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>, normal: SIMD3<Float>) {
        let i = UInt32(positions.count)
        positions += [a,b,c,d]; normals += Array(repeating: normal, count: 4)
        indices += [i,i+1,i+2,i,i+2,i+3]
    }
    public mutating func box(center: SIMD3<Float>, size: SIMD3<Float>) {
        let p = center-size/2, q = center+size/2
        quad([p.x,q.y,p.z],[p.x,q.y,q.z],[q.x,q.y,q.z],[q.x,q.y,p.z],normal:[0,1,0])
        quad([p.x,p.y,q.z],[p.x,p.y,p.z],[q.x,p.y,p.z],[q.x,p.y,q.z],normal:[0,-1,0])
        quad([q.x,p.y,p.z],[q.x,q.y,p.z],[q.x,q.y,q.z],[q.x,p.y,q.z],normal:[1,0,0])
        quad([p.x,p.y,q.z],[p.x,q.y,q.z],[p.x,q.y,p.z],[p.x,p.y,p.z],normal:[-1,0,0])
        quad([q.x,p.y,q.z],[q.x,q.y,q.z],[p.x,q.y,q.z],[p.x,p.y,q.z],normal:[0,0,1])
        quad([p.x,p.y,p.z],[p.x,q.y,p.z],[q.x,q.y,p.z],[q.x,p.y,p.z],normal:[0,0,-1])
    }
}

public enum Mesher {
    public static func building(_ b: Building, floor: Int?, roof: Bool) -> [MeshBatch] {
        let cells = BuildingGeometry.cells(b, visibleFloor: floor, roof: roof)
        var batches = BuildingGeometry.palette.map { MeshBatch(color: $0) }
        for (p,m) in cells {
            let x = Float(p.x)*0.25, y = Float(p.y)*0.25, z = Float(p.z)*0.25, s: Float = 0.25
            if cells[Cell(p.x,p.y+1,p.z)] == nil { batches[m].quad([x,y+s,z],[x,y+s,z+s],[x+s,y+s,z+s],[x+s,y+s,z],normal:[0,1,0]) }
            if cells[Cell(p.x,p.y-1,p.z)] == nil { batches[m].quad([x,y,z+s],[x,y,z],[x+s,y,z],[x+s,y,z+s],normal:[0,-1,0]) }
            if cells[Cell(p.x+1,p.y,p.z)] == nil { batches[m].quad([x+s,y,z],[x+s,y+s,z],[x+s,y+s,z+s],[x+s,y,z+s],normal:[1,0,0]) }
            if cells[Cell(p.x-1,p.y,p.z)] == nil { batches[m].quad([x,y,z+s],[x,y+s,z+s],[x,y+s,z],[x,y,z],normal:[-1,0,0]) }
            if cells[Cell(p.x,p.y,p.z+1)] == nil { batches[m].quad([x+s,y,z+s],[x+s,y+s,z+s],[x,y+s,z+s],[x,y,z+s],normal:[0,0,1]) }
            if cells[Cell(p.x,p.y,p.z-1)] == nil { batches[m].quad([x,y,z],[x,y+s,z],[x+s,y+s,z],[x+s,y,z],normal:[0,0,-1]) }
        }
        return batches.filter { !$0.indices.isEmpty }
    }
    public static func terrain(_ world: World, chunk: Grid, lookup: [Grid: Tile]) -> [MeshBatch] {
        var batches = Surface.allCases.map { MeshBatch(color: $0.color) }
        let materials = Dictionary(uniqueKeysWithValues: Surface.allCases.enumerated().map { ($0.element,$0.offset) })
        for x in chunk.x*16..<min(world.size,chunk.x*16+16) { for z in chunk.z*16..<min(world.size,chunk.z*16+16) {
            let t = lookup[Grid(x,z)] ?? Tile(Grid(x,z)), h = Float(t.height+1)
            let px = Float(x), pz = Float(z), m = materials[t.surface]!
            batches[m].quad([px,h,pz],[px,h,pz+1],[px+1,h,pz+1],[px+1,h,pz],normal:[0,1,0])
            let sides: [(Grid, SIMD3<Float>)] = [(Grid(x-1,z),[-1,0,0]),(Grid(x+1,z),[1,0,0]),(Grid(x,z-1),[0,0,-1]),(Grid(x,z+1),[0,0,1])]
            for (n,normal) in sides {
                let low: Float = world.contains(n) ? Float((lookup[n]?.height ?? 0)+1) : 0
                guard low < h else { continue }
                let earth = materials[Surface.earth]!
                if normal.x < 0 { batches[earth].quad([px,low,pz+1],[px,h,pz+1],[px,h,pz],[px,low,pz],normal:normal) }
                if normal.x > 0 { batches[earth].quad([px+1,low,pz],[px+1,h,pz],[px+1,h,pz+1],[px+1,low,pz+1],normal:normal) }
                if normal.z < 0 { batches[earth].quad([px,low,pz],[px,h,pz],[px+1,h,pz],[px+1,low,pz],normal:normal) }
                if normal.z > 0 { batches[earth].quad([px+1,low,pz+1],[px+1,h,pz+1],[px,h,pz+1],[px,low,pz+1],normal:normal) }
            }
        } }
        return batches.filter { !$0.indices.isEmpty }
    }
    public static func prop(_ prop: Prop) -> [MeshBatch] {
        let parts = Catalog.asset(prop.asset)?.parts ?? Catalog.placeholder
        var batches: [UInt32: MeshBatch] = [:]
        for part in parts {
            var batch = batches[part.color] ?? MeshBatch(color: part.color)
            batch.box(center: part.center, size: part.size); batches[part.color] = batch
        }
        return batches.values.sorted { $0.color < $1.color }
    }
}
