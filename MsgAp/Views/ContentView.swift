import SwiftUI
import MapKit

struct ContentView: View {
    @State private var store = MessageStore()

    // Follows the user; falls back to automatic framing when location is denied
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)

    // Tracks camera centre — updated on every pan/zoom, used for both fetch and message drop
    @State private var mapCenter = CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737)

    @State private var selectedMessage: Message?
    @State private var showLeaveMessage = false

    var body: some View {
        ZStack {
            map
            floatingControls
        }
        // Detail sheet — tap a pin
        .sheet(item: $selectedMessage) { message in
            MessageDetailView(message: message)
                .presentationDetents([.height(220)])
                .presentationDragIndicator(.visible)
        }
        // Compose sheet — FAB
        .sheet(isPresented: $showLeaveMessage) {
            LeaveMessageView(coordinate: mapCenter, store: store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: – Map

    private var map: some View {
        Map(position: $position) {
            UserAnnotation()
            ForEach(store.messages) { message in
                Annotation("", coordinate: message.coordinate, anchor: .bottom) {
                    MessagePin(isReadable: message.isReadable)
                        .onTapGesture { selectedMessage = message }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        // Native location + compass buttons — rendered by MapKit at the standard positions
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .onMapCameraChange { context in
            mapCenter = context.camera.centerCoordinate
        }
        .ignoresSafeArea()
    }

    // MARK: – Floating controls

    private var floatingControls: some View {
        VStack {
            Spacer()

            HStack(alignment: .bottom) {
                // ── "Seek Echoes" button — bottom centre ──────────────────────
                Spacer()

                VStack(spacing: 10) {
                    if let error = store.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    Button {
                        Task {
                            await store.fetchNearby(
                                latitude:  mapCenter.latitude,
                                longitude: mapCenter.longitude,
                                radius:    500
                            )
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if store.isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "flame.fill")
                            }
                            Text(store.isLoading ? "Seeking…" : "Seek Echoes")
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .background(.orange, in: Capsule())
                        .foregroundStyle(.white)
                        .shadow(radius: 4, y: 2)
                    }
                    .disabled(store.isLoading)
                }

                Spacer()

                // ── FAB — bottom trailing ─────────────────────────────────────
                Button {
                    showLeaveMessage = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(.orange, in: Circle())
                        .shadow(radius: 4, y: 2)
                }
                .padding(.trailing, 24)
            }
            .padding(.bottom, 48)
            .animation(.easeInOut, value: store.errorMessage)
        }
    }
}

// MARK: – MessagePin

struct MessagePin: View {
    let isReadable: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 38, height: 38)
            Image(systemName: isReadable ? "flame.fill" : "flame")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isReadable ? .orange : .gray)
        }
        .overlay(
            Circle().strokeBorder(
                isReadable ? Color.orange.opacity(0.6) : Color.gray.opacity(0.4),
                lineWidth: 1.5
            )
        )
    }
}

// MARK: – MessageDetailView

struct MessageDetailView: View {
    let message: Message

    var body: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 4)

            HStack(spacing: 8) {
                Image(systemName: message.isReadable ? "flame.fill" : "flame")
                    .foregroundStyle(message.isReadable ? .orange : .gray)
                Text(message.isReadable ? "Echo Discovered" : "Beyond Thy Reach")
                    .font(.headline)
            }

            Divider()

            if message.isReadable, let content = message.content {
                Text(content)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            } else {
                VStack(spacing: 6) {
                    Text("Draw closer to read this echo.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .italic()
                    Text(String(format: "%.6f, %.6f", message.latitude, message.longitude))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
        .padding(.top, 12)
    }
}

#Preview {
    ContentView()
}
