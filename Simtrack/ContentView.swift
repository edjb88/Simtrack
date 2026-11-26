
import SwiftUI
import ARKit
import SceneKit
import WebKit
import Network
import Metal
import simd

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

struct TrackingView: UIViewRepresentable {

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

    func updateUIView(_ uiView: ARSCNView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, ARSCNViewDelegate {

        private let udpClient = UDPClient()

        private var noseVertexIndex: Int?

        // Tamaño de los marcadores
        private let markerRadius: CGFloat = 0.006

        // MARK: Face added

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

            // Malla facial
            faceGeometry.firstMaterial?.fillMode = .lines
            faceGeometry.firstMaterial?.lightingModel = .constant
            faceGeometry.firstMaterial?.diffuse.contents = UIColor.systemGreen
            faceGeometry.firstMaterial?.isDoubleSided = true

            let meshNode = SCNNode(geometry: faceGeometry)
            meshNode.name = "faceMesh"

            node.addChildNode(meshNode)

            // Marcador de nariz
            let noseMarker = createMarker(
                color: .systemRed,
                radius: markerRadius * 1.5
            )

            noseMarker.name = "noseMarker"
            node.addChildNode(noseMarker)

            // Marcador ojo izquierdo
            let leftEyeMarker = createMarker(
                color: .systemBlue,
                radius: markerRadius
            )

            leftEyeMarker.name = "leftEyeMarker"
            node.addChildNode(leftEyeMarker)

            // Marcador ojo derecho
            let rightEyeMarker = createMarker(
                color: .systemYellow,
                radius: markerRadius
            )

            rightEyeMarker.name = "rightEyeMarker"
            node.addChildNode(rightEyeMarker)

            // Localizamos el vértice más adelantado de la cara.
            let vertices = faceAnchor.geometry.vertices

            noseVertexIndex = vertices.enumerated().max {
                $0.element.z < $1.element.z
            }?.offset

            print("Malla facial creada correctamente")
            print("Vértices de la cara: \(vertices.count)")
            print("Vértice de nariz: \(noseVertexIndex ?? -1)")
        }

        // MARK: Face updated

        func renderer(
            _ renderer: SCNSceneRenderer,
            didUpdate node: SCNNode,
            for anchor: ARAnchor
        ) {

            guard let faceAnchor = anchor as? ARFaceAnchor else {
                return
            }

            let transform = faceAnchor.transform

            // Actualizar malla facial
            if let meshNode = node.childNode(
                withName: "faceMesh",
                recursively: false
            ),
            let geometry = meshNode.geometry as? ARSCNFaceGeometry {

                geometry.update(from: faceAnchor.geometry)
            }

            // Actualizar marcador de nariz
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

                leftEyeMarker.simdTransform = faceAnchor.leftEyeTransform
            }

            // Actualizar ojo derecho
            if let rightEyeMarker = node.childNode(
                withName: "rightEyeMarker",
                recursively: false
            ) {

                rightEyeMarker.simdTransform = faceAnchor.rightEyeTransform
            }

            // Posición de la cabeza
            let x = transform.columns.3.x
            let y = transform.columns.3.y
            let z = transform.columns.3.z

            // Orientación de la cabeza
            let euler = transform.eulerAngles

            let yaw = euler.x
            let pitch = euler.y
            let roll = euler.z

            // Envío UDP al PC
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
        }

        // MARK: Marker creation

        private func createMarker(
            color: UIColor,
            radius: CGFloat
        ) -> SCNNode {

            let sphere = SCNSphere(radius: radius)

            sphere.segmentCount = 12

            sphere.firstMaterial?.diffuse.contents = color
            sphere.firstMaterial?.emission.contents = color
            sphere.firstMaterial?.lightingModel = .constant

            let marker = SCNNode(geometry: sphere)

            return marker
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
                .foregroundColor(.gray)
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

    func updateUIView(_ uiView: WKWebView, context: Context) {}
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

// MARK: - Matrix Euler Angles Extension

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
