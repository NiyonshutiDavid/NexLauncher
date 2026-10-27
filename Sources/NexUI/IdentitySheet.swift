import SwiftUI
import NexGit

struct IdentitySheet: View {
    let current: GitIdentity
    let onSave: (GitIdentity, GitScope) -> Void
    @Environment(\.closeModal) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var scope: GitScope = .global

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Git identity").font(.title2.weight(.semibold))
            Text("Used for the author of your commits.").foregroundStyle(.secondary)
            TextField("Name", text: $name)
            TextField("Email", text: $email)
            Picker("Apply to", selection: $scope) {
                Text("All repositories").tag(GitScope.global)
                Text("This repository only").tag(GitScope.repo)
            }
            .pickerStyle(.radioGroup)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    onSave(GitIdentity(name: name.trimmingCharacters(in: .whitespaces), email: email.trimmingCharacters(in: .whitespaces)), scope)
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || email.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(22)
        .frame(width: 380)
        .onAppear { name = current.name ?? ""; email = current.email ?? "" }
    }
}
