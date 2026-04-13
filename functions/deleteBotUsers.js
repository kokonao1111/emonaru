const admin = require("firebase-admin");

// Firebase Admin SDKを初期化
admin.initializeApp();

async function deleteBotUsers() {
  console.log("🗑️  botアカウントを削除中...\n");
  
  const db = admin.firestore();
  const usersRef = db.collection("users");
  
  // bot_user で始まるドキュメントを検索
  const snapshot = await usersRef.get();
  
  let deleteCount = 0;
  const deletePromises = [];
  
  snapshot.forEach((doc) => {
    if (doc.id.startsWith("bot_user_")) {
      console.log(`❌ 削除: ${doc.id}`);
      deletePromises.push(doc.ref.delete());
      deleteCount++;
    }
  });
  
  await Promise.all(deletePromises);
  
  console.log(`\n✅ ${deleteCount}個のbotアカウントを削除しました`);
  process.exit(0);
}

deleteBotUsers().catch((error) => {
  console.error("❌ エラー:", error);
  process.exit(1);
});
