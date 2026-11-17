// вставка ключа "smith" в data/dialogues_v2.json с сохранением окончаний строк
const fs = require('fs');
const f = 'pixel-rpg/data/dialogues_v2.json';
let t = fs.readFileSync(f, 'utf8');
if (t.includes('"smith"')) { console.log('already'); process.exit(0); }
const nl = t.includes('\r\n') ? '\r\n' : '\n';
const lines = [
  '"smith": [',
  '\t\t{"who": "smith", "text": "Куй да плати — вот и вся песня. Я Гриим: молот держу с семи зим, а лес у нас один на двоих — мой и гнили."},',
  '\t\t{"who": "smith", "text": "Мечи, топоры, кожа, кольчуга — всё за звонкое золото. Меч из сундука — игрушка, а у меня сталь."},',
  '\t\t{"who": "hero", "text": "Слушаю, кузнец. Что есть доброго?"}',
  '\t],',
];
const anchor = '\t"cave_intro": [';
const i = t.indexOf(anchor);
if (i < 0) { console.error('anchor not found'); process.exit(1); }
t = t.slice(0, i) + lines.join(nl) + nl + t.slice(i);
fs.writeFileSync(f, t);
// валидность JSON
JSON.parse(fs.readFileSync(f, 'utf8'));
console.log('ok, smith inserted, JSON valid, nl=' + JSON.stringify(nl));
