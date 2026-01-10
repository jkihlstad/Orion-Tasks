//
//  AuthenticationView.swift
//  TasksApp
//
//  Clerk authentication view with email, Apple, and Google sign-in
//  options with loading states and error handling
//

import SwiftUI
import AuthenticationServices

// MARK: - Authentication View

struct AuthenticationView: View {

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - State

    @StateObject private var viewModel = AuthenticationViewModel()
    @FocusState private var focusedField: AuthenticationField?

    // MARK: - Properties

    var onAuthenticated: ((ClerkUser) -> Void)?
    var onSkip: (() -> Void)?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                RemindersColors.background
                    .ignoresSafeArea()

                // Content
                ScrollView {
                    VStack(spacing: RemindersKit.Spacing.xxl) {
                        // Header
                        headerSection

                        // Auth options
                        authOptionsSection

                        // Divider
                        dividerWithText("or")

                        // Email sign in
                        emailSignInSection

                        // Terms
                        termsSection

                        Spacer(minLength: RemindersKit.Spacing.huge)
                    }
                    .padding(.top, RemindersKit.Spacing.xxl)
                }

                // Loading overlay
                if viewModel.isLoading {
                    loadingOverlay
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if viewModel.authMode == .signIn {
                        Button("Skip") {
                            onSkip?()
                        }
                        .foregroundColor(RemindersColors.textSecondary)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.authMode == .signUp {
                        Button("Sign In") {
                            withAnimation {
                                viewModel.authMode = .signIn
                                viewModel.clearError()
                            }
                        }
                        .foregroundColor(RemindersColors.accentBlue)
                    }
                }
            }
            .alert("Authentication Error", isPresented: $viewModel.showError) {
                Button("OK") {
                    viewModel.clearError()
                }
            } message: {
                Text(viewModel.errorMessage ?? "An unknown error occurred.")
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.onAuthenticated = onAuthenticated
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: RemindersKit.Spacing.lg) {
            // App icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: [RemindersColors.accentBlue, RemindersColors.accentCyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Title
            VStack(spacing: RemindersKit.Spacing.sm) {
                Text(viewModel.authMode == .signIn ? "Welcome Back" : "Create Account")
                    .font(RemindersTypography.title1)
                    .foregroundColor(RemindersColors.textPrimary)

                Text(viewModel.authMode == .signIn
                     ? "Sign in to sync your tasks across devices"
                     : "Get started with Tasks and sync everywhere")
                    .font(RemindersTypography.body)
                    .foregroundColor(RemindersColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, RemindersKit.Spacing.xl)
            }
        }
    }

    // MARK: - Auth Options Section

    private var authOptionsSection: some View {
        VStack(spacing: RemindersKit.Spacing.md) {
            // Sign in with Apple
            SignInWithAppleButton(
                viewModel.authMode == .signIn ? .signIn : .signUp,
                onRequest: { request in
                    request.requestedScopes = [.fullName, .email]
                },
                onCompletion: { result in
                    viewModel.handleAppleSignIn(result: result)
                }
            )
            .signInWithAppleButtonStyle(.white)
            .frame(height: 50)
            .cornerRadius(RemindersKit.Radius.button)
            .padding(.horizontal, RemindersKit.Spacing.lg)

            // Sign in with Google
            Button {
                Task {
                    await viewModel.signInWithGoogle()
                }
            } label: {
                HStack(spacing: RemindersKit.Spacing.md) {
                    Image(systemName: "g.circle.fill")
                        .font(.system(size: 20))

                    Text(viewModel.authMode == .signIn ? "Sign in with Google" : "Sign up with Google")
                        .font(RemindersTypography.button)
                }
                .foregroundColor(RemindersColors.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(RemindersColors.backgroundSecondary)
                .cornerRadius(RemindersKit.Radius.button)
                .overlay(
                    RoundedRectangle(cornerRadius: RemindersKit.Radius.button)
                        .stroke(RemindersColors.separator, lineWidth: 1)
                )
            }
            .padding(.horizontal, RemindersKit.Spacing.lg)
        }
    }

    // MARK: - Divider

    private func dividerWithText(_ text: String) -> some View {
        HStack(spacing: RemindersKit.Spacing.md) {
            Rectangle()
                .fill(RemindersColors.separator)
                .frame(height: 1)

            Text(text)
                .font(RemindersTypography.caption1)
                .foregroundColor(RemindersColors.textTertiary)

            Rectangle()
                .fill(RemindersColors.separator)
                .frame(height: 1)
        }
        .padding(.horizontal, RemindersKit.Spacing.xl)
    }

    // MARK: - Email Sign In Section

    private var emailSignInSection: some View {
        VStack(spacing: RemindersKit.Spacing.md) {
            // Email field
            VStack(alignment: .leading, spacing: RemindersKit.Spacing.xs) {
                Text("Email")
                    .font(RemindersTypography.caption1)
                    .foregroundColor(RemindersColors.textSecondary)

                TextField("", text: $viewModel.email)
                    .textFieldStyle(AuthTextFieldStyle())
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit {
                        focusedField = .password
                    }
            }

            // Password field
            VStack(alignment: .leading, spacing: RemindersKit.Spacing.xs) {
                Text("Password")
                    .font(RemindersTypography.caption1)
                    .foregroundColor(RemindersColors.textSecondary)

                HStack {
                    Group {
                        if viewModel.showPassword {
                            TextField("", text: $viewModel.password)
                        } else {
                            SecureField("", text: $viewModel.password)
                        }
                    }
                    .textContentType(viewModel.authMode == .signIn ? .password : .newPassword)
                    .focused($focusedField, equals: .password)
                    .submitLabel(viewModel.authMode == .signIn ? .go : .next)
                    .onSubmit {
                        if viewModel.authMode == .signIn {
                            Task { await viewModel.signInWithEmail() }
                        } else {
                            focusedField = .confirmPassword
                        }
                    }

                    Button {
                        viewModel.showPassword.toggle()
                    } label: {
                        Image(systemName: viewModel.showPassword ? "eye.slash" : "eye")
                            .foregroundColor(RemindersColors.textTertiary)
                    }
                }
                .padding(RemindersKit.Spacing.md)
                .background(RemindersColors.backgroundSecondary)
                .cornerRadius(RemindersKit.Radius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: RemindersKit.Radius.md)
                        .stroke(
                            focusedField == .password ? RemindersColors.accentBlue : RemindersColors.separator,
                            lineWidth: 1
                        )
                )
            }

            // Confirm password (sign up only)
            if viewModel.authMode == .signUp {
                VStack(alignment: .leading, spacing: RemindersKit.Spacing.xs) {
                    Text("Confirm Password")
                        .font(RemindersTypography.caption1)
                        .foregroundColor(RemindersColors.textSecondary)

                    SecureField("", text: $viewModel.confirmPassword)
                        .textContentType(.newPassword)
                        .focused($focusedField, equals: .confirmPassword)
                        .submitLabel(.go)
                        .onSubmit {
                            Task { await viewModel.signUp() }
                        }
                        .padding(RemindersKit.Spacing.md)
                        .background(RemindersColors.backgroundSecondary)
                        .cornerRadius(RemindersKit.Radius.md)
                        .overlay(
                            RoundedRectangle(cornerRadius: RemindersKit.Radius.md)
                                .stroke(
                                    focusedField == .confirmPassword ? RemindersColors.accentBlue : RemindersColors.separator,
                                    lineWidth: 1
                                )
                        )
                }
            }

            // Validation errors
            if let validationError = viewModel.validationError {
                HStack(spacing: RemindersKit.Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(validationError)
                }
                .font(RemindersTypography.footnote)
                .foregroundColor(RemindersColors.accentRed)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Sign in/up button
            PrimaryButton(
                viewModel.authMode == .signIn ? "Sign In" : "Create Account",
                isLoading: viewModel.isLoading,
                isDisabled: !viewModel.isFormValid
            ) {
                focusedField = nil
                Task {
                    if viewModel.authMode == .signIn {
                        await viewModel.signInWithEmail()
                    } else {
                        await viewModel.signUp()
                    }
                }
            }
            .padding(.top, RemindersKit.Spacing.sm)

            // Forgot password (sign in only)
            if viewModel.authMode == .signIn {
                Button("Forgot Password?") {
                    viewModel.showForgotPassword = true
                }
                .font(RemindersTypography.subheadline)
                .foregroundColor(RemindersColors.accentBlue)
            }

            // Switch mode
            HStack(spacing: RemindersKit.Spacing.xs) {
                Text(viewModel.authMode == .signIn ? "Don't have an account?" : "Already have an account?")
                    .font(RemindersTypography.subheadline)
                    .foregroundColor(RemindersColors.textSecondary)

                Button(viewModel.authMode == .signIn ? "Sign Up" : "Sign In") {
                    withAnimation {
                        viewModel.toggleAuthMode()
                    }
                }
                .font(RemindersTypography.subheadlineBold)
                .foregroundColor(RemindersColors.accentBlue)
            }
            .padding(.top, RemindersKit.Spacing.sm)
        }
        .padding(.horizontal, RemindersKit.Spacing.lg)
        .sheet(isPresented: $viewModel.showForgotPassword) {
            ForgotPasswordSheet(email: viewModel.email) { email in
                Task {
                    await viewModel.sendPasswordReset(email: email)
                }
            }
        }
    }

    // MARK: - Terms Section

    private var termsSection: some View {
        VStack(spacing: RemindersKit.Spacing.xs) {
            Text("By continuing, you agree to our")
                .font(RemindersTypography.caption1)
                .foregroundColor(RemindersColors.textTertiary)

            HStack(spacing: RemindersKit.Spacing.xxs) {
                Button("Terms of Service") {
                    // Open terms
                }
                .font(RemindersTypography.caption1Bold)
                .foregroundColor(RemindersColors.accentBlue)

                Text("and")
                    .font(RemindersTypography.caption1)
                    .foregroundColor(RemindersColors.textTertiary)

                Button("Privacy Policy") {
                    // Open privacy policy
                }
                .font(RemindersTypography.caption1Bold)
                .foregroundColor(RemindersColors.accentBlue)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, RemindersKit.Spacing.xl)
    }

    // MARK: - Loading Overlay

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: RemindersKit.Spacing.md) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)

                Text(viewModel.loadingMessage)
                    .font(RemindersTypography.subheadline)
                    .foregroundColor(.white)
            }
            .padding(RemindersKit.Spacing.xl)
            .background(RemindersColors.backgroundElevated)
            .cornerRadius(RemindersKit.Radius.lg)
        }
    }
}

// MARK: - Authentication Field

enum AuthenticationField {
    case email
    case password
    case confirmPassword
}

// MARK: - Auth Mode

enum AuthMode {
    case signIn
    case signUp
}

// MARK: - Auth Text Field Style

struct AuthTextFieldStyle: TextFieldStyle {
    @FocusState private var isFocused: Bool

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(RemindersKit.Spacing.md)
            .background(RemindersColors.backgroundSecondary)
            .cornerRadius(RemindersKit.Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: RemindersKit.Radius.md)
                    .stroke(RemindersColors.separator, lineWidth: 1)
            )
            .foregroundColor(RemindersColors.textPrimary)
    }
}

// MARK: - Authentication View Model

@MainActor
final class AuthenticationViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var authMode: AuthMode = .signIn
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var confirmPassword: String = ""
    @Published var showPassword: Bool = false
    @Published var isLoading: Bool = false
    @Published var loadingMessage: String = "Signing in..."
    @Published var showError: Bool = false
    @Published var errorMessage: String?
    @Published var validationError: String?
    @Published var showForgotPassword: Bool = false

    // MARK: - Callbacks

    var onAuthenticated: ((ClerkUser) -> Void)?

    // MARK: - Computed Properties

    var isFormValid: Bool {
        let emailValid = isValidEmail(email)
        let passwordValid = password.count >= 8

        if authMode == .signUp {
            return emailValid && passwordValid && password == confirmPassword
        }

        return emailValid && passwordValid
    }

    // MARK: - Actions

    func toggleAuthMode() {
        authMode = authMode == .signIn ? .signUp : .signIn
        validationError = nil
        password = ""
        confirmPassword = ""
    }

    func clearError() {
        showError = false
        errorMessage = nil
    }

    // MARK: - Email/Password Authentication

    func signInWithEmail() async {
        guard validateForm() else { return }

        isLoading = true
        loadingMessage = "Signing in..."

        do {
            // Simulate API call - replace with actual Clerk SDK integration
            try await Task.sleep(nanoseconds: 1_500_000_000)

            let user = ClerkUser(
                id: UUID().uuidString,
                email: email,
                firstName: nil,
                lastName: nil,
                username: nil,
                imageUrl: nil,
                createdAt: Date(),
                updatedAt: Date()
            )

            Logger.shared.logAuth(event: "Email sign in successful", userId: user.id)
            onAuthenticated?(user)

        } catch {
            Logger.shared.error(error, message: "Email sign in failed", category: .auth)
            errorMessage = error.localizedDescription
            showError = true
        }

        isLoading = false
    }

    func signUp() async {
        guard validateForm() else { return }

        isLoading = true
        loadingMessage = "Creating account..."

        do {
            // Simulate API call - replace with actual Clerk SDK integration
            try await Task.sleep(nanoseconds: 2_000_000_000)

            let user = ClerkUser(
                id: UUID().uuidString,
                email: email,
                firstName: nil,
                lastName: nil,
                username: nil,
                imageUrl: nil,
                createdAt: Date(),
                updatedAt: Date()
            )

            Logger.shared.logAuth(event: "Sign up successful", userId: user.id)
            onAuthenticated?(user)

        } catch {
            Logger.shared.error(error, message: "Sign up failed", category: .auth)
            errorMessage = error.localizedDescription
            showError = true
        }

        isLoading = false
    }

    func sendPasswordReset(email: String) async {
        isLoading = true
        loadingMessage = "Sending reset email..."

        do {
            // Simulate API call - replace with actual Clerk SDK integration
            try await Task.sleep(nanoseconds: 1_000_000_000)

            Logger.shared.logAuth(event: "Password reset email sent")

        } catch {
            Logger.shared.error(error, message: "Password reset failed", category: .auth)
            errorMessage = error.localizedDescription
            showError = true
        }

        isLoading = false
    }

    // MARK: - Apple Sign In

    func handleAppleSignIn(result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Invalid Apple credential"
                showError = true
                return
            }

            Task {
                await signInWithApple(credential: credential)
            }

        case .failure(let error):
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue {
                // User cancelled - don't show error
                return
            }

            Logger.shared.error(error, message: "Apple sign in failed", category: .auth)
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func signInWithApple(credential: ASAuthorizationAppleIDCredential) async {
        isLoading = true
        loadingMessage = "Signing in with Apple..."

        do {
            // Simulate API call - replace with actual Clerk SDK integration
            try await Task.sleep(nanoseconds: 1_500_000_000)

            let email = credential.email
            let fullName = credential.fullName

            let user = ClerkUser(
                id: credential.user,
                email: email,
                firstName: fullName?.givenName,
                lastName: fullName?.familyName,
                username: nil,
                imageUrl: nil,
                createdAt: Date(),
                updatedAt: Date()
            )

            Logger.shared.logAuth(event: "Apple sign in successful", userId: user.id)
            onAuthenticated?(user)

        } catch {
            Logger.shared.error(error, message: "Apple sign in failed", category: .auth)
            errorMessage = error.localizedDescription
            showError = true
        }

        isLoading = false
    }

    // MARK: - Google Sign In

    func signInWithGoogle() async {
        isLoading = true
        loadingMessage = "Signing in with Google..."

        do {
            // Simulate API call - replace with actual Google Sign In SDK integration
            try await Task.sleep(nanoseconds: 1_500_000_000)

            let user = ClerkUser(
                id: UUID().uuidString,
                email: "user@gmail.com",
                firstName: "Google",
                lastName: "User",
                username: nil,
                imageUrl: nil,
                createdAt: Date(),
                updatedAt: Date()
            )

            Logger.shared.logAuth(event: "Google sign in successful", userId: user.id)
            onAuthenticated?(user)

        } catch {
            Logger.shared.error(error, message: "Google sign in failed", category: .auth)
            errorMessage = error.localizedDescription
            showError = true
        }

        isLoading = false
    }

    // MARK: - Validation

    private func validateForm() -> Bool {
        validationError = nil

        guard isValidEmail(email) else {
            validationError = "Please enter a valid email address"
            return false
        }

        guard password.count >= 8 else {
            validationError = "Password must be at least 8 characters"
            return false
        }

        if authMode == .signUp {
            guard password == confirmPassword else {
                validationError = "Passwords do not match"
                return false
            }
        }

        return true
    }

    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: emailRegex, options: .regularExpression) != nil
    }
}

// MARK: - Forgot Password Sheet

struct ForgotPasswordSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var email: String
    @State private var isSent: Bool = false

    let onSubmit: (String) -> Void

    init(email: String, onSubmit: @escaping (String) -> Void) {
        _email = State(initialValue: email)
        self.onSubmit = onSubmit
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RemindersColors.background
                    .ignoresSafeArea()

                VStack(spacing: RemindersKit.Spacing.xl) {
                    // Icon
                    Image(systemName: isSent ? "envelope.badge.fill" : "lock.rotation")
                        .font(.system(size: 48))
                        .foregroundColor(RemindersColors.accentBlue)
                        .padding(.top, RemindersKit.Spacing.xxl)

                    // Title
                    Text(isSent ? "Check Your Email" : "Reset Password")
                        .font(RemindersTypography.title2)
                        .foregroundColor(RemindersColors.textPrimary)

                    // Description
                    Text(isSent
                         ? "We've sent a password reset link to \(email)"
                         : "Enter your email address and we'll send you a link to reset your password.")
                        .font(RemindersTypography.body)
                        .foregroundColor(RemindersColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, RemindersKit.Spacing.xl)

                    if !isSent {
                        // Email field
                        TextField("Email", text: $email)
                            .textFieldStyle(AuthTextFieldStyle())
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .padding(.horizontal, RemindersKit.Spacing.lg)

                        // Submit button
                        PrimaryButton("Send Reset Link") {
                            onSubmit(email)
                            withAnimation {
                                isSent = true
                            }
                        }
                        .padding(.horizontal, RemindersKit.Spacing.lg)
                    } else {
                        // Done button
                        PrimaryButton("Done") {
                            dismiss()
                        }
                        .padding(.horizontal, RemindersKit.Spacing.lg)
                    }

                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(RemindersColors.textSecondary)
                }
            }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }
}

// MARK: - Preview

#Preview("Sign In") {
    AuthenticationView(
        onAuthenticated: { user in
            print("Authenticated: \(user.displayName)")
        },
        onSkip: {
            print("Skipped")
        }
    )
}
