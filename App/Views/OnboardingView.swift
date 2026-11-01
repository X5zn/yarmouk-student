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
            Image("YULogo")
                .resizable().scaledToFit()
                .padding(10)
                .frame(width: 88, height: 88)
                .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
            Text("جامعة اليرموك").font(.largeTitle.bold()).foregroundStyle(.white)
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
/// If the saved session still works, it never shows the login page at all.
struct SISLoginSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var sync = SISSync(interactive: true)

    var body: some View {
        NavigationStack {
            SISLoginView(sync: sync)
                .overlay {
                    switch sync.phase {
                    case .checking:
                        busy(title: "لحظة…", subtitle: "عم نتأكد من دخولك على SIS")
                    case .syncing(let step):
                        busy(title: "عم نرتب معلوماتك…", subtitle: step)
                    case .failed(let msg):
                        VStack(spacing: 14) {
                            Image(systemName: "wifi.exclamationmark").font(.system(size: 40)).foregroundStyle(.orange)
                            Text(msg).font(.headline).multilineTextAlignment(.center)
                            Button("جرّب مرة ثانية") { Haptics.tap(); sync.start() }
                                .buttonStyle(.borderedProminent).tint(Brand.green)
                        }
                        .padding(32)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Brand.canvas)
                    default: EmptyView()
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: sync.phase)
                .safeAreaInset(edge: .bottom) {
                    if sync.phase == .login {
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("احفظ كلمة السر على جوالي (Keychain)", isOn: $sync.rememberPassword)
                                .font(.footnote)
                            Text("مرة وحدة بس. بعدها التطبيق بيستخدم نفس الجلسة لكل الصفحات.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.bar)
                    }
                }
                .navigationTitle("نظام معلومات الطلبة")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("إغلاق") { Haptics.tap(); dismiss() } }
                }
        }
        .interactiveDismissDisabled(isSyncing)
        .onAppear {
            sync.onFinished = { result in
                store.applySIS(result)
                Haptics.success()
                dismiss()
            }
            sync.start()
        }
    }

    private var isSyncing: Bool { if case .syncing = sync.phase { return true }; return false }

    private func busy(title: String, subtitle: String) -> some View {
        VStack(spacing: 14) {
            Image("YULogo").resizable().scaledToFit().frame(width: 64, height: 64)
            ProgressView().controlSize(.regular)
            Text(title).font(.headline)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary).contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.canvas)
    }
}
