// Updater.swift
// MonKeys
//
// Auto-updater backed by GitHub Releases. The repository is private, so
// requests carry a token that build.sh injects at compile time from the
// untracked `.updater_token` file (see the generated UpdaterToken.swift).
// The token never lives in the repository: CI and clean checkouts get an
// empty stub and the updater then works anonymously (enough if the repo
// ever becomes public). Anything compiled into the binary can be extracted
// from it, so that token must stay scoped to this repository, read-only.
//
// Private-repo asset downloads use the API asset URL with
// `Accept: application/octet-stream`; GitHub then redirects to its storage
// backend, where the Authorization header must be dropped (the signed URL
// and the token together get rejected) — RedirectSanitizer does that.

import Foundation
import Cocoa

@MainActor
final class Updater: NSObject, @unchecked Sendable {
    static let shared = Updater()

    private let repoOwner = "SafetH16"
    private let repoName = "Monkeys"

    private lazy var session: URLSession = {
        URLSession(configuration: .ephemeral, delegate: RedirectSanitizer(), delegateQueue: nil)
    }()

    private override init() {}

    private func makeRequest(_ url: URL, accept: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("MonKeys-App", forHTTPHeaderField: "User-Agent")
        if !UpdaterAuth.token.isEmpty {
            request.setValue("Bearer \(UpdaterAuth.token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    func checkForUpdates(silent: Bool) {
        guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")
        else { return }

        let request = makeRequest(url, accept: "application/vnd.github+json")
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            let fail: (String) -> Void = { detail in
                guard !silent else { return }
                Task { @MainActor [weak self] in
                    self?.showErrorAlert(message: L.shared.sf("up_failed", detail))
                }
            }

            if let error {
                fail(error.localizedDescription)
                return
            }
            guard let http = response as? HTTPURLResponse else {
                fail("no HTTP response")
                return
            }
            guard http.statusCode == 200 else {
                // 404: no release visible (private repo without a token, or
                // no releases yet). 401: the compiled-in token was revoked.
                fail("HTTP \(http.statusCode)")
                return
            }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let assets = json["assets"] as? [[String: Any]]
            else {
                fail("unexpected API response")
                return
            }

            let cleanCurrent = currentVersion.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            let cleanLatest = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))

            guard cleanLatest.compare(cleanCurrent, options: .numeric) == .orderedDescending else {
                if !silent {
                    Task { @MainActor [weak self] in
                        self?.showInfoAlert(message: L.shared.sf("up_uptodate", currentVersion))
                    }
                }
                return
            }

            guard let asset = assets.first(where: { ($0["name"] as? String) == "MonKeys.zip" }),
                  let assetURLString = asset["url"] as? String,
                  let assetURL = URL(string: assetURLString)
            else {
                fail("release \(tagName) has no MonKeys.zip asset")
                return
            }

            Task { @MainActor [weak self] in
                self?.promptUpdate(version: cleanLatest, current: cleanCurrent, downloadURL: assetURL)
            }
        }
        task.resume()
    }

    private func promptUpdate(version: String, current: String, downloadURL: URL) {
        let alert = NSAlert()
        alert.messageText = L.shared.s("up_title")
        alert.informativeText = L.shared.sf("up_available", version, current)
        alert.alertStyle = .informational
        alert.addButton(withTitle: L.shared.s("up_install"))
        alert.addButton(withTitle: L.shared.s("up_later"))

        if alert.runModal() == .alertFirstButtonReturn {
            downloadAndInstallUpdate(from: downloadURL)
        }
    }

    private func downloadAndInstallUpdate(from url: URL) {
        let request = makeRequest(url, accept: "application/octet-stream")

        let destURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("MonKeys_update.zip")
        try? FileManager.default.removeItem(at: destURL)

        let downloadTask = session.downloadTask(with: request) { [weak self] tempLocalURL, response, error in
            let fail: (String) -> Void = { detail in
                Task { @MainActor [weak self] in
                    self?.showErrorAlert(message: L.shared.sf("up_failed", detail))
                }
            }
            if let error {
                fail(error.localizedDescription)
                return
            }
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                fail("download HTTP \(http.statusCode)")
                return
            }
            guard let tempLocalURL else { return }

            do {
                try FileManager.default.moveItem(at: tempLocalURL, to: destURL)
                Task { @MainActor [weak self] in
                    self?.applyUpdate(zipURL: destURL)
                }
            } catch {
                fail(error.localizedDescription)
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
            showErrorAlert(message: L.shared.sf("up_failed", error.localizedDescription))
        }
    }

    private func showErrorAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = L.shared.s("up_title")
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func showInfoAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = L.shared.s("up_title")
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.runModal()
    }
}

/// Drops the Authorization header when a request is redirected away from
/// the GitHub API (asset downloads land on a signed storage URL that
/// rejects requests carrying a second credential).
private final class RedirectSanitizer: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        var cleaned = request
        if request.url?.host != "api.github.com" {
            cleaned.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        completionHandler(cleaned)
    }
}
