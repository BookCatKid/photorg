import SwiftUI

struct CropEditor: View {
    let image: UIImage
    @Binding var rect: CGRect

    @State private var dragStartRect: CGRect?
    @State private var activeCorner: Corner?

    private let handleSize: CGFloat = 28
    private let hitAreaSize: CGFloat = 56

    var body: some View {
        GeometryReader { geo in
            let displayed = aspectFitRect(image: image.size, in: geo.size)
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .overlay(cropOverlay(in: displayed))
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if dragStartRect == nil {
                            dragStartRect = rect
                        }
                        guard let start = dragStartRect else { return }
                        let dx = value.translation.width / displayed.width
                        let dy = value.translation.height / displayed.height
                        var newOrigin = CGPoint(x: start.origin.x + dx, y: start.origin.y + dy)
                        newOrigin.x = min(max(0, newOrigin.x), 1 - start.size.width)
                        newOrigin.y = min(max(0, newOrigin.y), 1 - start.size.height)
                        rect = CGRect(origin: newOrigin, size: start.size)
                    }
                    .onEnded { _ in
                        dragStartRect = nil
                    }
            )
        }
    }

    @ViewBuilder
    private func cropOverlay(in displayed: CGRect) -> some View {
        let r = pixelRect(in: displayed)
        ZStack {
            Path { p in
                p.addRect(displayed)
                p.addRect(r)
            }
            .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)

            Rectangle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: r.width, height: r.height)
                .position(x: r.midX, y: r.midY)
                .allowsHitTesting(false)

            ForEach(Corner.allCases, id: \.self) { corner in
                cropHandle(corner: corner, rect: r, displayed: displayed)
            }

            Path { p in
                let t1x = r.minX + r.width / 3, t2x = r.minX + 2 * r.width / 3
                let t1y = r.minY + r.height / 3, t2y = r.minY + 2 * r.height / 3
                p.move(to: CGPoint(x: t1x, y: r.minY)); p.addLine(to: CGPoint(x: t1x, y: r.maxY))
                p.move(to: CGPoint(x: t2x, y: r.minY)); p.addLine(to: CGPoint(x: t2x, y: r.maxY))
                p.move(to: CGPoint(x: r.minX, y: t1y)); p.addLine(to: CGPoint(x: r.maxX, y: t1y))
                p.move(to: CGPoint(x: r.minX, y: t2y)); p.addLine(to: CGPoint(x: r.maxX, y: t2y))
            }
            .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
            .allowsHitTesting(false)
        }
    }

    private func cropHandle(corner: Corner, rect r: CGRect, displayed: CGRect) -> some View {
        let center = cornerPoint(corner, in: r)
        return ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: handleSize, height: handleSize)
            Circle()
                .stroke(Color.black.opacity(0.3), lineWidth: 1.5)
                .frame(width: handleSize, height: handleSize)
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.black.opacity(0.5))
        }
        .frame(width: hitAreaSize, height: hitAreaSize)
        .position(center)
        .contentShape(Rectangle().size(CGSize(width: hitAreaSize, height: hitAreaSize)))
        .gesture(
            DragGesture()
                .onChanged { value in
                    if dragStartRect == nil {
                        dragStartRect = rect
                    }
                    guard let start = dragStartRect else { return }
                    let dx = value.translation.width / displayed.width
                    let dy = value.translation.height / displayed.height
                    let minSize: CGFloat = 0.08
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
                .onEnded { _ in
                    dragStartRect = nil
                }
        )
    }

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

    private func cornerPoint(_ c: Corner, in r: CGRect) -> CGPoint {
        switch c {
        case .topLeft:     return CGPoint(x: r.minX, y: r.minY)
        case .topRight:    return CGPoint(x: r.maxX, y: r.minY)
        case .bottomLeft:  return CGPoint(x: r.minX, y: r.maxY)
        case .bottomRight: return CGPoint(x: r.maxX, y: r.maxY)
        }
    }

    enum Corner: CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }
}