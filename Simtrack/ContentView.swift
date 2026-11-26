
import SwiftUI
import ARKit
import SceneKit
import WebKit
import Network
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

        guard ARFaceTrackingConfiguration.isSupported else {
            print("Face Tracking no soportado")
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

        func renderer(
            _ renderer: SCNSceneRenderer,
            didUpdate node: SCNNode,
            for anchor: ARAnchor
        ) {

            guard let faceAnchor = anchor as? ARFaceAnchor else {
                return
            }

            let transform = faceAnchor.transform

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

        let values: [Double] = [
            Double(pose.x),
            Double(pose.y),
            Double(pose.z),
            Double(pose.yaw),
            Double(pose.pitch),
            Double(pose.roll)
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

        // Orden: X = Yaw, Y = Pitch, Z = Roll
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
