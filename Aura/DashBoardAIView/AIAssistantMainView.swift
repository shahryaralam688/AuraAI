import SwiftUI

struct AIAssistantMainView: View {
@StateObject private var apiService = APIService.shared
@State private var userToken: String = ""
@State private var isAuthenticated = false

var body: some View {
Group {
if isAuthenticated {
AIAssistantHomeView()
} else {
authenticationView
}
}
.onAppear {
// For demo purposes, auto-authenticate with a demo token
// In production, this would come from your actual login flow
authenticateUser()
}
}

private var authenticationView: some View {
ZStack {
// Background gradient
LinearGradient(
colors: [
Color(red: 0.02, green: 0.05, blue: 0.08),
Color(red: 0.05, green: 0.08, blue: 0.12),
Color(red: 0.08, green: 0.12, blue: 0.16)
],
startPoint: .topLeading,
endPoint: .bottomTrailing
)
.ignoresSafeArea()

VStack(spacing: 24) {
// Logo
Image("logoSplash")
.resizable()
.aspectRatio(contentMode: .fit)
.frame(height: 120)

// Loading indicator
VStack(spacing: 16) {
ProgressView()
  .scaleEffect(1.2)
  .tint(Color(red: 0.31, green: 0.78, blue: 0.47))

Text("Initializing AI Assistant...")
  .font(.system(size: 18, weight: .medium))
  .foregroundColor(Color(red: 0.58, green: 0.75, blue: 0.48))
}
}
}
}

private func authenticateUser() {
// Simulate authentication delay
DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
// Set demo token - replace with actual authentication logic
let demoToken = "demo_token_\(UUID().uuidString.prefix(8))"
apiService.setUserToken(demoToken)

withAnimation(.easeInOut(duration: 0.5)) {
isAuthenticated = true
}
}
}
}

#Preview {
AIAssistantMainView()
.preferredColorScheme(.dark)
}
