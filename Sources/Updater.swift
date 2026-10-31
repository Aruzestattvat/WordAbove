import AppKit
import CryptoKit
import Foundation

struct UpdateRelease: Sendable {
    let version: String
    let downloadURL: URL
    let releaseURL: URL
    let sha256: String

    static func newer(_ candidate: String, than current: String) -> Bool {
        func parts(_ version: String) -> [Int]? {
            let values = version.split(separator: ".").compactMap { Int($0) }
            return values.count == 3 ? values : nil
        }
        guard let a = parts(candidate), let b = parts(current) else { return false }
        return b.lexicographicallyPrecedes(a)
    }

    static func fromGitHub(_ data: Data, currentVersion: String) throws -> UpdateRelease? {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
            let digest: String?
        }
        struct Release: Decodable {
            let tag_name: String
            let html_url: URL
            let assets: [Asset]
            let draft: Bool
            let prerelease: Bool
        }
        let release = try JSONDecoder().decode(Release.self, from: data)
        guard !release.draft, !release.prerelease, release.tag_name.hasPrefix("v") else { return nil }
        let version = String(release.tag_name.dropFirst())
        guard newer(version, than: currentVersion) else { return nil }
        let filename = "WordAbove-\(version)-macos-arm64.zip"
        guard let asset = release.assets.first(where: { $0.name == filename }),
              asset.browser_download_url.scheme == "https",
              asset.browser_download_url.host == "github.com",
              asset.browser_download_url.path == "/Aruzestattvat/WordAbove/releases/download/v\(version)/\(filename)",
              release.html_url.scheme == "https", release.html_url.host == "github.com",
              release.html_url.path == "/Aruzestattvat/WordAbove/releases/tag/v\(version)",
              let digest = asset.digest, digest.hasPrefix("sha256:") else {
            throw UpdateError.invalidRelease
        }
        let hash = String(digest.dropFirst(7)).lowercased()
        guard hash.count == 64, hash.allSatisfy({ $0.isHexDigit }) else { throw UpdateError.invalidRelease }
        return UpdateRelease(version: version, downloadURL: asset.browser_download_url,
                             releaseURL: release.html_url, sha256: hash)
    }
}

enum UpdateError: LocalizedError {
    case invalidRelease, invalidDownload, invalidApp, cannotInstall, failedCommand(String)
    var errorDescription: String? {
        switch self {
        case .invalidRelease: return "GitHub 发布信息缺少有效的安装包或校验值。"
        case .invalidDownload: return "下载的安装包未通过 SHA-256 校验。"
        case .invalidApp: return "下载的应用签名、版本或标识不正确。"
        case .cannotInstall: return "无法写入当前应用所在文件夹。请从 GitHub 手动下载并覆盖安装。"
        case .failedCommand(let command): return "更新准备失败：\(command)"
        }
    }
}

struct PreparedUpdate: Sendable {
    let target: URL
    let staged: URL
    let backup: URL
    let workspace: URL

    func launchInstaller(waitingFor pid: Int32) throws {
        let script = workspace.appendingPathComponent("install.sh")
        let content = """
        #!/bin/sh
        set -eu
        pid="$1"; target="$2"; staged="$3"; backup="$4"; workspace="$5"
        count=0
        while /bin/kill -0 "$pid" 2>/dev/null && [ "$count" -lt 100 ]; do
          /bin/sleep 0.2
          count=$((count + 1))
        done
        if /bin/kill -0 "$pid" 2>/dev/null; then exit 1; fi
        /bin/mv "$target" "$backup"
        if ! /bin/mv "$staged" "$target"; then
          /bin/mv "$backup" "$target"
          exit 1
        fi
        /usr/bin/open "$target"
        /bin/rm -rf "$backup" "$workspace"
        """
        try content.write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, String(pid), target.path, staged.path, backup.path, workspace.path]
        try process.run()
    }
}

enum GitHubUpdater {
    private static let api = URL(string: "https://api.github.com/repos/Aruzestattvat/WordAbove/releases/latest")!

    static func check(currentVersion: String) async throws -> UpdateRelease? {
        var request = URLRequest(url: api)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("WordAbove/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.invalidRelease }
        return try UpdateRelease.fromGitHub(data, currentVersion: currentVersion)
    }

    static func prepare(_ release: UpdateRelease, replacing target: URL) async throws -> PreparedUpdate {
        let (download, response) = try await URLSession.shared.download(from: release.downloadURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.invalidDownload }
        return try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let workspace = fileManager.temporaryDirectory.appendingPathComponent("WordAboveUpdate-\(UUID().uuidString)", isDirectory: true)
            let staged = target.deletingLastPathComponent().appendingPathComponent(".WordAbove-update-\(UUID().uuidString).app")
            let backup = target.deletingLastPathComponent().appendingPathComponent(".WordAbove-previous-\(UUID().uuidString).app")
            do {
                try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
                let archive = workspace.appendingPathComponent("update.zip")
                try fileManager.copyItem(at: download, to: archive)
                let hash = SHA256.hash(data: try Data(contentsOf: archive)).map { String(format: "%02x", $0) }.joined()
                guard hash == release.sha256 else { throw UpdateError.invalidDownload }
                let extracted = workspace.appendingPathComponent("extracted", isDirectory: true)
                try fileManager.createDirectory(at: extracted, withIntermediateDirectories: true)
                try run("/usr/bin/ditto", ["-x", "-k", archive.path, extracted.path])
                let app = extracted.appendingPathComponent("词在上.app", isDirectory: true)
                guard let bundle = Bundle(url: app),
                      bundle.bundleIdentifier == "local.wordabove.SpotlightDictionary",
                      bundle.infoDictionary?["CFBundleShortVersionString"] as? String == release.version else {
                    throw UpdateError.invalidApp
                }
                try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
                do { try fileManager.copyItem(at: app, to: staged) }
                catch { throw UpdateError.cannotInstall }
                try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", staged.path])
                return PreparedUpdate(target: target, staged: staged, backup: backup, workspace: workspace)
            } catch {
                try? fileManager.removeItem(at: staged)
                try? fileManager.removeItem(at: workspace)
                throw error
            }
        }.value
    }

    private static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError.failedCommand(executable) }
    }

    static func selfTest() {
        precondition(UpdateRelease.newer("1.1.18", than: "1.1.10"))
        precondition(!UpdateRelease.newer("1.1.2", than: "1.1.18"))
        precondition(!UpdateRelease.newer("1.1.18", than: "1.1.18"))
    }
}
