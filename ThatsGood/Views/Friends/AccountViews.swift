import SwiftUI

/// The Friends tab: connect, sign in, pick a username, then the hub.
struct FriendsView: View {
    @ObservedObject private var backend = Backend.shared

    var body: some View {
        NavigationStack {
            Group {
                switch backend.status {
                case .notConfigured: ConnectServerView()
                case .signedOut: SignInView()
                case .needsProfile: CreateProfileView()
                case .signedIn: FriendsHubView()
                }
            }
            .background(Color.tgBackground)
        }
    }
}

struct ConnectServerView: View {
    @ObservedObject private var backend = Backend.shared
    @State private var url = ""
    @State private var key = ""
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Text("Friends, matches and leaderboards need the That's Good server. Paste the two values from your Supabase project once.")
                    .font(.subheadline)
                    .foregroundStyle(Color.tgMuted)
            }
            Section {
                TextField("https://xxxx.supabase.co", text: $url)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Project URL")
            }
            Section {
                TextField("sb_publishable_… or the anon key", text: $key, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(1...4)
            } header: {
                Text("Publishable key")
            } footer: {
                Text("Supabase → Project Settings → API Keys. Use the publishable (or anon) key, never the secret one.")
            }
            if let error {
                Text(error).foregroundStyle(Color.tgLoss)
            }
            Button("Connect") {
                error = backend.connect(url: url, key: key) ? nil : "That doesn't look right. Check the URL starts with https:// and the key is complete."
            }
            .disabled(url.isEmpty || key.isEmpty)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Friends")
    }
}

struct SignInView: View {
    @ObservedObject private var backend = Backend.shared
    @State private var email = ""
    @State private var password = ""
    @State private var creating = false

    var body: some View {
        Form {
            Section {
                SegmentedPicker(options: [false, true], selection: $creating) { $0 ? "Create account" : "Sign in" }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            Section {
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password (at least 6 characters)", text: $password)
                    .textContentType(creating ? .newPassword : .password)
            }
            if let message = backend.message {
                Text(message).font(.footnote).foregroundStyle(Color.tgLoss)
            }
            Button(creating ? "Create account" : "Sign in") {
                Task {
                    if creating {
                        await backend.signUp(email: email, password: password)
                    } else {
                        await backend.signIn(email: email, password: password)
                    }
                }
            }
            .disabled(backend.isBusy || !email.contains("@") || password.count < 6)
            if backend.isBusy { ProgressView() }
            Section {
                Button("Disconnect from server", role: .destructive) { backend.disconnect() }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Friends")
    }
}

struct CreateProfileView: View {
    @ObservedObject private var backend = Backend.shared
    @State private var username = ""
    @State private var displayName = ""

    private var cleanUsername: String { username.lowercased().trimmingCharacters(in: .whitespaces) }
    private var usernameValid: Bool {
        cleanUsername.range(of: "^[a-z0-9_]{3,20}$", options: .regularExpression) != nil
    }

    var body: some View {
        Form {
            Section {
                Text("Pick a username so friends can find you.")
                    .font(.subheadline)
                    .foregroundStyle(Color.tgMuted)
            }
            Section {
                TextField("Name, e.g. Sammy", text: $displayName)
                    .textContentType(.givenName)
                TextField("username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } footer: {
                Text("3 to 20 letters, numbers or _. Friends add you with @\(cleanUsername.isEmpty ? "username" : cleanUsername).")
            }
            if let message = backend.message {
                Text(message).font(.footnote).foregroundStyle(Color.tgLoss)
            }
            Button("Save") {
                Task { await backend.createProfile(username: cleanUsername, displayName: displayName.trimmingCharacters(in: .whitespaces)) }
            }
            .disabled(backend.isBusy || !usernameValid || displayName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Your profile")
    }
}

struct AddFriendView: View {
    @ObservedObject private var backend = Backend.shared
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("@username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Your username is @\(backend.profile?.username ?? ""). Share it with your mates.")
                }
                if let message = backend.message {
                    Text(message).font(.footnote).foregroundStyle(Color.tgMuted)
                }
                Button("Send request") {
                    Task {
                        if await backend.addFriend(username: username) {
                            username = ""
                        }
                    }
                }
                .disabled(backend.isBusy || username.trimmingCharacters(in: .whitespaces).count < 3)
            }
            .navigationTitle("Add a friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}
