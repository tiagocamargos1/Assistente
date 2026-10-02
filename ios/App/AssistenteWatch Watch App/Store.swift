import Foundation
import SwiftUI
import Combine
import AuthenticationServices
import CryptoKit

// ── Modelos ──
struct HouseTask: Identifiable, Hashable {
    let id: String
    let label: String
    let time: String
    let order: Int
    var doneBy: String?   // nome de quem marcou
    var doneAt: String?
}

struct PersonalTask: Identifiable, Hashable {
    let id: String
    let text: String
    let urgency: String
    let date: String
}

struct ShopItem: Identifiable, Hashable {
    let id: String
    let label: String
    let qty: String
    let cat: String
    var bought: Bool
}

// ── Identidades da app (iguais ao index.html) ──
private let OWNER_EMAIL = "tiagocamargos@tocsmartgroup.com"
private let FAMILY_HOUSE = "casa"

@MainActor
final class Store: ObservableObject {
    @Published var signedIn = false
    @Published var loading = false
    @Published var error: String?
    @Published var userName = ""
    @Published var houseTasks: [HouseTask] = []
    @Published var tasks: [PersonalTask] = []
    @Published var shopping: [ShopItem] = []
    @Published var pairingCode: String?      // código a escrever no iPhone (Ligar Apple Watch)
    private var pairingTask: Task<Void, Never>?

    private(set) var cu: String?        // identidade na app ('tiago', 'monique', 'g_…', 'apple_…')
    private(set) var houseId: String?
    private var appleNonce = ""

    init() { Task { await bootstrap() } }

    // MARK: sessão
    func bootstrap() async {
        signedIn = await FirebaseAuth.shared.isSignedIn
        if signedIn { await resolveIdentity(); if cu != nil { await refreshAll() } }
    }

    func signOut() {
        pairingTask?.cancel(); pairingTask = nil
        if let c = pairingCode { Task { try? await Firestore.shared.delete("pairing/\(c)") } }
        pairingCode = nil
        Task { await FirebaseAuth.shared.signOut() }
        signedIn = false; cu = nil; houseId = nil
        houseTasks = []; tasks = []; shopping = []
    }

    /// Prepara o pedido Sign in with Apple (nonce SHA-256, como no iPhone).
    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        appleNonce = Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        request.requestedScopes = [.fullName, .email]
        request.nonce = SHA256.hash(data: Data(appleNonce.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let e):
            if (e as? ASAuthorizationError)?.code != .canceled { let ns = e as NSError; error = "\(ns.localizedDescription) [\(ns.domain) \(ns.code)]" }
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokData = cred.identityToken, let idToken = String(data: tokData, encoding: .utf8) else {
                error = "A Apple não devolveu o token."; return
            }
            let nonce = appleNonce
            loading = true; error = nil
            Task {
                do {
                    try await FirebaseAuth.shared.signInWithApple(idToken: idToken, rawNonce: nonce)
                    signedIn = true
                    await resolveIdentity()
                    if cu != nil { await refreshAll() }
                } catch { self.error = error.localizedDescription }
                loading = false
            }
        }
    }

    /// Mapeia a conta Firebase para a identidade da app e descobre a casa.
    /// Ordem: authMap (já ligado) → linkedAccounts (ligado no iPhone) → emparelhamento por código.
    private func resolveIdentity() async {
        let uid = await FirebaseAuth.shared.currentUid ?? ""
        var email = (await FirebaseAuth.shared.currentEmail ?? "").lowercased()
        var appUid: String?
        if let m = try? await Firestore.shared.get("authMap/\(uid)"), let a = m["appUid"] as? String { appUid = a }
        if let l = try? await Firestore.shared.get("linkedAccounts/\(uid)") {
            if let e = l["email"] as? String, !e.isEmpty { email = e.lowercased() }
            if appUid == nil, let a = l["appUid"] as? String {
                appUid = a
                try? await Firestore.shared.merge("authMap/\(uid)", fields: ["appUid": a, "updatedAt": Date()], mask: ["appUid", "updatedAt"])
            }
        }
        guard let id = appUid else { startPairing(); return }
        pairingTask?.cancel(); pairingTask = nil; pairingCode = nil
        cu = id
        userName = id == "tiago" ? "Tiago" : id == "monique" ? "Monique" : (email.split(separator: "@").first.map(String.init) ?? id)
        if let p = try? await Firestore.shared.get("prefs/\(id)"), let n = p["name"] as? String, !n.isEmpty { userName = n }
        if email == OWNER_EMAIL || id == "tiago" { houseId = FAMILY_HOUSE }
        else if let idx = try? await Firestore.shared.get("houseIndex/\(email)"), let h = idx["hid"] as? String { houseId = h }
        else { houseId = nil }
    }

    /// Publica pairing/{código} (válido 10 min) e espera que o iPhone o use em «Ligar Apple Watch».
    func startPairing() {
        pairingTask?.cancel()
        pairingTask = Task { [weak self] in
            guard let self else { return }
            let uid = await FirebaseAuth.shared.currentUid ?? ""
            var code = ""
            for _ in 0..<5 {
                code = String(format: "%06d", Int.random(in: 0...999_999))
                do {
                    try await Firestore.shared.create("pairing/\(code)", fields: [
                        "watchUid": uid,
                        "createdAt": Date(),
                        "expiresAt": Date().addingTimeInterval(600)
                    ])
                    break
                } catch { code = "" }
            }
            guard !code.isEmpty else { self.error = "Não foi possível gerar o código. Tenta outra vez."; return }
            self.pairingCode = code
            let deadline = Date().addingTimeInterval(600)
            while !Task.isCancelled && Date() < deadline {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if let l = try? await Firestore.shared.get("linkedAccounts/\(uid)"), l["appUid"] != nil {
                    try? await Firestore.shared.delete("pairing/\(code)")
                    self.pairingCode = nil
                    await self.resolveIdentity()
                    if self.cu != nil { await self.refreshAll() }
                    return
                }
            }
            if !Task.isCancelled { self.pairingCode = nil; self.error = "O código expirou."; self.startPairing() }
        }
    }

    // MARK: dados
    static func today() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "Europe/Lisbon")
        return f.string(from: Date())
    }

    func refreshAll() async {
        loading = true; error = nil
        async let a: Void = loadHouse()
        async let b: Void = loadTasks()
        async let c: Void = loadShopping()
        _ = await (a, b, c)
        loading = false
    }

    func loadHouse() async {
        guard let hid = houseId else { houseTasks = []; return }
        do {
            let house = try await Firestore.shared.get("household/\(hid)") ?? [:]
            let day = try await Firestore.shared.get("household/\(hid)/days/\(Store.today())") ?? [:]
            let done = day["done"] as? [String: Any] ?? [:]
            var list: [HouseTask] = []
            for case let t as [String: Any] in (house["tasks"] as? [Any] ?? []) {
                guard let id = t["id"] as? String, let label = t["label"] as? String, !label.isEmpty else { continue }
                let d = done[id] as? [String: Any]
                list.append(HouseTask(id: id, label: label, time: t["time"] as? String ?? "", order: t["order"] as? Int ?? 0, doneBy: d?["name"] as? String, doneAt: d?["at"] as? String))
            }
            for case let t as [String: Any] in (day["extras"] as? [Any] ?? []) {
                guard let id = t["id"] as? String, let label = t["label"] as? String else { continue }
                let d = done[id] as? [String: Any]
                list.append(HouseTask(id: id, label: label, time: t["time"] as? String ?? "", order: 1000 + list.count, doneBy: d?["name"] as? String, doneAt: d?["at"] as? String))
            }
            houseTasks = list.sorted { $0.order < $1.order }
        } catch { self.error = error.localizedDescription }
    }

    func toggleHouse(_ t: HouseTask) {
        guard let hid = houseId, let me = cu else { return }
        let path = "household/\(hid)/days/\(Store.today())"
        let wasDone = t.doneBy != nil
        if let i = houseTasks.firstIndex(of: t) {
            houseTasks[i].doneBy = wasDone ? nil : userName
            houseTasks[i].doneAt = wasDone ? nil : ISO8601DateFormatter().string(from: Date())
        }
        Task {
            do {
                if wasDone { try await Firestore.shared.deleteField(path, fieldPath: "done.\(t.id)") }
                else {
                    try await Firestore.shared.merge(path, fields: ["date": Store.today(), "done": [t.id: ["by": me, "name": userName, "at": ISO8601DateFormatter().string(from: Date())]]], mask: ["date", "done.\(t.id)"])
                }
            } catch { self.error = error.localizedDescription; await loadHouse() }
        }
    }

    func loadTasks() async {
        guard let me = cu else { tasks = []; return }
        do {
            let docs = try await Firestore.shared.list("users/\(me)/tasks")
            let today = Store.today()
            tasks = docs.compactMap { d -> PersonalTask? in
                let x = d.data
                guard (x["done"] as? Bool) != true, (x["type"] as? String) != "event", let text = x["text"] as? String else { return nil }
                let date = x["date"] as? String ?? ""
                guard date.isEmpty || date <= today else { return nil }   // hoje e atrasadas
                return PersonalTask(id: d.id, text: text, urgency: x["urgency"] as? String ?? "normal", date: date)
            }.sorted { ($0.urgency == "urgent" ? 0 : 1, $0.date) < ($1.urgency == "urgent" ? 0 : 1, $1.date) }
        } catch { self.error = error.localizedDescription }
    }

    func completeTask(_ t: PersonalTask) {
        guard let me = cu else { return }
        tasks.removeAll { $0.id == t.id }
        Task {
            do {
                try await Firestore.shared.merge("users/\(me)/tasks/\(t.id)", fields: ["done": true, "doneBy": me, "doneAt": ISO8601DateFormatter().string(from: Date()), "inProgress": false], mask: ["done", "doneBy", "doneAt", "inProgress"])
            } catch { self.error = error.localizedDescription; await loadTasks() }
        }
    }

    func loadShopping() async {
        guard let hid = houseId else { shopping = []; return }
        do {
            let docs = try await Firestore.shared.list("household/\(hid)/shopping")
            shopping = docs.compactMap { d -> ShopItem? in
                let x = d.data
                guard let label = x["label"] as? String else { return nil }
                return ShopItem(id: d.id, label: label, qty: x["qty"] as? String ?? "", cat: x["cat"] as? String ?? "", bought: x["bought"] as? Bool ?? false)
            }.sorted { ($0.bought ? 1 : 0, $0.cat, $0.label) < ($1.bought ? 1 : 0, $1.cat, $1.label) }
        } catch { self.error = error.localizedDescription }
    }

    func toggleShop(_ it: ShopItem) {
        guard let hid = houseId, let me = cu else { return }
        if let i = shopping.firstIndex(of: it) { shopping[i].bought.toggle() }
        Task {
            do {
                let now = ISO8601DateFormatter().string(from: Date())
                let f: [String: Any?] = it.bought ? ["bought": false, "boughtBy": nil, "boughtByName": nil, "boughtAt": nil]
                                                  : ["bought": true, "boughtBy": me, "boughtByName": userName, "boughtAt": now]
                try await Firestore.shared.merge("household/\(hid)/shopping/\(it.id)", fields: f, mask: ["bought", "boughtBy", "boughtByName", "boughtAt"])
            } catch { self.error = error.localizedDescription; await loadShopping() }
        }
    }
}
