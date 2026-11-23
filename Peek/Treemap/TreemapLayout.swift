import CoreGraphics
import Foundation

/// 方块视图的纯计算:squarified treemap 布局,以及哪些条目单独成块、哪些合并成"其他"。
/// 磁盘分析的规格见 `docs/analyze-treemap.md`;测试见 `PeekTests/AnalyzeTreemapTests.swift`
/// 和 `PeekTests/TreemapTilesTests.swift`。
enum TreemapLayout {
    /// 方块数量上限(含"其他")。
    static let maxTiles = 80
    /// 占总量不到这个比例的条目并进"其他"。
    static let minFraction = 0.002

    /// 按大小从大到小排好的 `sizes` 里,前多少个单独成块。其余的(如果有)合并成"其他"。
    /// 大小为 0 的不算;只剩 1 项要合并时直接单独成块,不出"其他"。
    static func individualCount(
        sizes: [UInt64],
        maxTiles: Int = maxTiles,
        minFraction: Double = minFraction
    ) -> Int {
        let positive = sizes.prefix { $0 > 0 }.count
        guard positive > 0, maxTiles > 0 else { return 0 }
        let total = Double(sizes.prefix(positive).reduce(UInt64(0)) { $0 &+ $1 })
        var count = 0
        while count < positive, Double(sizes[count]) / total >= minFraction {
            count += 1
        }
        // 留一块给"其他"。
        if count < positive || count > maxTiles {
            count = min(count, maxTiles - 1)
        }
        if positive - count == 1 { count = positive }
        return count
    }

    /// Squarified treemap(Bruls、Huizing、van Wijk,2000)。`values` 应按从大到小排好;
    /// 返回和 `values` 一一对应的矩形,面积和值成正比,铺满 `rect`。非正值得到空矩形。
    static func squarify(_ values: [Double], in rect: CGRect) -> [CGRect] {
        var result = [CGRect](repeating: .zero, count: values.count)
        let total = values.reduce(0) { $0 + max(0, $1) }
        guard total > 0, rect.width > 0, rect.height > 0 else { return result }

        let scale = Double(rect.width * rect.height) / total
        let indices = values.indices.filter { values[$0] > 0 }
        let areas = indices.map { values[$0] * scale }
        var remaining = rect
        var start = 0

        while start < areas.count {
            let side = Double(min(remaining.width, remaining.height))
            var end = start + 1
            var best = worstRatio(areas[start..<end], side: side)
            while end < areas.count {
                let next = worstRatio(areas[start...end], side: side)
                if next > best { break }
                best = next
                end += 1
            }

            let rowArea = areas[start..<end].reduce(0, +)
            let isLast = end == areas.count
            if remaining.width >= remaining.height {
                // 竖着放一列,贴左边。
                let thickness = isLast ? remaining.width : CGFloat(rowArea / Double(remaining.height))
                var y = remaining.minY
                for offset in start..<end {
                    let height = offset == end - 1
                        ? remaining.maxY - y
                        : CGFloat(areas[offset] / Double(thickness))
                    result[indices[offset]] = CGRect(x: remaining.minX, y: y, width: thickness, height: height)
                    y += height
                }
                remaining = CGRect(
                    x: remaining.minX + thickness, y: remaining.minY,
                    width: max(0, remaining.width - thickness), height: remaining.height)
            } else {
                // 横着放一行,贴上边。
                let thickness = isLast ? remaining.height : CGFloat(rowArea / Double(remaining.width))
                var x = remaining.minX
                for offset in start..<end {
                    let width = offset == end - 1
                        ? remaining.maxX - x
                        : CGFloat(areas[offset] / Double(thickness))
                    result[indices[offset]] = CGRect(x: x, y: remaining.minY, width: width, height: thickness)
                    x += width
                }
                remaining = CGRect(
                    x: remaining.minX, y: remaining.minY + thickness,
                    width: remaining.width, height: max(0, remaining.height - thickness))
            }
            start = end
        }
        return result
    }

    /// 一行里最"扁"的那个方块的长宽比(≥ 1),越小越接近正方形。
    private static func worstRatio<C: Collection>(_ row: C, side: Double) -> Double where C.Element == Double {
        let sum = row.reduce(0, +)
        guard sum > 0, side > 0, let largest = row.max(), let smallest = row.min(), smallest > 0 else {
            return .infinity
        }
        let sideSquared = side * side
        let sumSquared = sum * sum
        return max(sideSquared * largest / sumSquared, sumSquared / (sideSquared * smallest))
    }
}