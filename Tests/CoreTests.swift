import XCTest
@testable import MoonEarthCore

final class CoreTests: XCTestCase {
    func testNativeRoundTripPreservesInteriorAndExtensions() throws {
        var w = Generator.demo(); w.extensions["future"] = Data([0,1,2,3])
        let data = try DocumentCodec.encode(w)
        let (back,kind) = try DocumentCodec.decode(data)
        XCTAssertEqual(back,w); XCTAssertEqual(kind,.world)
        XCTAssertFalse(back.buildings[0].rooms.isEmpty)
    }
    func testCorruptionAndFutureVersionRejected() throws {
        let data = try DocumentCodec.encode(World())
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        envelope["checksum"] = "bad"
        XCTAssertThrowsError(try DocumentCodec.decode(JSONSerialization.data(withJSONObject:envelope)))
        var w = World(); w.version = 2
        XCTAssertThrowsError(try w.validated())
    }
    func testDuplicateIDsAndNaNAreRejected() throws {
        var w = World(); let b = Generator.house(at:Grid(0,0)); w.buildings = [b,b]
        XCTAssertThrowsError(try w.validated())
        w.buildings = []; w.props = [Prop(asset:"builtin.0.0",x:.nan,z:0)]
        XCTAssertThrowsError(try w.validated())
    }
    func testRotationRoundTrip() {
        for turn in 0...3 {
            var b = Generator.house(at:Grid(12,18)); b.turns = turn
            let p = SIMD3<Float>(2,4,6)
            let back = b.localPoint(b.worldPoint(x:p.x,y:p.y,z:p.z))
            XCTAssertEqual(back,p)
        }
    }
    func testGenerationDeterministicTerrain() {
        let a = Generator.world(template:.island,seed:12), b = Generator.world(template:.island,seed:12)
        XCTAssertEqual(a.tiles,b.tiles)
        XCTAssertNotEqual(a.tiles,Generator.world(template:.island,seed:13).tiles)
    }
    func testHistoryBranchAndUndo() {
        var h = History(); let original = World(); var modified = original; modified.name = "edited"
        h.commit(previous:original); XCTAssertEqual(h.undo(modified),original); XCTAssertEqual(h.redo(original),modified)
        _ = h.undo(modified); h.commit(previous:original); XCTAssertFalse(h.canRedo)
    }
    func testRoomDoorAndFloorCut() {
        let b = Generator.house(at:Grid(0,0),variant:2)
        let cells = BuildingGeometry.cells(b,visibleFloor:0,roof:false)
        XCTAssertNil(cells[Cell(b.width/2,4,b.depth-1)])
        XCTAssertNotNil(cells[Cell(0,4,0)])
        XCTAssertTrue(cells.keys.allSatisfy { $0.y < 12 })
        let r = b.rooms[0]
        XCTAssertNil(cells[Cell(r.x+r.width/2,4,r.z+r.depth)])
    }
    func testVoxelCarveAndRoundTrip() throws {
        var b = Generator.house(at:Grid(0,0)); b.edits.append(VoxelEdit(x:0,y:4,z:0,material:nil))
        XCTAssertNil(BuildingGeometry.cells(b)[Cell(0,4,0)])
        var w = World(); w.buildings = [b]
        XCTAssertEqual(try DocumentCodec.decode(DocumentCodec.encode(w)).0.buildings[0].edits,b.edits)
    }
    func testRegionRejectsCutBuildingsAndRemapsIDs() throws {
        var w = World(); let b = Generator.house(at:Grid(4,4)); w.buildings = [b]
        XCTAssertThrowsError(try DocumentCodec.region(w,from:Grid(0,0),to:Grid(6,6)))
        let region = try DocumentCodec.region(w,from:Grid(0,0),to:Grid(20,20))
        let merged = try DocumentCodec.merge(region,into:w,at:Grid(32,32))
        XCTAssertEqual(merged.buildings.count,2)
        XCTAssertNotEqual(merged.buildings[0].id,merged.buildings[1].id)
        XCTAssertNotEqual(merged.buildings[0].rooms[0].id,merged.buildings[1].rooms[0].id)
        XCTAssertThrowsError(try DocumentCodec.merge(region,into:w,at:Grid(0,0)))
    }
    func testPlanProtectsLockedBuildingsAndFurniture() throws {
        var w = World(); var b = Generator.house(at:Grid(4,4)); b.locked = true; w.buildings = [b]
        let plan = DesignPlan(title:"AI",width:32,depth:32,floors:1,rooms:[],furniture:[])
        XCTAssertThrowsError(try plan.applying(to:w,at:b.origin,replacing:b.id))
        w.buildings[0].locked = false; w.buildings[0].furniture[0].locked = true
        let after = try plan.applying(to:w,at:b.origin,replacing:b.id,interiorsOnly:true)
        XCTAssertEqual(after.buildings[0].furniture.count,1)
        XCTAssertTrue(after.buildings[0].furniture[0].locked)
    }
    func testRoadComponentsRespectElevation() {
        var w = World(); w.tiles = [Tile(Grid(0,0),surface:.road),Tile(Grid(1,0),surface:.road),Tile(Grid(2,0),height:5,surface:.road)]
        XCTAssertEqual(Analyzer.analyze(w).roadComponents,2)
    }
    func testRegionIncludesImplicitGround() throws {
        let empty = World()
        let region = try DocumentCodec.region(empty,from:Grid(0,0),to:Grid(3,3))
        XCTAssertEqual(region.tiles.count,16)
        var target = World(); target.tiles = [Tile(Grid(10,10),height:5,surface:.stone)]
        let merged = try DocumentCodec.merge(region,into:target,at:Grid(10,10))
        XCTAssertEqual(merged.tile(at:Grid(10,10)),Tile(Grid(10,10)))
    }
    func testLockedFurnitureCannotBeRemovedByFloorChange() throws {
        var before = Generator.house(at:Grid(0,0),variant:1)
        before.furniture[1].locked = true
        var after = before; after.floors = 1; after.furniture.removeLast()
        XCTAssertThrowsError(try after.validateLockedFurniture(previous:before))
        XCTAssertNoThrow(try before.validateLockedFurniture(previous:before))
        var unlocked = before; unlocked.furniture[1].locked = false
        XCTAssertNoThrow(try unlocked.validateLockedFurniture(previous:before))
    }
    func testGeometryContainsFiniteVerticesAndValidIndices() {
        for b in Mesher.building(Generator.house(at:Grid(0,0)),floor:nil,roof:true) {
            XCTAssertEqual(b.positions.count,b.normals.count)
            XCTAssertTrue(b.indices.allSatisfy { Int($0) < b.positions.count })
            XCTAssertTrue(b.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
        }
    }
    func testCatalogHasDistinctDimensionsAndNonEmptyGeometry() {
        XCTAssertEqual(Catalog.all.count,128)
        XCTAssertEqual(Set(Catalog.all.map(\.id)).count,128)
        XCTAssertTrue(Catalog.all.allSatisfy { !$0.parts.isEmpty })
    }
    func testMoonPixelPassThroughPreservesUnknownFields() throws {
        let chunk = MoonPixelBridge.ChunkData(cx:0,cy:0,l0:Data(repeating:1,count:1024),l1:Data(repeating:0,count:1024),l2:Data(repeating:0,count:1024),l3:Data(repeating:0,count:1024))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(chunk)) as? [String:Any])
        object["timers"] = []; object["future"] = "preserve"
        let original = try JSONSerialization.data(withJSONObject:object)
        var w = try MoonPixelBridge.importTerrainChunk(original,mapping:[1:.grass])
        XCTAssertEqual(try MoonPixelBridge.originalChunk(from:w),original)
        w.tiles[0].surface = .water
        XCTAssertThrowsError(try MoonPixelBridge.originalChunk(from:w))
    }
    func testAtomicSaveRecovery() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let repo = ProjectRepository(directory:directory)
        var world = World(); world.name = "before"; try await repo.save(world)
        world.name = "after"; try await repo.save(world)
        let path = directory.appendingPathComponent(world.id.uuidString).appendingPathExtension("pxworld")
        try Data("corrupt".utf8).write(to:path)
        let recovered = try await repo.list()
        XCTAssertEqual(recovered[0].world.name,"before"); XCTAssertTrue(recovered[0].recovered)
        try await repo.save(recovered[0].world)
    }
}
