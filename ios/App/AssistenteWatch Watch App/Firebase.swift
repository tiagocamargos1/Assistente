import Foundation
import Security

// ── Config (chaves públicas do projeto Firebase "assistente-ee1f4"; a mesma
//    web API key que a web app usa — a segurança está nas Security Rules) ──
enum FirebaseConfig {
    static let apiKey = "AIzaSyCwpeZ8z0dh0_4Ksf7x7ZAhYKkGL9Icnc4"
    static let projectId = "assistente-ee1f4"
    static var firestoreBase: String { "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/(default)/documents" }
}

struct FirebaseError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// ── Keychain mínimo para guardar a sessão ──
enum Keychain {
    private static let service = "com.tocsmartgroup.assistente.watch"
    static func set(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
        var add = q; add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }
    static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func remove(_ key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
    }
}

// ── Sessão Firebase Auth (REST) ──
struct FirebaseSession: Codable {
    var idToken: String
    var refreshToken: String
    var uid: String
    var email: String?
    var expiresAt: Date
}

actor FirebaseAuth {
    static let shared = FirebaseAuth()
    private var session: FirebaseSession?

    init() {
        if let raw = Keychain.get("session"), let d = raw.data(using: .utf8),
           let s = try? JSONDecoder().decode(FirebaseSession.self, from: d) { session = s }
    }

    var isSignedIn: Bool { session != nil }
    var currentEmail: String? { session?.email }
    var currentUid: String? { session?.uid }

    private func persist() {
        if let s = session, let d = try? JSONEncoder().encode(s), let raw = String(data: d, encoding: .utf8) { Keychain.set(raw, for: "session") }
        else { Keychain.remove("session") }
    }

    func signOut() { session = nil; persist() }

    /// Troca o identity token da Apple (com o nonce em claro) por uma sessão Firebase.
    func signInWithApple(idToken: String, rawNonce: String) async throws {
        let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=\(FirebaseConfig.apiKey)")!
        var req = URLRequest(url: url); req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let postBody = "id_token=\(idToken)&providerId=apple.com&nonce=\(rawNonce)"
        let body: [String: Any] = ["postBody": postBody, "requestUri": "https://assistente-ee1f4.firebaseapp.com", "returnIdpCredential": true, "returnSecureToken": true]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let idTok = json["idToken"] as? String, let refresh = json["refreshToken"] as? String, let uid = json["localId"] as? String else {
            let msg = ((json["error"] as? [String: Any])?["message"] as? String) ?? "Falha ao entrar no Firebase"
            throw FirebaseError(message: msg)
        }
        let expires = Double(json["expiresIn"] as? String ?? "3600") ?? 3600
        session = FirebaseSession(idToken: idTok, refreshToken: refresh, uid: uid, email: (json["email"] as? String)?.lowercased(), expiresAt: Date().addingTimeInterval(expires - 60))
        persist()
    }

    /// Devolve um ID token válido (renova pelo refresh token quando expira).
    func validToken() async throws -> String {
        guard var s = session else { throw FirebaseError(message: "Sem sessão") }
        if s.expiresAt > Date() { return s.idToken }
        let url = URL(string: "https://securetoken.googleapis.com/v1/token?key=\(FirebaseConfig.apiKey)")!
        var req = URLRequest(url: url); req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = "grant_type=refresh_token&refresh_token=\(s.refreshToken)".data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard (resp as? HTTPURLResponse)?.statusCode == 200, let idTok = json["id_token"] as? String else {
            session = nil; persist()
            throw FirebaseError(message: "Sessão expirada — entra de novo")
        }
        s.idToken = idTok
        if let r = json["refresh_token"] as? String { s.refreshToken = r }
        s.expiresAt = Date().addingTimeInterval((Double(json["expires_in"] as? String ?? "3600") ?? 3600) - 60)
        session = s; persist()
        return idTok
    }
}

// ── Firestore REST: conversão de/para o formato "Value" ──
enum FSValue {
    static func encode(_ v: Any?) -> [String: Any] {
        switch v {
        case nil: return ["nullValue": NSNull()]
        case let b as Bool: return ["booleanValue": b]
        case let i as Int: return ["integerValue": String(i)]
        case let d as Double: return ["doubleValue": d]
        case let s as String: return ["stringValue": s]
        case let a as [Any?]: return ["arrayValue": ["values": a.map { encode($0) }]]
        case let a as [Any]: return ["arrayValue": ["values": a.map { encode($0) }]]
        case let m as [String: Any?]:
            var f: [String: Any] = [:]; for (k, x) in m { f[k] = encode(x) }
            return ["mapValue": ["fields": f]]
        case let m as [String: Any]:
            var f: [String: Any] = [:]; for (k, x) in m { f[k] = encode(x) }
            return ["mapValue": ["fields": f]]
        default: return ["stringValue": String(describing: v!)]
        }
    }
    static func decode(_ v: [String: Any]) -> Any? {
        if let s = v["stringValue"] as? String { return s }
        if let b = v["booleanValue"] as? Bool { return b }
        if let i = v["integerValue"] as? String { return Int(i) ?? 0 }
        if let d = v["doubleValue"] as? Double { return d }
        if v["nullValue"] != nil { return nil }
        if let t = v["timestampValue"] as? String { return t }
        if let a = (v["arrayValue"] as? [String: Any])?["values"] as? [[String: Any]] { return a.map { decode($0) as Any } }
        if let m = (v["mapValue"] as? [String: Any]) { return decodeFields(m["fields"] as? [String: Any] ?? [:]) }
        return nil
    }
    static func decodeFields(_ fields: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (k, x) in fields { if let vv = x as? [String: Any], let d = decode(vv) { out[k] = d } }
        return out
    }
}

struct FSDoc {
    let id: String
    let data: [String: Any]
}

actor Firestore {
    static let shared = Firestore()

    private func request(_ path: String, method: String = "GET", query: String = "", body: [String: Any]? = nil) async throws -> [String: Any] {
        let token = try await FirebaseAuth.shared.validToken()
        let url = URL(string: FirebaseConfig.firestoreBase + "/" + path + query)!
        var req = URLRequest(url: url); req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let b = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: b)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        if code == 404 { return [:] }
        guard (200..<300).contains(code) else {
            let msg = ((json["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(code)"
            throw FirebaseError(message: msg)
        }
        return json
    }

    /// Lê um documento (nil se não existir).
    func get(_ path: String) async throws -> [String: Any]? {
        let j = try await request(path)
        guard let fields = j["fields"] as? [String: Any] else { return j.isEmpty ? nil : [:] }
        return FSValue.decodeFields(fields)
    }

    /// Lista os documentos de uma coleção (até 300).
    func list(_ collection: String) async throws -> [FSDoc] {
        let j = try await request(collection, query: "?pageSize=300")
        let docs = j["documents"] as? [[String: Any]] ?? []
        return docs.map { d in
            let name = d["name"] as? String ?? ""
            return FSDoc(id: String(name.split(separator: "/").last ?? ""), data: FSValue.decodeFields(d["fields"] as? [String: Any] ?? [:]))
        }
    }

    /// Escreve campos com merge (updateMask = apenas os campos indicados).
    func merge(_ path: String, fields: [String: Any?], mask: [String]) async throws {
        var f: [String: Any] = [:]; for (k, v) in fields { f[k] = FSValue.encode(v) }
        let q = "?" + mask.map { "updateMask.fieldPaths=" + ($0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0) }.joined(separator: "&")
        _ = try await request(path, method: "PATCH", query: q, body: ["fields": f])
    }

    /// Apaga um campo (updateMask com o campo e sem valor no corpo).
    func deleteField(_ path: String, fieldPath: String) async throws {
        let q = "?updateMask.fieldPaths=" + (fieldPath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? fieldPath)
        _ = try await request(path, method: "PATCH", query: q, body: ["fields": [:]])
    }
}
