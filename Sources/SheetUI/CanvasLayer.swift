import Charts
import SheetCore
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum CanvasCommand {
    case select(UUID)
    case edit(UUID)
    case drag(UUID, CGSize, resizing: Bool)
    case endDrag
}

/// Callbacks from canvas objects to the window.
final class CanvasActions {
    var perform: (CanvasCommand) -> Void = { _ in }
    var text: (UUID) -> Binding<String> = { _ in .constant("") }
}

/// Floating objects drawn over the grid, positioned from the corner of cell A1.
struct CanvasLayer: View {
    let objects: [CanvasObject]
    let charts: [UUID: ChartData]
    let selected: UUID?
    let editing: UUID?
    let drag: ObjectDrag?
    let zoom: CGFloat
    let origin: CGPoint
    let actions: CanvasActions

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(objects) { object in
                let frame = frame(for: object)
                CanvasObjectView(object: object, chart: charts[object.id], isSelected: selected == object.id,
                                 isEditing: editing == object.id, zoom: zoom, actions: actions)
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
            }
        }
    }

    private func frame(for object: CanvasObject) -> CGRect {
        var rect = CGRect(x: origin.x + object.x * zoom, y: origin.y + object.y * zoom,
                          width: object.width * zoom, height: object.height * zoom)
        if let drag, drag.id == object.id {
            rect.origin.x = max(origin.x, rect.origin.x + drag.offset.width)
            rect.origin.y = max(origin.y, rect.origin.y + drag.offset.height)
            rect.size.width = max(24 * zoom, rect.width + drag.resize.width)
            rect.size.height = max(24 * zoom, rect.height + drag.resize.height)
        }
        return rect
    }
}

struct CanvasObjectView: View {
    let object: CanvasObject
    let chart: ChartData?
    let isSelected: Bool
    let isEditing: Bool
    let zoom: CGFloat
    let actions: CanvasActions

    var body: some View {
        content
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                if case .text = object.kind { actions.perform(.edit(object.id)) }
            }
            .onTapGesture { actions.perform(.select(object.id)) }
            .gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .global)
                    .onChanged { actions.perform(.drag(object.id, $0.translation, resizing: false)) }
                    .onEnded { _ in actions.perform(.endDrag) },
                including: isEditing ? .subviews : .all
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(WorkbookView.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                        .padding(-3)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isSelected { resizeHandle }
            }
    }

    private var resizeHandle: some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(WorkbookView.accent, lineWidth: 2))
            .frame(width: 12, height: 12)
            .offset(x: 6, y: 6)
            .contentShape(Circle().inset(by: -6))
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { actions.perform(.drag(object.id, $0.translation, resizing: true)) }
                    .onEnded { _ in actions.perform(.endDrag) }
            )
            #if os(macOS)
            .onHover { inside in
                if inside { NSCursor.crosshair.push() } else { NSCursor.pop() }
            }
            #endif
    }

    private var fill: Color? { object.fill.map { Color($0) } }
    private var stroke: Color? { object.stroke.map { Color($0) } }

    @ViewBuilder
    private var content: some View {
        switch object.kind {
        case .chart(let kind, _, let title):
            ChartCard(kind: kind, title: title, data: chart ?? ChartData(categories: [], series: []), zoom: zoom)
        case .text(let text):
            ZStack(alignment: .topLeading) {
                (fill ?? Color.clear)
                if isEditing {
                    TextEditor(text: actions.text(object.id))
                        .font(.system(size: object.fontSize * zoom, weight: object.bold ? .bold : .regular))
                        .foregroundStyle(object.textColor.map { Color($0) } ?? Color.black)
                        .scrollContentBackground(.hidden)
                        .padding(4 * zoom)
                } else {
                    Text(text)
                        .font(.system(size: object.fontSize * zoom, weight: object.bold ? .bold : .regular))
                        .foregroundStyle(object.textColor.map { Color($0) } ?? Color.black)
                        .padding(8 * zoom)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .overlay { if let stroke { Rectangle().stroke(stroke, lineWidth: 1) } }
        case .shape(let shape):
            ShapeView(shape: shape, fill: fill, stroke: stroke, zoom: zoom)
        case .image(let data):
            if let image = Self.image(data) {
                image.resizable().scaledToFill().clipped()
                    .overlay { if let stroke { Rectangle().stroke(stroke, lineWidth: 2) } }
            } else {
                Color.gray.opacity(0.15).overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
        }
    }

    static func image(_ data: Data) -> Image? {
        #if os(macOS)
        NSImage(data: data).map { Image(nsImage: $0) }
        #else
        UIImage(data: data).map { Image(uiImage: $0) }
        #endif
    }
}

private struct ShapeView: View {
    let shape: CanvasObject.ShapeKind
    let fill: Color?
    let stroke: Color?
    let zoom: CGFloat

    var body: some View {
        switch shape {
        case .rectangle: styled(Rectangle())
        case .roundedRectangle: styled(RoundedRectangle(cornerRadius: 14 * zoom, style: .continuous))
        case .oval: styled(Ellipse())
        case .arrow: styled(ArrowShape())
        }
    }

    private func styled<S: Shape>(_ shape: S) -> some View {
        shape.fill(fill ?? Color.clear)
            .overlay { if let stroke { shape.stroke(stroke, lineWidth: 1.5 * zoom) } }
    }
}

private struct ArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        let shaft = rect.height * 0.36
        let head = min(rect.width * 0.4, rect.height)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY - shaft / 2))
        path.addLine(to: CGPoint(x: rect.maxX - head, y: rect.midY - shaft / 2))
        path.addLine(to: CGPoint(x: rect.maxX - head, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - head, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - head, y: rect.midY + shaft / 2))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY + shaft / 2))
        path.closeSubpath()
        return path
    }
}

/// A chart drawn live from its range, on a white card.
struct ChartCard: View {
    let kind: CanvasObject.ChartKind
    let title: String
    let data: ChartData
    let zoom: CGFloat

    static let palette: [Color] = [WorkbookView.accent, Color(red: 0.26, green: 0.45, blue: 0.85), Color(red: 0.95, green: 0.55, blue: 0.2),
                                   Color(red: 0.55, green: 0.35, blue: 0.8), Color(red: 0.2, green: 0.7, blue: 0.75), Color(red: 0.9, green: 0.35, blue: 0.45)]

    private struct Point: Identifiable {
        let id: Int
        let category: String
        let series: String
        let value: Double
    }

    private var points: [Point] {
        var points: [Point] = []
        for series in data.series {
            for (index, category) in data.categories.enumerated() where index < series.values.count {
                points.append(Point(id: points.count, category: category, series: series.name, value: series.values[index]))
            }
        }
        return points
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * zoom) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 14 * zoom, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.85))
            }
            if data.series.isEmpty {
                Text("No numbers in this range")
                    .font(.system(size: 12 * zoom))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                chart
                    .chartForegroundStyleScale(range: kind == .pie ? Self.palette : Array(Self.palette.prefix(max(1, data.series.count))))
                    .chartLegend(data.series.count > 1 || kind == .pie ? .visible : .hidden)
            }
        }
        .padding(12 * zoom)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 10 * zoom, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10 * zoom, style: .continuous).stroke(Color.black.opacity(0.08)))
        .shadow(color: Color.black.opacity(0.08), radius: 6 * zoom, y: 2 * zoom)
        .environment(\.colorScheme, .light)
    }

    @ViewBuilder
    private var chart: some View {
        let points = points
        switch kind {
        case .column:
            Chart(points) { point in
                BarMark(x: .value("Category", point.category), y: .value("Value", point.value))
                    .foregroundStyle(by: .value("Series", point.series))
                    .position(by: .value("Series", point.series))
                    .cornerRadius(3)
            }
        case .bar:
            Chart(points) { point in
                BarMark(x: .value("Value", point.value), y: .value("Category", point.category))
                    .foregroundStyle(by: .value("Series", point.series))
                    .position(by: .value("Series", point.series))
                    .cornerRadius(3)
            }
        case .line:
            Chart(points) { point in
                LineMark(x: .value("Category", point.category), y: .value("Value", point.value))
                    .foregroundStyle(by: .value("Series", point.series))
                    .symbol(by: .value("Series", point.series))
                    .interpolationMethod(.monotone)
            }
        case .pie:
            // A pie shows the first series only, as spreadsheet apps do.
            Chart(points.filter { $0.series == data.series.first?.name }) { point in
                SectorMark(angle: .value("Value", max(point.value, 0)), innerRadius: .ratio(0.5), angularInset: 1.5)
                    .foregroundStyle(by: .value("Category", point.category))
                    .cornerRadius(3)
            }
        }
    }
}
