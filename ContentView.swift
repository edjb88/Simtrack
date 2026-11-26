import SwiftUI

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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
