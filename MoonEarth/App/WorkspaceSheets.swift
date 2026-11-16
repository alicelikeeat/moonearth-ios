import SwiftUI

struct AssetLibrary: View {
    @Bindable var store: EditorStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var category = "全部"
    var assets: [Asset] {
        Catalog.all.filter { (category == "全部" || (category == "收藏" ? store.favorites.contains($0.id) : $0.category == category)) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns:[GridItem(.adaptive(minimum:140))],spacing:12) {
                    ForEach(assets) { asset in
                        VStack(alignment:.leading,spacing:8) {
                            Button {
                                store.assetID = asset.id; store.tool = .prop; dismiss()
                            } label: {
                                VStack(spacing:8) {
                                    AssetThumbnail(parts:asset.parts).frame(height:100)
                                    Text(asset.name).font(.subheadline).lineLimit(2)
                                }.frame(maxWidth:.infinity).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            HStack { Text(asset.category).font(.caption).foregroundStyle(.secondary); Spacer(); Button { store.toggleFavorite(asset.id) } label: { Image(systemName:store.favorites.contains(asset.id) ? "star.fill" : "star").frame(width:44,height:44) }.accessibilityLabel("收藏 \(asset.name)") }
                        }.padding(10).background(.quaternary,in:RoundedRectangle(cornerRadius:16))
                    }
                }.padding()
            }.searchable(text:$search,prompt:"搜索家具、植物、设施")
                .safeAreaInset(edge:.top) {
                    ScrollView(.horizontal,showsIndicators:false) { HStack { ForEach(["全部","收藏","家具","厨卫","灯具装饰","植物","户外设施"],id:\.self) { item in Button(item) { category = item }.buttonStyle(.bordered).tint(category == item ? .teal : .secondary) } }.padding(.horizontal) }
                }.navigationTitle("素材库 · 128 个尺寸变体").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("完成") { dismiss() } }
        }
    }
}

/// Orthographic isometric thumbnails generated from the same editable parts as 3D meshes.
struct AssetThumbnail: View {
    var parts: [Part]
    var body: some View {
        Canvas { context, size in
            func project(_ p: SIMD3<Float>) -> CGPoint { CGPoint(x:Double(p.x-p.z)*0.866,y:Double(p.x+p.z)*0.42-Double(p.y)) }
            let points = parts.flatMap { part -> [CGPoint] in
                let a = part.center-part.size/2, b = part.center+part.size/2
                return [project(a),project(b),project([a.x,b.y,a.z]),project([b.x,a.y,b.z]),project([a.x,a.y,b.z]),project([b.x,b.y,a.z])]
            }
            let minX = points.map(\.x).min() ?? 0, maxX = points.map(\.x).max() ?? 1
            let minY = points.map(\.y).min() ?? 0, maxY = points.map(\.y).max() ?? 1
            let scale = min((size.width-12)/max(0.1,maxX-minX),(size.height-12)/max(0.1,maxY-minY))
            func pt(_ p: SIMD3<Float>) -> CGPoint { let q = project(p); return CGPoint(x:(q.x-(minX+maxX)/2)*scale+size.width/2,y:(q.y-(minY+maxY)/2)*scale+size.height/2) }
            for part in parts.sorted(by:{ $0.center.x+$0.center.z < $1.center.x+$1.center.z }) {
                let a = part.center-part.size/2, b = part.center+part.size/2
                let faces: [([SIMD3<Float>],Double)] = [([[a.x,b.y,a.z],[b.x,b.y,a.z],[b.x,b.y,b.z],[a.x,b.y,b.z]],1),([[a.x,a.y,b.z],[a.x,b.y,b.z],[b.x,b.y,b.z],[b.x,a.y,b.z]],0.85),([[b.x,a.y,a.z],[b.x,b.y,a.z],[b.x,b.y,b.z],[b.x,a.y,b.z]],0.65)]
                for (corners,brightness) in faces {
                    var path = Path(); path.move(to:pt(corners[0])); for p in corners.dropFirst() { path.addLine(to:pt(p)) }; path.closeSubpath()
                    let c = part.color
                    context.fill(path,with:.color(Color(red:Double((c>>16)&255)/255*brightness,green:Double((c>>8)&255)/255*brightness,blue:Double(c&255)/255*brightness)))
                }
            }
        }.accessibilityHidden(true)
    }
}

struct AssistantSheet: View {
    @Bindable var store: EditorStore
    @Environment(\.dismiss) private var dismiss
    @State private var prompt = "设计一栋两层住宅，一楼有客厅和厨房，二楼有卧室。保留连接房门与楼梯的走廊。"
    @State private var scope: DesignScope = .house
    var body: some View {
        NavigationStack {
            Form {
                Section("AI 设计") {
                    Picker("范围",selection:$scope) { ForEach(DesignScope.allCases,id:\.self) { Text($0.rawValue).tag($0) } }
                    TextEditor(text:$prompt).frame(minHeight:130)
                    Text("\(prompt.count)/1000 字 · 放置位置 \(store.cursor.x),\(store.cursor.z)").font(.caption).foregroundStyle(.secondary)
                    if let message = DesignAssistant.availability { Label(message,systemImage:"info.circle").foregroundStyle(.secondary) }
                    Button("生成可编辑方案",systemImage:"sparkles") { store.generate(prompt:prompt,scope:scope) }
                        .disabled(store.busy || DesignAssistant.availability != nil || prompt.isEmpty || prompt.count>1000 || (scope == .interior && store.building == nil))
                    if store.busy { ProgressView("模型生成中"); Button("取消") { store.cancelGeneration() } }
                }
                Section("工作方式") {
                    Text("使用设备上的 Apple Foundation Models，不上传世界数据，不需要 API Key。设备或地区不支持时会明确提示。生成结果经过尺寸校验后进入三维预览；检查通行问题，再确认应用。").font(.footnote)
                    Text("室内模式会替换当前建筑的房间和未锁定家具；锁定物件保留。AI 不能保证一次布局就合理，所有内容均可继续编辑。").font(.footnote)
                }
                Section("离线程序模板 · 非 AI") {
                    Stepper("建筑模板 \(store.houseVariant+1)/12",value:$store.houseVariant,in:0...11)
                    Button("预览模板建筑") { store.previewTemplate() }.disabled(store.busy)
                    Text("按确定的规则生成，不理解上方的自然语言描述。").font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("设计助手").toolbar { Button("关闭") { dismiss() } }
        }
    }
}

struct AnalysisSheet: View {
    @Bindable var store: EditorStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if let report = store.report, store.reportRevision == store.revision {
                    Section("地图统计") {
                        LabeledContent("建筑占地",value:"\(report.buildingArea) m²")
                        LabeledContent("水域面积",value:"\(report.waterArea) m²")
                        LabeledContent("道路连通组",value:"\(report.roadComponents)")
                    }
                    Section("检查结果（最多显示 200 项）") {
                        if report.findings.isEmpty { Label("未发现当前规则覆盖的问题",systemImage:"checkmark.circle") }
                        ForEach(report.findings) { finding in Button { store.selected = finding.buildingID; store.focus(finding.position); dismiss() } label: { Label(finding.message,systemImage:"location.circle") } }
                    }
                    Section { Text("虚构世界检查，不是建筑安全或消防规范认证。室内使用 0.5 米宽、1.75 米高的简化通行模型；家具采用保守包围盒。道路容许相邻格高度差不超过 1 米。").font(.footnote).foregroundStyle(.secondary) }
                } else { ProgressView("分析中，或结果已过期…"); Button("重新分析") { store.analyze() } }
            }.navigationTitle("世界分析").toolbar { Button("完成") { dismiss() } }
        }
    }
}
