import SwiftUI

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var isRegister = false
    @State private var isLoading = false
    @State private var error: String?
    @State private var api = API.shared

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.black, DS.bg], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: DS.xl) {
                Spacer().frame(height: 40)

                VStack(spacing: DS.xs) {
                    Text("Rolify")
                        .font(.system(size: 54, weight: .black))
                        .foregroundStyle(DS.accent)
                    Text("Your music, your rules.")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.textSecondary)
                }
                .padding(.bottom, DS.xxl)

                VStack(spacing: DS.m) {
                    if isRegister {
                        field(placeholder: "Dein Name", text: $displayName)
                    }
                    field(placeholder: "E-Mail", text: $email, keyboard: .emailAddress)
                    field(placeholder: "Passwort", text: $password, secure: true)
                }
                .padding(.horizontal, 28)

                if let error {
                    Text(error)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.top, DS.xs)
                }

                Button {
                    Task { await submit() }
                } label: {
                    HStack(spacing: DS.s) {
                        if isLoading { ProgressView().tint(.black).scaleEffect(0.85) }
                        Text(isRegister ? "Registrieren" : "Einloggen")
                            .font(.system(size: 17, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(DS.accent)
                    .clipShape(Capsule())
                }
                .disabled(isLoading)
                .padding(.horizontal, 28)
                .padding(.top, DS.m)

                Button {
                    isRegister.toggle(); error = nil
                } label: {
                    Text(isRegister ? "Schon registriert? Einloggen" : "Noch kein Konto? Registrieren")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DS.textSecondary)
                }
                .padding(.top, DS.xs)

                Spacer()
            }
        }
    }

    @ViewBuilder
    private func field(placeholder: String, text: Binding<String>, secure: Bool = false, keyboard: UIKeyboardType = .default) -> some View {
        Group {
            if secure {
                SecureField(placeholder, text: text)
            } else {
                TextField(placeholder, text: text)
                    .textInputAutocapitalization(.never)
                    .keyboardType(keyboard)
                    .autocorrectionDisabled()
            }
        }
        .font(.system(size: 16))
        .foregroundStyle(DS.textPrimary)
        .padding(.horizontal, 18)
        .frame(height: 52)
        .background(DS.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusL, style: .continuous))
    }

    private func submit() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            if isRegister {
                _ = try await api.register(email: email, password: password, displayName: displayName)
            } else {
                _ = try await api.login(email: email, password: password)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
