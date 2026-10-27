import Foundation
import DeviceCheck
import CryptoKit

// ── Firebase App Check com App Attest (REST, sem SDK) ──
// Prova ao Firebase que os pedidos vêm desta app instalada a partir da Apple.
// 1.ª vez: cria uma chave no Secure Enclave, atesta-a junto da Apple e troca a
// atestação por um "artifact" + token. Depois: só uma asserção assinada por token.
// Sem obrigatoriedade na consola, uma falha aqui NÃO impede o relógio de funcionar
// (o pedido segue sem o cabeçalho). Registo no Firebase: App Check → Assistente
// Pessoal Watch → App Attest (Team CZ2956VY73, TTL 24 h).
enum AppCheckConfig {
    static let appId = "1:611661253806:ios:50025e092c933306f0313f"   // Assistente Pessoal Watch
    static let projectNumber = "611661253806"
    static var base: String { "https://firebaseappcheck.googleapis.com/v1/projects/\(projectNumber)/apps/\(appId)" }
}

actor AppCheck {
    static let shared = AppCheck()
    private var token: String?
    private var expiresAt = Date.distantPast
    private var inFlight: Task<String?, Never>?

    /// Token válido ou nil (App Attest indisponível / erro de rede).
    func currentToken() async -> String? {
        if let t = token, expiresAt > Date().addingTimeInterval(300) { return t }
        if let t = inFlight { return await t.value }
        let task = Task<String?, Never> { await self.refresh() }
        inFlight = task
        let v = await task.value
        inFlight = nil
        return v
    }

    private func refresh() async -> String? {
        guard DCAppAttestService.shared.isSupported else { return nil }
        do {
            if let keyId = Keychain.get("appattest.keyId"), let artifactB64 = Keychain.get("appattest.artifact"),
               let artifact = Data(base64Encoded: artifactB64) {
                do { return try await exchangeAssertion(keyId: keyId, artifact: artifact) }
                catch let e as AppCheckHTTPError where (400..<500).contains(e.status) {
                    // Chave/artifact rejeitados (ex.: app reinstalada) → atesta de novo.
                    Keychain.remove("appattest.keyId"); Keychain.remove("appattest.artifact")
                }
            }
            return try await attest()
        } catch {
            return nil
        }
    }

    private func challenge() async throws -> Data {
        let j = try await post(":generateAppAttestChallenge", body: [:])
        guard let c = j["challenge"] as? String, let d = Data(base64Encoded: Self.std(c)) else { throw AppCheckHTTPError(status: 0) }
        return d
    }

    private func attest() async throws -> String? {
        let svc = DCAppAttestService.shared
        let keyId = try await svc.generateKey()
        let ch = try await challenge()
        let hash = Data(SHA256.hash(data: ch))
        let attestation = try await svc.attestKey(keyId, clientDataHash: hash)
        let j = try await post(":exchangeAppAttestAttestation", body: [
            "attestationStatement": attestation.base64EncodedString(),
            "challenge": ch.base64EncodedString(),
            "keyId": keyId
        ])
        guard let artifact = j["artifact"] as? String else { throw AppCheckHTTPError(status: 0) }
        Keychain.set(keyId, for: "appattest.keyId")
        Keychain.set(Self.std(artifact), for: "appattest.artifact")
        if let t = j["appCheckToken"] as? [String: Any] { return store(t) }
        if let a = Data(base64Encoded: Self.std(artifact)) { return try await exchangeAssertion(keyId: keyId, artifact: a) }
        return nil
    }

    private func exchangeAssertion(keyId: String, artifact: Data) async throws -> String? {
        let ch = try await challenge()
        // Igual ao SDK oficial: clientDataHash = SHA256(artifact ‖ challenge).
        let hash = Data(SHA256.hash(data: artifact + ch))
        let assertion = try await DCAppAttestService.shared.generateAssertion(keyId, clientDataHash: hash)
        let j = try await post(":exchangeAppAttestAssertion", body: [
            "artifact": artifact.base64EncodedString(),
            "assertion": assertion.base64EncodedString(),
            "challenge": ch.base64EncodedString()
        ])
        return store(j)
    }

    private func store(_ t: [String: Any]) -> String? {
        guard let tok = t["token"] as? String else { return nil }
        let ttl = Double(String((t["ttl"] as? String ?? "3600s").dropLast())) ?? 3600
        token = tok
        expiresAt = Date().addingTimeInterval(ttl)
        return tok
    }

    private func post(_ method: String, body: [String: Any]) async throws -> [String: Any] {
        let url = URL(string: AppCheckConfig.base + method + "?key=\(FirebaseConfig.apiKey)")!
        var req = URLRequest(url: url); req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(FirebaseConfig.referer, forHTTPHeaderField: "Referer")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw AppCheckHTTPError(status: code) }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// base64url → base64 padrão (com padding).
    private static func std(_ s: String) -> String {
        var r = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while r.count % 4 != 0 { r += "=" }
        return r
    }
}

struct AppCheckHTTPError: Error { let status: Int }
