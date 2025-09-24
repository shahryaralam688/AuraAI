import SwiftUI

// MARK: - Navigation Coordinator
class NavigationCoordinator: ObservableObject {
    @Published var currentView: AppView = .aiAssistant
    @Published var showDashboard = false
    @Published var showVoiceView = false
    
    enum AppView {
        case aiAssistant
        case dashboard
        case voice
    }
    
    func navigateTo(_ view: AppView) {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentView = view
        }
    }
    
    func presentDashboard() {
        showDashboard = true
    }
    
    func presentVoiceView() {
        showVoiceView = true
    }
    
    func dismissAll() {
        showDashboard = false
        showVoiceView = false
    }
}
