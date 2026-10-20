# WezWordnCore — Build Log

Environment: Ubuntu 24.04 Linux x86_64, Swift 6.1.2 (`~/workspace/toolchains/swift/usr/bin/swift`).
Dependency: apple/swift-crypto from 3.0.0 (resolved in `Package.resolved`), `import Crypto`.

## Final verification run (actual output)

Command:

```sh
cd ~/workspace/wezwordn/WezWordnCore && ~/workspace/toolchains/swift/usr/bin/swift test
```

Result: **exit code 0 — 39 tests executed, 0 failures.**

Per-suite (verbatim from the final `swift test` output):

| Suite | Executed | Failures |
|---|---|---|
| ExtendedLoginFieldsTests | 5 | 0 |
| LocalTOTPTests | 9 | 0 |
| LocalEncryptedStorageTests | 6 | 0 |
| VaultHealthTests | 7 | 0 |
| HIBPClientTests | 4 | 0 |
| EmergencyRecoveryTests | 4 | 0 |
| SecureSharingTests | 4 | 0 |
| **Total** | **39** | **0** |

Closing line of the run: `Executed 39 tests, with 0 failures (0 unexpected)`.

## What is covered

- ExtendedLoginFields: separate username/email/password, Codable roundtrip,
  legacy migration (email-shaped username is copied to `email` and kept in
  `username` for AutoFill compatibility — documented in code), case-insensitive
  search over both fields, documented simple email regex.
- LocalTOTP: Base32 (RFC 4648, padding/space/case tolerant), HOTP (RFC 4226),
  TOTP (RFC 6238) for SHA1/SHA256/SHA512, 6–8 digits, remaining-seconds, and
  `OTPAuthParser` with explicit rejection errors. All 18 RFC 6238 Appendix B
  vectors (6 timestamps × 3 algorithms, 8 digits) are asserted; the SHA1
  values were cross-checked against the RFC text and an independent Python
  `hmac`/`hashlib` computation (an early draft of the test table had four
  SHA1 expectations shifted by one row — corrected before the final run, the
  implementation matched the independent computation throughout).
- LocalEncryptedStorage: chunked streaming AES-256-GCM (`WZEN` format
  documented in source: magic + version + 12-byte random baseNonce + chunkSize;
  per-chunk nonce = baseNonce XOR big-endian chunk counter in the last 8 bytes;
  per-chunk ciphertext+16-byte tag; explicit zero-length end-of-stream record).
  Tests: roundtrip > chunkSize (10,000 bytes @ 1024), empty and exact-chunk
  files, single-byte tamper fails and deletes partial plaintext, wrong key
  fails with `.authenticationFailed`, two encryptions of the same file differ
  (baseNonce differs), `KeyProvider`/`InMemoryKeyProvider` roundtrip.
- VaultHealth: fully offline analysis — weak (length < 12 OR common-list OR
  estimated entropy < 45 bits OR ≤ 3 distinct characters), reused, old
  (> 365 days), duplicate domain+username, missing TOTP, missing
  username+email, high-risk (weak AND (reused OR duplicate)). Score 0–100 by
  the documented proportional-penalty formula (weak 30, reused 25, missing
  TOTP 20, old 15, duplicate 10); empty vault = 100. Synthetic-data tests per
  category, including exact score checks (perfect vault 100; single worst-case
  item 35).
- HIBPClient: k-anonymity only — SHA1 locally (`Insecure.SHA1`), only the
  5-hex-char prefix reaches the injectable transport; suffix matched locally.
  Tested offline with a mock transport against the known vector
  SHA1("password") = `5BAA61E4C9B93F3F0682250B6CF8331B7EE68FD8`
  (prefix `5BAA6`, suffix `1E4C9B93F3F0682250B6CF8331B7EE68FD8`, mocked count
  9545824), plus not-pwned = 0 and malformed-response rejection. No real
  network in tests; `URLSessionHIBPTransport` exists for production use and
  is not exercised here.
- EmergencyRecovery: X25519 ephemeral → HKDF-SHA256 → AES-256-GCM package
  (`version, ephemeralPublicKey, salt, nonce, ciphertext(=ct‖tag), createdAt,
  ownerLabel`), Codable. Roundtrip, wrong-private-key (`.decryptionFailed`)
  and tamper tests pass. Local design only — no server-enforced waiting
  period/revocation is claimed (documented in source).
- SecureSharing: single-item JSON payload encrypted with the same
  X25519+HKDF+AES-GCM envelope, `.wezshare` JSON export/import, SHA-256
  fingerprint over (ephemeralPublicKey‖salt‖nonce‖ciphertext) verified before
  decryption. Roundtrip, export/import, tamper (`.fingerprintMismatch`) and
  wrong-recipient tests pass.

## Failures encountered during development (all fixed, none remaining)

1. `URLSession.shared` unavailable on Linux — fixed with a conditional
   `FoundationNetworking` import in HIBPClient.
2. Test-runner crash (Signal 4, `Data._Representation.subscript`) in the
   tamper tests: swift-crypto `SealedBox.ciphertext/tag` can be Data slices
   whose indices do not start at 0. Fixed in the libraries by normalising
   slices into fresh zero-based `Data` when assembling/unpacking packages,
   and in tests by mutating `[UInt8]` arrays instead of `data[i] ^= …`.
3. Three test-expectation fixes: the RFC 6238 SHA1 row alignment (above);
   a VaultHealth case that exposed a real heuristic gap — `"aaaaaaaaaaaaaa"`
   passed the pool-entropy estimate, so the ≤3-distinct-characters weak rule
   was added to the implementation and documented; HIBP prefix-capture count
   (two client calls in one test) and a SecureSharing date-precision issue
   (ISO-8601 second precision in `.wezshare` export — test now uses a
   whole-second `createdAt`).

## Remaining limitations

- This is the platform-independent core only: no iOS app, Keychain provider,
  Face ID, AutoFill extension or IPA is produced here (Linux environment).
  `InMemoryKeyProvider` is for tests; production must supply a Keychain-backed
  `KeyProvider`.
- `URLSessionHIBPTransport` is compiled but not integration-tested against
  the live HIBP API.
