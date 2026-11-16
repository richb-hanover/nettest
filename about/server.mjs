// Tiny HTTP server that renders ABOUT.md as a styled HTML page.
//
// ABOUT.md is built into the image (/opt/about/ABOUT.md); it is read and
// rendered once at startup. If it can't be read the server exits, so the
// problem shows up in "docker compose ps/logs" instead of as a broken page.
// If started as root (needed to bind port 80), the process drops to an
// unprivileged user as soon as the socket is listening.
//
// Environment:
//   ABOUT_FILE  path to the Markdown file   (default /opt/about/ABOUT.md)
//   ABOUT_PORT  TCP port to listen on       (default 80)
//   ABOUT_HOST  address to listen on        (default 0.0.0.0)
//   RUN_AS      user to switch to after bind (default nettest)

import http from 'node:http';
import { readFileSync } from 'node:fs';
import { marked } from 'marked';

const FILE = process.env.ABOUT_FILE || '/opt/about/ABOUT.md';
const PORT = Number(process.env.ABOUT_PORT || 80);
const HOST = process.env.ABOUT_HOST || '0.0.0.0';
const RUN_AS = process.env.RUN_AS || 'nettest';

marked.setOptions({ gfm: true, breaks: false });

// Give headings GitHub-style ids ("## Installing nettest-portable" ->
// id="installing-nettest-portable") so in-page links like
// [installed](#installing-nettest-portable) work here just as on GitHub.
// The page is rendered once, so one set of used slugs is enough.
const usedSlugs = new Map();
marked.use({
	renderer: {
		heading({ tokens, depth, text }) {
			const base = text
				.toLowerCase()
				.replace(/<[^>]*>/g, '')
				.replace(/[^\p{L}\p{N}\s_-]/gu, '')
				.trim()
				.replace(/\s/g, '-');
			const n = usedSlugs.get(base) ?? 0;
			usedSlugs.set(base, n + 1);
			const id = n ? `${base}-${n}` : base;
			return `<h${depth} id="${id}">${this.parser.parseInline(tokens)}</h${depth}>\n`;
		},
	},
});

const escapeHtml = (s) =>
	s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

// Use the first "# Heading" as the page title
function titleFrom(md) {
	const m = md.match(/^#\s+(.+?)\s*#*\s*$/m);
	return m ? m[1].replace(/[*_`[\]]/g, '') : 'About';
}

const CSS = `
:root {
  color-scheme: light dark;
  --bg: #ffffff; --fg: #1f2328; --muted: #59636e; --border: #d1d9e0;
  --link: #0969da; --code-bg: #f6f8fa; --quote: #59636e; --row-alt: #f6f8fa;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #0d1117; --fg: #e6edf3; --muted: #9198a1; --border: #3d444d;
    --link: #4493f8; --code-bg: #161b22; --quote: #9198a1; --row-alt: #161b22;
  }
}
* { box-sizing: border-box; }
html { -webkit-text-size-adjust: 100%; }
body {
  margin: 0; background: var(--bg); color: var(--fg);
  font: 16px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif;
}
main { max-width: 52rem; margin: 0 auto; padding: 2rem 1rem 4rem; overflow-wrap: break-word; }
h1, h2, h3, h4, h5, h6 { line-height: 1.25; margin: 1.6em 0 0.6em; font-weight: 600; }
h1 { font-size: 2em; padding-bottom: .3em; border-bottom: 1px solid var(--border); margin-top: 0; }
h2 { font-size: 1.5em; padding-bottom: .3em; border-bottom: 1px solid var(--border); }
h3 { font-size: 1.25em; }
p, ul, ol, blockquote, pre, table { margin: 0 0 1em; }
ul, ol { padding-left: 2em; }
li + li { margin-top: .25em; }
a { color: var(--link); text-decoration: none; }
a:hover { text-decoration: underline; }
code, pre { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, "Liberation Mono", monospace; font-size: .875em; }
code { background: var(--code-bg); padding: .2em .4em; border-radius: 6px; }
pre { background: var(--code-bg); padding: 1em; border-radius: 6px; overflow-x: auto; line-height: 1.45; }
pre code { background: none; padding: 0; font-size: 1em; }
blockquote { margin-left: 0; padding: 0 1em; color: var(--quote); border-left: .25em solid var(--border); }
table { border-collapse: collapse; display: block; width: max-content; max-width: 100%; overflow-x: auto; }
th, td { border: 1px solid var(--border); padding: .4em .8em; text-align: left; }
th { font-weight: 600; }
tr:nth-child(2n) td { background: var(--row-alt); }
img { max-width: 100%; height: auto; }
hr { border: 0; border-top: 1px solid var(--border); margin: 2em 0; }
input[type=checkbox] { margin-right: .4em; }
footer { margin-top: 3rem; color: var(--muted); font-size: .85em; }
`;

function page(title, bodyHtml) {
	return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)}</title>
<style>${CSS}</style>
</head>
<body>
<main>
${bodyHtml}
</main>
</body>
</html>
`;
}

let MD, HTML;
try {
	MD = readFileSync(FILE, 'utf8');
} catch (err) {
	console.error(`Cannot read ${FILE}: ${err.message}`);
	process.exit(1);
}
HTML = page(titleFrom(MD), marked.parse(MD));

const server = http.createServer((req, res) => {
	const url = new URL(req.url, 'http://localhost');

	if (req.method !== 'GET' && req.method !== 'HEAD') {
		res.writeHead(405, { Allow: 'GET, HEAD' }).end();
		return;
	}

	let body, type;
	if (url.pathname === '/' || url.pathname === '/index.html') {
		body = HTML;
		type = 'text/html; charset=utf-8';
	} else if (url.pathname === '/ABOUT.md') {
		// raw Markdown source
		body = MD;
		type = 'text/markdown; charset=utf-8';
	} else {
		res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' }).end('Not found\n');
		return;
	}

	res.writeHead(200, { 'Content-Type': type, 'Cache-Control': 'no-cache' });
	res.end(req.method === 'HEAD' ? undefined : body);
});

server.listen(PORT, HOST, () => {
	// Drop root privileges once the (privileged) port is bound
	if (typeof process.getuid === 'function' && process.getuid() === 0) {
		try {
			process.initgroups(RUN_AS, RUN_AS);
			process.setgid(RUN_AS);
			process.setuid(RUN_AS);
		} catch (err) {
			console.error(`Failed to drop privileges to ${RUN_AS}: ${err.message}`);
			process.exit(1);
		}
	}
	console.log(`About server: serving ${FILE} on http://${HOST}:${PORT} (uid ${process.getuid()})`);
});

for (const sig of ['SIGTERM', 'SIGINT']) {
	process.on(sig, () => server.close(() => process.exit(0)));
}
