// Parse quantities only in duration phrases, never calendar day numbers.
function dayQuantity(value) {
  const text = String(value || '').toLowerCase();
  if (/\b(?:half[ -](?:a[ -])?day|half a day|0\.5\s*(?:days?|adlaw|araw)|tunga sa adlaw|kalahating araw)\b/.test(text)) return 0.5;
  const numeric = text.match(/\b(\d+(?:\.\d+)?)\s*(?:ka\s*)?(?:days?|adlaw|araw)\b/);
  if (numeric) { const n = Number(numeric[1]); return n > 0 && n <= 365 ? n : null; }
  const units = {one:1,two:2,three:3,four:4,five:5,six:6,seven:7,eight:8,nine:9,ten:10,eleven:11,twelve:12,thirteen:13,fourteen:14,fifteen:15,sixteen:16,seventeen:17,eighteen:18,nineteen:19,twenty:20,thirty:30,forty:40,fifty:50,sixty:60,ninety:90,usa:1,isa:1,duha:2,dalawa:2,tulo:3,tatlo:3,upat:4,apat:4,lima:5,unom:6,anim:6,pito:7,walo:8,siyam:9,napulo:10};
  const match = text.match(/\b([a-z]+)(?:[ -]([a-z]+))?\s+(?:ka\s*)?(?:days?|adlaw|araw)\b/);
  if (!match) return null;
  if (!match[2]) return units[match[1]] || null;
  const tens = units[match[1]], ones = units[match[2]];
  if (tens >= 20 && tens % 10 === 0 && ones > 0 && ones < 10) return tens + ones;
  return ones || null;
}
module.exports = { dayQuantity };
