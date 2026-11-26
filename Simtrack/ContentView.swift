import SwiftUI
import ARKit
import SceneKit
import WebKit

// MARK: - ContentView (Tab Bar)
struct ContentView: View {
    var body: some View {
        TabView {
            TrackingView()
                .tabItem { Label("Tracking", systemImage: "faceid") }
            HeadphonesView()
                .tabItem { Label("Auriculares", systemImage: "headphones") }
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "speedometer") }
        }
    }
}

// MARK: - TrackingView
struct TrackingView: UIViewRepresentable {
    func makeUIView(context: Context) -> ARSCNView {
        let sceneView = ARSCNView()
        sceneView.delegate = context.coordinator
        guard ARFaceTrackingConfiguration.isSupported else {
            print("⚠️ Face Tracking no soportado")
            return sceneView
        }
        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = true
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        return sceneView
    }
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }
    class Coordinator: NSObject, ARSCNViewDelegate {
        func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
            guard let faceAnchor = anchor as? ARFaceAnchor else { return }
            let t = faceAnchor.transform
            print(String(format: "Cara → x=%.3f y=%.3f z=%.3f",
                         t.columns.3.x, t.columns.3.y, t.columns.3.z))
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
                .font(.title2).bold()
            Text("Aquí verás el estado de la conexión y los ajustes del head tracking.")
                .multilineTextAlignment(.center).padding()
            Text("(En desarrollo)").foregroundColor(.gray)
        }.padding()
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

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}
import Network // Necesario para NWConnection

class UDPClient {
    private var connection: NWConnection?
    
    init(host: String, port: UInt16) {
        let host = NWEndpoint.Host(host)
        let port = NWEndpoint.Port(rawValue: port)!
        connection = NWConnection(host: host, port: port, using: .udp)
        connection?.start(queue: .global())
    }
    
    func send(pose: (x: Float, y: Float, z: Float, yaw: Float, pitch: Float, roll: Float)) {
        // Empaquetamos los 6 valores como 'double' (Float64) en little-endian
        var data = Data()
        let values: [Double] = [Double(pose.x), Double(pose.y), Double(pose.z),
                                Double(pose.yaw), Double(pose.pitch), Double(pose.roll)]
        for value in values {
            var littleEndianValue = value.bitPattern.littleEndian
            withUnsafeBytes(of: &littleEndianValue) { data.append(contentsOf: $0) }
        }
        
        connection?.send(content: data, completion: .contentProcessed({ error in
            if let error = error {
                print("Error enviando UDP: \(error)")
            }
        }))
    }
}
