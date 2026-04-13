const admin = require("firebase-admin");
const {
  onDocumentCreated,
  onDocumentUpdated,
} = require("firebase-functions/v2/firestore");

admin.initializeApp();

exports.sendNotificationOnCreateV2 = onDocumentCreated(
  "notifications/{notificationId}",
  async (event) => {
    console.log("\n========================================");
    console.log("📨 Cloud Function トリガー: sendNotificationOnCreateV2");
    console.log("========================================");
    
    const data = event.data ? event.data.data() : {};
    const toUserID = data.toUserID;
    const notificationId = event.data ? event.data.id : "unknown";
    
    console.log("📋 通知データ:", {
      notificationId,
      type: data.type,
      title: data.title,
      body: data.body,
      toUserID,
      fromUserID: data.fromUserID,
      relatedID: data.relatedID,
    });
    
    if (!toUserID) {
      console.warn("❌ toUserIDが指定されていません");
      return null;
    }

    console.log("\n📂 Firestoreからユーザー情報を取得中...");
    const userDoc = await admin.firestore().collection("users").doc(toUserID).get();
    if (!userDoc.exists) {
      console.warn("❌ ユーザーが存在しません:", toUserID);
      return null;
    }
    console.log("✅ ユーザー情報取得成功");

    // トークンを収集（重複を排除）
    console.log("\n📱 FCMトークンの収集中...");
    const tokens = Array.isArray(userDoc.get("fcmTokens"))
      ? userDoc.get("fcmTokens")
      : [];
    const singleToken = userDoc.get("fcmToken");
    
    console.log("   - fcmTokens配列:", tokens.length > 0 ? `${tokens.length}個` : "なし");
    console.log("   - fcmToken (単体):", singleToken ? "あり" : "なし");
    
    if (singleToken && !tokens.includes(singleToken)) {
      tokens.push(singleToken);
      console.log("   - 単体トークンを配列に追加");
    }

    // トークンの重複を排除
    const uniqueTokens = [...new Set(tokens)];

    if (uniqueTokens.length === 0) {
      console.warn("❌ FCMトークンが登録されていません:", toUserID);
      console.warn("   → ユーザーはプッシュ通知を受け取れません");
      return null;
    }

    console.log("✅ 送信先トークン数:", uniqueTokens.length);
    uniqueTokens.forEach((token, index) => {
      console.log(`   ${index + 1}. ${token.substring(0, 30)}...`);
    });

    // 通常の通知ペイロード
    console.log("\n📦 通知ペイロードを作成中...");
    const payload = {
      notification: {
        title: data.title || "通知",
        body: data.body || "",
      },
      data: {
        type: data.type || "",
        relatedID: data.relatedID || "",
        notificationID: event.data ? event.data.id : "",
      },
      apns: {
        payload: {
          aps: {
            // バックグラウンドでもアプリを起動
            contentAvailable: true,
            // 通知音とバッジ
            sound: "default",
            badge: 1,
          },
        },
      },
    };
    
    console.log("✅ ペイロード作成完了:");
    console.log("   - タイトル:", payload.notification.title);
    console.log("   - 本文:", payload.notification.body);
    console.log("   - タイプ:", payload.data.type);

    console.log("\n📤 FCMメッセージを送信中...");
    try {
      // 各トークンに個別に送信（sendMulticastが使えない場合）
      const results = await Promise.allSettled(
        uniqueTokens.map((token) =>
          admin.messaging().send({
            token: token,
            ...payload,
          })
        )
      );

      let successCount = 0;
      let failureCount = 0;
      const invalidTokens = [];

      results.forEach((result, index) => {
        if (result.status === "fulfilled") {
          successCount++;
          console.log("✅ 通知送信成功:", uniqueTokens[index].substring(0, 20) + "...");
        } else {
          failureCount++;
          const error = result.reason;
          const code = error && error.code;
          console.error("❌ 通知送信エラー:", {
            token: uniqueTokens[index].substring(0, 20) + "...",
            code,
            message: error && error.message,
          });

          // 無効なトークンまたは未登録のトークン
          if (
            code === "messaging/registration-token-not-registered" ||
            code === "messaging/invalid-registration-token"
          ) {
            invalidTokens.push(uniqueTokens[index]);
          }
        }
      });

      console.log("\n========================================");
      console.log("✅ 通知送信処理完了");
      console.log("========================================");
      console.log("   - 成功:", successCount);
      console.log("   - 失敗:", failureCount);
      console.log("   - 無効トークン:", invalidTokens.length);
      console.log("========================================\n");

      // 無効なトークンを削除
      if (invalidTokens.length > 0) {
        console.log("🗑️ 無効なトークンをFirestoreから削除中...");
        await admin.firestore().collection("users").doc(toUserID).set(
          {
            fcmTokens: admin.firestore.FieldValue.arrayRemove(...invalidTokens),
          },
          { merge: true }
        );
        console.log("✅ 無効トークンの削除完了\n");
      }
    } catch (error) {
      console.error("\n❌❌❌ 通知送信中に予期しないエラーが発生 ❌❌❌");
      console.error("エラー詳細:", error);
      console.error("スタックトレース:", error.stack);
      console.error("========================================\n");
    }

    return null;
  }
);

exports.awardGaugeExperienceV2 = onDocumentUpdated(
  "prefectureGauges/{prefectureId}",
  async (event) => {
    const before = event.data && event.data.before ? event.data.before.data() || {} : {};
    const after = event.data && event.data.after ? event.data.after.data() || {} : {};

    const beforeCompleted = before.completedDate || null;
    const afterCompleted = after.completedDate || null;

    if (!afterCompleted || beforeCompleted === afterCompleted) {
      return null;
    }

    const contributors = Array.isArray(after.lastCompletedContributors)
      ? after.lastCompletedContributors
      : [];
    const completer = after.lastCompleterID || null;

    if (!contributors.length) {
      return null;
    }

    const updates = contributors.map((userId) => {
      const isCompleter = completer && userId === completer;
      const xp = isCompleter ? 50 : 10;
      return admin
        .firestore()
        .collection("users")
        .doc(userId)
        .set(
          {
            experiencePoints: admin.firestore.FieldValue.increment(xp),
            experienceUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
    });

    await Promise.all(updates);
    return null;
  }
);
