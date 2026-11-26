
import SwiftUI
import UIKit
import ARKit
import SceneKit
import WebKit
import Network
import Metal
import simd
import QuartzCore
import Combine

// MARK: - Network Configuration

enum SimtrackNetwork {
    static let pcIP = "192.168.1.37"

    // Tracking TrueDepth: formato binario actual de 48 bytes.
    static let trackingPort: UInt16 = 4242

    // Órdenes de control iPhone -> Windows.
    static let controlPort: UInt16 = 4243

    // Telemetría Windows -> iPhone.
    static let telemetryPort: UInt16 = 4244

    static let protocolVersion = "simtrack.bridge.v1"
}

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

// MARK: - Tracking Orientation

enum TrackingOrientation: Hashable {
    case portrait
    case landscape
}

// MARK: - Windows Telemetry

struct HeadphonesTelemetry {
    var connected = false
    var deviceName = "Sin información"
    var imuAvailable = false
    var sampleRateHz: Double?
    var yaw: Double?
    var pitch: Double?
    var roll: Double?
    var gyroX: Double?
    var gyroY: Double?
    var gyroZ: Double?
    var accelerometerX: Double?
    var accelerometerY: Double?
    var accelerometerZ: Double?
    var receivedAt: Date?
}

// MARK: - Windows Bridge

final class WindowsBridge: ObservableObject {

    static let shared = WindowsBridge()

    @Published private(set) var headphones = HeadphonesTelemetry()
    @Published private(set) var listenerStatus = "Iniciando receptor..."
    @Published private(set) var lastCommandStatus = "Sin órdenes enviadas"

    private let queue = DispatchQueue(
        label: "com.simtrack.windowsbridge",
        qos: .userInitiated
    )

    private var controlConnection: NWConnection?
    private var listener: NWListener?
    private var incomingConnection: NWConnection?

    private var listenerStarted = false

    private init() {
        setupControlConnection()
    }

    // MARK: PC Control Connection

    private func setupControlConnection() {
        let host = NWEndpoint.Host(SimtrackNetwork.pcIP)
        let port = NWEndpoint.Port(
            rawValue: SimtrackNetwork.controlPort
        )!

        let connection = NWConnection(
            host: host,
            port: port,
            using: .udp
        )

        controlConnection = connection

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("Simtrack Bridge: canal de control preparado")

            case .failed(let error):
                print("Simtrack Bridge: error de control: \(error)")

            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    // MARK: Global Recenter

    func sendGlobalRecenter() {

        let message: [String: Any] = [
            "protocol": SimtrackNetwork.protocolVersion,
            "type": "tracking.recenter",
            "source": "iphone",
            "requestId": UUID().uuidString,
            "timestampUnixMs": Int64(
                Date().timeIntervalSince1970 * 1000
            )
        ]

        guard JSONSerialization.isValidJSONObject(message),
              let data = try? JSONSerialization.data(
                withJSONObject: message
              )
        else {
            print("Simtrack Bridge: no se pudo crear la orden")
            return
        }

        controlConnection?.send(
            content: data,
            completion: .contentProcessed { [weak self] error in

                if let error = error {
                    print(
                        "Simtrack Bridge: error enviando recentrado: \(error)"
                    )

                    DispatchQueue.main.async {
                        self?.lastCommandStatus = "Error enviando orden"
                    }

                } else {
                    print(
                        "Simtrack Bridge: orden global de recentrado enviada"
                    )

                    DispatchQueue.main.async {
                        self?.lastCommandStatus = "Orden de recentrado enviada"
                    }
                }
            }
        )
    }

    // MARK: Windows Telemetry Listener

    func start() {
        guard !listenerStarted else { return }
        listenerStarted = true

        do {
            let port = NWEndpoint.Port(
                rawValue: SimtrackNetwork.telemetryPort
            )!

            let newListener = try NWListener(
                using: .udp,
                on: port
            )

            listener = newListener

            newListener.stateUpdateHandler = { [weak self] state in

                switch state {
                case .ready:
                    DispatchQueue.main.async {
                        self?.listenerStatus = "Esperando aplicación Windows"
                    }
                    print(
                        "Simtrack Bridge: receptor UDP activo en \(SimtrackNetwork.telemetryPort)"
                    )

                case .failed(let error):
                    DispatchQueue.main.async {
                        self?.listenerStatus = "Error de recepción"
                    }
                    print("Simtrack Bridge: error listener: \(error)")

                case .cancelled:
                    DispatchQueue.main.async {
                        self?.listenerStatus = "Receptor detenido"
                    }

                default:
                    break
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }

                self.incomingConnection = connection
                connection.start(queue: self.queue)
                self.receiveTelemetry(from: connection)
            }

            newListener.start(queue: queue)

        } catch {
            listenerStarted = false
            listenerStatus = "No se pudo iniciar el receptor"
            print("Simtrack Bridge: no se pudo crear listener: \(error)")
        }
    }

    private func receiveTelemetry(from connection: NWConnection) {

        connection.receiveMessage {
            [weak self] data, _, _, error in

            guard let self else { return }

            if let data, !data.isEmpty {
                self.processTelemetry(data)
            }

            if let error {
                print(
                    "Simtrack Bridge: error recibiendo telemetría: \(error)"
                )
                return
            }

            self.receiveTelemetry(from: connection)
        }
    }

    // MARK: Parse Windows Messages

    private func processTelemetry(_ data: Data) {

        guard
            let object = try? JSONSerialization.jsonObject(
                with: data
            ),
            let message = object as? [String: Any],
            let messageType = message["type"] as? String
        else {
            print("Simtrack Bridge: mensaje JSON no válido")
            return
        }

        guard messageType == "headphones.telemetry" else {
            return
        }

        let telemetry = HeadphonesTelemetry(
            connected: message["connected"] as? Bool ?? false,
            deviceName: message["deviceName"] as? String
                ?? "Dispositivo desconocido",
            imuAvailable: message["imuAvailable"] as? Bool ?? false,
            sampleRateHz: number(message["sampleRateHz"]),
            yaw: number(message["yaw"]),
            pitch: number(message["pitch"]),
            roll: number(message["roll"]),
            gyroX: number(message["gyroX"]),
            gyroY: number(message["gyroY"]),
            gyroZ: number(message["gyroZ"]),
            accelerometerX: number(message["accelerometerX"]),
            accelerometerY: number(message["accelerometerY"]),
            accelerometerZ: number(message["accelerometerZ"]),
            receivedAt: Date()
        )

        DispatchQueue.main.async {
            self.headphones = telemetry
        }
    }

    private func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let value = value as? Double {
            return value
        }
        return nil
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
    @State private var showSettings = false

    @State private var sensitivityX = 1.0
    @State private var sensitivityY = 1.0
    @State private var sensitivityZ = 1.0

    @State private var sensitivityYaw = 1.0
    @State private var sensitivityPitch = 1.0
    @State private var sensitivityRoll = 1.0

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
            .ignoresSafeArea()

            VStack(spacing: 0) {

                HStack(spacing: 12) {

                    Label("SIMTRACK", systemImage: "faceid")
                        .font(.headline)
                        .fontWeight(.bold)

                    Spacer()

                    Circle()
                        .fill(trackingActive ? Color.green : Color.orange)
                        .frame(width: 9, height: 9)

                    Text(trackingActive ? "LIVE" : "SIN SEÑAL")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 42, height: 42)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ajustes de tracking")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 12)
                .padding(.top, 8)

                Spacer()

                Button {

                    // Recentrado local de TrueDepth.
                    recenterToken += 1

                    // Recentrado global de todas las fuentes Windows.
                    WindowsBridge.shared.sendGlobalRecenter()

                } label: {
                    Label(
                        "RECENTRAR CÁMARA",
                        systemImage: "scope"
                    )
                    .font(.headline)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .padding(.horizontal, 24)
                .padding(.bottom, 14)
            }
        }
        .background(Color.black)
        .sheet(isPresented: $showSettings) {
            settingsSheet
        }
    }

    // MARK: - Settings Sheet

    private var settingsSheet: some View {

        NavigationView {

            ScrollView {

                VStack(alignment: .leading, spacing: 20) {

                    VStack(alignment: .leading, spacing: 12) {

                        Text("SEGUIMIENTO Y APARIENCIA")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)

                        Toggle("Malla facial", isOn: $showMesh)
                            .tint(.green)

                        Toggle(
                            "Marcadores de ojos y nariz",
                            isOn: $showMarkers
                        )
                        .tint(.green)

                        if showMesh {
                            VStack(alignment: .leading, spacing: 8) {

                                Text("COLOR DE MALLA")
                                    .font(.caption)
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
                            .padding(.top, 4)
                        }

                        HStack {
                            Text("Apariencia")
                            Spacer()
                            Text(
                                colorScheme == .dark
                                ? "Modo noche"
                                : "Modo día"
                            )
                            .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                    .padding(16)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    // Telemetría TrueDepth.

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
                                    trackingActive
                                    ? Color.green
                                    : Color.orange
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
                    .padding(16)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    // Sensibilidades.

                    VStack(alignment: .leading, spacing: 14) {

                        Label(
                            "CALIBRACIÓN DE SENSIBILIDAD",
                            systemImage: "slider.horizontal.3"
                        )
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

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
                        .padding(.top, 4)
                    }
                    .padding(16)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarTitle(
                "Ajustes de tracking",
                displayMode: .inline
            )
            .navigationBarItems(
                trailing: Button("Cerrar") {
                    showSettings = false
                }
            )
        }
    }

    // MARK: - Sensitivity Slider

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

                Text(
                    String(format: "%.1fx", value.wrappedValue)
                )
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

        // Referencias independientes para cada orientación.

        private var baselinePositions:
            [TrackingOrientation: SIMD3<Float>] = [:]

        private var baselineEulers:
            [TrackingOrientation: SIMD3<Float>] = [:]

        // Última orientación válida conocida.

        private var lastKnownOrientation: TrackingOrientation = .portrait

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

        // MARK: Orientation Detection

        private func currentTrackingOrientation(
            from renderer: SCNSceneRenderer
        ) -> TrackingOrientation {

            if let arView = renderer as? ARSCNView,
               let interfaceOrientation =
                arView.window?.windowScene?.interfaceOrientation {

                switch interfaceOrientation {

                case .portrait, .portraitUpsideDown:
                    lastKnownOrientation = .portrait
                    return .portrait

                case .landscapeLeft, .landscapeRight:
                    lastKnownOrientation = .landscape
                    return .landscape

                case .unknown:
                    break

                @unknown default:
                    break
                }
            }

            switch UIDevice.current.orientation {

            case .portrait, .portraitUpsideDown:
                lastKnownOrientation = .portrait
                return .portrait

            case .landscapeLeft, .landscapeRight:
                lastKnownOrientation = .landscape
                return .landscape

            default:
                return lastKnownOrientation
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

            // Face mesh.

            faceGeometry.firstMaterial?.fillMode = .lines
            faceGeometry.firstMaterial?.lightingModel = .constant
            faceGeometry.firstMaterial?.diffuse.contents = meshColor
            faceGeometry.firstMaterial?.isDoubleSided = true

            let meshNode = SCNNode(geometry: faceGeometry)
            meshNode.name = "faceMesh"
            node.addChildNode(meshNode)

            // Nose marker.

            let noseMarker = createMarker(
                color: .systemRed,
                radius: markerRadius * 1.5
            )

            noseMarker.name = "noseMarker"
            node.addChildNode(noseMarker)

            // Left eye.

            let leftEyeMarker = createMarker(
                color: .systemBlue,
                radius: markerRadius
            )

            leftEyeMarker.name = "leftEyeMarker"
            node.addChildNode(leftEyeMarker)

            // Right eye.

            let rightEyeMarker = createMarker(
                color: .systemYellow,
                radius: markerRadius
            )

            rightEyeMarker.name = "rightEyeMarker"
            node.addChildNode(rightEyeMarker)

            // Nose vertex.

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

            // Update mesh.

            if let meshNode = node.childNode(
                withName: "faceMesh",
                recursively: false
            ),
            let geometry = meshNode.geometry as? ARSCNFaceGeometry {

                geometry.update(from: faceAnchor.geometry)
            }

            // Update nose.

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

            // Update eyes.

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

            // Raw position.

            let position = SIMD3<Float>(
                transform.columns.3.x,
                transform.columns.3.y,
                transform.columns.3.z
            )

            // Raw rotation.

            let euler = transform.eulerAngles

            // Detectar orientación.

            let orientation = currentTrackingOrientation(
                from: renderer
            )

            // Referencia inicial independiente por orientación.

            if baselinePositions[orientation] == nil ||
               baselineEulers[orientation] == nil {

                baselinePositions[orientation] = position
                baselineEulers[orientation] = euler

                print(
                    "Simtrack: referencia inicial guardada para \(orientation)"
                )
            }

            // Recentrar la orientación actual.

            if recenterPending {

                baselinePositions[orientation] = position
                baselineEulers[orientation] = euler

                recenterPending = false

                print(
                    "Simtrack: recentrado realizado para \(orientation)"
                )
            }

            // Recuperar referencia.

            guard
                let originPosition = baselinePositions[orientation],
                let originEuler = baselineEulers[orientation]
            else {
                return
            }

            // Relative position.

            let relativePosition = position - originPosition

            // Relative rotation with angle wrapping.

            let relativeEuler = SIMD3<Float>(
                normalizedAngle(euler.x - originEuler.x),
                normalizedAngle(euler.y - originEuler.y),
                normalizedAngle(euler.z - originEuler.z)
            )

            // Apply individual sensitivities.

            let outputX = relativePosition.x * sensitivity.x
            let outputY = relativePosition.y * sensitivity.y
            let outputZ = relativePosition.z * sensitivity.z

            let outputYaw = relativeEuler.x * sensitivity.yaw
            let outputPitch = relativeEuler.y * sensitivity.pitch
            let outputRoll = relativeEuler.z * sensitivity.roll

            // Send tracking UDP.
            // Se conserva el formato original de 48 bytes.

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

            // Update telemetry at 10 Hz.

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

            // Conservamos ambas referencias al perder la cara.

            DispatchQueue.main.async { [weak self] in
                self?.onTrackingLost()
            }
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

    @StateObject private var bridge = WindowsBridge.shared

    var body: some View {

        NavigationView {

            ScrollView {

                VStack(spacing: 18) {

                    Image(systemName: "headphones")
                        .font(.system(size: 58))
                        .foregroundColor(.blue)
                        .padding(.top, 12)

                    Text("Auriculares")
                        .font(.title2)
                        .bold()

                    // Estado de Windows.

                    VStack(alignment: .leading, spacing: 10) {

                        Label(
                            "CONEXIÓN CON SIMTRACK WINDOWS",
                            systemImage: "desktopcomputer"
                        )
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                        HStack {
                            Circle()
                                .fill(
                                    bridge.listenerStatus ==
                                    "Esperando aplicación Windows"
                                    ? Color.orange
                                    : Color.secondary
                                )
                                .frame(width: 9, height: 9)

                            Text(bridge.listenerStatus)
                                .font(.subheadline)
                        }

                        Text(
                            "Receptor UDP: \(SimtrackNetwork.telemetryPort)"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    // Estado de los auriculares.

                    VStack(alignment: .leading, spacing: 12) {

                        Label(
                            "DISPOSITIVO",
                            systemImage: "headphones"
                        )
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                        HStack {

                            VStack(alignment: .leading, spacing: 4) {

                                Text(bridge.headphones.deviceName)
                                    .font(.headline)

                                Text(
                                    bridge.headphones.connected
                                    ? "Conectado al PC"
                                    : "Sin conexión comunicada"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Circle()
                                .fill(
                                    bridge.headphones.connected
                                    ? Color.green
                                    : Color.orange
                                )
                                .frame(width: 11, height: 11)
                        }

                        Divider()

                        HStack {
                            Text("Sensor IMU")
                            Spacer()
                            Text(
                                bridge.headphones.imuAvailable
                                ? "Disponible"
                                : "No disponible"
                            )
                            .foregroundStyle(
                                bridge.headphones.imuAvailable
                                ? Color.green
                                : Color.secondary
                            )
                        }
                        .font(.subheadline)

                        HStack {
                            Text("Frecuencia")
                            Spacer()
                            Text(
                                bridge.headphones.sampleRateHz.map {
                                    String(format: "%.1f Hz", $0)
                                } ?? "Sin datos"
                            )
                            .monospacedDigit()
                        }
                        .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    // Orientación.

                    VStack(alignment: .leading, spacing: 12) {

                        Label(
                            "ORIENTACIÓN",
                            systemImage: "gyroscope"
                        )
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                        telemetryRow(
                            "Yaw",
                            value: bridge.headphones.yaw,
                            suffix: "°"
                        )

                        telemetryRow(
                            "Pitch",
                            value: bridge.headphones.pitch,
                            suffix: "°"
                        )

                        telemetryRow(
                            "Roll",
                            value: bridge.headphones.roll,
                            suffix: "°"
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    // Giroscopio.

                    VStack(alignment: .leading, spacing: 12) {

                        Label(
                            "GIROSCOPIO",
                            systemImage: "rotate.3d"
                        )
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                        telemetryRow(
                            "X",
                            value: bridge.headphones.gyroX,
                            suffix: ""
                        )

                        telemetryRow(
                            "Y",
                            value: bridge.headphones.gyroY,
                            suffix: ""
                        )

                        telemetryRow(
                            "Z",
                            value: bridge.headphones.gyroZ,
                            suffix: ""
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    // Acelerómetro.

                    VStack(alignment: .leading, spacing: 12) {

                        Label(
                            "ACELERÓMETRO",
                            systemImage: "move.3d"
                        )
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                        telemetryRow(
                            "X",
                            value: bridge.headphones.accelerometerX,
                            suffix: ""
                        )

                        telemetryRow(
                            "Y",
                            value: bridge.headphones.accelerometerY,
                            suffix: ""
                        )

                        telemetryRow(
                            "Z",
                            value: bridge.headphones.accelerometerZ,
                            suffix: ""
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    Text(
                        "Los datos de movimiento llegarán desde Simtrack Windows. El iPhone no se conecta directamente a los auriculares."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarTitle(
                "Auriculares",
                displayMode: .inline
            )
            .onAppear {
                bridge.start()
            }
        }
    }

    // MARK: Telemetry Row

    private func telemetryRow(
        _ title: String,
        value: Double?,
        suffix: String
    ) -> some View {

        HStack {
            Text(title)
                .foregroundStyle(.secondary)

            Spacer()

            Text(
                value.map {
                    String(format: "%+.3f%@", $0, suffix)
                } ?? "—"
            )
            .font(.system(
                size: 13,
                weight: .medium,
                design: .monospaced
            ))
            .monospacedDigit()
        }
    }
}

// MARK: - DashboardView

struct DashboardView: View {

    var body: some View {

        GeometryReader { geometry in

            let isLandscape =
                geometry.size.width > geometry.size.height

            Group {

                if isLandscape {

                    DashboardWebView()
                        .ignoresSafeArea()

                } else {

                    DashboardWebView()
                }
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height
            )
            .toolbar(
                isLandscape ? .hidden : .visible,
                for: .tabBar
            )
        }
    }
}

// MARK: - Dashboard WebView

struct DashboardWebView: UIViewRepresentable {

    let urlString = "http://192.168.1.37:8888/"

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

    private let targetIP = SimtrackNetwork.pcIP
    private let targetPort = SimtrackNetwork.trackingPort

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
                print("UDP tracking conectado correctamente")

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

        // Centímetros y grados.
        // Se mantienen los seis Double little-endian.

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
                    print("Error enviando UDP tracking: \(error)")
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
