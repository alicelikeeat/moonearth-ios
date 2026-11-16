import SwiftUI
import RealityKit
import UIKit

private struct RenderItem: Sendable {
    var key: String
    var batches: [MeshBatch]
    var position: SIMD3<Float> = .zero
    var turns: Int = 0
}
private struct SceneDelta: Sendable {
    var items: [RenderItem]
    var keys: Set<String>
}

private actor SceneCompiler {
    private var chunkSignatures: [Grid:[Tile]] = [:]
    private var buildingSignatures: [UUID:Building] = [:]
    private var propSignatures: [String:Prop] = [:]
    private var previousCut: String = ""
    private var previousSize = 0
    func compile(_ world: World, selected: UUID?, floor: Int?, roof: Bool) -> SceneDelta {
        let cut = "\(selected?.uuidString ?? "")/\(floor ?? -1)/\(roof)"
        let changedCut = cut != previousCut; previousCut = cut
        let changedSize = world.size != previousSize; previousSize = world.size
        let lookup = Dictionary(uniqueKeysWithValues:world.tiles.map { ($0.position,$0) })
        let grouped = Dictionary(grouping:world.tiles) { Grid($0.position.x/16,$0.position.z/16) }
        var items: [RenderItem] = [], keys = Set<String>()
        for cx in 0..<((world.size+15)/16) { for cz in 0..<((world.size+15)/16) {
            let p = Grid(cx,cz), key = "terrain-\(cx)-\(cz)"
            keys.insert(key)
            // Include adjacent columns: changing one tile also changes neighboring exposed faces.
            let signature = (grouped[p] ?? []) + p.neighbors.flatMap { grouped[$0] ?? [] }
            if changedSize || chunkSignatures[p] != signature {
                chunkSignatures[p] = signature
                items.append(RenderItem(key:key,batches:Mesher.terrain(world,chunk:p,lookup:lookup)))
            }
        } }
        for b in world.buildings {
            let key = "building-\(b.id)"; keys.insert(key)
            if changedCut || buildingSignatures[b.id] != b {
                buildingSignatures[b.id] = b
                let position = b.worldPoint(x:0,y:0,z:0)
                items.append(RenderItem(key:key,batches:Mesher.building(b,floor:b.id == selected ? floor : nil,roof:roof),position:position,turns:b.turns))
            }
            for p in b.furniture where floor == nil || b.id != selected || p.y < Float((floor!+1)*3) {
                let key = "furniture-\(b.id)-\(p.id)"; keys.insert(key)
                // Parent transforms are cheap; build furniture only if parent changed or geometry changed.
                if changedCut || propSignatures[key] != p || items.contains(where: { $0.key == "building-\(b.id)" }) {
                    propSignatures[key] = p
                    items.append(RenderItem(key:key,batches:Mesher.prop(p),position:b.worldPoint(x:p.x,y:p.y,z:p.z),turns:(b.turns+p.turns)%4))
                }
            }
        }
        for p in world.props {
            let key = "prop-\(p.id)"; keys.insert(key)
            if propSignatures[key] != p { propSignatures[key] = p; items.append(RenderItem(key:key,batches:Mesher.prop(p),position:[p.x,p.y,p.z],turns:p.turns)) }
        }
        // Deleted items must be invalidated so undo recreates their geometry.
        propSignatures = propSignatures.filter { keys.contains($0.key) }
        buildingSignatures = buildingSignatures.filter { keys.contains("building-\($0.key)") }
        chunkSignatures = chunkSignatures.filter { keys.contains("terrain-\($0.key.x)-\($0.key.z)") }
        return SceneDelta(items:items,keys:keys)
    }
    func invalidate() { chunkSignatures.removeAll(); buildingSignatures.removeAll(); propSignatures.removeAll() }
}

struct WorldCanvas: UIViewRepresentable {
    var world: World
    var revision: Int
    var selected: UUID?
    var floor: Int?
    var roof: Bool
    var topDown: Bool
    var focus: SIMD3<Float>
    var focusToken: Int
    var store: EditorStore

    func makeCoordinator() -> Coordinator { Coordinator(store:store) }
    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame:.zero,cameraMode:.nonAR,automaticallyConfigureSession:false)
        view.environment.background = .color(UIColor(red:0.81,green:0.86,blue:0.86,alpha:1))
        context.coordinator.install(view)
        return view
    }
    func updateUIView(_ view: ARView, context: Context) {
        context.coordinator.update(self)
    }
    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) { coordinator.renderTask?.cancel(); uiView.scene.anchors.removeAll() }

    @MainActor final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let store: EditorStore
        weak var view: ARView?
        let root = AnchorEntity(world:.zero)
        let camera = PerspectiveCamera()
        var entities: [String:Entity] = [:]
        private let compiler = SceneCompiler()
        var renderTask: Task<Void,Never>?
        private var pendingInput: WorldCanvas?
        private var renderedRevision = -1
        private var renderedCut = ""
        private var token = -1
        private var focus = SIMD3<Float>(26,1,27)
        private var yaw: Float = .pi/4
        private var pitch: Float = 0.85
        private var distance: Float = 36
        private var topDown = false
        private var panStart = CGPoint.zero
        private var terrainLookup: [Grid:Tile] = [:]
        private var overlay = Entity()
        init(store: EditorStore) { self.store = store }
        func install(_ view: ARView) {
            self.view = view; view.scene.addAnchor(root)
            camera.camera.fieldOfViewInDegrees = 48; root.addChild(camera)
            let sun = DirectionalLight(); sun.light.intensity = 1800
            sun.look(at:.zero,from:[-20,40,15],relativeTo:nil); root.addChild(sun)
            let fill = DirectionalLight(); fill.light.intensity = 700
            fill.look(at:.zero,from:[20,20,-20],relativeTo:nil); root.addChild(fill)
            root.addChild(overlay)
            let tap = UITapGestureRecognizer(target:self,action:#selector(tap(_:)))
            let one = UIPanGestureRecognizer(target:self,action:#selector(onePan(_:))); one.maximumNumberOfTouches = 1
            let two = UIPanGestureRecognizer(target:self,action:#selector(twoPan(_:))); two.minimumNumberOfTouches = 2; two.maximumNumberOfTouches = 2
            let pinch = UIPinchGestureRecognizer(target:self,action:#selector(pinch(_:)))
            tap.require(toFail:one); tap.require(toFail:two)
            for gesture in [tap,one,two,pinch] { gesture.delegate = self; view.addGestureRecognizer(gesture) }
            updateCamera()
        }
        func update(_ input: WorldCanvas) {
            topDown = input.topDown
            if token != input.focusToken { token = input.focusToken; focus = input.focus; distance = store.interior ? 16 : 36 }
            updateCamera()
            let cut = "\(input.selected?.uuidString ?? "")/\(input.floor ?? -1)/\(input.roof)"
            guard renderedRevision != input.revision || renderedCut != cut else { return }
            renderedRevision = input.revision; renderedCut = cut
            terrainLookup = Dictionary(uniqueKeysWithValues:input.world.tiles.map { ($0.position,$0) })
            pendingInput = input
            guard renderTask == nil else { return }
            renderTask = Task {
              while let input = pendingInput {
                pendingInput = nil
                let delta = await compiler.compile(input.world,selected:input.selected,floor:input.floor,roof:input.roof)
                guard !Task.isCancelled else { await compiler.invalidate(); renderTask = nil; return }
                do {
                    for key in Array(entities.keys) where !delta.keys.contains(key) { entities.removeValue(forKey:key)?.removeFromParent() }
                    for item in delta.items {
                        let entity = Entity(); entity.name = item.key
                        for batch in item.batches {
                            var descriptor = MeshDescriptor(name:item.key)
                            descriptor.positions = MeshBuffers.Positions(batch.positions)
                            descriptor.normals = MeshBuffers.Normals(batch.normals)
                            descriptor.primitives = .triangles(batch.indices)
                            let mesh = try MeshResource.generate(from:[descriptor])
                            let color = UIColor(red:CGFloat((batch.color>>16)&255)/255,green:CGFloat((batch.color>>8)&255)/255,blue:CGFloat(batch.color&255)/255,alpha:1)
                            let material = SimpleMaterial(color:color,roughness:1,isMetallic:false)
                            entity.addChild(ModelEntity(mesh:mesh,materials:[material]))
                        }
                        entity.position = item.position
                        entity.orientation = simd_quatf(angle:Float(item.turns)*Float.pi/2,axis:[0,1,0])
                        entities.removeValue(forKey:item.key)?.removeFromParent(); entities[item.key] = entity; root.addChild(entity)
                    }
                    updateOverlay(input.world)
                } catch { store.error = "场景网格生成失败：\(error.localizedDescription)"; await compiler.invalidate() }
              }
              renderTask = nil
            }
        }
        private func updateOverlay(_ world: World) {
            overlay.children.removeAll()
            if let b = world.buildings.first(where: { $0.id == store.selected }) {
                let f = b.footprint, w = Float(f.width), d = Float(f.depth), y = Float(b.elevation)+0.08
                let material = UnlitMaterial(color:.systemMint)
                for (center,size) in [(SIMD3(w/2,y,0),SIMD3(w,0.06,0.06)),(SIMD3(w/2,y,d),SIMD3(w,0.06,0.06)),(SIMD3(0,y,d/2),SIMD3(0.06,0.06,d)),(SIMD3(w,y,d/2),SIMD3(0.06,0.06,d))] {
                    let line = ModelEntity(mesh:.generateBox(size:size),materials:[material]); line.position = center + [Float(b.origin.x),0,Float(b.origin.z)]; overlay.addChild(line)
                }
            }
        }
        private func updateCamera() {
            let p: Float = topDown ? 1.54 : pitch
            let offset = SIMD3<Float>(sin(yaw)*cos(p),sin(p),cos(yaw)*cos(p))*distance
            camera.look(at:focus,from:focus+offset,relativeTo:nil)
        }
        private func point(_ screen: CGPoint) -> SIMD3<Float>? {
            guard let ray = view?.ray(through:screen) else { return nil }
            if store.interior, let b = store.building {
                let level = Float(b.elevation+store.floor*3)+(store.tool == .voxel || store.tool == .carve ? Float(store.voxelHeight)/4 : 0.25)
                guard abs(ray.direction.y)>0.0001 else { return nil }
                let t = (level-ray.origin.y)/ray.direction.y
                return t > 0 ? ray.origin+ray.direction*t : nil
            }
            // Terrain heightfield picking avoids one collider per voxel.
            for step in 0..<2400 {
                let p = ray.origin+ray.direction*(Float(step)*0.25)
                let grid = Grid(Int(floor(p.x)),Int(floor(p.z)))
                if store.world.contains(grid), p.y <= Float((terrainLookup[grid]?.height ?? 0)+1), p.y >= 0 { return p }
            }
            return nil
        }
        @objc private func tap(_ gesture: UITapGestureRecognizer) {
            guard !store.presentation, let p = point(gesture.location(in:view)) else { return }
            store.beginStroke(); store.touch(p,end:true); store.endStroke(); updateOverlay(store.world)
        }
        @objc private func onePan(_ gesture: UIPanGestureRecognizer) {
            if store.tool == .select || store.presentation || store.isPreviewing {
                let t = gesture.translation(in:view); gesture.setTranslation(.zero,in:view)
                yaw -= Float(t.x)*0.006; pitch = min(1.5,max(0.15,pitch+Float(t.y)*0.006)); updateCamera(); return
            }
            switch gesture.state {
            case .began: store.beginStroke(); if let p = point(gesture.location(in:view)) { store.touch(p) }
            case .changed: if let p = point(gesture.location(in:view)) { store.touch(p) }
            case .ended: if let p = point(gesture.location(in:view)) { store.touch(p,end:true) }; store.endStroke()
            case .cancelled,.failed: store.cancelStroke()
            default: break
            }
        }
        @objc private func twoPan(_ gesture: UIPanGestureRecognizer) {
            if gesture.state == .began { store.cancelStroke() }
            let t = gesture.translation(in:view); gesture.setTranslation(.zero,in:view)
            let scale = distance*0.0015
            focus += SIMD3<Float>(-Float(t.x)*cos(yaw)-Float(t.y)*sin(yaw),0,Float(t.x)*sin(yaw)-Float(t.y)*cos(yaw))*scale
            updateCamera()
        }
        @objc private func pinch(_ gesture: UIPinchGestureRecognizer) {
            if gesture.state == .began { store.cancelStroke() }
            distance = min(500,max(3,distance/Float(gesture.scale))); gesture.scale = 1; updateCamera()
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            gestureRecognizer is UIPinchGestureRecognizer || otherGestureRecognizer is UIPinchGestureRecognizer
        }
    }
}
