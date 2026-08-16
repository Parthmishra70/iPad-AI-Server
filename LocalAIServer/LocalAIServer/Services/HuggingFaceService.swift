//
//  HuggingFaceService.swift
//  LocalAIServer
//
//  Lightweight client for the public HuggingFace HTTP API. Used by the
//  Models tab's live search to discover GGUF models, list files in a
//  chosen repo, and resolve direct download URLs. No auth required for
//  public reads.
//

import Foundation

struct HuggingFaceModel: Decodable, Identifiable, Hashable {
    let id: String
    let author: String?
    let downloads: Int?
    let lastModified: Date?
    let tags: [String]?
    let pipelineTag: String?

    enum CodingKeys: String, CodingKey {
        case id
        case author = "author"
        case downloads
        case lastModified = "lastModified"
        case tags
        case pipelineTag = "pipeline_tag"
    }

    var displayName: String { id }
    var hasGGUFTag: Bool {
        guard let tags else { return false }
        return tags.contains { $0.lowercased() == "gguf" }
    }
}

struct HuggingFaceFile: Decodable, Identifiable, Hashable {
    let path: String
    let size: Int64?
    let oid: String?

    var id: String { path }
    var filename: String { (path as NSString).lastPathComponent }
    var sizeGB: Double? {
        guard let size else { return nil }
        return Double(size) / 1024.0 / 1024.0 / 1024.0
    }
    var quantization: String {
        // Match common quantization labels: Q4_K_M, Q5_K_S, Q8_0, IQ4_XS, etc.
        let pattern = #"(Q\d+_K_(?:S|M|L)|Q\d+_\d+|IQ\d+_[A-Z]+|F16|F32)"#
        if let range = filename.range(of: pattern, options: .regularExpression) {
            return String(filename[range])
        }
        return "unknown"
    }
    var isGGUF: Bool { filename.lowercased().hasSuffix(".gguf") }

    /// Heuristic: does the filename suggest this is an instruction-tuned
    /// (chat-capable) model? We look for substrings like `instruct`,
    /// `chat`, `it`, `chatml`. Base-model GGUFs (no chat template) will
    /// produce poor conversational output.
    var looksLikeInstruct: Bool {
        let lower = filename.lowercased()
        let hints = ["instruct", "chat", "-it", "_it", "chatml"]
        return hints.contains { lower.contains($0) }
    }
}

final class HuggingFaceService {
    static let shared = HuggingFaceService()

    private let session: URLSession
    private let baseURL = URL(string: "https://huggingface.co/api")!

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.waitsForConnectivity = true
        session = URLSession(configuration: cfg)
    }

    /// Search the HF Hub for GGUF-tagged models matching the query.
    func searchModels(query: String, limit: Int = 30) async throws -> [HuggingFaceModel] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        var components = URLComponents(url: baseURL.appendingPathComponent("models"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "search", value: trimmed),
            .init(name: "filter", value: "gguf"),
            .init(name: "limit", value: String(limit)),
            .init(name: "full", value: "false"),
            .init(name: "sort", value: "downloads"),
            .init(name: "direction", value: "-1"),
        ]
        let (data, response) = try await session.data(from: components.url!)
        try Self.validate(response: response)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([HuggingFaceModel].self, from: data)
    }

    /// List GGUF files in a repo (e.g., "TheBloke/Llama-2-7B-Chat-GGUF").
    /// When `excludeBaseModels` is true, GGUFs whose filenames don't look
    /// instruction-tuned (no "instruct"/"chat"/"-it"/"chatml") are hidden
    /// so the user doesn't accidentally download a base model that won't
    /// chat properly. Set to false to list every GGUF verbatim.
    func listFiles(repoId: String, excludeBaseModels: Bool = true) async throws -> [HuggingFaceFile] {
        var components = URLComponents(url: baseURL.appendingPathComponent("models/\(repoId)/tree/main"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "recursive", value: "true"),
        ]
        let (data, response) = try await session.data(from: components.url!)
        try Self.validate(response: response)
        let decoder = JSONDecoder()
        let files = try decoder.decode([HuggingFaceFile].self, from: data)
        let ggufFiles = files.filter { $0.isGGUF }
        let filtered = excludeBaseModels ? ggufFiles.filter { $0.looksLikeInstruct } : ggufFiles
        return filtered.sorted { ($0.size ?? 0) > ($1.size ?? 0) }
    }

    /// Resolve a repo + filename to a direct download URL (HEAD to get size).
    func resolveDownload(repoId: String, filename: String) -> URL {
        let encoded = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filename
        return URL(string: "https://huggingface.co/\(repoId)/resolve/main/\(encoded)")!
    }

    /// Probe the actual file size for a resolved URL.
    func probeFileSize(url: URL) async -> Int64? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse,
               let contentLength = http.value(forHTTPHeaderField: "Content-Length"),
               let bytes = Int64(contentLength) {
                return bytes
            }
        } catch {
            return nil
        }
        return nil
    }

    private static func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw HuggingFaceError.invalidResponse
        }
        switch http.statusCode {
        case 200..<300:
            return
        case 401, 403:
            throw HuggingFaceError.gatedRepo
        case 404:
            throw HuggingFaceError.notFound
        case 429:
            throw HuggingFaceError.rateLimited
        default:
            throw HuggingFaceError.httpError(http.statusCode)
        }
    }
}

enum HuggingFaceError: LocalizedError, Equatable {
    case invalidResponse
    case httpError(Int)
    case gatedRepo
    case notFound
    case rateLimited
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "HuggingFace returned an invalid response."
        case .httpError(let code):
            return "HuggingFace returned HTTP \(code)."
        case .gatedRepo:
            return "This repository is gated. Access tokens aren't supported yet — try a public repo (e.g. Qwen, bartowski, TheBloke mirrors)."
        case .notFound:
            return "Repository or file not found on HuggingFace. The repo may have been renamed or removed."
        case .rateLimited:
            return "HuggingFace rate limit hit. Wait a moment and try again."
        case .networkError(let err):
            return "Network error reaching HuggingFace: \(err.localizedDescription)"
        }
    }

    static func == (lhs: HuggingFaceError, rhs: HuggingFaceError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidResponse, .invalidResponse): return true
        case (.httpError(let a), .httpError(let b)): return a == b
        case (.gatedRepo, .gatedRepo): return true
        case (.notFound, .notFound): return true
        case (.rateLimited, .rateLimited): return true
        case (.networkError(let a), .networkError(let b)):
            return (a as NSError) == (b as NSError)
        default:
            return false
        }
    }
}

extension HuggingFaceError {
    /// Wrap an arbitrary thrown error into a HuggingFaceError if it isn't one already.
    static func wrap(_ error: Error) -> HuggingFaceError {
        if let hf = error as? HuggingFaceError { return hf }
        return .networkError(error)
    }
}
