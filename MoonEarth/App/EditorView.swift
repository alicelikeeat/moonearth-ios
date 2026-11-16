import SwiftUI

struct EditorView: View {
    @Bindable var store: EditorStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var renaming = false
    @State private var name = ""
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                WorldCanvas(world:store.displayWorld,revision:store.revision,selected:store.selected,floor:store.interior ? store.floor : nil,roof:store.roof,topDown:store.topDown,focus:store.cameraFocus,focusToken:store.focusToken,store:store)
                    .ignoresSafeArea()
                VStack(spacing:10) {
                    topBar
                    if store.isPreviewing { previewBar }
                    HStack(alignment:.top) {
                        if !store.presentation { tools }
                        Spacer(minLength:0)
                        if !store.presentation && store.showInspector && geometry.size.width > 650 { InspectorView(store:store).frame(width:260).padding(14).studioGlass() }
                    }
                    Spacer(minLength:0)
                    if !store.presentation { bottomBar }
                }.padding(12)
                if store.busy {
                    VStack(spacing:16) { ProgressView(); Text("正在生成可编辑方案…"); Button("取消生成") { store.cancelGeneration() } }.padding(24).studioGlass()
                }
            }
            .sheet(isPresented:$store.showLibrary) { AssetLibrary(store:store) }
            .sheet(isPresented:$store.showAI) { AssistantSheet(store:store) }
            .sheet(isPresented:$store.showAnalysis) { AnalysisSheet(store:store) }
            .sheet(isPresented:Binding(get:{ store.showInspector && geometry.size.width <= 650 },set:{ store.showInspector = $0 })) {
                NavigationStack { ScrollView { InspectorView(store:store).padding() }.navigationTitle("属性").toolbar { Button("完成") { store.showInspector = false } } }.presentationDetents([.medium,.large])
            }
        }
        .fileExporter(isPresented:$store.exporting,document:store.exportFile,contentType:store.exportType,defaultFilename:store.exportName) { result in if case .failure(let error) = result { store.error = error.localizedDescription } }
        .fileImporter(isPresented:$store.importing,allowedContentTypes:[.moonWorld,.moonRegion,.moonBuilding]) { result in
            switch result { case .success(let url): store.importFile(url); case .failure(let error): store.error = error.localizedDescription }
        }
        .alert("提示",isPresented:Binding(get:{ store.error != nil },set:{ if !$0 { store.error = nil } })) { Button("好") { store.error = nil } } message: { Text(store.error ?? "") }
        .alert("项目名称",isPresented:$renaming) { TextField("名称",text:$name); Button("保存") { store.change { $0.name = String(name.prefix(100)) } }; Button("取消",role:.cancel) {} }
        .onChange(of:phase) { _, next in if next != .active { Task { await store.flush() } } }
    }
    private var topBar: some View {
        HStack(spacing:12) {
            Button { Task { await store.flush(); if store.saveStatus == "已保存" { dismiss() } } } label: { Image(systemName:"chevron.left").frame(width:44,height:44) }.accessibilityLabel("保存并返回项目").accessibilityIdentifier("save-back")
            VStack(alignment:.leading,spacing:2) {
                Text(store.displayWorld.name).font(.headline).lineLimit(1)
                Text(store.saveStatus).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if !store.presentation {
                Button { store.undo() } label: { Image(systemName:"arrow.uturn.backward").frame(width:44,height:44) }.disabled(!store.history.canUndo || store.isPreviewing || store.busy).accessibilityLabel("撤销")
                Button { store.redo() } label: { Image(systemName:"arrow.uturn.forward").frame(width:44,height:44) }.disabled(!store.history.canRedo || store.isPreviewing || store.busy).accessibilityLabel("重做")
                Button { store.showAI = true } label: { Label("AI",systemImage:"sparkles").frame(minHeight:44) }.disabled(store.isPreviewing || store.busy).accessibilityIdentifier("design-assistant")
            }
            Menu {
                Button("重命名",systemImage:"pencil") { name = store.world.name; renaming = true }.disabled(store.isPreviewing)
                Button("立即保存",systemImage:"square.and.arrow.down") { Task { await store.flush() } }
                Button("导入文件") { store.importing = true }.disabled(store.isPreviewing)
                Button("导出完整世界") { store.export(.world) }
                Button("导出选中建筑") { store.export(.building) }.disabled(store.building == nil)
                Button("导出标记区域") { store.export(.region) }
                Button("MoonPixel 兼容状态") { store.error = MoonPixelBridge.status }
            } label: { Image(systemName:"ellipsis").frame(width:44,height:44) }
            Button { store.presentation.toggle() } label: { Image(systemName:store.presentation ? "pencil" : "eye").frame(width:44,height:44) }.accessibilityLabel(store.presentation ? "恢复编辑界面" : "隐藏编辑工具")
        }.padding(.horizontal,10).studioGlass()
    }
    private var tools: some View {
        ScrollView(.vertical) {
            VStack(spacing:4) {
                ForEach(EditorTool.allCases,id:\.self) { tool in
                    Button { store.tool = tool; if tool == .prop { store.showLibrary = true } } label: {
                        VStack(spacing:3) { Image(systemName:tool.symbol).font(.title3); Text(tool.rawValue).font(.caption2) }
                            .frame(width:52,height:49).background(store.tool == tool ? Color.teal.opacity(0.18) : .clear,in:RoundedRectangle(cornerRadius:12))
                    }.disabled(store.isPreviewing || store.busy || ([EditorTool.room,.voxel,.carve].contains(tool) && !store.interior))
                }
            }.padding(6)
        }.frame(width:64).fixedSize(horizontal:false,vertical:false).studioGlass()
    }
    private var bottomBar: some View {
        ScrollView(.horizontal,showsIndicators:false) {
            HStack(spacing:16) {
                Label("\(store.cursor.x), \(store.cursor.z)",systemImage:"scope").font(.caption.monospaced())
                Button(store.topDown ? "透视" : "俯视",systemImage:"square.3.layers.3d") { store.topDown.toggle() }
                Button("属性",systemImage:"slider.horizontal.3") { store.showInspector.toggle() }
                Button("素材",systemImage:"square.grid.2x2") { store.showLibrary = true }
                Button("分析",systemImage:"chart.bar.xaxis") { store.analyze() }
                if store.interior {
                    Button("退出室内",systemImage:"arrow.up.left.and.arrow.down.right") { store.interior = false; store.roof = true; store.tool = .select }
                    Picker("楼层",selection:$store.floor) { ForEach(0..<(store.building?.floors ?? 1),id:\.self) { Text("\($0+1)楼").tag($0) } }.frame(width:90)
                } else if store.building != nil { Button("进入室内",systemImage:"door.left.hand.open") { store.enterBuilding() } }
                Menu("区域") { Button("标记起点") { store.regionStart = store.cursor }; Button("标记终点") { store.regionEnd = store.cursor }; Button("清除标记") { store.regionStart = nil; store.regionEnd = nil } }
            }.buttonStyle(.borderless).frame(minHeight:44).padding(.horizontal,16)
        }.studioGlass()
    }
    private var previewBar: some View {
        HStack {
            VStack(alignment:.leading) { Text("方案预览 · 尚未写入").font(.headline); Text(store.previewTitle).font(.caption).lineLimit(2) }
            Spacer()
            Button("检查") { store.analyze() }
            Button("取消") { store.discardPreview() }
            Button("应用") { store.applyPreview() }.buttonStyle(.borderedProminent).accessibilityIdentifier("apply-preview")
        }.padding(12).studioGlass()
    }
}

struct InspectorView: View {
    @Bindable var store: EditorStore
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:14) {
                Text(store.interior ? "室内工作台" : "世界工作台").font(.headline)
                Text(store.tool == .select ? "单指旋转 · 双指平移 · 捏合缩放\n点击选择建筑，进入室内设计。" : "单指绘制 · 双指平移\n每次笔画可整体撤销。").font(.caption).foregroundStyle(.secondary)
                if [.paint,.raise,.lower,.flatten].contains(store.tool) {
                    Stepper("笔刷：\(store.brush*2-1) 格",value:$store.brush,in:1...5)
                    Picker("地表",selection:$store.surface) { ForEach(Surface.allCases,id:\.self) { Text($0.name).tag($0) } }
                    if store.tool == .flatten { Stepper("目标高度 \(store.targetHeight)",value:$store.targetHeight,in:0...96) }
                }
                if store.tool == .house { Stepper("建筑模板 \(store.houseVariant+1)/12",value:$store.houseVariant,in:0...11); Text("点击地图放置，可进入室内继续编辑。").font(.caption) }
                if store.tool == .prop { Text(Catalog.asset(store.assetID)?.name ?? "未知素材"); Button("选择素材") { store.showLibrary = true } }
                if store.tool == .voxel || store.tool == .carve {
                    Stepper("楼层内高度：\(store.voxelHeight) 格",value:$store.voxelHeight,in:0...11)
                    Picker("材质",selection:$store.voxelMaterial) { ForEach(0..<7) { Text(["墙面","木材","屋顶","窗玻璃","暖色砖","石材","植物"][$0]).tag($0) } }
                    Text("细节格 0.25 米；开洞工具可雕刻门窗与内部空间。").font(.caption)
                }
                if store.tool == .room { Text("在地板上拖出矩形。房间自动生成内墙和门洞；靠东侧保留楼梯空间。").font(.caption) }
                Divider()
                if let b = store.building {
                    Text(b.name).font(.headline)
                    Text("\(b.width/4) × \(b.depth/4) 米 · \(b.floors) 层").font(.caption)
                    Toggle("锁定建筑",isOn:Binding(get:{ b.locked },set:{ _ in store.toggleBuildingLock() }))
                    if !b.locked {
                        TextField("建筑名称",text:Binding(get:{ b.name },set:{ value in store.updateBuilding { $0.name = String(value.prefix(100)) } }))
                        Stepper("宽度 \(Float(b.width)/4,specifier:"%.2f") m",value:Binding(get:{ b.width },set:{ value in store.updateBuilding { $0.width = value } }),in:16...96)
                        Stepper("进深 \(Float(b.depth)/4,specifier:"%.2f") m",value:Binding(get:{ b.depth },set:{ value in store.updateBuilding { $0.depth = value } }),in:16...96)
                        Stepper("楼层 \(b.floors)",value:Binding(get:{ b.floors },set:{ count in store.updateBuilding { building in building.floors = count; building.rooms.removeAll { $0.floor >= count }; building.furniture.removeAll { $0.y >= Float(count*3) }; building.edits.removeAll { $0.y > count*12 }; }; store.floor = min(store.floor,count-1) }),in:1...6)
                        HStack { Button("旋转 90°") { store.updateBuilding { $0.turns = ($0.turns+1)%4 } }; Button("复制") { store.duplicateBuilding() } }
                        HStack { Button("←") { store.updateBuilding { $0.origin.x -= 1 } }; Button("→") { store.updateBuilding { $0.origin.x += 1 } }; Button("↑") { store.updateBuilding { $0.origin.z -= 1 } }; Button("↓") { store.updateBuilding { $0.origin.z += 1 } } }.frame(minHeight:44)
                    }
                    if !store.interior { Button("进入室内") { store.enterBuilding() } }
                    Toggle("显示屋顶",isOn:$store.roof).disabled(store.interior)
                    ForEach(b.rooms.filter { !store.interior || $0.floor == store.floor }) { room in
                        DisclosureGroup("\(room.name) · \(room.squareMetres,specifier:"%.1f") m²") {
                            RoomControls(store:store,room:room).disabled(b.locked)
                        }
                    }
                    if store.selectedProp != nil { FurnitureControls(store:store) }
                    Button("删除选中对象",role:.destructive) { store.removeSelected() }.disabled(b.locked)
                } else if store.selectedProp != nil { FurnitureControls(store:store); Button("删除物件",role:.destructive) { store.removeSelected() } }
                else { Text("选择建筑后可编辑楼层、室内结构和家具。").font(.caption).foregroundStyle(.secondary) }
                if let a = store.regionStart { Text("区域起点 \(a.x),\(a.z)").font(.caption) }
                if let b = store.regionEnd { Text("区域终点 \(b.x),\(b.z)").font(.caption) }
            }.font(.subheadline).disabled(store.isPreviewing || store.busy)
        }
    }
}

struct RoomControls: View {
    @Bindable var store: EditorStore
    let room: Room
    func edit(_ action: (inout Room) -> Void) {
        store.updateBuilding { b in if let i = b.rooms.firstIndex(where:{ $0.id == room.id }) { action(&b.rooms[i]) } }
    }
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            TextField("房间名称",text:Binding(get:{ room.name },set:{ name in edit { $0.name = String(name.prefix(80)) } }))
            Stepper("宽 \(Float(room.width)/4,specifier:"%.2f") m",value:Binding(get:{ room.width },set:{ value in edit { $0.width = value } }),in:4...80)
            Stepper("深 \(Float(room.depth)/4,specifier:"%.2f") m",value:Binding(get:{ room.depth },set:{ value in edit { $0.depth = value } }),in:4...80)
            HStack { Button("←") { edit { $0.x -= 1 } }; Button("→") { edit { $0.x += 1 } }; Button("↑") { edit { $0.z -= 1 } }; Button("↓") { edit { $0.z += 1 } } }.frame(minHeight:44)
            Button("删除房间分隔",role:.destructive) { store.updateBuilding { $0.rooms.removeAll { $0.id == room.id } } }
        }.padding(.top,8)
    }
}

struct FurnitureControls: View {
    @Bindable var store: EditorStore
    var prop: Prop? { (store.interior ? store.building?.furniture ?? [] : store.world.props).first { $0.id == store.selectedProp } }
    func edit(_ action: (inout Prop) -> Void, allowLocked: Bool = false) {
        guard let id = store.selectedProp else { return }
        if store.interior { store.updateBuilding { b in if let i = b.furniture.firstIndex(where: { $0.id == id }), allowLocked || !b.furniture[i].locked { action(&b.furniture[i]) } } }
        else { store.change { w in if let i = w.props.firstIndex(where: { $0.id == id }), allowLocked || !w.props[i].locked { action(&w.props[i]) } } }
    }
    var body: some View {
        if let p = prop {
            VStack(alignment:.leading,spacing:10) {
                Text(Catalog.asset(p.asset)?.name ?? p.asset).font(.headline)
                Toggle("锁定物件",isOn:Binding(get:{ p.locked },set:{ _ in edit({ $0.locked.toggle() },allowLocked:true) }))
                if !p.locked {
                    Button("旋转家具 90°") { edit { $0.turns = ($0.turns+1)%4 } }
                    HStack { Button("←") { edit { $0.x -= 0.25 } }; Button("→") { edit { $0.x += 0.25 } }; Button("↑") { edit { $0.z -= 0.25 } }; Button("↓") { edit { $0.z += 0.25 } } }.frame(minHeight:44)
                }
            }
        }
    }
}
