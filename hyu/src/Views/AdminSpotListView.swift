import SwiftUI

struct AdminSpotListView: View {
    @State private var spots: [Spot] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText: String = ""
    @State private var showForm = false
    @State private var editingSpot: Spot?

    private let firestoreService = FirestoreService()

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            ForEach(filteredSpots) { spot in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(spot.name)
                            .font(.headline)
                        Spacer()
                        Text(spot.isActive ? "有効" : "無効")
                            .font(.caption)
                            .foregroundColor(spot.isActive ? .green : .secondary)
                    }
                    Text("lat: \(spot.latitude), lon: \(spot.longitude)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("半径: \(Int(spot.radius))m")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    editingSpot = spot
                    showForm = true
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        Task { await deleteSpot(spot) }
                    } label: {
                        Text("削除")
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button {
                        Task { await setSpotActive(spot, isActive: !spot.isActive) }
                    } label: {
                        Text(spot.isActive ? "無効化" : "有効化")
                    }
                    .tint(spot.isActive ? .gray : .green)
                }
            }
        }
        .navigationTitle("スポット管理")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "スポット名で検索")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("追加") {
                    editingSpot = nil
                    showForm = true
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("更新") {
                    Task { await loadSpots() }
                }
                .disabled(isLoading)
            }
        }
        .sheet(isPresented: $showForm, onDismiss: {
            Task { await loadSpots() }
        }) {
            AdminSpotFormView(spot: editingSpot)
        }
        .task {
            await loadSpots()
        }
    }

    private func loadSpots() async {
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await firestoreService.fetchAllSpots()
            await MainActor.run {
                spots = fetched
            }
        } catch {
            errorMessage = "スポットの取得に失敗しました"
        }
        isLoading = false
    }

    private func setSpotActive(_ spot: Spot, isActive: Bool) async {
        do {
            try await firestoreService.updateSpotActive(spotID: spot.id, isActive: isActive)
            await loadSpots()
        } catch {
            errorMessage = "スポットの更新に失敗しました"
        }
    }

    private func deleteSpot(_ spot: Spot) async {
        do {
            try await firestoreService.deleteSpot(spotID: spot.id)
            await loadSpots()
        } catch {
            errorMessage = "スポットの削除に失敗しました"
        }
    }

    private var filteredSpots: [Spot] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return spots }
        return spots.filter { $0.name.localizedCaseInsensitiveContains(keyword) }
    }
}
