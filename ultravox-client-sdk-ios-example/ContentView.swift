import SwiftUI
import Ultravox

struct UltravoxApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = CallViewModel()

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if viewModel.session == nil {
                    ConnectionView(viewModel: viewModel)
                } else if !viewModel.isConnected {
                    ProgressView()
                    Text("Connecting...")
                } else {
                    CallView(viewModel: viewModel)
                }
            }
            .padding()
            .navigationTitle("Ultravox iOS Example")
        }
    }
}

struct ConnectionView: View {
    @ObservedObject var viewModel: CallViewModel

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Toggle("Debug", isOn: $viewModel.isDebugEnabled)

                Spacer()

                Button(action: {
                    Task {
                        await viewModel.startCall()
                    }
                }) {
                    Label("Start Call", systemImage: "phone.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}

struct CallView: View {
    @ObservedObject var viewModel: CallViewModel
    @State private var messageText: String = ""

    var body: some View {
        VStack {
            // Transcripts
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading) {
                        ForEach(viewModel.transcripts, id: \.id) { transcript in
                            TranscriptRow(transcript: transcript)
                        }
                    }
                }
                .onChange(of: viewModel.transcripts.count) { _, _ in
                    if let last = viewModel.transcripts.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .frame(maxHeight: 200)

            // Message input
            HStack {
                TextField("Type a message", text: $messageText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Button(action: {
                    Task {
                        await viewModel.sendMessage(messageText)
                        messageText = ""
                    }
                }) {
                    Label("Send", systemImage: "paperplane.fill")
                }
                .disabled(messageText.isEmpty)
            }

            // Control buttons
            HStack(spacing: 20) {
                Button(action: {
                    Task {
                        await viewModel.toggleMic()
                    }
                }) {
                    Label(viewModel.isMicMuted ? "Unmute" : "Mute",
                          systemImage: viewModel.isMicMuted ? "mic.slash.fill" : "mic.fill")
                }
                .buttonStyle(.bordered)

                Button(action: {
                    Task {
                        await viewModel.toggleSpeaker()
                    }
                }) {
                    Label(viewModel.isSpeakerMuted ? "Unmute Agent" : "Mute Agent",
                          systemImage: viewModel.isSpeakerMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
                .buttonStyle(.bordered)

                Button(action: {
                    Task {
                        await viewModel.endCall()
                    }
                }) {
                    Label("End Call", systemImage: "phone.down.fill")
                        .foregroundColor(.red)
                }
                .buttonStyle(.bordered)
            }

            if viewModel.isDebugEnabled {
                VStack(alignment: .leading) {
                    Text("Last Debug Message:")
                        .font(.headline)

                    if let debugMessage = viewModel.lastDebugMessage {
                        DebugMessageView(message: debugMessage)
                    }
                }
                .padding(.top)
            }
        }
        .padding()
    }
}

struct TranscriptRow: View {
    let transcript: TranscriptViewModel

    var body: some View {
        HStack(alignment: .top) {
            Text(transcript.speaker == .user ? "You:" : "Agent:")
                .font(.headline)
            Text(transcript.text)
        }
    }
}

struct DebugMessageView: View {
    let message: [String: Any]

    var body: some View {
        VStack(alignment: .leading) {
            ForEach(Array(message.keys), id: \.self) { key in
                HStack {
                    Text("\(key):")
                        .bold()
                    Text("\(String(describing: message[key]!))")
                }
            }
        }
        .font(.caption)
    }
}

struct TranscriptViewModel: Identifiable, Equatable {
    let id = UUID()
    let speaker: Role
    let text: String

    static func == (lhs: TranscriptViewModel, rhs: TranscriptViewModel) -> Bool {
        lhs.id == rhs.id && lhs.speaker == rhs.speaker && lhs.text == rhs.text
    }
}

// Codable structs for API interaction
struct CreateCallRequest: Codable {
    let systemPrompt: String
    let voice: String
    let model: String
    let firstSpeaker: String
    let recordingEnabled: Bool
    // Add other parameters as needed, matching the API documentation
}

struct CreateCallResponse: Codable {
    let joinUrl: String
}

@MainActor
class CallViewModel: ObservableObject {
    @Published var session: UltravoxSession?
    @Published var isConnected: Bool = false
    @Published var transcripts: [TranscriptViewModel] = []
    @Published var isMicMuted: Bool = false
    @Published var isSpeakerMuted: Bool = false
    @Published var isDebugEnabled: Bool = false
    @Published var lastDebugMessage: [String: Any]?

    private var statusObserver: NSObjectProtocol?
    private var transcriptsObserver: NSObjectProtocol?
    private var micMutedObserver: NSObjectProtocol?
    private var speakerMutedObserver: NSObjectProtocol?
    private var experimentalMessageObserver: NSObjectProtocol?

    private func buildJoinURL() async throws -> String {
        guard let apiKey = ProcessInfo.processInfo.environment["ULTRAVOX_API_KEY"] else {
            print("Error: ULTRAVOX_API_KEY environment variable not set.")
            throw NSError(domain: "CallViewModel", code: 1001, userInfo: [NSLocalizedDescriptionKey: "ULTRAVOX_API_KEY not set. Please set it in your Xcode scheme's environment variables."])
        }

        guard let url = URL(string: "https://api.ultravox.ai/api/calls") else {
            throw NSError(domain: "CallViewModel", code: 1002, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL."])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        let requestBody = CreateCallRequest(
            systemPrompt: "You are a story teller for children. You tell engaging and magical stories.",
            voice: "91fa9bcf-93c8-467c-8b29-973720e3f167",
            model: "fixie-ai/ultravox", // Sensible default
            firstSpeaker: "FIRST_SPEAKER_AGENT", // Sensible default
            recordingEnabled: true // Sensible default
        )

        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            print("Error encoding request body: \(error.localizedDescription)")
            throw NSError(domain: "CallViewModel", code: 1003, userInfo: [NSLocalizedDescriptionKey: "Failed to encode request body: \(error.localizedDescription)"])
        }
        
        print("Attempting to create call with API Key: \(apiKey.prefix(5))... URL: \(url.absoluteString)")


        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "CallViewModel", code: 1004, userInfo: [NSLocalizedDescriptionKey: "Invalid response from server."])
        }
        
        if httpResponse.statusCode != 201 {
            let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
            print("Error creating call. Status: \(httpResponse.statusCode). Body: \(responseBody)")
            throw NSError(domain: "CallViewModel", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed to create call. Status: \(httpResponse.statusCode). Details: \(responseBody)"])
        }

        do {
            let decodedResponse = try JSONDecoder().decode(CreateCallResponse.self, from: data)
            print("Successfully created call. Join URL: \(decodedResponse.joinUrl)")
            return decodedResponse.joinUrl
        } catch {
            let responseBody = String(data: data, encoding: .utf8) ?? "Invalid JSON response"
            print("Error decoding response: \(error.localizedDescription). Body: \(responseBody)")
            throw NSError(domain: "CallViewModel", code: 1005, userInfo: [NSLocalizedDescriptionKey: "Failed to decode response: \(error.localizedDescription). Response: \(responseBody)"])
        }
    }

    func startCall() async {
        // End existing call if active
        if session != nil {
            await endCall()
        }
        // session is now nil, isConnected is false

        do {
            let joinUrl = try await buildJoinURL()

            session = UltravoxSession(experimentalMessages: isDebugEnabled ? ["debug"] : [])

            struct MenuItem: Codable {
                var name: String
                var price: Float
            }
            struct SecretMenu: Codable {
                var specialItems: [MenuItem]
            }
            session?.registerToolImplementation(name: "getSecretMenu", implementation: { _ in
                let secretMenu = SecretMenu(specialItems: [
                    MenuItem(name: "Banana smoothie", price: 3.99),
                    MenuItem(name: "Butter pecan ice cream (one scoop)", price: 1.99),
                ])
                let json = try JSONEncoder().encode(secretMenu)
                return ClientToolResult(result: String(data: json, encoding: .utf8) ?? "Secret menu unavailable")
            })

            // Set up notification observers with Task for main actor calls
            statusObserver = NotificationCenter.default.addObserver(
                forName: .status,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.updateConnectionStatus()
                }
            }

            transcriptsObserver = NotificationCenter.default.addObserver(
                forName: .transcripts,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.updateTranscripts()
                }
            }

            micMutedObserver = NotificationCenter.default.addObserver(
                forName: .micMuted,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.updateMicStatus()
                }
            }

            speakerMutedObserver = NotificationCenter.default.addObserver(
                forName: .speakerMuted,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.updateSpeakerStatus()
                }
            }

            if isDebugEnabled {
                experimentalMessageObserver = NotificationCenter.default.addObserver(
                    forName: .experimentalMessage,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    Task { @MainActor in
                        if let message = notification.object as? [String: Any] {
                            self?.lastDebugMessage = message
                        }
                    }
                }
            }

            // Join call
            await session?.joinCall(joinUrl: joinUrl)
            // Status will be updated by observers
        } catch {
            print("Failed to start call: \(error.localizedDescription)")
            // Ensure UI reflects failure: session is nil, isConnected remains false.
            // ContentView will show ConnectionView.
            // Optionally, set an @Published error message here to display in the UI.
        }
    }

    func endCall() async {
        await session?.leaveCall()

        // Remove observers
        if let statusObserver = statusObserver {
            NotificationCenter.default.removeObserver(statusObserver)
        }
        if let transcriptsObserver = transcriptsObserver {
            NotificationCenter.default.removeObserver(transcriptsObserver)
        }
        if let micMutedObserver = micMutedObserver {
            NotificationCenter.default.removeObserver(micMutedObserver)
        }
        if let speakerMutedObserver = speakerMutedObserver {
            NotificationCenter.default.removeObserver(speakerMutedObserver)
        }
        if let experimentalMessageObserver = experimentalMessageObserver {
            NotificationCenter.default.removeObserver(experimentalMessageObserver)
        }

        session = nil
        isConnected = false
    }

    func sendMessage(_ text: String) async {
        await session?.sendText(text)
    }

    func toggleMic() async {
        session?.toggleMicMuted()
    }

    func toggleSpeaker() async {
        session?.toggleSpeakerMuted()
    }

    private func updateConnectionStatus() {
        isConnected = session?.status.isLive() ?? false
    }

    private func updateTranscripts() {
        transcripts = session?.transcripts.map {
            TranscriptViewModel(speaker: $0.speaker, text: $0.text)
        } ?? []
    }

    private func updateMicStatus() {
        isMicMuted = session?.micMuted ?? false
    }

    private func updateSpeakerStatus() {
        isSpeakerMuted = session?.speakerMuted ?? false
    }
}
