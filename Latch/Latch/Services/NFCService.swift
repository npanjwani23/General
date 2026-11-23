import CoreNFC

enum NFCScanError: LocalizedError {
    case unavailable
    case cancelled
    case unreadable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "NFC is not available on this device."
        case .cancelled: return nil
        case .unreadable: return "Could not read that tag. Try again."
        case .failed(let message): return message
        }
    }
}

/// Scans a single NFC tag and returns its factory unique ID as a hex string.
final class NFCService: NSObject, NFCTagReaderSessionDelegate {
    private var session: NFCTagReaderSession?
    private var continuation: CheckedContinuation<String, Error>?

    func scan(prompt: String) async throws -> String {
        #if targetEnvironment(simulator)
        // The simulator has no NFC radio. Pretend one fixed tag was tapped so
        // the pair, lock and unlock flows can be exercised. Never compiled
        // into a device build.
        try await Task.sleep(nanoseconds: 400_000_000)
        return "04A1B2C3D4E5F6"
        #else
        return try await scanDevice(prompt: prompt)
        #endif
    }

    private func scanDevice(prompt: String) async throws -> String {
        guard NFCTagReaderSession.readingAvailable else {
            throw NFCScanError.unavailable
        }
        return try await withCheckedThrowingContinuation { continuation in
            guard let session = NFCTagReaderSession(
                pollingOption: [.iso14443, .iso15693],
                delegate: self,
                queue: .main
            ) else {
                continuation.resume(throwing: NFCScanError.unavailable)
                return
            }
            self.continuation = continuation
            self.session = session
            session.alertMessage = prompt
            session.begin()
        }
    }

    private func finish(_ result: Result<String, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        self.session = nil
        continuation.resume(with: result)
    }

    // MARK: NFCTagReaderSessionDelegate

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        // Also fires after our own invalidate(); finish() ignores it once we have a result.
        if let nfcError = error as? NFCReaderError,
           nfcError.code == .readerSessionInvalidationErrorUserCanceled {
            finish(.failure(NFCScanError.cancelled))
        } else if let nfcError = error as? NFCReaderError,
                  nfcError.code == .readerSessionInvalidationErrorSessionTimeout {
            finish(.failure(NFCScanError.failed("No tag found. Try again.")))
        } else {
            finish(.failure(NFCScanError.failed(error.localizedDescription)))
        }
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first else { return }

        let identifier: Data?
        switch tag {
        case .miFare(let t): identifier = t.identifier
        case .iso7816(let t): identifier = t.identifier
        case .iso15693(let t): identifier = t.identifier
        case .feliCa(let t): identifier = t.currentIDm
        @unknown default: identifier = nil
        }

        guard let identifier, !identifier.isEmpty else {
            session.invalidate(errorMessage: "Could not read that tag.")
            finish(.failure(NFCScanError.unreadable))
            return
        }

        let hex = identifier.map { String(format: "%02X", $0) }.joined()
        session.alertMessage = "Tag read."
        finish(.success(hex))
        session.invalidate()
    }
}
