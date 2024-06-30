const http = require('http');
const fs = require('fs');
const path = require('path');

const REQUIRED_STARTUP_HASH = "c2fecbeea51125a4e4ae487355ff5c15d17d28d93897c3e6dd49d36a828227a9";

const ALLOWED_IPS = [
    '::ffff:127.0.0.1',
    '127.0.0.1'
];

const ALLOWED_IDS = [
    7
];

const PORT = 3000;
const FILE_PATH = path.join(__dirname, 'script.lua');

function parseHeader(headerValue) {
    const drmPattern = /^DRM-(\d+)-([a-f0-9]+)$/;
    const match = headerValue.match(drmPattern);

    if (!match) {
        return null;
    }

    const computerID = parseInt(match[1], 10);
    const startupHash = match[2];

    return { computerID, startupHash };
}

const server = http.createServer((req, res) => {
    if (req.method === 'GET' && req.url === '/script.lua') {
        const clientIp = req.connection.remoteAddress;

        if (!ALLOWED_IPS.includes(clientIp)) {
            console.log(`Forbidden IP: ${clientIp}`);
            res.writeHead(403, { 'Content-Type': 'text/plain' });
            res.end('Forbidden: invalid IP');
            return;
        }

        const headerValue = req.headers['ccromdrm'];
        if (!headerValue) {
            console.log('Missing header');
            res.writeHead(400, { 'Content-Type': 'text/plain' });
            res.end('Bad Request: missing header');
            return;
        }

        const parsedHeader = parseHeader(headerValue);

        if (!parsedHeader) {
            console.log(`Invalid header: ${headerValue}`);
            res.writeHead(400, { 'Content-Type': 'text/plain' });
            res.end('Bad Request: invalid header format');
            return;
        }

        if (!ALLOWED_IDS.includes(parsedHeader.computerID)) {
            console.log(`Forbidden ID: ${parsedHeader.computerID}`);
            res.writeHead(403, { 'Content-Type': 'text/plain' });
            res.end('Forbidden: invalid ID');
            return;
        }

        if (parsedHeader.startupHash !== REQUIRED_STARTUP_HASH) {
            console.log(`Invalid hash: ${parsedHeader.startupHash}`);
            res.writeHead(403, { 'Content-Type': 'text/plain' });
            res.end('Forbidden: invalid hash');
            return;
        }

        fs.readFile(FILE_PATH, 'utf8', (err, data) => {
            if (err) {
                res.writeHead(500, { 'Content-Type': 'text/plain' });
                res.end('Internal Server Error: could not read file');
                return;
            }

            res.writeHead(200, { 'Content-Type': 'text/plain' });
            res.end(data);
        });
    } else {
        res.writeHead(404, { 'Content-Type': 'text/plain' });
        res.end('Not Found');
    }
});

server.listen(PORT, () => {
    console.log(`Server running at http://localhost:${PORT}/`);
});
