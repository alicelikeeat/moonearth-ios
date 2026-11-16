import Foundation

public struct Part: Sendable {
    public var center: SIMD3<Float>
    public var size: SIMD3<Float>
    public var color: UInt32
    public init(_ center: SIMD3<Float>, _ size: SIMD3<Float>, _ color: UInt32) {
        self.center = center; self.size = size; self.color = color
    }
}

public struct Asset: Identifiable, Sendable {
    public var id: String
    public var name: String
    public var category: String
    public var kind: Int
    public var scale: SIMD3<Float>
    public var parts: [Part] { Catalog.parts(kind: kind).map { Part($0.center * scale, $0.size * scale, $0.color) } }
}

public enum Catalog {
    // Original procedural geometry; no downloaded art or licensing dependencies.
    public static let names = ["餐椅", "扶手椅", "沙发", "长凳", "餐桌", "书桌", "茶几", "床", "双层床", "衣柜", "书架", "矮柜", "橱柜", "水槽", "灶台", "浴缸", "洗手台", "马桶", "落地灯", "路灯", "花盆", "乔木", "松树", "灌木", "围栏", "路牌", "水井", "水塔", "箱子", "雕像", "拱门", "花架"]
    public static let all: [Asset] = names.enumerated().flatMap { i, name in
        let category = i < 12 ? "家具" : i < 18 ? "厨卫" : i < 21 ? "灯具装饰" : i < 24 ? "植物" : "户外设施"
        let scales: [(String, SIMD3<Float>)] = [("标准", [1,1,1]), ("窄型", [0.75,1,1]), ("宽型", [1.5,1,1]), ("加高", [1,1.5,1])]
        return scales.enumerated().map { v, item in Asset(id: "builtin.\(i).\(v)", name: name + "·" + item.0, category: category, kind: i, scale: item.1) }
    }
    public static func asset(_ id: String) -> Asset? { all.first { $0.id == id } }
    public static let placeholder = [Part([0.4,0.4,0.4], [0.8,0.8,0.8], 0xD88BA7)]
    public static func parts(kind: Int) -> [Part] {
        let wood: UInt32 = 0xA87952, dark: UInt32 = 0x4F585C, light: UInt32 = 0xE1D8C7, green: UInt32 = 0x66885D
        var p: [Part] = []
        func box(_ x: Float, _ y: Float, _ z: Float, _ w: Float, _ h: Float, _ d: Float, _ c: UInt32) { p.append(Part([x,y,z],[w,h,d],c)) }
        func legs(_ width: Float, _ depth: Float, _ height: Float) {
            for x in [Float(0.08), width-0.08] { for z in [Float(0.08), depth-0.08] { box(x,height/2,z,0.12,height,0.12,wood) } }
        }
        switch kind {
        case 0,1:
            legs(0.65,0.65,0.45); box(0.325,0.48,0.325,0.7,0.12,0.7,kind == 0 ? wood : light)
            box(0.325,0.83,0.06,0.7,0.65,0.12,wood)
            if kind == 1 { for x in [Float(0),0.65] { box(x,0.7,0.35,0.12,0.15,0.7,wood) } }
        case 2:
            box(1,0.3,0.45,2,0.5,0.9,0x839A92); box(1,0.75,0.05,2,0.65,0.2,0x839A92)
            for x in [Float(0.08),1.92] { box(x,0.6,0.45,0.2,0.5,0.9,0x839A92) }
        case 3:
            legs(1.8,0.55,0.45); box(0.9,0.48,0.275,1.9,0.12,0.6,wood)
        case 4,5,6:
            let h: Float = kind == 6 ? 0.45 : 0.8
            legs(1.5,0.85,h); box(0.75,h,0.425,1.65,0.12,0.95,wood)
            if kind == 5 { box(1.2,0.4,0.4,0.5,0.7,0.7,light); box(0.5,1.1,0.2,0.6,0.4,0.08,dark) }
        case 7,8:
            let heights: [Float] = kind == 8 ? [0.4,1.65] : [0.4]
            for y in heights { box(0.75,y,1,1.5,0.25,2,wood); box(0.75,y+0.2,1,1.4,0.2,1.9,light); box(0.75,y+0.35,0.3,0.95,0.15,0.35,0xF5F1E6) }
            box(0.75,0.6,0.05,1.6,1.2,0.15,wood)
            if kind == 8 { for x in [Float(0.05),1.45] { for z in [Float(0.05),1.95] { box(x,1.1,z,0.1,2.2,0.1,wood) } } }
        case 9,10,11:
            let h: Float = kind == 11 ? 0.9 : 2
            box(0.6,h/2,0.05,1.2,h,0.1,wood)
            for x in [Float(0.05),1.15] { box(x,h/2,0.3,0.1,h,0.6,wood) }
            for y in stride(from: Float(0.1), through: h, by: 0.45) { box(0.6,y,0.3,1.2,0.08,0.6,wood) }
            if kind == 9 { box(0.6,h/2,0.6,1.1,h-0.1,0.08,light) }
            if kind == 10 { for x in stride(from: Float(0.15), through: 1.05, by: 0.18) { box(x,0.3,0.3,0.12,0.3,0.35,0x7A909B) } }
        case 12,13,14:
            box(0.5,0.43,0.35,1,0.86,0.7,light); box(0.5,0.9,0.35,1.1,0.08,0.8,dark)
            if kind == 13 { box(0.5,0.95,0.35,0.6,0.04,0.5,0x74A8B4); box(0.5,1.15,0.05,0.08,0.4,0.08,dark) }
            if kind == 14 { for x in [Float(0.25),0.75] { box(x,0.96,0.35,0.25,0.04,0.3,0x171F25) } }
        case 15:
            box(0.45,0.12,0.9,0.9,0.24,1.8,light)
            for x in [Float(0.05),0.85] { box(x,0.35,0.9,0.1,0.6,1.8,light) }
            for z in [Float(0.05),1.75] { box(0.45,0.35,z,0.9,0.6,0.1,light) }
        case 16:
            box(0.35,0.4,0.25,0.2,0.8,0.2,light); box(0.35,0.85,0.25,0.7,0.15,0.5,light)
        case 17:
            box(0.3,0.2,0.4,0.35,0.4,0.5,light); box(0.3,0.45,0.4,0.6,0.12,0.8,light); box(0.3,0.65,0.08,0.6,0.7,0.2,light)
        case 18,19:
            let h: Float = kind == 19 ? 3 : 1.5
            box(0.3,0.05,0.3,0.6,0.1,0.6,dark); box(0.3,h/2,0.3,0.08,h,0.08,dark); box(0.3,h,0.3,0.5,0.3,0.5,0xF9DA91)
        case 20:
            box(0.3,0.2,0.3,0.6,0.4,0.6,0xB88068); box(0.3,0.65,0.3,0.45,0.6,0.45,green)
        case 21:
            box(0.7,0.9,0.7,0.3,1.8,0.3,wood); box(0.7,2,0.7,1.5,1.1,1.5,green); box(0.7,2.7,0.7,1.05,0.6,1.05,0x88A66D)
        case 22:
            box(0.6,0.6,0.6,0.25,1.2,0.25,wood)
            for n in 0..<4 { let w = Float(4-n)*0.35; box(0.6,Float(n)*0.5+0.8,0.6,w,0.55,w,green) }
        case 23:
            box(0.5,0.35,0.4,1,0.7,0.8,green); box(0.7,0.75,0.4,0.5,0.25,0.5,0x88A66D)
        case 24:
            for x in [Float(0.05),1.45] { box(x,0.6,0.1,0.12,1.2,0.2,wood) }
            for y in [Float(0.4),0.9] { box(0.75,y,0.1,1.5,0.1,0.1,wood) }
        case 25:
            box(0.5,0.9,0.1,0.12,1.8,0.12,wood); box(0.5,1.7,0.1,1,0.4,0.15,0x6D8C94)
        case 26:
            for x in [Float(0.1),1.3] { box(x,0.4,0.7,0.2,0.8,1.4,0x909997) }
            for z in [Float(0.1),1.3] { box(0.7,0.4,z,1.4,0.8,0.2,0x909997) }
            box(0.7,0.1,0.7,1,0.1,1,0x69ADB8)
        case 27:
            legs(1.5,1.5,2); box(0.75,2.5,0.75,1.7,1,1.7,0x7D9299)
        case 28:
            box(0.5,0.5,0.5,1,1,1,wood); box(0.5,1.03,0.5,1.1,0.08,1.1,light)
        case 29:
            box(0.4,0.2,0.4,0.8,0.4,0.8,dark); box(0.4,0.9,0.4,0.4,1,0.4,light); box(0.4,1.6,0.4,0.5,0.5,0.5,light)
        case 30:
            for x in [Float(0.15),1.85] { box(x,1.2,0.2,0.3,2.4,0.4,light) }; box(1,2.4,0.2,2,0.3,0.4,light)
        default:
            legs(2,2,2.3); for z in stride(from: Float(0), through: 2, by: 0.4) { box(1,2.3,z,2.2,0.15,0.1,wood) }; box(1,2.45,1,1.8,0.15,1.8,green)
        }
        return p
    }
}
