// node tools/gh_search.js <file.json> — печать name | stars | desc из ответа GitHub API.
'use strict';
const fs = require('fs');
const j = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
(j.items || []).forEach(r => console.log(r.full_name, '|', r.stargazers_count, '|', (r.description || '').slice(0, 90)));
if (!j.items) console.log(JSON.stringify(j).slice(0, 300));
