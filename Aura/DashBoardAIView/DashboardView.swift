import SwiftUI
import Combine

struct DashboardView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var apiService = APIService.shared
    @State private var selectedTab: RequestStatus = .current
    @State private var requests: [UserRequest] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
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
                    
                    VStack(spacing: 0) {
                        // Header
                        headerView
                        
                        // Tab Navigation
                        tabNavigationView
                        
                        // Content
                        contentView
                        
                        Spacer()
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            loadRequests()
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(alabaster)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .background(Color.white.opacity(0.05))
                    )
            }
            
            Spacer()
            
            VStack(spacing: 4) {
                Text("Dashboard")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(alabaster)
                
                Text("Your AI Requests")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(eton.opacity(0.8))
            }
            
            Spacer()
            
            // Placeholder for balance
            Color.clear
                .frame(width: 40, height: 40)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 10)
    }
    
    // MARK: - Tab Navigation View
    private var tabNavigationView: some View {
        HStack(spacing: 0) {
            ForEach(RequestStatus.allCases, id: \.self) { status in
                Button(action: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        selectedTab = status
                    }
                }) {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: iconForStatus(status))
                                .font(.system(size: 16, weight: .medium))
                            
                            Text(status.displayName)
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(selectedTab == status ? alabaster : eton.opacity(0.6))
                        
                        // Count badge
                        Text("\(filteredRequests(for: status).count)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(selectedTab == status ? Color.black : eton.opacity(0.8))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(selectedTab == status ? alabaster : Color.white.opacity(0.1))
                            )
                        
                        // Selection indicator
                        Rectangle()
                            .fill(selectedTab == status ? emerald : Color.clear)
                            .frame(height: 3)
                            .cornerRadius(1.5)
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                }
                .animation(.easeInOut(duration: 0.3), value: selectedTab)
            }
        }
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .background(Color.white.opacity(0.02))
                .padding(.horizontal, 16)
        )
    }
    
    // MARK: - Content View
    private var contentView: some View {
        VStack(spacing: 0) {
            if isLoading {
                loadingView
            } else if let errorMessage = errorMessage {
                errorView(errorMessage)
            } else {
                requestsListView
            }
        }
        .padding(.top, 20)
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(emerald)
            
            Text("Loading requests...")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(eton)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Error View
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48, weight: .medium))
                .foregroundColor(.red.opacity(0.8))
            
            Text("Error")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(alabaster)
            
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(eton.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button(action: loadRequests) {
                Text("Retry")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(emerald.opacity(0.8))
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Requests List View
    private var requestsListView: some View {
        let filteredRequests = filteredRequests(for: selectedTab)
        
        return Group {
            if filteredRequests.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredRequests) { request in
                            RequestItemView(request: request)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                ))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: selectedTab)
    }
    
    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: emptyStateIcon)
                .font(.system(size: 48, weight: .medium))
                .foregroundColor(eton.opacity(0.6))
            
            Text("No \(selectedTab.displayName) Requests")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(alabaster)
            
            Text(emptyStateMessage)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(eton.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Helper Properties
    private var emptyStateIcon: String {
        switch selectedTab {
        case .current: return "clock.arrow.circlepath"
        case .completed: return "checkmark.circle"
        case .cancelled: return "xmark.circle"
        }
    }
    
    private var emptyStateMessage: String {
        switch selectedTab {
        case .current: return "You don't have any requests in progress at the moment."
        case .completed: return "No completed requests to show yet."
        case .cancelled: return "No cancelled requests found."
        }
    }
    
    // MARK: - Color Definitions (using extensions)
    private var charlesGreen: Color { Color(red: 23.0/255.0, green: 29.0/255.0, blue: 30.0/255.0) } // Charleston Green
    private var eton: Color { Color(red: 147.0/255.0, green: 207.0/255.0, blue: 162.0/255.0) }      // Eton
    private var emerald: Color { Color(red: 84.0/255.0, green: 187.0/255.0, blue: 116.0/255.0) }   // Emerald
    private var alabaster: Color { Color(red: 243.0/255.0, green: 235.0/255.0, blue: 226.0/255.0) }
    
    // MARK: - Helper Methods
    private func iconForStatus(_ status: RequestStatus) -> String {
        switch status {
        case .current: return "clock.arrow.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }
    
    private func filteredRequests(for status: RequestStatus) -> [UserRequest] {
        return requests.filter { $0.status == status }
    }
    
    private func loadRequests() {
        isLoading = true
        errorMessage = nil
        
        apiService.fetchUserRequests()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [self] completion in
                    self.isLoading = false
                    if case .failure(let error) = completion {
                        self.errorMessage = error.localizedDescription
                        // Load demo data for testing
                        self.loadDemoData()
                    }
                },
                receiveValue: { [self] requests in
                    self.requests = requests
                }
            )
            .store(in: &cancellables)
    }
    
    private func loadDemoData() {
        // Demo data for testing
        requests = [
            UserRequest(
                id: "1",
                title: "Lighting Configuration Request",
                status: .current,
                createdAt: "2024-01-15T10:30:00Z",
                updatedAt: "2024-01-15T11:00:00Z",
                description: "Configure smart lighting for living room"
            ),
            UserRequest(
                id: "2",
                title: "Voice Assistant Setup",
                status: .completed,
                createdAt: "2024-01-14T09:15:00Z",
                updatedAt: "2024-01-14T09:45:00Z",
                description: "Set up AI voice assistant integration"
            ),
            UserRequest(
                id: "3",
                title: "Room Mapping Analysis",
                status: .current,
                createdAt: "2024-01-13T14:20:00Z",
                updatedAt: "2024-01-13T15:00:00Z",
                description: "Analyze room layout for optimal lighting placement"
            ),
            UserRequest(
                id: "4",
                title: "Color Temperature Adjustment",
                status: .cancelled,
                createdAt: "2024-01-12T16:45:00Z",
                updatedAt: "2024-01-12T17:00:00Z",
                description: "Adjust color temperature for evening ambiance"
            ),
            UserRequest(
                id: "5",
                title: "Schedule Automation",
                status: .completed,
                createdAt: "2024-01-11T08:30:00Z",
                updatedAt: "2024-01-11T09:15:00Z",
                description: "Create automated lighting schedule"
            )
        ]
    }
}

#Preview {
    DashboardView()
        .preferredColorScheme(.dark)
}
