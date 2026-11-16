import SwiftUI

@main
struct MoonEarthApp: App {
    @State private var store = EditorStore()
    var body: some Scene { WindowGroup { ProjectHome(store:store) } }
}

struct GlassPanel: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if reduceTransparency { content.background(.background,in:RoundedRectangle(cornerRadius:22)) }
        else { content.glassEffect(.regular,in:RoundedRectangle(cornerRadius:22)) }
    }
}
extension View { func studioGlass() -> some View { modifier(GlassPanel()) } }

struct ProjectHome: View {
    @Bindable var store: EditorStore
    @State private var editing = false
    @State private var newSheet = false
    @State private var openCreatedProject = false
    @State private var template: WorldTemplate = .plain
    @State private var size = 128
    @State private var seed = "42"
    @State private var deleting: World?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:24) {
                    VStack(alignment:.leading,spacing:8) {
                        Text("MOON EARTH").font(.caption.monospaced()).tracking(4).foregroundStyle(.secondary)
                        Text("从一块土地，\n到一盏灯。").font(.largeTitle.bold())
                        Text("构建你的像素世界 · 设计每一层生活").foregroundStyle(.secondary)
                    }.padding(.vertical,20)
                    HStack {
                        Button("创建世界",systemImage:"plus") { newSheet = true }.buttonStyle(.borderedProminent).accessibilityIdentifier("new-world")
                        Button("打开示例",systemImage:"sparkles") { store.open(Generator.demo()); editing = true }.buttonStyle(.bordered)
                        Button("导入",systemImage:"square.and.arrow.down") { store.importing = true }.buttonStyle(.bordered)
                    }
                    Text("我的项目").font(.title2.bold())
                    if store.projects.isEmpty { ContentUnavailableView("你的第一座世界",systemImage:"square.stack.3d.up",description:Text("从空白、平原、岛屿或山谷开始。")) }
                    LazyVGrid(columns:[GridItem(.adaptive(minimum:230))],spacing:16) {
                        ForEach(store.projects) { project in
                            Button { store.open(project); editing = true } label: {
                                VStack(alignment:.leading,spacing:14) {
                                    Image(systemName:"building.2.crop.circle").font(.system(size:42)).foregroundStyle(.teal)
                                    Text(project.name).font(.headline).foregroundStyle(.primary)
                                    Text("\(project.size) × \(project.size) · \(project.buildings.count) 栋建筑").font(.caption).foregroundStyle(.secondary)
                                }.frame(maxWidth:.infinity,alignment:.leading).padding(22).studioGlass()
                            }.buttonStyle(.plain).contextMenu {
                                Button("复制项目") { Task { await store.duplicateProject(project) } }
                                Button("删除",role:.destructive) { deleting = project }
                            }
                        }
                    }
                    Button("恢复已删除项目",systemImage:"arrow.uturn.backward") { Task { await store.restoreTrash() } }.font(.footnote)
                }.padding(24).frame(maxWidth:1100,alignment:.leading).frame(maxWidth:.infinity)
            }.background(Color(red:0.93,green:0.95,blue:0.93))
                .navigationTitle("Moon Earth").navigationBarTitleDisplayMode(.inline)
                .fullScreenCover(isPresented:$editing,onDismiss:{ Task { await store.loadProjects() } }) { EditorView(store:store) }
                .sheet(isPresented:$newSheet,onDismiss:{
                    if openCreatedProject { openCreatedProject = false; editing = true }
                }) {
                    NavigationStack {
                        Form {
                            Picker("模板",selection:$template) { ForEach(WorldTemplate.allCases,id:\.self) { Text($0.rawValue).tag($0) } }
                            Picker("尺寸",selection:$size) { ForEach([128,256,512],id:\.self) { Text("\($0) × \($0)").tag($0) } }
                            TextField("随机种子",text:$seed).keyboardType(.numberPad)
                            Text("地图格为 1 米，建筑细节格为 0.25 米。较大地图需要更多内存。").font(.footnote).foregroundStyle(.secondary)
                        }.navigationTitle("新建世界").toolbar {
                            ToolbarItem(placement:.cancellationAction) { Button("取消") { newSheet = false } }
                            ToolbarItem(placement:.confirmationAction) { Button("创建") { store.newProject(template:template,size:size,seed:UInt64(seed) ?? 42); openCreatedProject = true; newSheet = false }.accessibilityIdentifier("confirm-create") }
                        }
                    }.presentationDetents([.medium])
                }
                .fileImporter(isPresented:$store.importing,allowedContentTypes:[.moonWorld,.moonRegion,.moonBuilding]) { result in
                    switch result {
                    case .success(let url): store.open(Generator.world(template:.blank)); store.importFile(url); if store.preview != nil { editing = true }
                    case .failure(let error): store.error = error.localizedDescription
                    }
                }
                .confirmationDialog("删除这个项目？可在首页恢复。",isPresented:Binding(get:{ deleting != nil },set:{ if !$0 { deleting = nil } })) {
                    Button("删除",role:.destructive) { if let project = deleting { Task { await store.deleteProject(project) } }; deleting = nil }
                }
                .alert("提示",isPresented:Binding(get:{ store.error != nil && !editing },set:{ if !$0 { store.error = nil } })) { Button("好") { store.error = nil } } message: { Text(store.error ?? "") }
                .onOpenURL { url in store.importFile(url); if store.preview != nil { editing = true } }
                .task { await store.loadProjects() }
        }
    }
}
