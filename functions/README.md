# EmotionSNS - Firebase Cloud Functions

EmotionSNSアプリのプッシュ通知とゲーム機能を管理するCloud Functions。

## 📋 機能一覧

### 1. sendNotificationOnCreateV2
**トリガー**: Firestoreの`notifications`コレクションにドキュメントが作成された時

**機能**: 
- ユーザーに対してFCMプッシュ通知を送信
- 複数のFCMトークンをサポート（マルチデバイス対応）
- 無効なトークンの自動削除
- iOS APNs設定（バックグラウンド起動、サウンド、バッジ）

**対応する通知タイプ**:
- 友達申請 (`friendRequest`)
- 友達承認 (`friendAccepted`)
- いいね (`like`)
- 共感/応援 (`support`)
- コメント (`comment`)
- 投稿閲覧 (`view`)
- ミッション達成 (`missionCleared`)
- ゲージ満タン (`gaugeFilled`)
- モヤ浄化完了 (`mistCleared`)

### 2. awardGaugeExperienceV2
**トリガー**: Firestoreの`prefectureGauges`コレクションのドキュメントが更新された時

**機能**:
- 都道府県ゲージが満タンになった時、貢献者に経験値を付与
- ゲージを完了させたユーザー: +50 XP
- その他の貢献者: +10 XP

## 🚀 デプロイ方法

### 前提条件
- Node.js 20以上
- Firebase CLI
- Firebaseプロジェクトへのアクセス権限

### 初回セットアップ

1. Firebase CLIにログイン:
```bash
firebase login
```

2. functionsフォルダに移動:
```bash
cd functions
```

3. 依存関係をインストール:
```bash
npm install
```

### 全Functionsをデプロイ

```bash
npx firebase deploy --only functions
```

### 特定のFunctionのみデプロイ

```bash
# 通知機能のみ
npx firebase deploy --only functions:sendNotificationOnCreateV2

# ゲージ経験値機能のみ
npx firebase deploy --only functions:awardGaugeExperienceV2
```

## 🔧 トラブルシューティング

### `sendMulticast is not a function` エラー
**原因**: `firebase-admin`の古いバージョンまたはAPIの非互換性

**解決策**: このプロジェクトでは`send()`メソッドを使用して個別送信しています（既に修正済み）

### `npm ci` エラー
**原因**: `package-lock.json`が同期していない

**解決策**:
```bash
rm -rf node_modules package-lock.json
npm install
```

### 認証エラー
**原因**: Firebase CLIの認証トークンが期限切れ

**解決策**:
```bash
firebase login --reauth
```

## 📊 ログの確認

### 最近のログを表示
```bash
npx firebase functions:log --lines 50
```

### 特定のFunctionのログを表示
```bash
npx firebase functions:log --only sendNotificationOnCreateV2
```

### リアルタイムでログを監視
```bash
npx firebase functions:log --tail
```

## 🔐 必要な権限

Cloud Functionsが正しく動作するには、以下のFirebase APIが有効になっている必要があります：

- Cloud Functions API (`cloudfunctions.googleapis.com`)
- Cloud Build API (`cloudbuild.googleapis.com`)
- Artifact Registry API (`artifactregistry.googleapis.com`)
- Cloud Run API (`run.googleapis.com`)
- Eventarc API (`eventarc.googleapis.com`)
- Pub/Sub API (`pubsub.googleapis.com`)

これらは初回デプロイ時に自動的に有効化されます。

## 📱 iOS APNs設定

プッシュ通知をiOSで受信するには、Firebase ConsoleでAPNs認証キーまたは証明書を設定する必要があります：

1. [Firebase Console](https://console.firebase.google.com/) にアクセス
2. プロジェクトを選択
3. **プロジェクトの設定** > **Cloud Messaging**
4. **Apple アプリの設定** セクションでAPNs認証キーまたは証明書をアップロード

## 🛠️ 開発

### ローカルでテスト（エミュレータ）

```bash
firebase emulators:start --only functions
```

### コードの修正後

1. コードを修正
2. 変更をコミット
3. デプロイ:
```bash
npx firebase deploy --only functions
```

## 📝 注意事項

- Node.js 20は2026年10月30日にサポート終了予定です
- 定期的に`firebase-admin`と`firebase-functions`を最新バージョンに更新してください
- 本番環境へのデプロイ前に、必ずテストを実施してください

## 📞 サポート

問題が発生した場合は、以下を確認してください：

1. [Firebase Console](https://console.firebase.google.com/)でプロジェクトの状態を確認
2. Cloud Functionsのログを確認
3. Firestoreのセキュリティルールを確認
4. FCMトークンが正しく保存されているか確認（`users`コレクション）

---

最終更新: 2026-02-12
