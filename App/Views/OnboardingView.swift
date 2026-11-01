import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var store: AppStore
    @State private var showMoodle = false
    @State private var showSIS = false
    @State private var notificationsOn = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                VStack(spacing: 12) {
                    step(number: 1, title: "الايليرنينغ", subtitle: "بإيميلك الجامعي (Microsoft) — موادك، الملفات، الواجبات",
                         done: store.moodleLinked) { showMoodle = true }
                    step(number: 2, title: "نظام معلومات الطلبة SIS", subtitle: "اسمك، تخصصك، علاماتك وخطتك الدراسية (بيجيك رمز SMS)",
                         done: store.sisLinked) { showSIS = true }
                    step(number: 3, title: "الإشعارات", subtitle: "تذكير المحاضرات والواجبات والامتحانات",
                         done: notificationsOn) {
                        Task { notificationsOn = await NotificationManager.shared.requestPermission() }
                    }
                    Text("كلمة السر بتنكتب بصفحة الجامعة نفسها وبتضل على جوالك بس.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                }
                .padding(16)

                Button {
                    Haptics.success()
                    store.onboarded = true
                    store.rescheduleEverything()
                } label: {
                    Text(store.moodleLinked || store.sisLinked ? "يلا نبلش" : "كمّل بدون ربط هلأ")
                        .font(.headline)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Brand.green, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(PressableStyle())
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
        .background(Brand.canvas)
        .ignoresSafeArea(edges: .top)
        .sheet(isPresented: $showMoodle) { MoodleLoginSheet() }
        .sheet(isPresented: $showSIS) { SISLoginSheet() }
    }

    private var header: some View {
        VStack(spacing: 14) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Brand.green)
                .frame(width: 76, height: 76)
                .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text("طالب اليرموك").font(.largeTitle.bold()).foregroundStyle(.white)
            Text("جامعتك كلها بتطبيق واحد").font(.body).foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 90).padding(.bottom, 36)
        .background(Brand.green)
    }

    private func step(number: Int, title: String, subtitle: String, done: Bool, action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(done ? Brand.green : Color(uiColor: .systemGray5)).frame(width: 36, height: 36)
                    if done { Image(systemName: "checkmark").font(.headline).foregroundStyle(.white) }
                    else { Text("\(number)").font(.headline).foregroundStyle(.primary) }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .healthCard()
        }
        .buttonStyle(PressableStyle())
    }
}

/// E-learning sign-in: the university's own Microsoft page, inside the app.
struct MoodleLoginSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = BrowserModel()
    @State private var finishing = false

    var body: some View {
        NavigationStack {
            WebViewContainer(url: URL(string: "https://elearning.yu.edu.jo/auth/oidc/?source=loginpage")!, model: model)
                .overlay {
                    if finishing {
                        VStack(spacing: 12) {
                            ProgressView().controlSize(.large)
                            Text("عم نجيب موادك…").font(.headline)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.regularMaterial)
                    }
                }
                .navigationTitle("تسجيل الدخول")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("إلغاء") { Haptics.tap(); dismiss() }
                    }
                }
        }
        .onChange(of: model.currentURL) { _, url in
            guard !finishing, url.contains("elearning.yu.edu.jo/my") else { return }
            finishing = true
            Task {
                await WebSession.shared.syncCookiesToURLSession()
                await store.refreshMoodle()
                Haptics.success()
                dismiss()
            }
        }
    }
}

/// SIS sign-in (username, password, SMS code) then automatic sync of his pages.
struct SISLoginSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var sync = SISSync()

    var body: some View {
        NavigationStack {
            SISLoginView(sync: sync)
                .overlay {
                    switch sync.phase {
                    case .syncing(let step):
                        VStack(spacing: 12) {
                            ProgressView().controlSize(.large)
                            Text("عم نرتب معلوماتك…").font(.headline)
                            Text(step).font(.subheadline).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.regularMaterial)
                    case .failed(let msg):
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
                            Text(msg).font(.headline)
                            Button("جرّب مرة ثانية") { Haptics.tap(); sync.start() }.buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.regularMaterial)
                    default: EmptyView()
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if sync.phase == .login {
                        Toggle("احفظ كلمة السر على جوالي (Keychain)", isOn: $sync.rememberPassword)
                            .font(.footnote)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(.bar)
                    }
                }
                .navigationTitle("SIS")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("إغلاق") { Haptics.tap(); dismiss() } }
                }
        }
        .onAppear {
            sync.onFinished = { result in
                store.applySIS(result)
                Haptics.success()
                dismiss()
            }
            sync.start()
        }
    }
}
