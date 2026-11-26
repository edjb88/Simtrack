import SwiftUI

struct HeadphonesView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "headphones")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Auriculares (Sony ULT WEAR)")
                .font(.title2)
                .bold()
            
            Text("Aquí verás el estado de la conexión y los ajustes del head tracking.")
                .multilineTextAlignment(.center)
                .padding()
            
            Text("(En desarrollo)")
                .foregroundColor(.gray)
        }
        .padding()
    }
}

struct HeadphonesView_Previews: PreviewProvider {
    static var previews: some View {
        HeadphonesView()
    }
}
