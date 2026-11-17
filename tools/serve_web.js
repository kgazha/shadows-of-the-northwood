// Статический сервер для локального теста WebGL-сборки.
// Запуск:  node tools/serve_web.js  →  открыть http://127.0.0.1:8099/
// Потоковый MIME для wasm (иначе streaming compile падает). Никаких внешних зависимостей.
const http = require('http');
const fs = require('fs');
const path = require('path');
const ROOT = path.join(__dirname, '..', 'build', 'web');
const MIME = {
	'.html': 'text/html; charset=utf-8',
	'.js': 'text/javascript',
	'.wasm': 'application/wasm',
	'.pck': 'application/octet-stream',
	'.png': 'image/png',
	'.ico': 'image/x-icon',
	'.svg': 'image/svg+xml',
	'.json': 'application/json',
};
http.createServer((req, res) => {
	let p = decodeURIComponent(req.url.split('?')[0]);
	if (p === '/') p = '/index.html';
	const f = path.join(ROOT, p);
	if (!f.startsWith(ROOT)) { res.writeHead(403); return res.end(); }
	fs.readFile(f, (err, buf) => {
		if (err) { res.writeHead(404); return res.end('not found'); }
		res.writeHead(200, { 'Content-Type': MIME[path.extname(f)] || 'application/octet-stream' });
		res.end(buf);
	});
}).listen(8099, '127.0.0.1', () => console.log('serve http://127.0.0.1:8099/ root=' + ROOT));
