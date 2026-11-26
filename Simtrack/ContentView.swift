
import SwiftUI
import UIKit
import ARKit
import SceneKit
import WebKit
import Network
import Metal
import simd
import QuartzCore

// MARK: - Mesh Colors

enum MeshColor: String, CaseIterable, Identifiable {

    case green
    case cyan
    case white

    var id: String { rawValue }

    var title: String {
        switch self {
        case .green: return "Verde"
        case .cyan: return "Cian"
        case .white: return "Blanco"
        }
    }

    var uiColor: UIColor {
        switch self {
        case .green: return .systemGreen
        case .cyan: return .cyan
        case .white: return .white
        }
    }
}

// MARK: - ContentView

struct ContentView: View {

    var body: some View {

        TabView {

            TrackingView()
                .tabItem {
                    Label("Tracking", systemImage: "faceid")
                }

            HeadphonesView()
                .tabItem {
                    Label("Auriculares", systemImage: "headphones")
                }

            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "speedometer")
                }
        }
        // No forzamos el esquema: iOS decide entre claro y oscuro.
    }
}

// MARK: - TrackingView

struct TrackingView: View {

    @Environment(\.colorScheme) private var colorScheme

    @State private var showMesh = true
    @State private var showMarkers = true

    @State private var selectedMeshColor: MeshColor = .green

    @State private var poseText = "Esperando seguimiento facial..."

    var body: some View {

        ZStack {

            FaceTrackingRepresentable(
                showMesh: showMesh,
                showMarkers: showMarkers,
                meshColor: selectedMeshColor.uiColor,
                onPoseUpdate: { value in
                    poseText = value
                }
            )
            .ignoresSafeArea(edges: .top)

            VStack(spacing: 0) {

                // Panel superior de controles
                VStack(alignment: .leading, spacing: 12) {

                    HStack {

                        Label("SIMTRACK", systemImage: "faceid")
                            .font(.headline)
                            .fontWeight(.bold)

                        Spacer()

                        Text(
                            colorScheme == .dark
                            ? "MODO NOCHE"
                            : "MODO DÍA"
                        )
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                    }

                    Divider()

                    Toggle(
                        "Malla facial",
                        isOn: $showMesh
                    )
                    .font(.subheadline)
                    .tint(.green)

                    Toggle(
                        "Marcadores de ojos y nariz",
                        isOn: $showMarkers
                    )
                    .font(.subheadline)
                    .tint(.green)

                    if showMesh {

                        VStack(alignment: .leading, spacing: 6) {

                            Text("COLOR DE MALLA")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)

                            Picker(
                                "Color de malla",
                                selection: $selectedMeshColor
                            ) {

                                ForEach(MeshColor.allCases) { color in

                                    Text(color.title)
                                        .tag(color)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                }
                .padding(14)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 12)
                .padding(.top, 8)

                Spacer()

                // Panel inferior de telemetría
                VStack(alignment: .leading, spacing: 10) {

                    HStack {

                        Text("DATOS DE SEGUIMIENTO")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("LIVE")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.green)
                    }

                    Divider()

                    Text(poseText)
                        .font(.system(
                            size: 12,
                            weight: .medium,
                            design: .monospaced
                        ))
                        .lineSpacing(5)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(14)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .background(Color(uiColor: .systemBackground))
    }
}

// MARK: - Face Tracking Representable

struct FaceTrackingRepresentable: UIViewRepresentable {

    let showMesh: Bool
    let showMarkers: Bool
    let meshColor: UIColor

    let onPoseUpdate: (String) -> Void

    func makeUIView(context: Context) -> ARSCNView {

        let sceneView = ARSCNView()

        sceneView.delegate = context.coordinator
        sceneView.automaticallyUpdatesLighting = true
        sceneView.backgroundColor = .black

        guard ARFaceTrackingConfiguration.isSupported else {

            print("Face Tracking no soportado")

            return sceneView
        }

        guard sceneView.device != nil else {

            print("No se ha podido obtener el dispositivo Metal")

            return sceneView
        }

        let configuration = ARFaceTrackingConfiguration()

        configuration.isLightEstimationEnabled = true

        sceneView.session.run(
            configuration,
            options: [
                .resetTracking,
                .removeExistingAnchors
            ]
        )

        return sceneView
    }

    func updateUIView(
        _ uiView: ARSCNView,
        context: Context
    ) {

        context.coordinator.updateSettings(
            showMesh: showMesh,
            showMarkers: showMarkers,
            meshColor: meshColor
        )
    }

    func makeCoordinator() -> Coordinator {

        Coordinator(onPoseUpdate: onPoseUpdate)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, ARSCNViewDelegate {

        private let udpClient = UDPClient()

        private let onPoseUpdate: (String) -> Void

        private weak var trackedFaceNode: SCNNode?

        private var noseVertexIndex: Int?

        private var showMesh = true
        private var showMarkers = true

        private var meshColor: UIColor = .systemGreen

        private let markerRadius: CGFloat = 0.006

        private var lastTelemetryUpdate: TimeInterval = 0

        init(onPoseUpdate: @escaping (String) -> Void) {

            self.onPoseUpdate = onPoseUpdate

            super.init()
        }

        // MARK: Settings

        func updateSettings(
            showMesh: Bool,
            showMarkers: Bool,
            meshColor: UIColor
        ) {

            self.showMesh = showMesh
            self.showMarkers = showMarkers
            self.meshColor = meshColor

            guard let node = trackedFaceNode else {
                return
            }

            applySettings(to: node)
        }

        private func applySettings(to node: SCNNode) {

            if let meshNode = node.childNode(
                withName: "faceMesh",
                recursively: false
            ) {

                meshNode.isHidden = !showMesh

                meshNode.geometry?
                    .firstMaterial?
                    .diffuse.contents = meshColor
            }

            if let noseMarker = node.childNode(
                withName: "noseMarker",
                recursively: false
            ) {

                noseMarker.isHidden = !showMarkers
            }

            if let leftEyeMarker = node.childNode(
                withName: "leftEyeMarker",
                recursively: false
            ) {

                leftEyeMarker.isHidden = !showMarkers
            }

            if let rightEyeMarker = node.childNode(
                withName: "rightEyeMarker",
                recursively: false
            ) {

                rightEyeMarker.isHidden = !showMarkers
            }
        }

        // MARK: Face Added

        func renderer(
            _ renderer: SCNSceneRenderer,
            didAdd node: SCNNode,
            for anchor: ARAnchor
        ) {

            guard let faceAnchor = anchor as? ARFaceAnchor else {
                return
            }

            guard
                let arView = renderer as? ARSCNView,
                let device = arView.device,
                let faceGeometry = ARSCNFaceGeometry(
                    device: device,
                    fillMesh: false
                )
            else {

                print("No se pudo crear la geometría facial")

                return
            }

            trackedFaceNode = node

            // Malla facial

            faceGeometry.firstMaterial?.fillMode = .lines

            faceGeometry.firstMaterial?.lightingModel = .constant

            faceGeometry.firstMaterial?.diffuse.contents = meshColor

            faceGeometry.firstMaterial?.isDoubleSided = true

            let meshNode = SCNNode(geometry: faceGeometry)

            meshNode.name = "faceMesh"

            node.addChildNode(meshNode)

            // Nariz

            let noseMarker = createMarker(
                color: .systemRed,
                radius: markerRadius * 1.5
            )

            noseMarker.name = "noseMarker"

            node.addChildNode(noseMarker)

            // Ojo izquierdo

            let leftEyeMarker = createMarker(
                color: .systemBlue,
                radius: markerRadius
            )

            leftEyeMarker.name = "leftEyeMarker"

            node.addChildNode(leftEyeMarker)

            // Ojo derecho

            let rightEyeMarker = createMarker(
                color: .systemYellow,
                radius: markerRadius
            )

            rightEyeMarker.name = "rightEyeMarker"

            node.addChildNode(rightEyeMarker)

            // Localizar vértice de nariz

            let vertices = faceAnchor.geometry.vertices

            noseVertexIndex = vertices.enumerated().max {
                $0.element.z < $1.element.z
            }?.offset

            applySettings(to: node)

            print("Malla facial creada correctamente")
            print("Vértices: \(vertices.count)")
            print("Vértice nariz: \(noseVertexIndex ?? -1)")
        }

        // MARK: Face Updated

        func renderer(
            _ renderer: SCNSceneRenderer,
            didUpdate node: SCNNode,
            for anchor: ARAnchor
        ) {

            guard let faceAnchor = anchor as? ARFaceAnchor else {
                return
            }

            let transform = faceAnchor.transform

            // Actualizar malla

            if let meshNode = node.childNode(
                withName: "faceMesh",
                recursively: false
            ),
            let geometry = meshNode.geometry as? ARSCNFaceGeometry {

                geometry.update(from: faceAnchor.geometry)
            }

            // Actualizar nariz

            if let noseMarker = node.childNode(
                withName: "noseMarker",
                recursively: false
            ),
            let index = noseVertexIndex {

                let vertices = faceAnchor.geometry.vertices

                if index < vertices.count {

                    noseMarker.simdPosition = vertices[index]
                }
            }

            // Actualizar ojo izquierdo

            if let leftEyeMarker = node.childNode(
                withName: "leftEyeMarker",
                recursively: false
            ) {

                leftEyeMarker.simdTransform =
                    faceAnchor.leftEyeTransform
            }

            // Actualizar ojo derecho

            if let rightEyeMarker = node.childNode(
                withName: "rightEyeMarker",
                recursively: false
            ) {

                rightEyeMarker.simdTransform =
                    faceAnchor.rightEyeTransform
            }

            // Posición de cabeza

            let x = transform.columns.3.x
            let y = transform.columns.3.y
            let z = transform.columns.3.z

            // Orientación

            let euler = transform.eulerAngles

            let yaw = euler.x
            let pitch = euler.y
            let roll = euler.z

            // Envío UDP

            udpClient.send(
                pose: (
                    x: x,
                    y: y,
                    z: z,
                    yaw: yaw,
                    pitch: pitch,
                    roll: roll
                )
            )

            // Telemetría visual, limitada a 10 actualizaciones por segundo

            let currentTime = CACurrentMediaTime()

            if currentTime - lastTelemetryUpdate >= 0.1 {

                lastTelemetryUpdate = currentTime

                let telemetry = String(
                    format:
                    "X: %+.2f cm    Y: %+.2f cm    Z: %+.2f cm\nYaw: %+.1f°    Pitch: %+.1f°    Roll: %+.1f°",
                    x * 100,
                    y * 100,
                    z * 100,
                    yaw * 180 / .pi,
                    pitch * 180 / .pi,
                    roll * 180 / .pi
                )

                DispatchQueue.main.async { [weak self] in

                    self?.onPoseUpdate(telemetry)
                }
            }
        }

        // MARK: Face Removed

        func renderer(
            _ renderer: SCNSceneRenderer,
            didRemove node: SCNNode,
            for anchor: ARAnchor
        ) {

            guard anchor is ARFaceAnchor else {
                return
            }

            if trackedFaceNode === node {
                trackedFaceNode = nil
            }

            DispatchQueue.main.async { [weak self] in

                self?.onPoseUpdate(
                    "Seguimiento facial perdido..."
                )
            }
        }

        // MARK: Marker Creation

        private func createMarker(
            color: UIColor,
            radius: CGFloat
        ) -> SCNNode {

            let sphere = SCNSphere(radius: radius)

            sphere.segmentCount = 12

            sphere.firstMaterial?.diffuse.contents = color

            sphere.firstMaterial?.emission.contents = color

            sphere.firstMaterial?.lightingModel = .constant

            return SCNNode(geometry: sphere)
        }
    }
}

// MARK: - HeadphonesView

struct HeadphonesView: View {

    var body: some View {

        VStack(spacing: 20) {

            Image(systemName: "headphones")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("Auriculares (Sony ULT WEAR)")
                .font(.title2)
                .bold()

            Text(
                "Aquí verás el estado de la conexión y los ajustes del head tracking."
            )
            .multilineTextAlignment(.center)
            .padding()

            Text("(En desarrollo)")
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

// MARK: - DashboardView

struct DashboardView: UIViewRepresentable {

    let urlString = "http://172.20.10.12:8888/"

    func makeUIView(context: Context) -> WKWebView {

        let webView = WKWebView()

        if let url = URL(string: urlString) {

            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateUIView(
        _ uiView: WKWebView,
        context: Context
    ) {}
}

// MARK: - UDPClient

class UDPClient {

    private var connection: NWConnection?

    private let targetIP = "172.20.10.12"

    private let targetPort: UInt16 = 4242

    init() {

        let host = NWEndpoint.Host(targetIP)

        let port = NWEndpoint.Port(rawValue: targetPort)!

        connection = NWConnection(
            host: host,
            port: port,
            using: .udp
        )

        connection?.stateUpdateHandler = { state in

            switch state {

            case .ready:

                print("UDP conectado correctamente")

            case .failed(let error):

                print("Error de conexión UDP: \(error)")

            default:

                break
            }
        }

        connection?.start(queue: .global())
    }

    func send(
        pose: (
            x: Float,
            y: Float,
            z: Float,
            yaw: Float,
            pitch: Float,
            roll: Float
        )
    ) {

        var data = Data()

        // Posición en centímetros y rotación en grados

        let values: [Double] = [

            Double(pose.x) * 100.0,
            Double(pose.y) * 100.0,
            Double(pose.z) * 100.0,

            Double(pose.yaw) * 180.0 / .pi,
            Double(pose.pitch) * 180.0 / .pi,
            Double(pose.roll) * 180.0 / .pi
        ]

        for value in values {

            var littleEndianValue = value.bitPattern.littleEndian

            withUnsafeBytes(of: &littleEndianValue) {

                data.append(contentsOf: $0)
            }
        }

        connection?.send(
            content: data,
            completion: .contentProcessed { error in

                if let error = error {

                    print("Error enviando UDP: \(error)")
                }
            }
        )
    }
}

// MARK: - Matrix Euler Angles

extension simd_float4x4 {

    var eulerAngles: SIMD3<Float> {

        let yaw = atan2(
            columns.2.x,
            columns.2.z
        )

        let pitch = asin(
            max(-1.0, min(1.0, -columns.2.y))
        )

        let roll = atan2(
            columns.1.x,
            columns.1.y
        )

        return SIMD3<Float>(
            yaw,
            pitch,
            roll
        )
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {

    static var previews: some View {

        ContentView()
    }
}
