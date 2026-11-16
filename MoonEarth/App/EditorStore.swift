import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let moonWorld = UTType(exportedAs:"com.moonearth.world",conformingTo:.data)
    static let moonRegion = UTType(exportedAs:"com.moonearth.region",conformingTo:.data)
    static let moonBuilding = UTType(exportedAs:"com.moonearth.building",conformingTo:.data)
}

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.moonWorld,.moonRegion,.moonBuilding] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw WorldError.invalid("无法读取文件") }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents:data) }
}

enum EditorTool: String, CaseIterable {
    case select = "选择", paint = "地表", raise = "抬高", lower = "降低", flatten = "压平", house = "建筑", prop = "物件", room = "房间", voxel = "体素", carve = "开洞"
    var symbol: String {
        switch self {
        case .select: "cursorarrow"; case .paint: "paintbrush.pointed"; case .raise: "mountain.2"; case .lower: "arrow.down.to.line"; case .flatten: "rectangle.compress.vertical"
        case .house: "house"; case .prop: "chair.lounge"; case .room: "square.dashed"; case .voxel: "cube"; case .carve: "eraser"
        }
    }
}

@MainActor @Observable
final class EditorStore {
    var world = Generator.demo()
    var projects: [World] = []
    var history = History()
    var revision = 0
    var selected: UUID?
    var selectedProp: UUID?
    var cursor = Grid(18,20)
    var interior = false
    var floor = 0
    var roof = true
    var topDown = false
    var tool: EditorTool = .select
    var surface: Surface = .grass
    var brush = 1
    var targetHeight = 0
    var assetID = "builtin.0.0"
    var houseVariant = 0
    var voxelHeight = 2
    var voxelMaterial = 0
    var showLibrary = false
    var showInspector = false
    var showAI = false
    var showAnalysis = false
    var presentation = false
    var error: String?
    var saveStatus = "尚未保存"
    var busy = false
    var preview: World?
    var previewTitle = ""
    var previewBase = 0
    var report: AnalysisReport?
    var reportRevision = -1
    var cameraFocus = SIMD3<Float>(26,1,27)
    var focusToken = 0
    var regionStart: Grid?
    var regionEnd: Grid?
    var exportFile: ExportDocument?
    var exportType = UTType.moonWorld
    var exportName = "MoonEarth"
    var exporting = false
    var importing = false
    var favorites: Set<String> = Set(UserDefaults.standard.stringArray(forKey:"favorites") ?? [])
    private var saveTask: Task<Void,Never>?
    private var generationID = UUID()
    private var generationTask: Task<Void,Never>?
    private var strokeWorld: World?
    private var strokePoints = Set<Grid>()
    private var roomStart: SIMD3<Float>?
    private let repository = ProjectRepository(directory:URL.documentsDirectory.appendingPathComponent("MoonEarthProjects",isDirectory:true))
    var displayWorld: World { preview ?? world }
    var building: Building? { world.buildings.first { $0.id == selected } }
    var isPreviewing: Bool { preview != nil }

    func loadProjects() async {
        do {
            let loaded = try await repository.list(); projects = loaded.map(\.world)
            if loaded.contains(where: \.recovered) { error = "部分项目从上一份有效备份恢复。" }
        } catch { self.error = "读取项目失败：\(error.localizedDescription)" }
    }
    func open(_ project: World) {
        saveTask?.cancel(); cancelGeneration(); preview = nil; world = project; history = History(); selected = nil; interior = false
        selectedProp = nil; report = nil; revision += 1; saveStatus = "已打开"; focus(Grid(project.size/4,project.size/4))
    }
    func newProject(template: WorldTemplate, size: Int, seed: UInt64) {
        open(Generator.world(template:template,size:size,seed:seed)); scheduleSave()
    }
    func duplicateProject(_ project: World) async {
        do { var copy = project; copy.id = UUID(); copy.name += " · 副本"; try await repository.save(copy); await loadProjects() }
        catch { self.error = error.localizedDescription }
    }
    func deleteProject(_ project: World) async {
        do { try await repository.trash(project.id); await loadProjects() } catch { self.error = error.localizedDescription }
    }
    func restoreTrash() async {
        do { try await repository.restoreAll(); await loadProjects() } catch { self.error = error.localizedDescription }
    }
    func change(_ action: (inout World) throws -> Void) {
        guard preview == nil && !busy else { return }
        do {
            var next = world; try action(&next); _ = try next.validated()
            guard next != world else { return }
            history.commit(previous:world); world = next; changed()
        } catch { self.error = error.localizedDescription }
    }
    private func changed() { revision += 1; report = nil; scheduleSave() }
    func undo() { guard preview == nil, !busy, let old = history.undo(world) else { return }; world = old; reconcileSelection(); changed() }
    func redo() { guard preview == nil, !busy, let next = history.redo(world) else { return }; world = next; reconcileSelection(); changed() }
    private func reconcileSelection() { if building == nil { selected = nil; interior = false }; floor = min(floor,(building?.floors ?? 1)-1) }
    func scheduleSave() {
        saveTask?.cancel(); saveStatus = "等待保存"
        let snapshot = world, rev = revision
        saveTask = Task {
            do {
                try await Task.sleep(for:.milliseconds(600)); try Task.checkCancellation()
                saveStatus = "保存中"
                try await repository.save(snapshot)
                if rev == revision { saveStatus = "已保存" }
            } catch is CancellationError { } catch { if rev == revision { saveStatus = "保存失败"; self.error = error.localizedDescription } }
        }
    }
    func flush() async {
        saveTask?.cancel()
        let snapshot = strokeWorld ?? world, rev = revision
        do { try await repository.save(snapshot); if revision == rev { saveStatus = "已保存" } }
        catch { saveStatus = "保存失败"; self.error = error.localizedDescription }
    }
    func focus(_ grid: Grid) {
        cameraFocus = [Float(grid.x)+0.5,Float(world.tile(at:grid).height+1),Float(grid.z)+0.5]; focusToken += 1
    }
    func enterBuilding() {
        guard let b = building else { return }; interior = true; floor = 0; roof = false
        cameraFocus = b.worldPoint(x:Float(b.width)/8,y:1,z:Float(b.depth)/8); focusToken += 1
    }
    func updateBuilding(_ action: (inout Building) -> Void) {
        guard let id = selected else { return }
        change { w in
            guard let i = w.buildings.firstIndex(where: { $0.id == id }), !w.buildings[i].locked else { throw WorldError.invalid("建筑已锁定") }
            let previous = w.buildings[i]
            action(&w.buildings[i])
            try w.buildings[i].validateLockedFurniture(previous:previous)
        }
    }
    func toggleBuildingLock() {
        guard let id = selected else { return }; change { w in if let i = w.buildings.firstIndex(where: { $0.id == id }) { w.buildings[i].locked.toggle() } }
    }
    func removeSelected() {
        if let propID = selectedProp {
            if interior { updateBuilding { $0.furniture.removeAll { $0.id == propID && !$0.locked } } }
            else { change { $0.props.removeAll { $0.id == propID && !$0.locked } } }
            selectedProp = nil
        } else if let id = selected {
            change { $0.buildings.removeAll { $0.id == id && !$0.locked } }; reconcileSelection()
        }
    }
    func duplicateBuilding() {
        guard var b = building else { return }; b.id = UUID(); b.origin.x += b.footprint.width+1; b.locked = false
        b.rooms = b.rooms.map { r in var r = r; r.id = UUID(); return r }
        b.furniture = b.furniture.map { p in var p = p; p.id = UUID(); return p }
        change { $0.buildings.append(b) }
    }
    func toggleFavorite(_ id: String) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
        UserDefaults.standard.set(Array(favorites),forKey:"favorites")
    }
    func beginStroke() { guard !busy, preview == nil else { return }; strokeWorld = world; strokePoints.removeAll(); roomStart = nil }
    func cancelStroke() { if let old = strokeWorld { world = old; revision += 1 }; strokeWorld = nil; roomStart = nil; strokePoints.removeAll() }
    func endStroke() {
        if let old = strokeWorld, old != world {
            do { _ = try world.validated(); history.commit(previous:old); changed() }
            catch { world = old; revision += 1; self.error = error.localizedDescription }
        }
        strokeWorld = nil; strokePoints.removeAll(); roomStart = nil
    }
    func touch(_ point: SIMD3<Float>, end: Bool = false) {
        let grid = Grid(Int(Foundation.floor(point.x)),Int(Foundation.floor(point.z)))
        guard world.contains(grid), preview == nil, !busy else { return }; cursor = grid
        if tool == .select {
            if interior, let b = building {
                let p = b.localPoint(point)
                selectedProp = b.furniture.filter { Int($0.y/3) == floor }.min(by: { hypot($0.x-p.x,$0.z-p.z) < hypot($1.x-p.x,$1.z-p.z) }).flatMap { hypot($0.x-p.x,$0.z-p.z)<1.2 ? $0.id : nil }
            } else {
                selected = world.buildings.last { $0.contains(grid) }?.id
                selectedProp = world.props.last { abs($0.x-point.x)<1 && abs($0.z-point.z)<1 }?.id
            }
            return
        }
        guard strokeWorld != nil else { return }
        if tool == .room {
            guard interior, let b = building, !b.locked else { return }
            let p = b.localPoint(point)
            if roomStart == nil { roomStart = p }
            if end, let start = roomStart {
                let x = max(1,Int(min(start.x,p.x)*4)), z = max(1,Int(min(start.z,p.z)*4))
                let width = max(4,Int(abs(start.x-p.x)*4)), depth = max(4,Int(abs(start.z-p.z)*4))
                if x+width < b.width && z+depth < b.depth, let i = world.buildings.firstIndex(where: { $0.id == b.id }) {
                    world.buildings[i].rooms.append(Room(name:"房间 \(b.rooms.count+1)",floor:floor,x:x,z:z,width:width,depth:depth)); revision += 1
                } else { error = "房间超出建筑，请从室内拖出矩形" }
            }; return
        }
        if tool == .voxel || tool == .carve {
            guard interior, let b = building, !b.locked, let i = world.buildings.firstIndex(where: { $0.id == b.id }) else { return }
            let p = b.localPoint(point), x = Int(Foundation.floor(p.x*4)), z = Int(Foundation.floor(p.z*4)), y = floor*12+voxelHeight
            guard x >= 0, x < b.width, z >= 0, z < b.depth else { return }
            world.buildings[i].edits.removeAll { $0.x == x && $0.y == y && $0.z == z }
            world.buildings[i].edits.append(VoxelEdit(x:x,y:y,z:z,material:tool == .carve ? nil : voxelMaterial)); revision += 1; return
        }
        guard strokePoints.insert(grid).inserted else { return }
        if tool == .house {
            guard strokePoints.count == 1 else { return }
            let b = Generator.house(at:grid,elevation:world.tile(at:grid).height+1,variant:houseVariant)
            var next = world; next.buildings.append(b)
            do { world = try next.validated(); selected = b.id; revision += 1 } catch { self.error = error.localizedDescription }
        } else if tool == .prop {
            guard strokePoints.count == 1 else { return }
            if interior, let b = building, !b.locked, let i = world.buildings.firstIndex(where: { $0.id == b.id }) {
                let p = b.localPoint(point)
                guard p.x >= 0, p.z >= 0, p.x < Float(b.width)/4, p.z < Float(b.depth)/4 else { return }
                world.buildings[i].furniture.append(Prop(asset:assetID,x:(p.x*4).rounded()/4,y:Float(floor*3)+0.25,z:(p.z*4).rounded()/4))
            } else if !interior { world.props.append(Prop(asset:assetID,x:Float(grid.x),y:Float(world.tile(at:grid).height+1),z:Float(grid.z))) }
            revision += 1
        } else {
            guard !interior else { return }
            for x in (grid.x-brush+1)...(grid.x+brush-1) { for z in (grid.z-brush+1)...(grid.z+brush-1) {
                let p = Grid(x,z)
                guard world.contains(p), !world.buildings.contains(where: { $0.contains(p) }) else { continue }
                var t = world.tile(at:p)
                switch tool {
                case .paint: t.surface = surface
                case .raise: t.height = min(96,t.height+1)
                case .lower: t.height = max(0,t.height-1)
                case .flatten: t.height = targetHeight
                default: break
                }
                world.setTile(t)
            } }; revision += 1
        }
    }
    func analyze() {
        let snapshot = displayWorld, rev = revision
        Task {
            let result = await Task.detached(priority:.userInitiated) { Analyzer.analyze(snapshot) }.value
            if rev == revision { report = result; reportRevision = rev }; showAnalysis = true
        }
    }
    func setPreview(_ next: World, title: String) { preview = next; previewTitle = title; previewBase = revision; revision += 1 }
    func applyPreview() {
        guard let next = preview else { return }; history.commit(previous:world); world = next; preview = nil; reconcileSelection(); changed()
    }
    func discardPreview() { preview = nil; revision += 1 }
    func generate(prompt: String, scope: DesignScope) {
        guard !busy, preview == nil else { return }
        busy = true; let snapshot = world, rev = revision, point = cursor, id = selected
        let requestID = UUID(); generationID = requestID
        generationTask = Task {
            do {
                let (next,summary) = try await DesignAssistant.generate(prompt:prompt,world:snapshot,cursor:point,selected:id,scope:scope)
                try Task.checkCancellation()
                guard revision == rev else { throw WorldError.invalid("生成期间地图已变化，请重新生成") }
                setPreview(next,title:summary); showAI = false
            } catch is CancellationError { } catch { self.error = error.localizedDescription }
            if generationID == requestID { busy = false }
        }
    }
    func cancelGeneration() { generationID = UUID(); generationTask?.cancel(); generationTask = nil; busy = false }
    func previewTemplate() {
        let b = Generator.house(at:cursor,elevation:world.tile(at:cursor).height+1,variant:houseVariant)
        let plan = DesignPlan(title:b.name,width:b.width,depth:b.depth,floors:b.floors,rooms:b.rooms,furniture:b.furniture)
        do { setPreview(try plan.applying(to:world,at:cursor),title:"离线程序模板 · \(b.name)（非 AI）"); showAI = false } catch { self.error = error.localizedDescription }
    }
    func export(_ kind: PackageKind) {
        do {
            let out: World
            switch kind {
            case .world: out = world; exportType = .moonWorld
            case .building:
                guard let b = building else { throw WorldError.invalid("先选择建筑") }; out = try DocumentCodec.building(b); exportType = .moonBuilding
            case .region:
                guard let a = regionStart, let b = regionEnd else { throw WorldError.invalid("先在工具栏标记区域起点和终点") }
                out = try DocumentCodec.region(world,from:a,to:b); exportType = .moonRegion
            }
            exportFile = ExportDocument(data:try DocumentCodec.encode(out,kind:kind)); exportName = out.name; exporting = true
        } catch { self.error = error.localizedDescription }
    }
    func importFile(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
            guard size <= DocumentCodec.maximumBytes else { throw WorldError.invalid("文件超过 32 MB") }
            let (incoming,kind) = try DocumentCodec.decode(Data(contentsOf:url,options:.mappedIfSafe))
            if kind == .world {
                var copy = incoming; copy.id = UUID()
                setPreview(copy,title:"导入独立世界：\(copy.name) · 确认后以新项目保存")
            } else { setPreview(try DocumentCodec.merge(incoming,into:world,at:cursor),title:"导入预览：\(incoming.name) · 将合并到当前光标位置") }
        } catch { self.error = error.localizedDescription }
    }
}
