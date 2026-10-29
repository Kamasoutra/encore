import AppKit
import QuartzCore
import SwiftUI
import MetalKit

struct ClipDustFramesKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct ClipDustViewportKey: PreferenceKey {
    static let defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

struct ClipDustFrame: ViewModifier {
    let id: UUID
    func body(content: Content) -> some View {
        content.background {
            GeometryReader { proxy in
                Color.clear.preference(key: ClipDustFramesKey.self, value: [id: proxy.frame(in: .named("clip-dust"))])
            }
        }
    }
}

@MainActor final class ClipDustAnimator {
    weak var panel: NSPanel?
    var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private var overlay: ClipDustOverlay?

    init(panel: NSPanel) {
        self.panel = panel
        overlay = ClipDustOverlay(dustFrame: panel.contentView?.bounds ?? .zero)
    }

    func animate(_ ids: Set<UUID>, frames: [UUID: CGRect], viewport: CGRect) {
        guard let panel, panel.isVisible, let host = panel.contentView, viewport.width > 0 else { return }
        overlay?.isHidden = true
        var snapshots: [(CGImage, CGRect)] = []
        let scale = panel.backingScaleFactor
        for id in ids {
            guard let frame = frames[id] else { continue }
            let visible = frame.intersection(viewport).intersection(host.bounds)
            guard visible.width > 8, visible.height > 8,
                  let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(ceil(visible.width * scale)), pixelsHigh: Int(ceil(visible.height * scale)), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
            bitmap.size = visible.size
            let capture = host.isFlipped ? visible : CGRect(x: visible.minX, y: host.bounds.height - visible.maxY, width: visible.width, height: visible.height)
            host.cacheDisplay(in: capture, to: bitmap)
            if let image = bitmap.cgImage { snapshots.append((image, visible)) }
        }
        overlay?.isHidden = false
        guard !snapshots.isEmpty else { return }
        let view: ClipDustOverlay
        if let overlay { view = overlay } else {
            guard let next = ClipDustOverlay(dustFrame: host.bounds) else { return }
            view = next
            view.autoresizingMask = [.width, .height]
            overlay = view
        }
        let region = snapshots.reduce(CGRect.null) { $0.union($1.1) }.insetBy(dx: -80, dy: -90).intersection(host.bounds)
        view.cover(region)
        if view.superview !== host { host.addSubview(view, positioned: .above, relativeTo: nil) }
        let local = snapshots.map { ($0.0, $0.1.offsetBy(dx: -view.frame.minX, dy: -view.frame.minY)) }
        view.emit(local, reduced: reduceMotion())
    }

    func cancel() { overlay?.cancel() }
}

@MainActor final class ClipDustOverlay: MTKView, MTKViewDelegate {
    private struct Fragment {
        var rect: SIMD4<Float>
        var motion: SIMD4<Float>
        var variation: SIMD4<Float>
    }
    private struct Emission {
        let texture: MTLTexture
        let fragments: MTLBuffer
        let count: Int
        var frame: CGRect
        let start: Double
        let reduced: Bool
    }
    private struct Uniforms {
        var viewport: SIMD4<Float>
        var frame: SIMD4<Float>
    }
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var emissions: [Emission] = []
    private var timer: Timer?
    private var updatingRegion = false
    var activeCount: Int { emissions.count }

    init?(dustFrame frame: CGRect) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: Self.shader, options: nil),
              let vertex = library.makeFunction(name: "dustVertex"),
              let fragment = library.makeFunction(name: "dustFragment") else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex; descriptor.fragmentFunction = fragment
        let color = descriptor.colorAttachments[0]!
        color.pixelFormat = .bgra8Unorm
        color.isBlendingEnabled = true
        color.sourceRGBBlendFactor = .one; color.sourceAlphaBlendFactor = .one
        color.destinationRGBBlendFactor = .oneMinusSourceAlpha; color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        self.queue = queue; self.pipeline = pipeline
        super.init(frame: frame, device: device)
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        layer?.isOpaque = false
        (layer as? CAMetalLayer)?.displaySyncEnabled = false
        isPaused = true; enableSetNeedsDisplay = false
        delegate = self
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func setFrameSize(_ newSize: NSSize) {
        if !updatingRegion && frame.size != newSize { cancel() }
        super.setFrameSize(newSize)
    }

    func cover(_ rect: CGRect) {
        let region = emissions.isEmpty ? rect : frame.union(rect)
        let dx = frame.minX - region.minX, dy = frame.minY - region.minY
        for i in emissions.indices { emissions[i].frame = emissions[i].frame.offsetBy(dx: dx, dy: dy) }
        updatingRegion = true
        frame = region
        updatingRegion = false
    }

    private func random(_ x: Int, _ y: Int, _ seed: Int) -> Float {
        var value = UInt64(x &* 73_856_093 ^ y &* 19_349_663 ^ seed &* 83_492_791)
        value = (value ^ (value >> 13)) &* 1_274_126_177
        return Float(value & 65535) / 65535
    }

    func emit(_ snapshots: [(CGImage, CGRect)], reduced: Bool) {
        guard let device else { return }
        let loader = MTKTextureLoader(device: device)
        let area = snapshots.reduce(0) { $0 + $1.1.width * $1.1.height }
        let grain = max(4, ceil(sqrt(area / 6000)))
        for (index, pair) in snapshots.enumerated() {
            let (image, frame) = pair
            guard let texture = try? loader.newTexture(cgImage: image, options: [.SRGB: false, .origin: MTKTextureLoader.Origin.topLeft]) else { continue }
            var pieces: [Fragment] = []
            if reduced {
                pieces = [Fragment(rect: SIMD4(0, 0, Float(frame.width), Float(frame.height)), motion: .zero, variation: .zero)]
            } else {
                for y in stride(from: CGFloat.zero, to: frame.height, by: grain) {
                    for x in stride(from: CGFloat.zero, to: frame.width, by: grain) {
                        let a = random(Int(x), Int(y), index + 7), b = random(Int(x), Int(y), index + 18), c = random(Int(x), Int(y), index + 36)
                        let width = min(grain, frame.width - x), height = min(grain, frame.height - y)
                        let wind = min(CGFloat(35 + 35 * b), max(0, bounds.maxX - frame.minX - x - width / 2 - 8))
                        let lift = min(CGFloat(35 + 45 * c), max(0, frame.minY + y + height / 2 - 8))
                        pieces.append(Fragment(
                            rect: SIMD4(Float(x), Float(y), Float(width), Float(height)),
                            motion: SIMD4(0.02 + 0.18 * (1 - Float(x / frame.width)) + 0.08 * Float(y / frame.height) + 0.10 * a, 0.42 + 0.10 * b, Float(wind), Float(lift)),
                            variation: SIMD4((a - 0.5) * 2, c, 0, 0)))
                    }
                }
            }
            guard let buffer = pieces.withUnsafeBytes({ bytes in
                device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared)
            }) else { continue }
            emissions.append(Emission(texture: texture, fragments: buffer, count: pieces.count, frame: frame, start: CACurrentMediaTime(), reduced: reduced))
        }
        if timer == nil {
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        preferredFramesPerSecond = window?.screen?.maximumFramesPerSecond ?? 60
        isPaused = false
    }

    private func tick() {
        let now = CACurrentMediaTime()
        emissions.removeAll { now - $0.start > ($0.reduced ? 0.12 : 0.92) }
        if emissions.isEmpty { cancel() }
    }

    func cancel() {
        isPaused = true
        timer?.invalidate(); timer = nil
        emissions.removeAll()
        removeFromSuperview()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard bounds.width > 0, bounds.height > 0,
              let pass = currentRenderPassDescriptor, let drawable = currentDrawable,
              let command = queue.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        let now = CACurrentMediaTime()
        for emission in emissions {
            var uniforms = Uniforms(
                viewport: SIMD4(Float(bounds.width), Float(bounds.height), Float(now - emission.start), emission.reduced ? 1 : 0),
                frame: SIMD4(Float(emission.frame.minX), Float(emission.frame.minY), Float(emission.frame.width), Float(emission.frame.height)))
            encoder.setVertexBuffer(emission.fragments, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.setFragmentTexture(emission.texture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: emission.count)
        }
        encoder.endEncoding()
        command.present(drawable); command.commit()
    }

    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    struct Fragment { float4 rect; float4 motion; float4 variation; };
    struct Uniforms { float4 viewport; float4 frame; };
    struct Vertex {
        float4 position [[position]];
        float2 uv;
        float2 local;
        float opacity;
        float detached;
        float seed;
    };
    vertex Vertex dustVertex(uint vertexID [[vertex_id]], uint instanceID [[instance_id]],
                             const device Fragment* pieces [[buffer(0)]], constant Uniforms& u [[buffer(1)]]) {
        const float2 corners[6] = {float2(0,0), float2(1,0), float2(0,1), float2(1,0), float2(1,1), float2(0,1)};
        Fragment piece = pieces[instanceID];
        float2 corner = corners[vertexID];
        float2 center = piece.rect.xy + piece.rect.zw * 0.5;
        float2 local = (corner - 0.5) * piece.rect.zw;
        float opacity = 1.0, detached = 0.0;
        if (u.viewport.w > 0.5) {
            opacity = max(0.0, 1.0 - u.viewport.z / 0.12);
        } else if (u.viewport.z >= piece.motion.x) {
            float p = clamp((u.viewport.z - piece.motion.x) / piece.motion.y, 0.0, 1.0);
            float motion = 0.7 * p + 0.3 * p * p;
            float flutter = sin(p * M_PI_F * 2.0 + piece.variation.y * M_PI_F * 2.0) * p;
            center += float2(piece.motion.z * motion + flutter * 2.0, -piece.motion.w * sin(p * M_PI_F / 2.0) + flutter * 3.0);
            float angle = piece.variation.x * p;
            float2 spun = float2(local.x * cos(angle) - local.y * sin(angle), local.x * sin(angle) + local.y * cos(angle));
            local = spun * (1.0 - p * 0.76);
            opacity = pow(1.0 - p, 0.8);
            detached = 1.0;
        }
        float2 point = u.frame.xy + center + local;
        Vertex out;
        out.position = float4(point.x / u.viewport.x * 2.0 - 1.0, 1.0 - point.y / u.viewport.y * 2.0, 0.0, 1.0);
        out.uv = (piece.rect.xy + corner * piece.rect.zw) / u.frame.zw;
        out.local = corner - 0.5;
        out.opacity = opacity; out.detached = detached; out.seed = piece.variation.y;
        return out;
    }
    fragment float4 dustFragment(Vertex in [[stage_in]], texture2d<float> texture [[texture(0)]]) {
        if (in.opacity <= 0.0) { discard_fragment(); }
        if (in.detached > 0.5) {
            float2 points[5];
            for (int i = 0; i < 5; i++) {
                float angle = float(i) * M_PI_F * 2.0 / 5.0;
                float radius = 0.4 + 0.1 * sin(float(i) * 7.0 + in.seed * 12.0);
                points[i] = float2(cos(angle), sin(angle)) * radius;
            }
            for (int i = 0; i < 5; i++) {
                float2 edge = points[(i + 1) % 5] - points[i], point = in.local - points[i];
                if (edge.x * point.y - edge.y * point.x < 0.0) { discard_fragment(); }
            }
        }
        constexpr sampler sample(filter::linear, address::clamp_to_edge);
        float4 color = texture.sample(sample, in.uv);
        if (in.detached > 0.5) { color.rgb = mix(color.rgb, float3(0.68, 0.66, 0.70) * color.a, 0.28); }
        return color * in.opacity;
    }
    """
}
