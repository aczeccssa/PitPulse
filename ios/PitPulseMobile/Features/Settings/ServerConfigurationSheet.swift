import SharedData
import SwiftUI

struct ServerConfigurationSheet: View {
    @EnvironmentObject var model: MobileModel
    @Environment(\.dismiss) var dismiss
    @State var address = ""
    @State var token = ""
    @State var result: String?
    @State var testRequest: UUID?
    @State var isTesting = false
    @FocusState var focusedField: Field?
    enum Field { case address, token }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 16) {
                        field("Server Address") {
                            TextField("https://server.example", text: $address)
                                .keyboardType(.URL).textContentType(.URL)
                                .focused($focusedField, equals: .address)
                                .submitLabel(.next)
                                .onSubmit { focusedField = .token }
                        }
                        Divider()
                        field("Access Token") {
                            SecureField(model.hasToken ? "Leave blank to keep the saved token" : "Optional", text: $token)
                                .focused($focusedField, equals: .token)
                                .submitLabel(.done)
                                .onSubmit { focusedField = nil }
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(16)
                    .dashboardPanel(WebDashboardStyle.homePanel)

                    HStack(spacing: 12) {
                        Button {
                            focusedField = nil
                            isTesting = true
                            result = nil
                            testRequest = UUID()
                        } label: {
                            Group {
                                if isTesting { ProgressView() }
                                else { Label("Test Connection", systemImage: "antenna.radiowaves.left.and.right") }
                            }
                            .frame(maxWidth: .infinity, minHeight: 32)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Test this server")

                        Button {
                            if let error = model.saveConnection(address: address, token: token) {
                                result = error
                            } else {
                                token = ""
                                dismiss()
                                Task { await model.loadCalendar(force: true) }
                            }
                        } label: {
                            Text("Save").frame(maxWidth: .infinity, minHeight: 32)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .disabled(isTesting || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonBorderShape(.capsule)

                    if let result {
                        Text(result)
                            .font(.subheadline)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .dashboardPanel(WebDashboardStyle.homePanel)
                    }
                }
                .padding(16)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(PulseStyle.background)
            .tint(PulseStyle.red)
            .navigationTitle("Server Configuration")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close server configuration")
                }
            }
            .onAppear { address = model.serverText }
            .onChange(of: address) { _, _ in invalidateTest() }
            .onChange(of: token) { _, _ in invalidateTest() }
            .task(id: testRequest) {
                guard testRequest != nil else { return }
                do {
                    let server = try ServerAddress(rawValue: address)
                    let typedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
                    let credential = typedToken.isEmpty ? (server.url == model.serverURL ? model.currentToken : nil) : typedToken
                    let health = try await APIClient(baseURL: server.url).health(token: credential)
                    guard !Task.isCancelled else { return }
                    result = health.database && health.status == "ok" ? "Connection successful" : "Server reached. Database unavailable."
                } catch {
                    guard !Task.isCancelled else { return }
                    result = MobileModel.message(for: error).pulseEnglishError
                }
                isTesting = false
            }
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder input: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            input()
                .font(.body)
                .frame(minHeight: 44)
                .accessibilityLabel(title)
        }
    }

    func invalidateTest() {
        testRequest = nil
        isTesting = false
        result = nil
    }
}
