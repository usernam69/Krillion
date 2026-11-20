# Krillion Mirror

A local, offline-capable mirror of [krillion.io](https://krillion.io/) with a small static server.

## Run

```bash
npm start
```

Then open http://localhost:3000.

- `PORT` env var changes the port (default 3000).
- API calls are proxied to krillion.io so live puzzle data still loads.
- WebSocket upgrades (party mode) are tunneled to the origin.

## Features

- All 15 routes + RSC payloads for client-side navigation.
- Full asset set (images, fonts, JS/CSS chunks).
- Unlimited mode unlocked in the client bundle.
- gzip compression + long-term caching for hashed assets.
- Path-traversal guard and request timeouts.
