import SwiftUI
import PhotosUI
import AVFoundation

/// «شو اخدتوا؟» — voice, photo and text notes saved per course.
struct NotesView: View {
    let courseCode: String
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = VoiceRecorder()
    @State private var text = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false

    var notes: [CourseNote] { store.notes.filter { $0.courseCode == courseCode }.sorted { $0.date > $1.date } }

    var body: some View {
        List {
            Section {
                TextField("شو اخدتوا اليوم؟", text: $text, axis: .vertical)
                    .lineLimit(2...6)
                HStack(spacing: 10) {
                    Button {
                        Haptics.tap()
                        if recorder.isRecording {
                            if let name = recorder.stop() { add(.audio, file: name) }
                        } else { recorder.start() }
                    } label: {
                        Label(recorder.isRecording ? "وقّف" : "صوت", systemImage: recorder.isRecording ? "stop.circle.fill" : "mic.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).tint(recorder.isRecording ? .red : Brand.green)

                    Button { Haptics.tap(); showCamera = true } label: {
                        Label("صوّر اللوح", systemImage: "camera.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).tint(Brand.green)

                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Image(systemName: "photo.on.rectangle")
                    }
                    .buttonStyle(.bordered).tint(Brand.green)
                }
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("احفظ الملاحظة") { Haptics.success(); add(.text, file: nil) }
                }
                if recorder.isRecording {
                    HStack(spacing: 8) {
                        Circle().fill(.red).frame(width: 8, height: 8)
                            .phaseAnimator([1.0, 0.3]) { v, p in v.opacity(p) } animation: { _ in .easeInOut(duration: 0.6) }
                        Text("عم نسجّل… اضغط «وقّف» لما تخلص").font(.plex(.footnote, .medium)).foregroundStyle(.red)
                    }
                }
            } header: {
                HStack(spacing: 8) {
                    Circle().fill(store.course(courseCode)?.color ?? Brand.green).frame(width: 8, height: 8)
                    Text(store.course(courseCode)?.name ?? courseCode).font(.plex(.footnote, .semibold))
                }
            }

            Section {
                if notes.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "note.text").font(.system(size: 30)).foregroundStyle(Brand.green.opacity(0.8))
                        Text("لسا ما في ملاحظات").font(.plex(.headline))
                        Text("سجّل صوت، صوّر اللوح، أو اكتب شو اخدتوا، وبتلاقيها هون مرتبة حسب التاريخ.")
                            .font(.plex(.footnote)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
                }
                ForEach(notes) { NoteRow(note: $0) }
                    .onDelete { idx in
                        let ids = idx.map { notes[$0].id }
                        store.notes.removeAll { ids.contains($0.id) }
                    }
            } header: {
                Text("الملاحظات (\(notes.count))").font(.plex(.footnote, .semibold))
            }
        }
        .scrollContentBackground(.hidden)
        .background(Brand.canvas)
        .animation(.snappy, value: notes.count)
        .animation(.snappy, value: recorder.isRecording)
        .navigationTitle("شو اخدتوا؟")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("تم") { dismiss() } } }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { savePhoto(data) }
                photoItem = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { data in if let data { savePhoto(data) } }.ignoresSafeArea()
        }
    }

    private func savePhoto(_ data: Data) {
        let name = "photo-\(UUID().uuidString).jpg"
        let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.8) ?? data
        try? jpeg.write(to: AppStore.mediaDir.appendingPathComponent(name))
        add(.photo, file: name)
        Haptics.success()
    }

    private func add(_ kind: CourseNote.Kind, file: String?) {
        store.notes.append(CourseNote(courseCode: courseCode, kind: kind, text: text, fileName: file))
        text = ""
    }
}

struct NoteRow: View {
    let note: CourseNote
    @StateObject private var player = VoicePlayer()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch note.kind {
            case .photo:
                if let f = note.fileName, let img = UIImage(contentsOfFile: AppStore.mediaDir.appendingPathComponent(f).path) {
                    Image(uiImage: img).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            case .audio:
                Button {
                    Haptics.tap()
                    if let f = note.fileName { player.toggle(AppStore.mediaDir.appendingPathComponent(f)) }
                } label: {
                    Label(player.isPlaying ? "إيقاف" : "تسجيل صوتي", systemImage: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                }
            case .text:
                EmptyView()
            }
            if !note.text.isEmpty { Text(note.text).font(.plex(.body)) }
            Text(ArabicFormat.shortDate(note.date) + " · " + ArabicFormat.time(note.date)).font(.plex(.caption)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

@MainActor
final class VoiceRecorder: ObservableObject {
    @Published var isRecording = false
    private var recorder: AVAudioRecorder?
    private var fileName: String?

    func start() {
        AVAudioApplication.requestRecordPermission { granted in
            guard granted else { return }
            Task { @MainActor in self.begin() }
        }
    }

    private func begin() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? session.setActive(true)
        let name = "voice-\(UUID().uuidString).m4a"
        let settings: [String: Any] = [AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1,
                                       AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]
        recorder = try? AVAudioRecorder(url: AppStore.mediaDir.appendingPathComponent(name), settings: settings)
        if recorder?.record() == true { fileName = name; isRecording = true }
    }

    func stop() -> String? {
        recorder?.stop()
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false)
        defer { fileName = nil }
        return fileName
    }
}

@MainActor
final class VoicePlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    private var player: AVAudioPlayer?

    func toggle(_ url: URL) {
        if isPlaying { player?.stop(); isPlaying = false; return }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        isPlaying = player?.play() ?? false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.isPlaying = false }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    var onFinish: (Data?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let img = info[.originalImage] as? UIImage
            parent.onFinish(img?.jpegData(compressionQuality: 0.8))
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onFinish(nil); parent.dismiss()
        }
    }
}
