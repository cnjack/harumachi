import AppKit
import SwiftUI
import MetalKit
import MioCore

struct CharacterView: NSViewRepresentable {
    @ObservedObject var state: CompanionState
    func makeNSView(context: Context) -> MTKView {
        let view = TrackingMetalView()
        guard let device = MTLCreateSystemDefaultDevice() else { state.error = "这台 Mac 暂不可用 Metal"; return view }
        view.device = device; view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.layer?.isOpaque = false
        view.wantsLayer = true
        (view.layer as? CAMetalLayer)?.isOpaque = false
        view.preferredFramesPerSecond = 60
        do {
            let renderer = try MioRenderer(device: device)
            renderer.onFrame = { [weak state] in
                DispatchQueue.main.async { state?.frames += 60 }
            }
            context.coordinator.renderer = renderer; state.renderer = renderer
            view.rigRenderer = renderer
            view.delegate = renderer
        } catch { state.error = "角色资源加载失败：\(error.localizedDescription)" }
        return view
    }
    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.renderer?.selectGesture(state.gesture, revision: state.gestureRevision)
        context.coordinator.renderer?.pose.mood = state.mood
        context.coordinator.renderer?.speakingUntil = state.speakingUntil
        context.coordinator.renderer?.isPaused = state.paused
        nsView.isPaused = state.paused
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var renderer: MioRenderer? }
}

final class TrackingMetalView: MTKView {
    weak var rigRenderer: MioRenderer?
    private var mouseArea: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let mouseArea { removeTrackingArea(mouseArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area); mouseArea = area
    }
    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        rigRenderer?.targetLook.x = Float(max(-1, min(1, point.x / max(1, bounds.width) * 2 - 1)))
        rigRenderer?.targetLook.y = Float(max(-1, min(1, point.y / max(1, bounds.height) * 2 - 1)))
    }
    override func mouseExited(with event: NSEvent) { rigRenderer?.targetLook = .zero }
}

private let ink = Color(red: 0.19, green: 0.24, blue: 0.28)
private let muted = Color(red: 0.45, green: 0.49, blue: 0.50)
private let accent = Color(red: 0.25, green: 0.49, blue: 0.57)

struct Dashboard: View {
    @ObservedObject var state: CompanionState
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("晴町 · 桌面来信").font(.system(size: 12, weight: .medium)).tracking(3).foregroundStyle(accent)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("澪").font(.system(size: 44, weight: .light, design: .serif))
                    Text("MIO").font(.system(size: 13, weight: .medium)).tracking(5).foregroundStyle(muted)
                }.padding(.top, 12)
                CharacterView(state: state).frame(maxWidth: .infinity, maxHeight: .infinity)
                Text(state.phrase).font(.system(size: 14, design: .serif)).lineSpacing(5).frame(maxWidth: .infinity, minHeight: 50)
                HStack(spacing: 6) {
                    Circle().fill(state.source == "Clef 决策" ? accent : Color.orange.opacity(0.7)).frame(width: 6, height: 6)
                    Text(state.source).font(.system(size: 11)).foregroundStyle(muted)
                }.frame(maxWidth: .infinity).padding(.bottom, 12)
            }.padding(.horizontal, 36).padding(.top, 24).frame(width: 372)
                .background(LinearGradient(colors: [Color(red: 0.91, green: 0.95, blue: 0.95), Color(red: 0.99, green: 0.97, blue: 0.92)], startPoint: .topLeading, endPoint: .bottomTrailing))
            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("今天，也在你身边。").font(.system(size: 21, weight: .medium, design: .serif))
                        Text("系统来信 · 表情回应 · 安静陪伴").font(.system(size: 12)).foregroundStyle(muted)
                    }
                    Spacer()
                    Button(state.paused ? "继续" : "暂停", action: state.togglePause).buttonStyle(.bordered)
                }
                Divider()
                HStack(spacing: 22) {
                    metric("收到来信", "\(state.events.count)")
                    metric("完成决策", "\(state.decisions)")
                    metric("渲染帧", "\(state.frames)")
                    Spacer()
                    Toggle("桌面角色", isOn: $state.showCompanion).toggleStyle(.switch).font(.system(size: 12))
                        .onChange(of: state.showCompanion) { _, value in state.onVisibility?(value) }
                }
                HStack(spacing: 8) {
                    Text("动作").font(.system(size: 11)).foregroundStyle(muted)
                    ForEach(CharacterGesture.allCases, id: \.self) { gesture in
                        Button(gesture.title) { state.play(gesture) }.disabled(state.paused)
                    }
                }.controlSize(.small)
                VStack(alignment: .leading, spacing: 7) {
                    Text("CLEF").font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(accent)
                    HStack { TextField("服务地址", text: $state.baseURL); TextField("模型", text: $state.model).frame(width: 105); Button("连接", action: state.reconnect) }
                        .textFieldStyle(.roundedBorder)
                    Text(state.connection).font(.system(size: 11)).foregroundStyle(muted)
                    if !state.error.isEmpty { Text(state.error).font(.system(size: 11)).foregroundStyle(.orange) }
                }
                HStack {
                    Text("最近来信").font(.system(size: 14, weight: .medium))
                    Spacer()
                    Text("仅保留内存中的最近 80 条").font(.system(size: 10)).foregroundStyle(muted)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(state.events) { event in
                            HStack(alignment: .top, spacing: 10) {
                                Text(event.date, style: .time).font(.system(size: 10, design: .monospaced)).foregroundStyle(muted).frame(width: 55, alignment: .leading)
                                Text(event.summary).font(.system(size: 12)).lineLimit(2)
                                Spacer(minLength: 0)
                            }.padding(.vertical, 10)
                            Divider().opacity(0.5)
                        }
                    }
                }.frame(maxHeight: .infinity)
                HStack {
                    TextField("给澪留句话…", text: $state.draft).textFieldStyle(.roundedBorder).onSubmit(state.send)
                    Button("送出", action: state.send).disabled(state.paused || state.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                HStack {
                    Text("只接收无需授权的系统事件").font(.system(size: 10)).foregroundStyle(muted)
                    Spacer()
                    Button("消息收件箱") { NSWorkspace.shared.open(state.inbox) }.font(.system(size: 10)).buttonStyle(.plain).foregroundStyle(accent)
                }
            }.padding(26).background(Color(red: 0.995, green: 0.991, blue: 0.976))
        }.foregroundStyle(ink).frame(minWidth: 860, minHeight: 670).preferredColorScheme(.light)
    }
    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.system(size: 22, weight: .light, design: .rounded))
            Text(label).font(.system(size: 10)).foregroundStyle(muted)
        }
    }
}

struct DesktopCompanion: View {
    @ObservedObject var state: CompanionState
    let openDashboard: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Button(action: openDashboard) {
                VStack(spacing: 5) {
                    Text(state.phrase).font(.system(size: 12, design: .serif)).lineSpacing(3)
                    Text(state.paused ? "已暂停" : state.source).font(.system(size: 9)).foregroundStyle(muted)
                }.padding(12).frame(maxWidth: .infinity)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15))
            }.buttonStyle(.plain).padding(.horizontal, 14)
            CharacterView(state: state)
        }.padding(.top, 8).foregroundStyle(ink).preferredColorScheme(.light)
    }
}
