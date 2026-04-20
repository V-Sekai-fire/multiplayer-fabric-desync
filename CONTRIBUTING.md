# Contributing

A Go reimplementation of `casync` — content-addressed synchronization
for large binary files.  Files are split with a rolling hash into
variable-length chunks, each chunk compressed with zstd and stored by
its SHA256 digest.  Stores compose via interfaces: local cache, S3,
HTTP, SFTP/SSH, and reflink-capable filesystems are all first-class.
The CLI lives in `cmd/desync/`.

Built strictly red-green-refactor: every feature is driven by a failing
test, committed when green, then any cleanup is done with the test
still green.

## Guiding principles

- **RED first, always.** Before writing implementation, write a test
  that fails.  Mutation-test it by breaking the implementation briefly
  if the failure message is ambiguous.
- **Interface composition, not inheritance.** Every store type
  implements a minimal interface (`Store`, `WriteStore`, `IndexStore`,
  etc.).  New store backends require only the interface methods; do not
  add methods to the interface unless every existing store needs them.
- **Context propagation.** Every function that performs I/O accepts a
  `context.Context` as its first argument.  Cancellation and deadline
  propagation must work end-to-end; do not use `context.Background()`
  inside library code.
- **No global state.** Options are passed explicitly.  `init()` blocks
  that modify global state are not permitted outside `cmd/`.
- **Commit every green.** One commit per feature cycle.  Messages use
  sentence case and describe what changed, e.g. `Add S3 store chunked
  upload support` or `Fix chunk boundary detection for small files`.

## Workflow

```
go build ./...
go test ./...
go vet ./...
gofmt -l .        # must produce no output
```

## Design notes

### Rolling hash chunker

The chunker uses a Rabin–Karp style polynomial rolling hash over a
sliding window.  Chunk boundaries are declared when the hash modulo
`chunkSizeAvg` equals a fixed discriminator.  Min and max chunk sizes
clamp the output.  Do not change the hash polynomial or discriminator
constants — doing so invalidates all existing chunk stores.

### Chunk store composition

```
LocalStore         – on-disk cache ($XDG_CACHE_HOME/desync)
S3Store            – MinIO / AWS S3 via the AWS SDK
HTTPStore          – read-only HTTP(S) CDN
SFTPStore          – SSH/SFTP remote
TarStore           – streaming tar archive (for piped transfers)
CompressedLocalStore – local store with transparent zstd compression
```

A `Cache` wraps a remote read store with a local write store:
reads populate the cache transparently.  Compose stores at the call
site, not inside store implementations.

### zstd compression

Chunks are stored as `zstd`-compressed blobs.  The compression level
is fixed at the default (level 3); do not expose it as a per-call
option.  Decompression is lazy — a chunk is only decompressed when
its content is actually read, not when it is fetched from the store.

### Reflinks

On filesystems that support copy-on-write (`btrfs`, `APFS`, `XFS`
with reflinks), the assembler uses `FICLONE` / `clonefile` to avoid
data copies.  The reflink path is attempted first and falls back to a
regular copy on `EOPNOTSUPP`.  Tests that cover the reflink path must
run on a supporting filesystem or be skipped with `t.Skip`.
