import SwiftUI

struct AdminSpotFormView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var latitude: String
    @State private var longitude: String
    @State private var radius: String
    @State private var isActive: Bool
    @State private var errorMessage: String?
    @State private var isSaving = false

    private let existingSpot: Spot?
    private let firestoreService = FirestoreService()

    init(spot: Spot? = nil) {
        self.existingSpot = spot
        _name = State(initialValue: spot?.name ?? "")
        _latitude = State(initialValue: spot.map { String($0.latitude) } ?? "")
        _longitude = State(initialValue: spot.map { String($0.longitude) } ?? "")
        _radius = State(initialValue: spot.map { String(Int($0.radius)) } ?? "50")
        _isActive = State(initialValue: spot?.isActive ?? true)
    }

    var body: some View {
        NavigationView {
            Form {
                Section("スポット情報") {
                    TextField("名称", text: $name)
                    TextField("緯度", text: $latitude)
                        .keyboardType(.decimalPad)
                    TextField("経度", text: $longitude)
                        .keyboardType(.decimalPad)
                    TextField("半径（m）", text: $radius)
                        .keyboardType(.numberPad)
                    Toggle("有効", isOn: $isActive)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .navigationTitle(existingSpot == nil ? "スポット追加" : "スポット編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private func save() async {
        errorMessage = nil
        isSaving = true

        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "名称を入力してください"
            isSaving = false
            return
        }
        guard let lat = Double(latitude), let lon = Double(longitude) else {
            errorMessage = "緯度・経度を正しく入力してください"
            isSaving = false
            return
        }
        guard let radiusValue = Double(radius), radiusValue > 0 else {
            errorMessage = "半径を正しく入力してください"
            isSaving = false
            return
        }

        do {
            if let spot = existingSpot {
                try await firestoreService.updateSpot(
                    spotID: spot.id,
                    name: name,
                    latitude: lat,
                    longitude: lon,
                    radius: radiusValue,
                    isActive: isActive
                )
            } else {
                let newSpot = Spot(
                    id: UUID().uuidString,
                    name: name,
                    latitude: lat,
                    longitude: lon,
                    radius: radiusValue,
                    isActive: isActive
                )
                try await firestoreService.createSpot(newSpot)
            }
            dismiss()
        } catch {
            errorMessage = "保存に失敗しました"
        }

        isSaving = false
    }
}
