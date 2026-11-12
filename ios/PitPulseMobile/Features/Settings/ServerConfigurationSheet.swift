import SceneKit
import SharedComponents
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
            VStack(spacing: 28) {
                VStack(spacing: 18) {
                    Text("服务器设置")
                        .font(.title)
                        .foregroundStyle(.primary)

                    Text("连接到你的私人服务器")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

                VStack(spacing: 14) {
                    TextField("服务器地址", text: $address)
                        .keyboardType(.URL).textContentType(.URL)
                        .focused($focusedField, equals: .address)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .token }
                        .padding(16)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                    SecureField(model.hasToken ? "Token（留空保留已有令牌）" : "Token（可选）", text: $token)
                        .focused($focusedField, equals: .token)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                        .padding(16)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Spacer()

                VStack(spacing: 14) {
                    Button {
                        focusedField = nil
                        isTesting = true
                        result = nil
                        testRequest = UUID()
                    } label: {
                        Group {
                            if isTesting { ProgressView().frame(maxWidth: .infinity) }
                            else { Text("测试").frame(maxWidth: .infinity) }
                        }.padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isTesting || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("测试当前填写的服务器")
                    .buttonBorderShape(.capsule)

                    Button {
                        if let error = model.saveConnection(address: address, token: token) {
                            result = error
                        } else {
                            token = ""
                            dismiss()
                            Task { await model.loadCalendar(force: true) }
                        }
                    } label: {
                        Text("保存").frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isTesting || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonBorderShape(.capsule)

                    if let result {
                        Text(result).font(.footnote).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: 480).frame(maxWidth: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
            .tint(PulseStyle.red)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("关闭服务器配置")
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
                    result = health.database && health.status == "ok" ? "连接成功" : "服务已响应，数据库暂不可用"
                } catch {
                    guard !Task.isCancelled else { return }
                    result = MobileModel.message(for: error)
                }
                isTesting = false
            }
        }
    }

    func invalidateTest() {
        testRequest = nil
        isTesting = false
        result = nil
    }
}
