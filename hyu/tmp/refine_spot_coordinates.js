const fs = require("fs");
const path = require("path");

const inputPath = path.join(__dirname, "spot_coordinates.json");
const outputPath = path.join(__dirname, "spot_coordinates.json");

const data = JSON.parse(fs.readFileSync(inputPath, "utf8"));

const queryOverrides = {
  "富良野・美瑛のラベンダー畑": "ファーム富田 北海道",
  "十和田湖・奥入瀬渓流": "奥入瀬渓流 青森",
  "平泉世界遺産": "平泉町 岩手",
  "角館の武家屋敷通り": "角館 武家屋敷通り 秋田",
  "男鹿半島のなまはげ館": "なまはげ館 秋田",
  "蔵王連峰・御釜": "蔵王 御釜 宮城",
  "日立海浜公園": "国営ひたち海浜公園 茨城",
  "川越の蔵造りの街並み": "川越 蔵造りの町並み 埼玉",
  "長瀞ライン下り": "長瀞 ラインくだり 埼玉",
  "鎌倉大仏（高徳院）": "高徳院 鎌倉大仏 神奈川",
  "越後湯沢温泉エリア": "越後湯沢温泉 新潟",
  "五箇山合掌造り集落": "五箇山 相倉集落 富山",
  "越前海岸": "越前海岸 福井",
  "富士山（河口湖周辺・五合目エリア）": "河口湖 富士山 山梨",
  "白川郷合掌造り集落": "白川郷 岐阜",
  "高山の古い町並み": "高山 古い町並み 岐阜",
  "富士山（世界遺産・周辺エリア）": "富士山 静岡",
  "熱海温泉": "熱海温泉 静岡",
  "神戸・北野異人館街": "北野異人館街 神戸",
  "那智の滝": "那智の滝 和歌山",
  "倉吉の白壁土蔵群": "倉吉 白壁土蔵群 鳥取",
  "広島平和記念公園・原爆ドーム": "広島平和記念公園",
  "呉の大和ミュージアム": "大和ミュージアム 呉",
  "秋吉台カルスト台地": "秋吉台 山口",
  "鳴門公園（大鳴門橋架橋記念公園）": "鳴門公園 徳島",
  "長崎原爆資料館・平和公園": "長崎原爆資料館",
  "日南海岸": "日南海岸 宮崎",
};

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function geocode(query) {
  const url =
    "https://nominatim.openstreetmap.org/search?format=json&limit=1&q=" +
    encodeURIComponent(query);
  const res = await fetch(url, {
    headers: {
      "User-Agent": "EmotionSNS/1.0 (contact: local-script)",
    },
  });
  if (!res.ok) {
    return null;
  }
  const json = await res.json();
  if (!Array.isArray(json) || json.length === 0) {
    return null;
  }
  return {
    latitude: Number(json[0].lat),
    longitude: Number(json[0].lon),
  };
}

async function run() {
  for (let i = 0; i < data.length; i += 1) {
    const item = data[i];
    if (item.latitude != null && item.longitude != null) {
      continue;
    }
    const query = queryOverrides[item.name];
    if (!query) {
      continue;
    }
    const coords = await geocode(query);
    if (coords) {
      item.latitude = coords.latitude;
      item.longitude = coords.longitude;
    }
    process.stdout.write(`\r${item.name}`);
    await sleep(1100);
  }
  process.stdout.write("\n");
  fs.writeFileSync(outputPath, JSON.stringify(data, null, 2));
  console.log("Updated:", outputPath);
}

run().catch((err) => {
  console.error(err);
  process.exit(1);
});
