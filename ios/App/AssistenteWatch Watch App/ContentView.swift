import SwiftUI
import AuthenticationServices

let gold = Color(red: 0.83, green: 0.66, blue: 0.29)

// ── Login ──
struct LoginView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        ScrollView {
        VStack(spacing: 10) {
            Image(systemName: "sparkle").font(.system(size: 28)).foregroundStyle(gold)
            Text("Assistente Pessoal").font(.headline)
            Text("Entra com a tua conta Apple (a mesma do iPhone).").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            SignInWithAppleButton(.signIn) { req in store.prepareAppleRequest(req) } onCompletion: { store.handleApple($0) }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 40)
            if store.loading { ProgressView() }
            if let e = store.error { Text(e).font(.caption2).foregroundStyle(.red).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(.horizontal, 6)
        }
    }
}

// ── Emparelhamento com o iPhone ──
struct PairingView: View {
    @EnvironmentObject var store: Store
    let code: String
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Image(systemName: "applewatch.radiowaves.left.and.right").font(.system(size: 24)).foregroundStyle(gold)
                Text("Ligar ao iPhone").font(.headline)
                Text("\(String(code.prefix(3))) \(String(code.suffix(3)))").font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                Text("No iPhone: Assistente → A minha conta → Ligar Apple Watch, e escreve este código.").font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                ProgressView()
                Button(role: .destructive) { store.signOut() } label: { Text("Cancelar") }
            }
            .padding(.horizontal, 4)
        }
    }
}

// ── Raiz: 3 páginas ──
struct RootView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        TabView {
            CasaView().tag(0)
            TarefasView().tag(1)
            ComprasView().tag(2)
        }
        .tabViewStyle(.page)
        .task { await store.refreshAll() }
    }
}

struct Header: View {
    let title: String
    let count: Int
    var body: some View {
        HStack {
            Text(title).font(.headline).foregroundStyle(gold)
            Spacer()
            Text("\(count)").font(.caption2).foregroundStyle(.secondary)
        }
        .listRowBackground(Color.clear)
    }
}

struct CasaView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        List {
            Header(title: "🏡 Casa · hoje", count: store.houseTasks.filter { $0.doneBy == nil }.count)
            if store.houseId == nil {
                Text("Ainda não fazes parte de nenhuma casa.").font(.footnote).foregroundStyle(.secondary)
            } else if store.houseTasks.isEmpty {
                Text(store.loading ? "A carregar…" : "Sem tarefas hoje 🎉").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(store.houseTasks) { t in
                Button { store.toggleHouse(t) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: t.doneBy == nil ? "circle" : "checkmark.circle.fill").foregroundStyle(t.doneBy == nil ? Color.secondary : Color.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.label).font(.body).strikethrough(t.doneBy != nil).foregroundStyle(t.doneBy == nil ? Color.primary : Color.secondary)
                            if let by = t.doneBy { Text("✓ \(by)").font(.caption2).foregroundStyle(.secondary) }
                            else if !t.time.isEmpty { Text("até \(t.time)").font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            RefreshRow()
        }
    }
}

struct TarefasView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        List {
            Header(title: "✅ Tarefas", count: store.tasks.count)
            if store.tasks.isEmpty {
                Text(store.loading ? "A carregar…" : "Nada pendente para hoje 🎉").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(store.tasks) { t in
                Button { store.completeTask(t) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "circle").foregroundStyle(t.urgency == "urgent" ? Color.red : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.text).font(.body)
                            if !t.date.isEmpty && t.date < Store.today() { Text("atrasada · \(t.date.suffix(5))").font(.caption2).foregroundStyle(.red) }
                        }
                    }
                }
            }
            RefreshRow()
        }
    }
}

struct ComprasView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        List {
            Header(title: "🛒 Compras", count: store.shopping.filter { !$0.bought }.count)
            if store.houseId == nil {
                Text("Sem casa associada.").font(.footnote).foregroundStyle(.secondary)
            } else if store.shopping.isEmpty {
                Text(store.loading ? "A carregar…" : "Lista vazia").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(store.shopping) { it in
                Button { store.toggleShop(it) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: it.bought ? "checkmark.circle.fill" : "circle").foregroundStyle(it.bought ? Color.green : Color.secondary)
                        Text(it.qty.isEmpty ? it.label : "\(it.label) · \(it.qty)").strikethrough(it.bought).foregroundStyle(it.bought ? Color.secondary : Color.primary)
                    }
                }
            }
            RefreshRow()
        }
    }
}

struct RefreshRow: View {
    @EnvironmentObject var store: Store
    var body: some View {
        Section {
            Button { Task { await store.refreshAll() } } label: { Label("Atualizar", systemImage: "arrow.clockwise") }
            Button(role: .destructive) { store.signOut() } label: { Label("Sair (\(store.userName))", systemImage: "rectangle.portrait.and.arrow.right") }
            if let e = store.error { Text(e).font(.caption2).foregroundStyle(.red) }
        }
    }
}
