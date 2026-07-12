import Foundation
import Cocoa

@MainActor
final class Updater: @unchecked Sendable {
    static let shared = Updater()
    
    // Updates are fetched anonymously from the public GitHub Releases API.
    // Never embed credentials here: anything compiled into the binary can be
    // extracted by anyone who downloads the app.
    private let repoOwner = "SafetH16"
    private let repoName = "Monkeys"
    
    private init() {}
    
    func checkForUpdates(silent: Bool) {
        guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return
        }
        
        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: urlString) else { return }
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("MonKeys-App", forHTTPHeaderField: "User-Agent")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                if !silent {
                    Task { @MainActor in
                        self.showErrorAlert(message: "Errore durante la verifica: \(error.localizedDescription)")
                    }
                }
                return
            }
            
            guard let data = data else { return }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let tagName = json["tag_name"] as? String,
                   let assets = json["assets"] as? [[String: Any]] {
                    
                    let cleanCurrent = currentVersion.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
                    let cleanLatest = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
                    
                    if cleanLatest.compare(cleanCurrent, options: .numeric) == .orderedDescending {
                        // Find MonKeys.zip asset
                        if let asset = assets.first(where: { ($0["name"] as? String) == "MonKeys.zip" }),
                           let downloadURLString = asset["browser_download_url"] as? String,
                           let downloadURL = URL(string: downloadURLString) {
                            Task { @MainActor in
                                self.promptUpdate(version: tagName, downloadURL: downloadURL)
                            }
                        }
                    } else {
                        if !silent {
                            Task { @MainActor in
                                self.showInfoAlert(message: "L'applicazione è aggiornata all'ultima versione (\(currentVersion)).")
                            }
                        }
                    }
                }
            } catch {
                if !silent {
                    Task { @MainActor in
                        self.showErrorAlert(message: "Errore nel parsing dell'aggiornamento.")
                    }
                }
            }
        }
        task.resume()
    }
    
    private func promptUpdate(version: String, downloadURL: URL) {
        let alert = NSAlert()
        alert.messageText = "Aggiornamento Disponibile"
        alert.informativeText = "È disponibile una nuova versione di MonKeys (\(version)). Desideri scaricarla e installarla automaticamente?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Aggiorna Ora")
        alert.addButton(withTitle: "Annulla")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            downloadAndInstallUpdate(from: downloadURL)
        }
    }
    
    private func downloadAndInstallUpdate(from url: URL) {
        var request = URLRequest(url: url)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("MonKeys-App", forHTTPHeaderField: "User-Agent")
        
        let destURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("MonKeys_update.zip")
        try? FileManager.default.removeItem(at: destURL)
        
        let downloadTask = URLSession.shared.downloadTask(with: request) { tempLocalURL, response, error in
            if let error = error {
                Task { @MainActor in
                    self.showErrorAlert(message: "Errore durante il download: \(error.localizedDescription)")
                }
                return
            }
            
            guard let tempLocalURL = tempLocalURL else { return }
            
            do {
                try FileManager.default.moveItem(at: tempLocalURL, to: destURL)
                Task { @MainActor in
                    self.applyUpdate(zipURL: destURL)
                }
            } catch {
                Task { @MainActor in
                    self.showErrorAlert(message: "Errore di salvataggio del file temporaneo: \(error.localizedDescription)")
                }
            }
        }
        downloadTask.resume()
    }
    
    private func applyUpdate(zipURL: URL) {
        let appPath = Bundle.main.bundlePath
        let scriptPath = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("monkeys_apply_update.sh").path

        // Never delete the running app before the replacement is verified:
        // extract to a private mktemp dir, check the bundle exists, move the
        // old app aside as a backup, and restore it if the copy fails.
        let scriptContent = """
        #!/bin/bash
        set -u
        sleep 1
        WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/monkeys_update.XXXXXX")" || exit 1
        cleanup() { rm -rf "$WORKDIR"; rm -f "\(zipURL.path)"; rm -f "$0"; }
        if ! unzip -q "\(zipURL.path)" -d "$WORKDIR"; then cleanup; exit 1; fi
        if [ ! -d "$WORKDIR/MonKeys.app" ]; then cleanup; exit 1; fi
        BACKUP="$WORKDIR/MonKeys_previous.app"
        if ! mv "\(appPath)" "$BACKUP"; then cleanup; exit 1; fi
        if cp -R "$WORKDIR/MonKeys.app" "\(appPath)"; then
            xattr -cr "\(appPath)" 2>/dev/null || true
        else
            mv "$BACKUP" "\(appPath)"
        fi
        open "\(appPath)"
        cleanup
        """
        
        do {
            try scriptContent.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [scriptPath]
            try process.run()
            
            NSApplication.shared.terminate(nil)
        } catch {
            showErrorAlert(message: "Impossibile applicare l'aggiornamento: \(error.localizedDescription)")
        }
    }
    
    private func showErrorAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Errore Aggiornamento"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.runModal()
    }
    
    private func showInfoAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Verifica Aggiornamenti"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.runModal()
    }
}
