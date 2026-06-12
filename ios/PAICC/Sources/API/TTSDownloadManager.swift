import Foundation
import AVFoundation

/// TTS 下载状态
enum TTSDownloadState {
    case idle
    case synthesizing
    case downloading
    case completed(URL)
    case failed(Error)
}

/// TTS 下载管理器 - 处理 TTS 音频下载和缓存
class TTSDownloadManager {

    // MARK: - 单例
    static let shared = TTSDownloadManager()

    // MARK: - 属性

    private let session: URLSession
    private var activeTasks: [String: URLSessionDownloadTask] = [:]
    private var downloadProgress: [String: Double] = [:]

    // 缓存配置
    private let cacheDirectory: URL
    private let maxCacheSize: Int = 50 * 1024 * 1024  // 50MB

    // 回调
    var onProgress: ((String, Double) -> Void)?
    var onComplete: ((String, URL) -> Void)?
    var onError: ((String, Error) -> Void)?

    // MARK: - 初始化

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        session = URLSession(configuration: config, delegate: nil, delegateQueue: .main)

        // 设置缓存目录
        let cachePath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = cachePath.appendingPathComponent("TTS")

        createCacheDirectoryIfNeeded()
    }

    private func createCacheDirectoryIfNeeded() {
        if !FileManager.default.fileExists(atPath: cacheDirectory.path) {
            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }

    // MARK: - 缓存管理

    /// 生成缓存键
    private func cacheKey(text: String, voice: String) -> String {
        let input = "\(text)_\(voice)"
        return input.data(using: .utf8)!.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
    }

    /// 检查缓存
    private func cachedFile(text: String, voice: String) -> URL? {
        let key = cacheKey(text: text, voice: voice)
        let fileURL = cacheDirectory.appendingPathComponent("\(key).mp3")

        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL
        }
        return nil
    }

    /// 清理过期缓存
    func cleanExpiredCache(maxAge: TimeInterval = 24 * 60 * 60) {  // 默认 24 小时
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        let now = Date()

        for file in files {
            guard let attributes = try? file.resourceValues(forKeys: [.creationDateKey]),
                  let creationDate = attributes.creationDate else {
                continue
            }

            if now.timeIntervalSince(creationDate) > maxAge {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// 清理所有缓存
    func clearCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        createCacheDirectoryIfNeeded()
    }

    /// 获取缓存大小
    func cacheSize() -> Int {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: .skipsHiddenFiles
        ) else { return 0 }

        return files.reduce(0) { total, file in
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return total + size
        }
    }

    /// 清理超出大小的缓存
    private func cleanCacheIfNeeded() {
        let currentSize = cacheSize()
        if currentSize <= maxCacheSize { return }

        guard var files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
            options: .skipsHiddenFiles
        ) else { return }

        // 按创建日期排序，最老的先删除
        files.sort { file1, file2 in
            let date1 = (try? file1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
            let date2 = (try? file2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
            return date1 < date2
        }

        var sizeToDelete = currentSize - maxCacheSize

        for file in files {
            guard sizeToDelete > 0 else { break }
            let fileSize = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            try? FileManager.default.removeItem(at: file)
            sizeToDelete -= fileSize
        }
    }

    // MARK: - 下载

    /// 下载 TTS 音频
    /// - Parameters:
    ///   - text: 要转换的文本
    ///   - voice: 语音类型
    ///   - useCache: 是否使用缓存，默认 true
    func download(text: String, voice: String = "zh-CN", useCache: Bool = true) async throws -> URL {
        // 检查缓存
        if useCache, let cachedURL = cachedFile(text: text, voice: voice) {
            return cachedURL
        }

        // 异步合成并下载
        let response = try await APIClient.shared.synthesizeAsync(text: text, voice: voice)
        let audioData = try await APIClient.shared.downloadTTSAudio(from: response.downloadUrl)

        // 保存到缓存
        let key = cacheKey(text: text, voice: voice)
        let fileURL = cacheDirectory.appendingPathComponent("\(key).mp3")

        try audioData.write(to: fileURL)

        // 检查并清理缓存
        cleanCacheIfNeeded()

        return fileURL
    }

    /// 下载 TTS 音频（带进度回调）
    func downloadWithProgress(text: String, voice: String = "zh-CN", useCache: Bool = true) async throws -> URL {
        // 检查缓存
        if useCache, let cachedURL = cachedFile(text: text, voice: voice) {
            return cachedURL
        }

        let key = cacheKey(text: text, voice: voice)

        // 异步合成并下载
        let response = try await APIClient.shared.synthesizeAsync(text: text, voice: voice)

        // 使用带进度的下载
        let audioData = try await downloadWithProgress(urlString: response.downloadUrl, key: key)

        // 保存到缓存
        let fileURL = cacheDirectory.appendingPathComponent("\(key).mp3")
        try audioData.write(to: fileURL)

        // 检查并清理缓存
        cleanCacheIfNeeded()

        return fileURL
    }

    private func downloadWithProgress(urlString: String, key: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }

        return try await withCheckedThrowingContinuation { continuation in
            let task = session.downloadTask(with: url) { [weak self] tempURL, response, error in
                self?.activeTasks.removeValue(forKey: key)

                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let tempURL = tempURL else {
                    continuation.resume(throwing: APIError.noData)
                    return
                }

                do {
                    let data = try Data(contentsOf: tempURL)
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            activeTasks[key] = task
            task.resume()
        }
    }

    /// 取消下载
    func cancelDownload(key: String) {
        activeTasks[key]?.cancel()
        activeTasks.removeValue(forKey: key)
        downloadProgress.removeValue(forKey: key)
    }

    /// 取消所有下载
    func cancelAllDownloads() {
        for (_, task) in activeTasks {
            task.cancel()
        }
        activeTasks.removeAll()
        downloadProgress.removeAll()
    }

    // MARK: - 获取下载进度

    func progress(for key: String) -> Double {
        return downloadProgress[key] ?? 0
    }

    // MARK: - 直接播放

    /// 下载并直接播放
    func downloadAndPlay(text: String, voice: String = "zh-CN") async throws {
        let fileURL = try await download(text: text, voice: voice, useCache: true)
        VoiceService.shared.playAudioFile(at: fileURL)
    }
}

// MARK: - VoiceService 扩展

extension VoiceService {

    /// 播放本地音频文件
    func playAudioFile(at url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            updateStateInternal(.playing)
        } catch {
            print("Failed to play audio file: \(error)")
        }
    }
}