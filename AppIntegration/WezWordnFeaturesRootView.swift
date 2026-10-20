// WezWordnFeaturesRootView.swift — WezWordn AppIntegration (iOS only)
//
// SwiftUI integration layer that wires the five WezWordn feature areas to
// the real WezWordnCore modules. Every screen below calls the actual Core
// APIs (no mock buttons, no placeholder services):
//
//   Local Encrypted Files -> LocalEncryptedStorage (AES-256-GCM chunked files)
//   Authenticator         -> LocalTOTP (OTPGenerator / OTPAuthParser / Base32)
//   Security Reports      -> VaultHealth (+ optional HIBPClient, k-anonymity)
//   Emergency Recovery    -> EmergencyRecovery (X25519 + HKDF + AES-GCM)
//   Secure Sharing        -> SecureSharing (X25519 + HKDF + AES-GCM packages)
//   (login editor demo)   -> ExtendedLoginFields (ExtendedLogin)
//
// Module note: the WezWordnCore package currently exposes one library
// product per feature module (see its Package.swift) — there is no single
// umbrella module named "WezWordnCore". These files therefore import the
// real module names. If an umbrella product is added later, only the
// import lines change.
//
// State note (honest scope): view models here keep feature data in memory
// for the editing session, except Encrypted Files, which is genuinely
// file-backed on disk. Persisting TOTP secrets / health items / recovery
// keys across launches must go through an encrypted store (Keychain for
// secrets and keys, LocalEncryptedStorage for payloads) — that wiring
// belongs to the host app's repository layer and is marked TODO where it
// applies instead of being faked with a UI-only store.

#if os(iOS)

import Crypto
import EmergencyRecovery
import ExtendedLoginFields
import Foundation
import HIBPClient
import LocalEncryptedStorage
import LocalTOTP
import SecureSharing
import SwiftUI
import UniformTypeIdentifiers
import VaultHealth

// MARK: - Root

public struct WezWordnFeaturesRootView: View {
    private let keyProvider: KeyProvider

    public init(keyProvider: KeyProvider = KeychainKeyProvider()) {
        self.keyProvider = keyProvider
    }

    public var body: some View {
        // NavigationView (لا NavigationStack): هدف التطبيق iOS 15 وNavigationStack
        // متاحة iOS 16+ فقط — أسقطت Run #4. NavigationLink بالوجهة يعمل في الاثنين.
        NavigationView {
            List {
                Section("WezWordn") {
                    NavigationLink {
                        EncryptedFilesView(keyProvider: keyProvider)
                    } label: {
                        Label("Local Encrypted Files", systemImage: "lock.doc")
                    }
                    NavigationLink {
                        AuthenticatorView()
                    } label: {
                        Label("Authenticator", systemImage: "key.viewfinder")
                    }
                    NavigationLink {
                        SecurityReportsView()
                    } label: {
                        Label("Security Reports", systemImage: "checkmark.shield")
                    }
                    NavigationLink {
                        EmergencyRecoveryView()
                    } label: {
                        Label("Emergency Recovery", systemImage: "lifepreserver")
                    }
                    NavigationLink {
                        SecureSharingView()
                    } label: {
                        Label("Secure Sharing", systemImage: "paperplane.circle")
                    }
                }
                Section("Vault") {
                    NavigationLink {
                        ExtendedLoginEditorView()
                    } label: {
                        Label("Login Item (Username + Email)", systemImage: "person.text.rectangle")
                    }
                }
            }
            .navigationTitle("WezWordn Features")
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - Shared helpers

/// بديل LabeledContent المتوافق مع iOS 15 (LabeledContent متاحة iOS 16+ فقط).
private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}

private func copyToPasteboard(_ value: String) {
    #if canImport(UIKit)
    UIPasteboard.general.string = value
    #endif
}

private struct ErrorBanner: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Extended Login (Username + Email as independent fields)

struct ExtendedLoginEditorView: View {
    @State private var login = ExtendedLogin()
    @State private var searchQuery = ""
    @State private var entries: [ExtendedLogin] = [
        // Synthetic demo entries only — never real account data.
        ExtendedLogin(username: "demo_user", email: "demo@example.com", password: nil),
        ExtendedLogin(username: nil, email: "second@example.org", password: nil),
    ]
    @State private var statusMessage: String?

    private var filtered: [ExtendedLogin] {
        entries.filter { $0.matches(search: searchQuery) }
    }

    var body: some View {
        Form {
            Section("Independent fields") {
                TextField("Username", text: Binding(
                    get: { login.username ?? "" },
                    set: { login.username = $0.isEmpty ? nil : $0 }
                ))
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                TextField("Email", text: Binding(
                    get: { login.email ?? "" },
                    set: { login.email = $0.isEmpty ? nil : $0 }
                ))
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                if let email = login.email, !email.isEmpty, !login.emailIsValid {
                    ErrorBanner(message: "Email format is invalid (ExtendedLogin.isValidEmail).")
                }
                SecureField("Password", text: Binding(
                    get: { login.password ?? "" },
                    set: { login.password = $0.isEmpty ? nil : $0 }
                ))
                Button("Add to list") {
                    entries.append(login)
                    statusMessage = "Added. Search matches username OR email via ExtendedLogin.matches."
                    login = ExtendedLogin()
                }
                if let statusMessage { Text(statusMessage).font(.footnote) }
            }
            Section("Copy individually") {
                Button("Copy username") { copyToPasteboard(login.username ?? "") }
                    .disabled((login.username ?? "").isEmpty)
                Button("Copy email") { copyToPasteboard(login.email ?? "") }
                    .disabled((login.email ?? "").isEmpty)
                Button("Copy password") { copyToPasteboard(login.password ?? "") }
                    .disabled((login.password ?? "").isEmpty)
            }
            Section("Search (username + email)") {
                TextField("Search", text: $searchQuery)
                    .textInputAutocapitalization(.never)
                if filtered.isEmpty {
                    Text("No entries match.").foregroundStyle(.secondary)
                }
                ForEach(Array(filtered.enumerated()), id: \.offset) { _, entry in
                    VStack(alignment: .leading) {
                        if let u = entry.username { Text("user: \(u)") }
                        if let e = entry.email { Text("email: \(e)") }
                    }
                    .font(.footnote)
                }
            }
            Section("Legacy migration") {
                Button("Migrate legacy item (username holds an email)") {
                    let migrated = ExtendedLogin.migrate(
                        legacy: LegacyLogin(username: "legacy@example.net", password: nil)
                    )
                    entries.append(migrated)
                    statusMessage = "Migrated: email copied to the email field, username kept unchanged (AutoFill-safe)."
                }
            }
        }
        .navigationTitle("Username + Email")
    }
}

// MARK: - Local Encrypted Files (file-backed, real disk storage)

@MainActor
final class EncryptedFilesViewModel: ObservableObject {
    @Published var encryptedFiles: [URL] = []
    @Published var previewText: String?
    @Published var errorMessage: String?
    @Published var isBusy = false

    let keyProvider: KeyProvider
    let directory: URL

    init(keyProvider: KeyProvider) {
        self.keyProvider = keyProvider
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WezWordn/EncryptedFiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        // Encrypted payloads must not be backed up unencrypted elsewhere and
        // should follow the device data-protection class of the container.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var dir = base
        try? dir.setResourceValues(values)
        self.directory = dir
        reload()
    }

    func reload() {
        let all = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        encryptedFiles = all.filter { $0.pathExtension == "wzen" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    var usedBytes: Int64 {
        encryptedFiles.reduce(0) { sum, url in
            sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    func encryptPickedFile(at source: URL) {
        isBusy = true
        defer { isBusy = false }
        do {
            let accessing = source.startAccessingSecurityScopedResource()
            defer { if accessing { source.stopAccessingSecurityScopedResource() } }
            let destination = directory.appendingPathComponent(source.lastPathComponent + ".wzen")
            try LocalEncryptedStorage.encryptFile(at: source, to: destination, keyProvider: keyProvider)
            reload()
        } catch {
            errorMessage = "Encryption failed: \(error)"
        }
    }

    func decryptForPreview(_ file: URL) {
        isBusy = true
        defer { isBusy = false }
        do {
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + "-" + file.deletingPathExtension().lastPathComponent)
            try LocalEncryptedStorage.decryptFile(at: file, to: temp, keyProvider: keyProvider)
            defer { try? FileManager.default.removeItem(at: temp) }
            let data = try Data(contentsOf: temp)
            if let text = String(data: data, encoding: .utf8) {
                previewText = text
            } else {
                previewText = "(binary file, \(data.count) bytes — decrypted successfully; use Export in the host app for non-text previews)"
            }
        } catch {
            errorMessage = "Decryption failed (wrong key or corrupt file): \(error)"
            previewText = nil
        }
    }

    func delete(_ file: URL) {
        do {
            try FileManager.default.removeItem(at: file)
            reload()
        } catch {
            errorMessage = "Delete failed: \(error)"
        }
    }
}

struct EncryptedFilesView: View {
    @StateObject private var model: EncryptedFilesViewModel
    @State private var importerPresented = false

    init(keyProvider: KeyProvider) {
        _model = StateObject(wrappedValue: EncryptedFilesViewModel(keyProvider: keyProvider))
    }

    var body: some View {
        List {
            Section("Storage") {
                Text("Used: \(ByteCountFormatter.string(fromByteCount: model.usedBytes, countStyle: .file))")
                Text("Files are AES-256-GCM encrypted (chunked, streaming) before they touch disk. Format: WZEN v1.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let error = model.errorMessage {
                Section { ErrorBanner(message: error) }
            }
            Section("Encrypted files") {
                if model.encryptedFiles.isEmpty {
                    Text("No encrypted files yet. Import a file to encrypt it.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.encryptedFiles, id: \.path) { file in
                    HStack {
                        Text(file.lastPathComponent)
                        Spacer()
                        Button("Preview") { model.decryptForPreview(file) }
                            .buttonStyle(.borderless)
                        Button(role: .destructive) { model.delete(file) } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            if let preview = model.previewText {
                Section("Decrypted preview (in memory, temp file removed)") {
                    Text(preview).font(.footnote.monospaced())
                }
            }
        }
        .navigationTitle("Encrypted Files")
        .toolbar {
            Button {
                importerPresented = true
            } label: {
                Label("Import & Encrypt", systemImage: "plus")
            }
            .disabled(model.isBusy)
        }
        .fileImporter(isPresented: $importerPresented, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result {
                model.encryptPickedFile(at: url)
            }
        }
    }
}

// MARK: - Authenticator (TOTP, RFC 4226 / RFC 6238)

struct AuthenticatorView: View {
    @State private var entries: [OTPAuthEntry] = []
    @State private var uriText = ""
    @State private var manualAccount = ""
    @State private var manualSecretBase32 = ""
    @State private var errorMessage: String?
    @State private var now = Date()

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            if let error = errorMessage {
                Section { ErrorBanner(message: error) }
            }
            Section("Add via otpauth:// URI") {
                TextField("otpauth://totp/...", text: $uriText)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                Button("Parse & Add") {
                    do {
                        entries.append(try OTPAuthParser.parse(uriText))
                        uriText = ""
                        errorMessage = nil
                    } catch {
                        errorMessage = "Invalid URI: \(error)"
                    }
                }
                Text("QR scanning uses the host app's camera flow and feeds the scanned string into OTPAuthParser — no separate parser exists.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Add manually (Base32 secret)") {
                TextField("Account", text: $manualAccount)
                TextField("Base32 secret", text: $manualSecretBase32)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                Button("Add") {
                    do {
                        let secret = try Base32.decode(manualSecretBase32)
                        entries.append(OTPAuthEntry(
                            issuer: nil, account: manualAccount, secret: secret,
                            secretBase32: manualSecretBase32, algorithm: .sha1, digits: 6, period: 30
                        ))
                        manualAccount = ""
                        manualSecretBase32 = ""
                        errorMessage = nil
                    } catch {
                        errorMessage = "Invalid Base32 secret: \(error)"
                    }
                }
            }
            Section("Accounts") {
                if entries.isEmpty {
                    Text("No TOTP accounts yet. Secrets are held in memory in this integration screen.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.issuer.map { "\($0): \(entry.account)" } ?? entry.account)
                            .font(.subheadline.bold())
                        HStack {
                            Text(code(for: entry))
                                .font(.title3.monospaced())
                            Spacer()
                            Text("\(OTPGenerator.remainingSeconds(date: now, period: entry.period))s")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button("Copy") { copyToPasteboard(code(for: entry)) }
                                .buttonStyle(.borderless)
                        }
                    }
                }
            }
            Section {
                // TODO(host-app): persist entries with secrets encrypted at rest
                // (Keychain via a dedicated secret store, or LocalEncryptedStorage)
                // before shipping. This screen intentionally does not write
                // secrets to UserDefaults or plaintext files.
                Text("TODO (host app): encrypted persistence of TOTP secrets is not wired in this integration file — see AppIntegration/README.md.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Authenticator")
        .onReceive(ticker) { now = $0 }
    }

    private func code(for entry: OTPAuthEntry) -> String {
        (try? OTPGenerator.totp(secret: entry.secret, date: now, period: entry.period, digits: entry.digits, algorithm: entry.algorithm)) ?? "------"
    }
}

// MARK: - Security Reports (VaultHealth + optional HIBP k-anonymity check)

struct SecurityReportsView: View {
    @State private var items: [VaultHealthItem] = []
    @State private var domain = ""
    @State private var password = ""
    @State private var hasTOTP = false
    @State private var report: HealthReport?
    @State private var hibpPassword = ""
    @State private var hibpResult: String?
    @State private var hibpBusy = false

    var body: some View {
        List {
            Section("Add item to analyse (analysed locally)") {
                TextField("Domain (e.g. example.com)", text: $domain)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                SecureField("Password", text: $password)
                Toggle("Has TOTP", isOn: $hasTOTP)
                Button("Add item") {
                    items.append(VaultHealthItem(
                        id: UUID().uuidString, domain: domain, username: nil, email: nil,
                        password: password, updatedAt: Date(), hasTOTP: hasTOTP
                    ))
                    domain = ""
                    password = ""
                    hasTOTP = false
                }
                Button("Run health analysis") {
                    report = VaultHealth.analyze(items: items)
                }
                .disabled(items.isEmpty)
                Text("\(items.count) item(s) queued. In the host app these items come from the decrypted vault in memory — never from disk or network.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let report {
                Section("Security Dashboard") {
                    InfoRow(label: "Total accounts", value: "\(report.totalCount)")
                    InfoRow(label: "Weak", value: "\(report.weakCount)")
                    InfoRow(label: "Reused", value: "\(report.reusedCount)")
                    InfoRow(label: "Old (>365 days)", value: "\(report.oldCount)")
                    InfoRow(label: "Duplicate accounts", value: "\(report.duplicateAccountCount)")
                    InfoRow(label: "Missing TOTP", value: "\(report.missingTOTPCount)")
                    InfoRow(label: "High risk", value: "\(report.highRiskCount)")
                    InfoRow(label: "Score (documented formula)", value: "\(report.score)/100")
                }
                Section("Issues") {
                    if report.issues.isEmpty {
                        Text("No issues found.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(report.issues.enumerated()), id: \.offset) { _, issue in
                        VStack(alignment: .leading) {
                            Text(issue.kind.rawValue).font(.subheadline.bold())
                            Text(issue.detail).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Have I Been Pwned (optional, online)") {
                SecureField("Password to check", text: $hibpPassword)
                Button(hibpBusy ? "Checking..." : "Check via k-anonymity") {
                    checkHIBP()
                }
                .disabled(hibpPassword.isEmpty || hibpBusy)
                Text("Only the first 5 hex characters of SHA-1(password) leave the device (HIBP range API). The full hash and the password never do.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let hibpResult { Text(hibpResult).font(.footnote) }
            }
        }
        .navigationTitle("Security Reports")
    }

    private func checkHIBP() {
        hibpBusy = true
        let candidate = hibpPassword
        // URLSessionHIBPTransport.fetchRange is synchronous in Core; run it
        // off the main thread and publish the result back on the main actor.
        DispatchQueue.global(qos: .userInitiated).async {
            let client = HIBPClient(transport: URLSessionHIBPTransport())
            let outcome: String
            do {
                let count = try client.pwnedCount(for: candidate)
                outcome = count == 0
                    ? "Not found in the HIBP password corpus (range match, local comparison)."
                    : "Found \(count) time(s) in the HIBP password corpus — change this password."
            } catch {
                outcome = "HIBP check failed: \(error)"
            }
            DispatchQueue.main.async {
                hibpResult = outcome
                hibpBusy = false
            }
        }
    }
}

// MARK: - Emergency Recovery (local package, X25519 envelope)

struct EmergencyRecoveryView: View {
    // In-memory key material for this screen's session only.
    // TODO(host-app): persist the recipient private key in the Keychain
    // (kSecAttrAccessibleWhenUnlockedThisDeviceOnly) — never in UserDefaults.
    @State private var recipientPrivateKey = Curve25519.KeyAgreement.PrivateKey()
    @State private var packageJSON = ""
    @State private var recoveredHex = ""
    @State private var errorMessage: String?
    @State private var demoVaultKey = Data((0..<32).map { _ in UInt8.random(in: 0...255) })

    var body: some View {
        List {
            if let error = errorMessage {
                Section { ErrorBanner(message: error) }
            }
            Section("Trusted contact key pair (this device, demo)") {
                Text("Public key (share with the vault owner):")
                    .font(.footnote).foregroundStyle(.secondary)
                Text(recipientPrivateKey.publicKey.rawRepresentation.map { String(format: "%02x", $0) }.joined())
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                Button("Regenerate key pair") {
                    recipientPrivateKey = Curve25519.KeyAgreement.PrivateKey()
                }
            }
            Section("Create recovery package") {
                Text("Demo vault key (random 32 bytes, this session): \(demoVaultKey.map { String(format: "%02x", $0) }.joined())")
                    .font(.footnote.monospaced())
                Button("Create package for my public key") {
                    do {
                        let pkg = try EmergencyRecovery.createPackage(
                            vaultKey: demoVaultKey,
                            recipientPublicKey: recipientPrivateKey.publicKey,
                            ownerLabel: "WezWordn demo owner"
                        )
                        let encoder = JSONEncoder()
                        encoder.dateEncodingStrategy = .iso8601
                        encoder.outputFormatting = [.sortedKeys]
                        packageJSON = String(data: try encoder.encode(pkg), encoding: .utf8) ?? ""
                        errorMessage = nil
                    } catch {
                        errorMessage = "Package creation failed: \(error)"
                    }
                }
                Button("New demo vault key") {
                    demoVaultKey = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
                }
            }
            Section("Package JSON (export / import)") {
                TextEditor(text: $packageJSON)
                    .font(.footnote.monospaced())
                    .frame(minHeight: 140)
                Button("Copy package") { copyToPasteboard(packageJSON) }
                    .disabled(packageJSON.isEmpty)
                Button("Recover vault key from package above") {
                    recover()
                }
                .disabled(packageJSON.isEmpty)
            }
            if !recoveredHex.isEmpty {
                Section("Recovered vault key") {
                    Text(recoveredHex).font(.footnote.monospaced()).textSelection(.enabled)
                    Text(recoveredHex == demoVaultKey.map { String(format: "%02x", $0) }.joined()
                        ? "Matches the demo vault key."
                        : "Does not match the current demo key (expected if the package was created for another key/session).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Text("Local design limits: no server, no enforced waiting period, no revocation. Anyone holding the recipient private key + package can recover immediately. See SECURITY.md.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Emergency Recovery")
    }

    private func recover() {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let pkg = try decoder.decode(RecoveryPackage.self, from: Data(packageJSON.utf8))
            let key = try EmergencyRecovery.recoverVaultKey(package: pkg, recipientPrivateKey: recipientPrivateKey)
            recoveredHex = key.map { String(format: "%02x", $0) }.joined()
            errorMessage = nil
        } catch {
            errorMessage = "Recovery failed (wrong private key or malformed package): \(error)"
            recoveredHex = ""
        }
    }
}

// MARK: - Secure Sharing (encrypted .wezshare packages)

struct SecureSharingView: View {
    @State private var recipientPrivateKey = Curve25519.KeyAgreement.PrivateKey()
    @State private var title = ""
    @State private var username = ""
    @State private var sharePassword = ""
    @State private var notes = ""
    @State private var packageBase64 = ""
    @State private var openedItem: ShareableItem?
    @State private var fingerprint: String?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let error = errorMessage {
                Section { ErrorBanner(message: error) }
            }
            Section("Create encrypted share package") {
                TextField("Title", text: $title)
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                SecureField("Password", text: $sharePassword)
                TextField("Notes", text: $notes)
                Button("Encrypt for my demo recipient key") {
                    createPackage()
                }
                Text("Demo recipient = a key pair generated in this screen. In the host app the recipient public key comes from the contact's published key. Delivery (AirDrop / Share Sheet) sends the .wezshare bytes produced here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Package (.wezshare, Base64 for copy/paste)") {
                TextEditor(text: $packageBase64)
                    .font(.footnote.monospaced())
                    .frame(minHeight: 120)
                if let fingerprint {
                    Text("Fingerprint (compare out-of-band): \(fingerprint)")
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
                Button("Copy package") { copyToPasteboard(packageBase64) }
                    .disabled(packageBase64.isEmpty)
                Button("Open package with my private key") { openPackage() }
                    .disabled(packageBase64.isEmpty)
            }
            if let openedItem {
                Section("Decrypted item") {
                    InfoRow(label: "Title", value: openedItem.title)
                    if let u = openedItem.username { InfoRow(label: "Username", value: u) }
                    if let e = openedItem.email { InfoRow(label: "Email", value: e) }
                    if let n = openedItem.notes { InfoRow(label: "Notes", value: n) }
                    Text("Once decrypted by a recipient, the copy cannot be revoked from them.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Secure Sharing")
    }

    private func createPackage() {
        do {
            let item = ShareableItem(
                title: title, username: username.isEmpty ? nil : username,
                email: nil, password: sharePassword.isEmpty ? nil : sharePassword,
                notes: notes.isEmpty ? nil : notes, url: nil
            )
            let pkg = try SecureSharing.createPackage(item: item, recipientPublicKey: recipientPrivateKey.publicKey)
            packageBase64 = try SecureSharing.exportData(pkg).base64EncodedString()
            fingerprint = pkg.fingerprint
            errorMessage = nil
        } catch {
            errorMessage = "Share package creation failed: \(error)"
        }
    }

    private func openPackage() {
        do {
            guard let data = Data(base64Encoded: packageBase64.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                errorMessage = "Package field is not valid Base64."
                return
            }
            let pkg = try SecureSharing.importData(data)
            openedItem = try SecureSharing.openPackage(pkg, recipientPrivateKey: recipientPrivateKey)
            fingerprint = pkg.fingerprint
            errorMessage = nil
        } catch {
            errorMessage = "Open failed (fingerprint/GCM verification or wrong key): \(error)"
            openedItem = nil
        }
    }
}

#endif
