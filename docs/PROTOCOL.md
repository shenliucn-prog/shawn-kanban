# Display protocol v1

A manifest is a JSON response with `schemaVersion: 1`, `image_url` (HTTP(S), absolute or relative), a 64-character hexadecimal `sha256`, `generatedAt` (Unix milliseconds), `width`, `height`, `state`, `staleAfterSeconds` and `refreshAfterSeconds`.

Pages publishes `manifest.json` for Chinese and `en/manifest.json` for English, plus immutable `images/<sha256>.png` under the corresponding folder. Existing screen.png aliases remain compatible. The plugin validates the manifest, limits response sizes, verifies image bytes, decodes a temporary file and only then replaces the cache. A manifest/image deployment race fails safely and retries. `generatedAt` means generation, not download; plain custom PNG URLs do not claim a generation timestamp. The device keeps its own refresh schedule; refreshAfterSeconds is informational in this release.

The LAN service exposes `/api/display?lang=en|zh`, returning an image URL under `/api/image/<sha256>.png`. Eight recent images are retained in server memory; after restart or eviction a client must obtain a fresh manifest. `/api/screen` remains supported. Language never changes the configured timezone or units.

A custom HTTPS manifest may not downgrade its image to HTTP. TLS verification remains enabled. The first implementation does not follow HTTP redirects; configure final URLs. Failed attempts preserve the displayed image and retry with bounded backoff.
