import AppKit
import Observation
import TranscribeCore

@MainActor @Observable final class ChatGPTConnection {
    let client = ChatGPTClient(namespace: Bundle.main.bundleIdentifier ?? "se.marcusliback.Transcribe")
    var accounts: [ChatGPTAccount] = []
    var models: [ChatGPTModel] = []
    var modelsAccountID: String?
    var busy = false
    var signingIn = false
    var message: String?
    var connectedAccountID: String?
    var pendingClientID = UserDefaults.standard.string(forKey: "chatGPTPendingClientID")
    @ObservationIgnored private var loginTask: Task<Void, Never>?
    @ObservationIgnored private var server: ChatGPTCallbackServer?
    @ObservationIgnored private var modelTask: Task<Void, Never>?

    func load() async {
        do { accounts = try await client.savedAccounts() }
        catch { message = error.localizedDescription }
    }

    func connect(accountID: String?, retryPending: Bool = false) {
        guard !busy else { return }
        busy = true; signingIn = true; message = "Finish signing in and approve ChatGPT plan usage in your browser."; connectedAccountID = nil
        let previous = accounts.first { $0.id == accountID } ?? (retryPending ? pendingClientID.map { ChatGPTAccount(clientID: $0, subject: "", email: nil, tokens: nil) } : nil)
        let server = ChatGPTCallbackServer()
        self.server = server
        loginTask = Task {
            defer { busy = false; signingIn = false; self.server = nil; loginTask = nil }
            do {
                let redirectURI = try await server.start()
                let key = "chatGPTHostID"
                let hostID: String
                if let saved = UserDefaults.standard.string(forKey: key) { hostID = saved }
                else { hostID = "urn:uuid:" + UUID().uuidString.lowercased(); UserDefaults.standard.set(hostID, forKey: key) }
                let login = try ChatGPTLogin(redirectURI: redirectURI, hostID: hostID, account: previous)
                // Register the pending transaction before a fast browser callback can arrive.
                await server.prepare(login)
                let callbackTask = Task { try await server.wait() }
                guard NSWorkspace.shared.open(login.authorizationURL()) else {
                    callbackTask.cancel(); await server.cancel()
                    throw TranscribeError.message("Cannot open your browser for ChatGPT sign-in.")
                }
                let callback = try await withTaskCancellationHandler { try await callbackTask.value } onCancel: { callbackTask.cancel() }
                let registration = try login.callback(callback)
                if previous == nil || previous?.subject.isEmpty == true {
                    pendingClientID = registration.clientID
                    UserDefaults.standard.set(registration.clientID, forKey: "chatGPTPendingClientID")
                }
                let account = try await client.finishLogin(login, callback: callback)
                if pendingClientID == account.clientID {
                    pendingClientID = nil
                    UserDefaults.standard.removeObject(forKey: "chatGPTPendingClientID")
                }
                await load()
                connectedAccountID = account.id
                message = account.planEnabled ? "Connected. Choose a model, then Save Changes to use your ChatGPT plan." : "Signed in, but ChatGPT plan usage was not enabled. Choose Enable plan usage to approve it."
            } catch is CancellationError { message = "ChatGPT sign-in cancelled." }
            catch { message = error.localizedDescription }
            await server.cancel()
        }
    }

    func cancel() { loginTask?.cancel(); if let server { Task { await server.cancel() } } }

    func loadModels(accountID: String?) {
        modelTask?.cancel(); models = []; modelsAccountID = nil
        guard let accountID, accounts.first(where: { $0.id == accountID })?.planEnabled == true else { return }
        modelTask = Task {
            do {
                let catalog = try await client.models(for: accountID)
                try Task.checkCancellation()
                models = catalog; modelsAccountID = accountID
            } catch is CancellationError { }
            catch { message = error.localizedDescription; await load() }
        }
    }

    func signOut(_ id: String) {
        guard !busy else { return }
        busy = true; message = "Signing out of ChatGPT…"
        modelTask?.cancel(); models = []; modelsAccountID = nil
        Task {
            defer { busy = false }
            do {
                let confirmed = try await client.signOut(id)
                await load()
                message = confirmed ? "Signed out of ChatGPT." : "Signed out locally. Remote revocation could not be confirmed; disconnect Transcribe in ChatGPT Settings → Security and login → Sign in with ChatGPT."
            } catch { message = error.localizedDescription }
        }
    }
}
