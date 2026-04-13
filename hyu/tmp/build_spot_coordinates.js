const fs = require("fs");
const path = require("path");

const repoRoot = path.resolve(__dirname, "..");
const sourcePath = path.join(
  repoRoot,
  "src",
  "Services",
  "FirestoreService.swift"
);
const outputPath = path.join(__dirname, "spot_coordinates.json");

const source = fs.readFileSync(sourcePath, "utf8");
const spotBlockMatch = source.match(/private var spotDefinitions: [\s\S]*?\n\s*\]\n\s*\}/);
if (!spotBlockMatch) {
  console.error("spotDefinitions block not found.");
  process.exit(1);
}

const tupleRegex = /\("([^"]+)",\s*"([^"]+)"\)/g;
const spots = [];
let match;
while ((match = tupleRegex.exec(spotBlockMatch[0])) !== null) {
  spots.push({ prefecture: match[1], name: match[2] });
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function geocodeSpot(spot) {
  const query = `${spot.name} ${spot.prefecture} 日本`;
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
  const data = await res.json();
  if (!Array.isArray(data) || data.length === 0) {
    return null;
  }
  return {
    latitude: Number(data[0].lat),
    longitude: Number(data[0].lon),
  };
}

async function run() {
  const results = [];
  for (let i = 0; i < spots.length; i += 1) {
    const spot = spots[i];
    const coords = await geocodeSpot(spot);
    results.push({
      prefecture: spot.prefecture,
      name: spot.name,
      latitude: coords ? coords.latitude : null,
      longitude: coords ? coords.longitude : null,
    });
    process.stdout.write(`\r${i + 1}/${spots.length} ${spot.name}`);
    await sleep(1100);
  }
  process.stdout.write("\n");
  fs.writeFileSync(outputPath, JSON.stringify(results, null, 2));
  console.log(`Saved: ${outputPath}`);
}

run().catch((err) => {
  console.error(err);
  process.exit(1);
});
