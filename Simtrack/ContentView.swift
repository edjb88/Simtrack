
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

// MARK: - Pose Sensitivity

struct PoseSensitivity {
    var x: Float = 1.0
    var y: Float = 1.0
    var z: Float = 1.0
    var yaw: Float = 1.0
    var pitch: Float = 1.0
    var roll: Float = 1.0
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
    }
}

// MARK: - TrackingView

struct TrackingView: View {

    @Environment(\.colorScheme) private var colorScheme

    @State private var showMesh = true
    @State private var showMarkers = true
    @State private var selectedMeshColor: MeshColor = .green

    @State private var poseText = "Esperando seguimiento facial..."
    @State private var trackingActive = false

    @State private var recenterToken = 0

    @State private var sensitivityX = 1.0
    @State private var sensitivityY = 1.0
    @State private var sensitivityZ = 1.0

    @State private var sensitivityYaw = 1.0
    @State private var sensitivityPitch = 1.0
    @State private var sensitivityRoll = 1.0

    @State private var showCalibration = true

    private var sensitivity: PoseSensitivity {
        PoseSensitivity(
            x: Float(sensitivityX),
            y: Float(sensitivityY),
            z: Float(sensitivityZ),
            yaw: Float(sensitivityYaw),
            pitch: Float(sensitivityPitch),
            roll: Float(sensitivityRoll)
        )
    }

    var body: some View {

        ZStack {

            FaceTrackingRepresentable(
                showMesh: showMesh,
                showMarkers: showMarkers,
                meshColor: selectedMeshColor.uiColor,
                sensitivity: sensitivity,
                recenterToken: recenterToken,
                onPoseUpdate: { value in
                    poseText = value
                    trackingActive = true
                },
                onTrackingLost: {
                    trackingActive = false
                    poseText = "Seguimiento facial perdido..."
                }
            )
            .ignoresSafeArea(edges: .top)

            VStack(spacing: 0) {

                // MARK: Top Controls

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
                            .fill(trackingActive ? .green : .orange)
                            .frame(width: 9, height: 9)
                    }

                    Divider()

                    Toggle("Malla facial", isOn: $showMesh)
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

                Spacer(minLength: 8)

                // MARK: Bottom Panel

                ScrollView {

                    VStack(alignment: .leading, spacing: 12) {

                        // Telemetry

                        VStack(alignment: .leading, spacing: 10) {

                            HStack {

                                Text("DATOS DE SEGUIMIENTO")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)

                                Spacer()

                                Text(trackingActive ? "LIVE" : "SIN SEÑAL")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(
                                        trackingActive ? .green : .orange
                                    )
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
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: .leading
                                )
                        }
                        .padding(14)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                        // Recenter

                        Button {

                            recenterToken += 1

                        } label: {

                            Label(
                                "RECENTRAR CABEZA",
                                systemImage: "scope"
                            )
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .disabled(!trackingActive)

                        // Sensitivity calibration

                        VStack(alignment: .leading, spacing: 12) {

                            DisclosureGroup(
                                isExpanded: $showCalibration
                            ) {

                                VStack(spacing: 14) {

                                    sensitivityControl(
                                        "X · Movimiento lateral",
                                        value: $sensitivityX
                                    )

                                    sensitivityControl(
                                        "Y · Movimiento vertical",
                                        value: $sensitivityY
                                    )

                                    sensitivityControl(
                                        "Z · Acercar / alejar",
                                        value: $sensitivityZ
                                    )

                                    Divider()

                                    sensitivityControl(
                                        "Yaw · Girar izquierda / derecha",
                                        value: $sensitivityYaw
                                    )

                                    sensitivityControl(
                                        "Pitch · Mirar arriba / abajo",
                                        value: $sensitivityPitch
                                    )

                                    sensitivityControl(
                                        "Roll · Inclinar cabeza",
                                        value: $sensitivityRoll
                                    )

                                    Button {

                                        sensitivityX = 1.0
                                        sensitivityY = 1.0
                                        sensitivityZ = 1.0

                                        sensitivityYaw = 1.0
                                        sensitivityPitch = 1.0
                                        sensitivityRoll = 1.0

                                    } label: {

                                        Label(
                                            "Restablecer sensibilidades",
                                            systemImage: "arrow.counterclockwise"
                                        )
                                        .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                }
                                .padding(.top, 12)

                            } label: {

                                Label(
                                    "CALIBRACIÓN DE SENSIBILIDAD",
                                    systemImage: "slider.horizontal.3"
                                )
                                .font(.caption)
                                .fontWeight(.bold)
                            }
                        }
                        .padding(14)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
                .frame(maxHeight: 370)
            }
        }
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: Sensitivity Slider

    private func sensitivityControl(
        _ title: String,
        value: Binding<Double>
    ) -> some View {

        VStack(alignment: .leading, spacing: 4) {

            HStack {

                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)

                Spacer()

                Text(String(format: "%.1fx", value.wrappedValue))
                    .font(.caption)
                    .fontWeight(.bold)
                    .monospacedDigit()
            }

            Slider(
                value: value,
                in: 0.1...3.0,
                step: 0.1
            )
            .tint(.blue)
        }
    }
}

// MARK: - Face Tracking Representable

struct FaceTrackingRepresentable: UIViewRepresentable {

    let showMesh: Bool
    let showMarkers: Bool
    let meshColor: UIColor

    let sensitivity: PoseSensitivity
    let recenterToken: Int

    let onPoseUpdate: (String) -> Void
    let onTrackingLost: () -> Void

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
            options: [.resetTracking, .removeExistingAnchors]
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
            meshColor: meshColor,
            sensitivity: sensitivity,
            recenterToken: recenterToken
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onPoseUpdate: onPoseUpdate,
            onTrackingLost: onTrackingLost
        )
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, ARSCNViewDelegate {

        private let udpClient = UDPClient()

        private let onPoseUpdate: (String) -> Void
        private let onTrackingLost: () -> Void

        private weak var trackedFaceNode: SCNNode?

        private var noseVertexIndex: Int?

        private var showMesh = true
        private var showMarkers = true
        private var meshColor: UIColor = .systemGreen

        private var sensitivity = PoseSensitivity()

        private var lastRecenterToken = 0
        private var recenterPending = false

        private var baselinePosition: SIMD3<Float>?
        private var baselineEuler: SIMD3<Float>?

        private let markerRadius: CGFloat = 0.006

        private var lastTelemetryUpdate: TimeInterval = 0

        init(
            onPoseUpdate: @escaping (String) -> Void,
            onTrackingLost: @escaping () -> Void
        ) {

            self.onPoseUpdate = onPoseUpdate
            self.onTrackingLost = onTrackingLost

            super.init()
        }

        // MARK: Settings

        func updateSettings(
            showMesh: Bool,
            showMarkers: Bool,
            meshColor: UIColor,
            sensitivity: PoseSensitivity,
            recenterToken: Int
        ) {

            self.showMesh = showMesh
            self.showMarkers = showMarkers
            self.meshColor = meshColor
            self.sensitivity = sensitivity

            if recenterToken != lastRecenterToken {

                lastRecenterToken = recenterToken
                recenterPending = true
            }

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

            // Face mesh

            faceGeometry.firstMaterial?.fillMode = .lines
            faceGeometry.firstMaterial?.lightingModel = .constant
            faceGeometry.firstMaterial?.diffuse.contents = meshColor
            faceGeometry.firstMaterial?.isDoubleSided = true

            let meshNode = SCNNode(geometry: faceGeometry)
            meshNode.name = "faceMesh"

            node.addChildNode(meshNode)

            // Nose marker

            let noseMarker = createMarker(
                color: .systemRed,
                radius: markerRadius * 1.5
            )

            noseMarker.name = "noseMarker"
            node.addChildNode(noseMarker)

            // Left eye

            let leftEyeMarker = createMarker(
                color: .systemBlue,
                radius: markerRadius
            )

            leftEyeMarker.name = "leftEyeMarker"
            node.addChildNode(leftEyeMarker)

            // Right eye

            let rightEyeMarker = createMarker(
                color: .systemYellow,
                radius: markerRadius
            )

            rightEyeMarker.name = "rightEyeMarker"
            node.addChildNode(rightEyeMarker)

            // Nose vertex

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

            // Update mesh

            if let meshNode = node.childNode(
                withName: "faceMesh",
                recursively: false
            ),
            let geometry = meshNode.geometry as? ARSCNFaceGeometry {

                geometry.update(from: faceAnchor.geometry)
            }

            // Update nose

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

            // Update eyes

            if let leftEyeMarker = node.childNode(
                withName: "leftEyeMarker",
                recursively: false
            ) {

                leftEyeMarker.simdTransform =
                    faceAnchor.leftEyeTransform
            }

            if let rightEyeMarker = node.childNode(
                withName: "rightEyeMarker",
                recursively: false
            ) {

                rightEyeMarker.simdTransform =
                    faceAnchor.rightEyeTransform
            }

            // Raw position

            let position = SIMD3<Float>(
                transform.columns.3.x,
                transform.columns.3.y,
                transform.columns.3.z
            )

            // Raw rotation

            let euler = transform.eulerAngles

            // First frame establishes initial centre

            if baselinePosition == nil || baselineEuler == nil {

                baselinePosition = position
                baselineEuler = euler
            }

            // Recenter on next valid tracking frame

            if recenterPending {

                baselinePosition = position
                baselineEuler = euler

                recenterPending = false

                print("Simtrack: recentrado realizado")
            }

            guard
                let originPosition = baselinePosition,
                let originEuler = baselineEuler
            else {
                return
            }

            // Relative position

            let relativePosition = position - originPosition

            // Relative rotation with angle wrapping

            let relativeEuler = SIMD3<Float>(
                normalizedAngle(euler.x - originEuler.x),
                normalizedAngle(euler.y - originEuler.y),
                normalizedAngle(euler.z - originEuler.z)
            )

            // Apply individual sensitivities

            let outputX = relativePosition.x * sensitivity.x
            let outputY = relativePosition.y * sensitivity.y
            let outputZ = relativePosition.z * sensitivity.z

            let outputYaw = relativeEuler.x * sensitivity.yaw
            let outputPitch = relativeEuler.y * sensitivity.pitch
            let outputRoll = relativeEuler.z * sensitivity.roll

            // Send UDP

            udpClient.send(
                pose: (
                    x: outputX,
                    y: outputY,
                    z: outputZ,
                    yaw: outputYaw,
                    pitch: outputPitch,
                    roll: outputRoll
                )
            )

            // Update telemetry at 10 Hz

            let currentTime = CACurrentMediaTime()

            if currentTime - lastTelemetryUpdate >= 0.1 {

                lastTelemetryUpdate = currentTime

                let telemetry = String(
                    format:
                    "X: %+.2f cm    Y: %+.2f cm    Z: %+.2f cm\nYaw: %+.1f°    Pitch: %+.1f°    Roll: %+.1f°",
                    outputX * 100,
                    outputY * 100,
                    outputZ * 100,
                    outputYaw * 180 / .pi,
                    outputPitch * 180 / .pi,
                    outputRoll * 180 / .pi
                )

                DispatchQueue.main.async { [weak self] in {
                    self?.onPoseUpdate(telemetry)
                }}
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

            baselinePosition = nil
            baselineEuler = nil

            DispatchQueue.main.async { [weak self] in {
                self?.onTrackingLost()
            }}
        }

        // MARK: Angle Normalization

        private func normalizedAngle(_ angle: Float) -> Float {

            atan2(sin(angle), cos(angle))
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
                .foregroundStyle(.secondary)
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

        // Centímetros y grados

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
