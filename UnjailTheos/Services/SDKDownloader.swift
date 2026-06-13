import Foundation

/// 在线 SDK 下载器，使用 URLSession 流式下载并追踪进度
@MainActor
final class SDKDownloader: NSObject, ObservableObject {
    @Published var progress = DownloadProgress()
    @Published var isDownloading = false
    @Published var lastError: String?

    private var downloadTask: URLSessionDownloadTask?
    private var completionHandler: ((Result<URL, Error>) -> Void)?
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 3600
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    func download(source: SDKSource) async throws -> URL {
        try TheosPaths.ensureDirectoryStructure()
        let destination = TheosPaths.sdksDirectory.appendingPathComponent(source.filename)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        // 应用 gh-proxy 加速（国内网络）
        let requestURL = NetworkConfig.proxiedURL(source.url)

        return try await withCheckedThrowingContinuation { continuation in
            isDownloading = true
            progress = DownloadProgress()
            lastError = nil
            completionHandler = { result in
                continuation.resume(with: result)
            }
            downloadTask = session.downloadTask(with: requestURL)
            downloadTask?.resume()
        }
    }

    func cancel() {
        downloadTask?.cancel()
        isDownloading = false
    }
}

extension SDKDownloader: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        Task { @MainActor in
            progress = DownloadProgress(
                bytesReceived: totalBytesWritten,
                totalBytes: totalBytesExpectedToWrite
            )
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let filename = downloadTask.originalRequest?.url?.lastPathComponent ?? "sdk.tar.xz"
        let destination = TheosPaths.sdksDirectory.appendingPathComponent(filename)

        do {
            try TheosPaths.ensureDirectoryStructure()
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            Task { @MainActor in
                isDownloading = false
                completionHandler?(.success(destination))
                completionHandler = nil
            }
        } catch {
            Task { @MainActor in
                isDownloading = false
                lastError = error.localizedDescription
                completionHandler?(.failure(error))
                completionHandler = nil
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        Task { @MainActor in
            isDownloading = false
            lastError = error.localizedDescription
            completionHandler?(.failure(error))
            completionHandler = nil
        }
    }
}
