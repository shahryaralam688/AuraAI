import SwiftUI

struct RequestItemView: View {
    let request: UserRequest
    @State private var showDetails = false
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showDetails.toggle()
            }
        }) {
            VStack(spacing: 0) {
                // Main content
                HStack(spacing: 16) {
                    // Status indicator
                    VStack(spacing: 8) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 12, height: 12)
                            .shadow(color: statusColor.opacity(0.6), radius: 4, x: 0, y: 0)
                        
                        Rectangle()
                            .fill(statusColor.opacity(0.3))
                            .frame(width: 2, height: 40)
                    }
                    
                    // Request details
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(request.title)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(alabaster)
                                .multilineTextAlignment(.leading)
                            
                            Spacer()
                            
                            // Status badge
                            Text(request.status.displayName.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(statusTextColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(statusColor.opacity(0.2))
                                        .overlay(
                                            Capsule()
                                                .stroke(statusColor.opacity(0.4), lineWidth: 1)
                                        )
                                )
                        }
                        
                        // Request ID and date
                        HStack {
                            Text("ID: \(request.id)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(eton.opacity(0.7))
                            
                            Spacer()
                            
                            Text(formatDate(request.createdAt))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(eton.opacity(0.7))
                        }
                        
                        // Description preview (if available)
                        if let description = request.description, !description.isEmpty {
                            Text(description)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(alabaster.opacity(0.8))
                                .lineLimit(showDetails ? nil : 2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    
                    // Expand/collapse indicator
                    Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(eton.opacity(0.6))
                        .rotationEffect(.degrees(showDetails ? 180 : 0))
                }
                .padding(20)
                
                // Expanded details
                if showDetails {
                    VStack(spacing: 12) {
                        Divider()
                            .background(eton.opacity(0.3))
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Created")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(eton.opacity(0.7))
                                
                                Text(formatDateTime(request.createdAt))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(alabaster)
                            }
                            
                            Spacer()
                            
                            if let updatedAt = request.updatedAt {
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("Updated")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(eton.opacity(0.7))
                                    
                                    Text(formatDateTime(updatedAt))
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(alabaster)
                                }
                            }
                        }
                        
                        // Action buttons for current requests
                        if request.status == .current {
                            HStack(spacing: 12) {
                                Button(action: {
                                    // Handle view details action
                                    print("View details for request: \(request.id)")
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "eye")
                                            .font(.system(size: 12, weight: .medium))
                                        Text("View Details")
                                            .font(.system(size: 14, weight: .semibold))
                                    }
                                    .foregroundColor(emerald)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(emerald.opacity(0.1))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 16)
                                                    .stroke(emerald.opacity(0.3), lineWidth: 1)
                                            )
                                    )
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    // Handle cancel action
                                    print("Cancel request: \(request.id)")
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 12, weight: .medium))
                                        Text("Cancel")
                                            .font(.system(size: 14, weight: .semibold))
                                    }
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(Color.red.opacity(0.1))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 16)
                                                    .stroke(Color.red.opacity(0.3), lineWidth: 1)
                                            )
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.02))
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.1), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(
            color: Color.black.opacity(0.2),
            radius: 8,
            x: 0,
            y: 4
        )
        .scaleEffect(showDetails ? 1.02 : 1.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showDetails)
    }
    
    // MARK: - Color Definitions (using extensions)
    private var charlesGreen: Color { Color(red: 23.0/255.0, green: 29.0/255.0, blue: 30.0/255.0) } // Charleston Green
    private var eton: Color { Color(red: 147.0/255.0, green: 207.0/255.0, blue: 162.0/255.0) }      // Eton
    private var emerald: Color { Color(red: 84.0/255.0, green: 187.0/255.0, blue: 116.0/255.0) }   // Emerald
    private var alabaster: Color { Color(red: 243.0/255.0, green: 235.0/255.0, blue: 226.0/255.0) }
    
    // MARK: - Computed Properties
    private var statusColor: Color {
        switch request.status {
        case .current:
            return Color.blue
        case .completed:
            return emerald
        case .cancelled:
            return Color.red
        }
    }
    
    private var statusTextColor: Color {
        switch request.status {
        case .current:
            return Color.blue
        case .completed:
            return emerald
        case .cancelled:
            return Color.red
        }
    }
    
    // MARK: - Helper Methods
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateString) else {
            return dateString
        }
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        return displayFormatter.string(from: date)
    }
    
    private func formatDateTime(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateString) else {
            return dateString
        }
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .short
        return displayFormatter.string(from: date)
    }
}

#Preview {
    VStack(spacing: 16) {
        RequestItemView(
            request: UserRequest(
                id: "1",
                title: "Lighting Configuration Request",
                status: .current,
                createdAt: "2024-01-15T10:30:00Z",
                updatedAt: "2024-01-15T11:00:00Z",
                description: "Configure smart lighting for living room with optimal brightness and color temperature settings."
            )
        )
        
        RequestItemView(
            request: UserRequest(
                id: "2",
                title: "Voice Assistant Setup",
                status: .completed,
                createdAt: "2024-01-14T09:15:00Z",
                updatedAt: "2024-01-14T09:45:00Z",
                description: "Set up AI voice assistant integration"
            )
        )
        
        RequestItemView(
            request: UserRequest(
                id: "3",
                title: "Color Temperature Adjustment",
                status: .cancelled,
                createdAt: "2024-01-12T16:45:00Z",
                updatedAt: "2024-01-12T17:00:00Z",
                description: "Adjust color temperature for evening ambiance"
            )
        )
    }
    .padding()
    .background(
        LinearGradient(
            colors: [
                Color(red: 0.02, green: 0.05, blue: 0.08),
                Color(red: 0.05, green: 0.08, blue: 0.12),
                Color(red: 0.08, green: 0.12, blue: 0.16)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
    .preferredColorScheme(.dark)
}
