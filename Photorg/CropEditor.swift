import SwiftUI

struct CropEditor: View {
    let image: UIImage
    @Binding var rect: CGRect

    // Unified drag state
    @State private var dragStartRect: CGRect? = nil
    @State private var dragTarget: DragTarget = .none

    private let handleSize: CGFloat = 28
    private let hitAreaSize: CGFloat = 56

    enum DragTarget { case none, move, corner(Corner) }
    enum Corner: CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }

    var body: some View {
        GeometryReader { geo in
            let displayed = aspectFitRect(image: image.size, in: geo.size)
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                cropOverlay(in: displayed)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragStartRect == nil {
                            // Determine target on first touch
                            let loc = value.startLocation
                            let r = pixelRect(in: displayed)
                            dragTarget = hitTarget(at: loc, pixelRect: r)
                            dragStartRect = rect
                        }
                        guard let start = dragStartRect else { return }

                        let dx = value.translation.width / displayed.width
                        let dy = value.translation.height / displayed.height
                        let minSize: CGFloat = 0.08

                        switch dragTarget {
                        case .none:
                            break

                        case .move:
                            var newOrigin = CGPoint(x: start.origin.x + dx, y: start.origin.y + dy)
                            newOrigin.x = min(max(0, newOrigin.x), 1 - start.size.width)
                            newOrigin.y = min(max(0, newOrigin.y), 1 - start.size.height)
                            rect = CGRect(origin: newOrigin, size: start.size)

                        case .corner(let corner):
                            var newRect = start
                            switch corner {
                            case .topLeft:
                                let nx = min(max(0, start.minX + dx), start.maxX - minSize)
                                let ny = min(max(0, start.minY + dy), start.maxY - minSize)
                                newRect = CGRect(x: nx, y: ny, width: start.maxX - nx, height: start.maxY - ny)
                            case .topRight:
                                let nMaxX = max(min(1, start.maxX + dx), start.minX + minSize)
                                let ny = min(max(0, start.minY + dy), start.maxY - minSize)
                                newRect = CGRect(x: start.minX, y: ny, width: nMaxX - start.minX, height: start.maxY - ny)
                            case .bottomLeft:
                                let nx = min(max(0, start.minX + dx), start.maxX - minSize)
                                let nMaxY = max(min(1, start.maxY + dy), start.minY + minSize)
                                newRect = CGRect(x: nx, y: start.minY, width: start.maxX - nx, height: nMaxY - start.minY)
                            case .bottomRight:
                                let nMaxX = max(min(1, start.maxX + dx), start.minX + minSize)
                                let nMaxY = max(min(1, start.maxY + dy), start.minY + minSize)
                                newRect = CGRect(x: start.minX, y: start.minY, width: nMaxX - start.minX, height: nMaxY - start.minY)
                            }
                            rect = newRect
                        }
                    }
                    .onEnded { _ in
                        dragStartRect = nil
                        dragTarget = .none
                    }
            )
        }
    }

    // MARK: - Hit testing

    /// Determine what the drag started on: a corner handle, the crop interior (move), or nothing.
    private func hitTarget(at loc: CGPoint, pixelRect r: CGRect) -> DragTarget {
        let half = hitAreaSize / 2
        let corners: [(Corner, CGPoint)] = [
            (.topLeft,     CGPoint(x: r.minX, y: r.minY)),
            (.topRight,    CGPoint(x: r.maxX, y: r.minY)),
            (.bottomLeft,  CGPoint(x: r.minX, y: r.maxY)),
            (.bottomRight, CGPoint(x: r.maxX, y: r.maxY)),
        ]
        for (corner, center) in corners {
            let zone = CGRect(x: center.x - half, y: center.y - half, width: hitAreaSize, height: hitAreaSize)
            if zone.contains(loc) { return .corner(corner) }
        }
        if r.contains(loc) { return .move }
        return .none
    }

    // MARK: - Overlay drawing (pure visuals, no hit testing)

    @ViewBuilder
    private func cropOverlay(in displayed: CGRect) -> some View {
        let r = pixelRect(in: displayed)
        Canvas { ctx, _ in
            // Dim outside
            var outside = Path(); outside.addRect(displayed); outside.addRect(r)
            ctx.fill(outside, with: .color(.black.opacity(0.55)), style: FillStyle(eoFill: true))

            // Border
            ctx.stroke(Path(r), with: .color(.white), lineWidth: 2)

            // Rule-of-thirds grid
            var grid = Path()
            let t1x = r.minX + r.width / 3, t2x = r.minX + 2 * r.width / 3
            let t1y = r.minY + r.height / 3, t2y = r.minY + 2 * r.height / 3
            grid.move(to: CGPoint(x: t1x, y: r.minY)); grid.addLine(to: CGPoint(x: t1x, y: r.maxY))
            grid.move(to: CGPoint(x: t2x, y: r.minY)); grid.addLine(to: CGPoint(x: t2x, y: r.maxY))
            grid.move(to: CGPoint(x: r.minX, y: t1y)); grid.addLine(to: CGPoint(x: r.maxX, y: t1y))
            grid.move(to: CGPoint(x: r.minX, y: t2y)); grid.addLine(to: CGPoint(x: r.maxX, y: t2y))
            ctx.stroke(grid, with: .color(.white.opacity(0.4)), lineWidth: 0.5)

            // Corner handles
            let half = handleSize / 2
            let centers: [CGPoint] = [
                CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY),
            ]
            for center in centers {
                let circle = Path(ellipseIn: CGRect(x: center.x - half, y: center.y - half, width: handleSize, height: handleSize))
                ctx.fill(circle, with: .color(.white))
                ctx.stroke(circle, with: .color(.black.opacity(0.3)), lineWidth: 1.5)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Geometry helpers

    private func aspectFitRect(image: CGSize, in container: CGSize) -> CGRect {
        let scale = min(container.width / image.width, container.height / image.height)
        let w = image.width * scale, h = image.height * scale
        return CGRect(x: (container.width - w) / 2,
                      y: (container.height - h) / 2,
                      width: w, height: h)
    }

    private func pixelRect(in displayed: CGRect) -> CGRect {
        CGRect(x: displayed.minX + rect.origin.x * displayed.width,
               y: displayed.minY + rect.origin.y * displayed.height,
               width: rect.size.width * displayed.width,
               height: rect.size.height * displayed.height)
    }
}