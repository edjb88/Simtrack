import SwiftUI
import WebKit

struct DashboardView: UIViewRepresentable {
    let urlString = "http://192.168.1.100:8888" // ⚠️ Cambia por la IP de tu PC
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        DashboardView()
    }
}
