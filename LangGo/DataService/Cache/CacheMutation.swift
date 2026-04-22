import Foundation

enum CacheMutation {
    static func perform(
        remoteWrite: () async throws -> Void,
        applyLocalSuccess: () async -> Void
    ) async throws {
        try await remoteWrite()
        await applyLocalSuccess()
    }

    static func perform<Response>(
        remoteWrite: () async throws -> Response,
        applyLocalSuccess: (Response) async -> Void
    ) async throws -> Response {
        let response = try await remoteWrite()
        await applyLocalSuccess(response)
        return response
    }
}
