# LatrKit

Public Swift package for [L@tr.link](https://latr.link) read-later workflows on ATProto.

LatrKit implements deterministic record keys, HTTPS URL normalization, Open Graph merging, and PDS repository helpers for `com.latr.saved.*` lexicons. It is the canonical server-side library used by the L@tr gateway and is safe to embed in other Swift clients.

## Requirements

- Swift 6.0+
- macOS 14+ / iOS 17+

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/Stygian-Tech/latr-kit.git", from: "0.1.0"),
]
```

Then add `LatrKit` to your target dependencies.

### Local development

```bash
git clone https://github.com/Stygian-Tech/latr-kit.git
cd latr-kit
bash scripts/bootstrap.sh
bash scripts/check.sh
```

## Usage

```swift
import LatrKit

let library = SavedLibrary(repository: repositoryClient)
let item = try await library.saveExternal(url: "https://example.com/article")
```

See `Sources/LatrKit/` for models (`SavedItem`, `ExternalSave`), `RecordKey`, `URLNormalizer`, and `SavedLibrary`.

## Related packages

- [latr-packages](https://github.com/Stygian-Tech/latr-packages) — TypeScript lexicons, record keys, and gateway client
- [latr-link](https://github.com/Stygian-Tech/latr-link) — L@tr.link web app and gateway monorepo

## License

MIT — see [LICENSE](./LICENSE).
