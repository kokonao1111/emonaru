import SwiftUI
import UIKit

struct MiniGameView: View {
    @State private var registeredPrefecture: Prefecture?
    @State private var showSettings = false
    private let firestoreService = FirestoreService()

    var body: some View {
        if let registeredPrefecture = registeredPrefecture {
            PrefectureGameMapView(prefecture: registeredPrefecture)
                .onAppear {
                    Task {
                        await syncAndRegisterPrefecture()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SettingsUpdated"))) { _ in
                    Task {
                        await syncAndRegisterPrefecture()
                    }
                }
        } else {
            setupView
        }
    }
    
    // 累計報酬を計算
    private func calculateTotalRewards(completedCount: Int) -> (totalExperience: Int, totalPostBonus: Int) {
        var totalExp = 0
        var totalPost = 0
        
        for level in 1...completedCount {
            let rewards = calculateRewards(completedCount: level)
            totalExp += rewards.experience
            totalPost += rewards.postBonus
        }
        
        return (totalExp, totalPost)
    }
    
    // 報酬情報カードのビュー
    private func rewardInfoCardView(isSmallScreen: Bool) -> some View {
        let baseRewards = calculateRewards(completedCount: 1)
        
        return VStack(spacing: isSmallScreen ? 12 : 16) {
            Text("ゲージ満タン報酬")
                .font(isSmallScreen ? .headline : .title3)
                .fontWeight(.bold)
            
            VStack(spacing: isSmallScreen ? 8 : 12) {
                // 経験値
                HStack(spacing: isSmallScreen ? 8 : 12) {
                    Image(systemName: "bolt.circle.fill")
                        .font(.system(size: isSmallScreen ? 24 : 32))
                        .foregroundColor(.yellow)
                    
                    VStack(alignment: .leading, spacing: isSmallScreen ? 2 : 4) {
                        Text("経験値")
                            .font(isSmallScreen ? .subheadline : .headline)
                            .foregroundColor(.primary)
                        Text("+\(baseRewards.experience)~ EXP")
                            .font(isSmallScreen ? .headline : .title2)
                            .fontWeight(.bold)
                            .foregroundColor(.yellow)
                    }
                    
                    Spacer()
                }
                .padding(isSmallScreen ? 12 : 16)
                .background(Color.yellow.opacity(0.1))
                .cornerRadius(isSmallScreen ? 10 : 12)
                
                // 投稿回数
                HStack(spacing: isSmallScreen ? 8 : 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: isSmallScreen ? 24 : 32))
                        .foregroundColor(.green)
                    
                    VStack(alignment: .leading, spacing: isSmallScreen ? 2 : 4) {
                        Text("投稿回数ボーナス")
                            .font(isSmallScreen ? .subheadline : .headline)
                            .foregroundColor(.primary)
                        Text("+\(baseRewards.postBonus)~回")
                            .font(isSmallScreen ? .headline : .title2)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    }
                    
                    Spacer()
                }
                .padding(isSmallScreen ? 12 : 16)
                .background(Color.green.opacity(0.1))
                .cornerRadius(isSmallScreen ? 10 : 12)
            }
            
            Text("レベルが上がるほど報酬も増えます！\nみんなで感情を投稿してゲージを貯めよう！")
                .font(isSmallScreen ? .caption2 : .caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(isSmallScreen ? 12 : 16)
        .background(Color.white.opacity(0.8))
        .cornerRadius(isSmallScreen ? 12 : 16)
        .shadow(color: .black.opacity(0.1), radius: 5)
    }

    private var setupView: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let isSmallScreen = screenWidth <= 375 // iPhone SE (375px) 以下
            
            NavigationView {
                ScrollView {
                    VStack(spacing: isSmallScreen ? 16 : 24) {
                        Text("ミニゲームを始めるには\n設定で住んでいる県を登録してください")
                            .multilineTextAlignment(.center)
                            .font(isSmallScreen ? .subheadline : .headline)
                        
                        // 報酬情報カード
                        rewardInfoCardView(isSmallScreen: isSmallScreen)

                        Button(action: {
                            showSettings = true
                        }) {
                            Text("設定を開く")
                                .font(isSmallScreen ? .subheadline : .headline)
                                .foregroundColor(.white)
                                .padding(.horizontal, isSmallScreen ? 20 : 24)
                                .padding(.vertical, isSmallScreen ? 10 : 12)
                                .background(Color.blue)
                                .cornerRadius(isSmallScreen ? 8 : 10)
                        }
                    }
                    .padding(isSmallScreen ? 12 : 16)
                }
                .navigationTitle("ミニゲーム")
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .onAppear {
                Task {
                    await syncAndRegisterPrefecture()
                }
            }
            .navigationViewStyle(.stack)
        }
    }

    private func syncAndRegisterPrefecture() async {
        registeredPrefecture = UserService.shared.homePrefecture
        
        // 県が設定されている場合は、自動的に登録を試みる
        if let prefecture = registeredPrefecture {
            do {
                try await firestoreService.registerToPrefecture(prefecture)
                print("✅ \(prefecture.rawValue)の登録を確認しました")
            } catch {
                print("⚠️ \(prefecture.rawValue)の登録確認中にエラー: \(error.localizedDescription)")
            }
        }
    }
    
    // 完了回数に応じた報酬を計算
    private func calculateRewards(completedCount: Int) -> (experience: Int, postBonus: Int) {
        // 10回ごとに報酬が増える
        let tier = completedCount / 10
        
        // 経験値: 基本100 + (tier * 50)
        let experience = 100 + (tier * 50)
        
        // 投稿回数ボーナス: 基本1 + (tier / 2)
        let postBonus = 1 + (tier / 2)
        
        return (experience, postBonus)
    }
}

// 都道府県カード
struct PrefectureCard: View {
    let prefecture: Prefecture
    let gauge: PrefectureGauge?
    let registration: UserPrefectureRegistration?
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Text(prefecture.rawValue)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                if let gauge = gauge {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 8)
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(gauge.isCompleted ? Color.green : Color.blue)
                                .frame(width: geometry.size.width * gauge.progress, height: 8)
                        }
                    }
                    .frame(height: 8)
                    
                    if gauge.isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)
                }
            }
            .padding(8)
            .background(Color.white.opacity(0.8))
            .cornerRadius(8)
            .shadow(radius: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// 都道府県詳細ビュー
struct PrefectureDetailView: View {
    let prefecture: Prefecture
    let gauge: PrefectureGauge?
    let registration: UserPrefectureRegistration?
    let onRegistered: (Prefecture) -> Void
    @Environment(\.dismiss) private var dismiss
    
    private let firestoreService = FirestoreService()
    @State private var isRegistering = false
    @State private var showSuccessAlert = false
    
    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let isSmallScreen = screenWidth <= 375 // iPhone SE (375px) 以下
            
            NavigationView {
                ScrollView {
                    VStack(spacing: isSmallScreen ? 16 : 24) {
                        Text(prefecture.rawValue)
                            .font(isSmallScreen ? .title : .largeTitle)
                            .fontWeight(.bold)
                            .padding(.top, isSmallScreen ? 8 : 16)
                        
                        if let gauge = gauge {
                            VStack(spacing: isSmallScreen ? 12 : 16) {
                                Text("感情ゲージ")
                                    .font(isSmallScreen ? .subheadline : .headline)
                            
                                VStack(spacing: isSmallScreen ? 4 : 8) {
                                    HStack {
                                        Text("進捗")
                                            .font(isSmallScreen ? .caption : .body)
                                        Spacer()
                                        Text("\(gauge.currentValue)/\(gauge.maxValue)")
                                            .font(isSmallScreen ? .caption : .body)
                                            .fontWeight(.semibold)
                                    }
                                    
                                    GeometryReader { gaugeGeometry in
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: isSmallScreen ? 10 : 12)
                                                .fill(Color.gray.opacity(0.2))
                                                .frame(height: isSmallScreen ? 24 : 30)
                                            
                                            RoundedRectangle(cornerRadius: isSmallScreen ? 10 : 12)
                                                .fill(gauge.isCompleted ? Color.green : Color.blue)
                                                .frame(width: gaugeGeometry.size.width * gauge.progress, height: isSmallScreen ? 24 : 30)
                                                .animation(.spring(), value: gauge.progress)
                                        }
                                    }
                                    .frame(height: isSmallScreen ? 24 : 30)
                                
                                    Text("\(Int(gauge.progress * 100))%")
                                        .font(isSmallScreen ? .caption2 : .caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(isSmallScreen ? 12 : 16)
                                .background(Color.white.opacity(0.8))
                                .cornerRadius(isSmallScreen ? 10 : 12)
                            
                            // 報酬情報（常に表示）
                            rewardInfoSection(gauge: gauge, registration: registration, isSmallScreen: isSmallScreen)
                        }
                        .padding(isSmallScreen ? 12 : 16)
                    }
                    
                    if registration == nil {
                        registrationPromptSectionView(isSmallScreen: isSmallScreen)
                    } else if let reg = registration {
                        registrationStatusSection(registration: reg, isSmallScreen: isSmallScreen)
                    }
                }
                .padding(isSmallScreen ? 12 : 16)
            }
            .navigationTitle("都道府県詳細")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
            .alert("登録完了", isPresented: $showSuccessAlert) {
                Button("OK") { }
            } message: {
                registrationSuccessMessage
            }
        }
        }
    }
    
    private func registerToPrefecture() async {
        isRegistering = true
        do {
            try await firestoreService.registerToPrefecture(prefecture)
            await MainActor.run {
                showSuccessAlert = true
                isRegistering = false
            }
            // 登録後に地図ビューに切り替え
            onRegistered(prefecture)
            dismiss()
        } catch {
            await MainActor.run {
                isRegistering = false
            }
        }
    }
    
    // 完了回数に応じた報酬を計算
    private func calculateRewards(completedCount: Int) -> (experience: Int, postBonus: Int) {
        // 10回ごとに報酬が増える
        let tier = completedCount / 10
        
        // 経験値: 基本100 + (tier * 50)
        let experience = 100 + (tier * 50)
        
        // 投稿回数ボーナス: 基本1 + (tier / 2)
        let postBonus = 1 + (tier / 2)
        
        return (experience, postBonus)
    }
    
    // 累計報酬を計算
    private func calculateTotalRewards(completedCount: Int) -> (totalExperience: Int, totalPostBonus: Int) {
        var totalExp = 0
        var totalPost = 0
        
        for level in 1...completedCount {
            let rewards = calculateRewards(completedCount: level)
            totalExp += rewards.experience
            totalPost += rewards.postBonus
        }
        
        return (totalExp, totalPost)
    }
    
    // 報酬情報セクションのビュー
    private func rewardInfoSection(gauge: PrefectureGauge, registration: UserPrefectureRegistration?, isSmallScreen: Bool) -> some View {
        let nextLevel = (registration?.completedCount ?? 0) + 1
        let nextRewards = calculateRewards(completedCount: nextLevel)
        
        return VStack(spacing: isSmallScreen ? 8 : 12) {
            if gauge.isCompleted {
                HStack {
                    Image(systemName: "star.circle.fill")
                        .font(.system(size: isSmallScreen ? 24 : 32))
                        .foregroundColor(.yellow)
                    
                    Text("ゲージ満タン達成！")
                        .font(isSmallScreen ? .headline : .title3)
                        .fontWeight(.bold)
                }
            } else {
                HStack {
                    Image(systemName: "gift.fill")
                        .font(.system(size: isSmallScreen ? 20 : 24))
                        .foregroundColor(.orange)
                    
                    VStack(alignment: .leading, spacing: isSmallScreen ? 1 : 2) {
                        Text("満タン時の報酬")
                            .font(isSmallScreen ? .subheadline : .headline)
                            .fontWeight(.semibold)
                        Text("レベル\(nextLevel)")
                            .font(isSmallScreen ? .caption2 : .caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            VStack(spacing: isSmallScreen ? 4 : 8) {
                HStack {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: isSmallScreen ? 14 : 16))
                        .foregroundColor(.yellow)
                    Text("経験値 +\(nextRewards.experience)")
                        .font(isSmallScreen ? .subheadline : .headline)
                        .fontWeight(.bold)
                }
                
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: isSmallScreen ? 14 : 16))
                        .foregroundColor(.green)
                    Text("投稿回数 +\(nextRewards.postBonus)回")
                        .font(isSmallScreen ? .subheadline : .headline)
                        .fontWeight(.bold)
                }
                
                if gauge.isCompleted, let reg = registration {
                    Divider()
                    
                    Text("レベル\(reg.completedCount) クリア済み")
                        .font(isSmallScreen ? .caption : .subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(isSmallScreen ? 12 : 16)
            .background(Color.yellow.opacity(0.1))
            .cornerRadius(isSmallScreen ? 6 : 8)
        }
        .padding(isSmallScreen ? 12 : 16)
        .background(gauge.isCompleted ? Color.green.opacity(0.1) : Color.blue.opacity(0.1))
        .cornerRadius(isSmallScreen ? 10 : 12)
    }
    
    // 登録促進セクションのビュー
    private func registrationPromptSectionView(isSmallScreen: Bool) -> some View {
        let firstRewards = calculateRewards(completedCount: 1)
        
        return VStack(spacing: isSmallScreen ? 8 : 12) {
            Text("この都道府県に登録すると、ゲージ満タン時に経験値\(firstRewards.experience)と投稿回数+\(firstRewards.postBonus)回がもらえます")
                .font(isSmallScreen ? .caption2 : .caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: {
                Task {
                    await registerToPrefecture()
                }
            }) {
                HStack {
                    Image(systemName: "bolt.fill")
                    Text("この都道府県に登録する")
                }
                .font(isSmallScreen ? .subheadline : .headline)
                .foregroundColor(.white)
                .padding(isSmallScreen ? 12 : 16)
                .frame(maxWidth: .infinity)
                .background(Color.blue)
                .cornerRadius(isSmallScreen ? 10 : 12)
            }
            .disabled(isRegistering)
        }
        .padding(isSmallScreen ? 12 : 16)
    }
    
    // 登録完了メッセージ
    private var registrationSuccessMessage: Text {
        let firstRewards = calculateRewards(completedCount: 1)
        return Text("\(prefecture.rawValue)に登録しました！ゲージが満タンになると経験値\(firstRewards.experience)と投稿回数+\(firstRewards.postBonus)回を獲得できます。")
    }
    
    // 登録済み状態のセクション
    private func registrationStatusSection(registration: UserPrefectureRegistration, isSmallScreen: Bool) -> some View {
        let totalRewards = calculateTotalRewards(completedCount: registration.completedCount)
        
        return VStack(spacing: isSmallScreen ? 8 : 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: isSmallScreen ? 20 : 24))
                    .foregroundColor(.green)
                Text("登録済み")
                    .font(isSmallScreen ? .subheadline : .headline)
                    .foregroundColor(.green)
            }
            
            VStack(spacing: isSmallScreen ? 4 : 8) {
                HStack {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: isSmallScreen ? 14 : 16))
                        .foregroundColor(.yellow)
                    Text("クリア回数: \(registration.completedCount)")
                        .font(isSmallScreen ? .caption : .subheadline)
                        .fontWeight(.semibold)
                }
                
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: isSmallScreen ? 14 : 16))
                        .foregroundColor(.blue)
                    Text("累計経験値: \(totalRewards.totalExperience)")
                        .font(isSmallScreen ? .caption : .subheadline)
                }
                
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: isSmallScreen ? 14 : 16))
                        .foregroundColor(.green)
                    Text("累計投稿回数: +\(totalRewards.totalPostBonus)")
                        .font(isSmallScreen ? .caption : .subheadline)
                }
            }
        }
        .padding(isSmallScreen ? 12 : 16)
        .background(Color.green.opacity(0.1))
        .cornerRadius(isSmallScreen ? 10 : 12)
    }
}

private func titleAssetName(for title: String) -> String {
    let normalized = title
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "・", with: "")
        .replacingOccurrences(of: "／", with: "")
        .replacingOccurrences(of: "（", with: "")
        .replacingOccurrences(of: "）", with: "")
        .replacingOccurrences(of: "ー", with: "")
        .replacingOccurrences(of: "－", with: "")
        .replacingOccurrences(of: "—", with: "")
        .replacingOccurrences(of: "〜", with: "")
    return "title_\(normalized)"
}
