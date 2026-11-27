import CoreNFC

enum NFCScanError: LocalizedError {
    case unavailable
    case cancelled
    case unreadable
    case busy
    case unstable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "NFC is not available on this device."
        case .cancelled: return nil
        case .unreadable: return "Could not read that tag. Try again."
        case .unstable: return "That tag gave a different ID on the second read, so it can't unlock Latch. Use an NFC sticker (NTAG213 or NTAG215)."
        case .busy: return "iOS says the NFC reader is busy. Close Wallet and the Camera, turn off iPhone Mirroring, then try again. If it keeps happening, restart the iPhone."
        case .failed(let message): return message
        }
    }
}

/// Scans a single NFC tag and returns its factory unique ID as a hex string.
final class NFCService: NSObject, NFCTagReaderSessionDelegate {
    private var session: NFCTagReaderSession?
    private var continuation: CheckedContinuation<String, Error>?
    /// The outcome of a read, held until iOS has closed the scan sheet.
    private var outcome: Result<String, Error>?
    /// Pairing reads the tag twice in one go, to prove its ID is stable.
    private var readsTwice = false
    private var firstRead: String?

    /// `readTwice` keeps the same sheet up and reads the tag a second time,
    /// failing with `.unstable` if the two IDs differ.
    func scan(prompt: String, readTwice: Bool = false) async throws -> String {
        #if targetEnvironment(simulator)
        // The simulator has no NFC radio. Pretend one fixed tag was tapped so
        // the pair, lock and unlock flows can be exercised. Never compiled
        // into a device build.
        try await Task.sleep(nanoseconds: 400_000_000)
        return "04A1B2C3D4E5F6"
        #else
        // iOS refuses a new scan for a second or two after the last scan
        // sheet closes (pairing scans twice in a row), and whenever another
        // app holds the reader. Wait and retry before giving up.
        var attempt = 0
        while true {
            do {
                return try await scanDevice(prompt: prompt, readTwice: readTwice)
            } catch NFCScanError.busy where attempt < 4 {
                attempt += 1
                try await Task.sleep(nanoseconds: 1_200_000_000)
            }
        }
        #endif
    }

    private func scanDevice(prompt: String, readTwice: Bool) async throws -> String {
        guard NFCTagReaderSession.readingAvailable else {
            throw NFCScanError.unavailable
        }
        // A second scan would overwrite the first one's continuation and
        // leave it waiting forever.
        guard continuation == nil else {
            throw NFCScanError.failed("A scan is already in progress.")
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
            self.readsTwice = readTwice
            session.alertMessage = prompt
            session.begin()
        }
    }

    private func finish(_ result: Result<String, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        self.session = nil
        self.outcome = nil
        self.firstRead = nil
        continuation.resume(with: result)
    }

    // MARK: NFCTagReaderSessionDelegate

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        // iOS reports a closed sheet a couple of seconds late. A late report
        // from an earlier scan must not end the scan that is running now.
        guard session === self.session else { return }
        // Our own invalidate() after a good read lands here too. Only now is
        // the sheet gone, so the next scan (pairing asks twice) can open.
        if let outcome {
            finish(outcome)
            return
        }
        if let nfcError = error as? NFCReaderError,
           nfcError.code == .readerSessionInvalidationErrorUserCanceled {
            finish(.failure(NFCScanError.cancelled))
        } else if let nfcError = error as? NFCReaderError,
                  nfcError.code == .readerSessionInvalidationErrorSessionTimeout {
            finish(.failure(NFCScanError.failed("No tag found. Try again.")))
        } else if let nfcError = error as? NFCReaderError,
                  nfcError.code == .readerSessionInvalidationErrorSystemIsBusy {
            finish(.failure(NFCScanError.busy))
        } else {
            let code = (error as NSError).code
            finish(.failure(NFCScanError.failed("\(error.localizedDescription) (NFC error \(code))")))
        }
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard session === self.session, outcome == nil, let tag = tags.first else { return }

        let identifier: Data?
        switch tag {
        case .miFare(let t): identifier = t.identifier
        case .iso7816(let t): identifier = t.identifier
        case .iso15693(let t): identifier = t.identifier
        case .feliCa(let t): identifier = t.currentIDm
        @unknown default: identifier = nil
        }

        guard let identifier, !identifier.isEmpty else {
            outcome = .failure(NFCScanError.unreadable)
            session.invalidate(errorMessage: "Could not read that tag.")
            return
        }

        let hex = identifier.map { String(format: "%02X", $0) }.joined()
        if readsTwice && firstRead == nil {
            // Keep the sheet up and read again. The tag answers afresh each
            // time, so a card with a changing ID shows up here.
            firstRead = hex
            session.alertMessage = "Checking the tag. Keep holding."
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, session === self.session, self.outcome == nil else { return }
                session.restartPolling()
            }
            return
        }
        if readsTwice && firstRead != hex {
            outcome = .failure(NFCScanError.unstable)
            session.invalidate(errorMessage: "This tag changes its ID.")
            return
        }
        session.alertMessage = readsTwice ? "Tag paired." : "Tag read."
        outcome = .success(hex)
        session.invalidate()
    }
}
