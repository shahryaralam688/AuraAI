import Foundation
import Combine

// MARK: - API Models
struct UserResponse: Codable {
    let id: String
    let name: String?
    let email: String?
}

struct UserRequest: Codable, Identifiable {
    let id: String
    let title: String
    let status: RequestStatus
    let createdAt: String
    let updatedAt: String?
    let description: String?
}

enum RequestStatus: String, Codable, CaseIterable {
    case current = "in_progress"
    case completed = "completed"
    case cancelled = "cancelled"
    
    var displayName: String {
        switch self {
        case .current: return "Current"
        case .completed: return "Past"
        case .cancelled: return "Cancelled"
        }
    }
    
    var color: String {
        switch self {
        case .current: return "blue"
        case .completed: return "green"
        case .cancelled: return "red"
        }
    }
}

// MARK: - API Service
class APIService: ObservableObject {
    static let shared = APIService()
    
    private let baseURL = "https://dev.api.limitless-lighting.co.uk"
    private var cancellables = Set<AnyCancellable>()
    
    @Published var userToken: String?
    @Published var currentUser: UserResponse?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private init() {}
    
    // MARK: - Authentication
    func setUserToken(_ token: String) {
        self.userToken = token
        fetchUserProfile()
    }
    
    // MARK: - User Profile
    func fetchUserProfile() {
        guard let token = userToken else {
            errorMessage = "No authentication token available"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        guard let url = URL(string: "\(baseURL)/api/user/profile") else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        URLSession.shared.dataTaskPublisher(for: request)
            .map(\.data)
            .decode(type: UserResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.errorMessage = "Failed to fetch user profile: \(error.localizedDescription)"
                    }
                },
                receiveValue: { [weak self] user in
                    self?.currentUser = user
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - User Requests
    func fetchUserRequests() -> AnyPublisher<[UserRequest], Error> {
        guard let token = userToken else {
            return Fail(error: URLError(.userAuthenticationRequired))
                .eraseToAnyPublisher()
        }
        
        guard let url = URL(string: "\(baseURL)/api/user/requests") else {
            return Fail(error: URLError(.badURL))
                .eraseToAnyPublisher()
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        return URLSession.shared.dataTaskPublisher(for: request)
            .map(\.data)
            .decode(type: [UserRequest].self, decoder: JSONDecoder())
            .eraseToAnyPublisher()
    }
    
    // MARK: - Helper Methods
    func getUserDisplayName() -> String {
        return currentUser?.name ?? "User"
    }
    
    func getGreetingText() -> String {
        let name = getUserDisplayName()
        return "Hi, \(name)"
    }
}
