import Foundation

/// Centralized `@MainActor` service managing the user's playlists:
/// loading, creating (with title, description, visibility, and optional initial tracks),
/// editing metadata, deleting, and adding/removing tracks.
@MainActor
@Observable
public final class PlaylistsService {
    public static let shared = PlaylistsService()

    public private(set) var playlists: [YMPlaylist] = []
    public private(set) var isLoading: Bool = false
    public var errorMessage: String? = nil
    public var isQuickCreateSheetPresented: Bool = false
    public var pendingInitialTrack: YMTrack? = nil
    public var toastMessage: String? = nil

    @ObservationIgnored private var loadGeneration: UInt64 = 0
    private var toastDismissTask: Task<Void, Never>? = nil
    private let networkClient: YMNetworkClient
    private let keychain: KeychainManager

    public init(
        networkClient: YMNetworkClient = .shared,
        keychain: KeychainManager = .shared
    ) {
        self.networkClient = networkClient
        self.keychain = keychain
    }

    public func currentUserId() -> String? {
        AuthService.shared.currentUser?.userId ?? (try? keychain.getString(for: .userId))
    }

    private func resolvedOwnerUid(for playlist: YMPlaylist) throws -> String {
        if !playlist.uid.isEmpty && playlist.uid != "0" {
            return playlist.uid
        }
        if let uid = currentUserId(), !uid.isEmpty {
            return uid
        }
        throw YMAPIError.unauthorized
    }

    private func isRevisionConflict(_ error: Error) -> Bool {
        if let apiError = error as? YMAPIError {
            switch apiError {
            case .httpError(let statusCode, _):
                return statusCode == 409 || statusCode == 412
            case .serverError(let name, let message):
                let lower = (name + " " + message).lowercased()
                return lower.contains("revision") || lower.contains("wrong-revision")
            default:
                return false
            }
        }
        return false
    }

    private func extractCleanId(from trackId: String) -> String {
        trackId.split(separator: ":", maxSplits: 1).first.map(String.init) ?? trackId
    }

    public func ensureLoaded() async {
        if playlists.isEmpty && !isLoading {
            await loadPlaylists(force: false)
        }
    }

    public func loadPlaylists(force: Bool = true) async {
        if !force && !playlists.isEmpty { return }
        guard let uid = currentUserId(), !uid.isEmpty else {
            errorMessage = "Не удалось определить ID пользователя"
            return
        }

        loadGeneration &+= 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await networkClient.fetchUserPlaylists(
                uid: uid,
                cachePolicy: force ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
            )
            guard self.loadGeneration == generation else { return }
            self.playlists = fetched
            self.isLoading = false
        } catch {
            guard self.loadGeneration == generation else { return }
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }

    @discardableResult
    public func createPlaylist(
        title: String,
        description: String? = nil,
        isPrivate: Bool = false,
        initialTracks: [YMTrack] = []
    ) async throws -> YMPlaylist {
        guard let uid = currentUserId(), !uid.isEmpty else {
            throw YMAPIError.unauthorized
        }

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            throw YMAPIError.serverError(name: "invalid-title", message: "Введите название плейлиста")
        }

        let visibility = isPrivate ? "private" : "public"
        var created = try await networkClient.createPlaylist(
            uid: uid,
            title: cleanTitle,
            description: description,
            visibility: visibility
        )

        if !initialTracks.isEmpty {
            var addError: Error?
            do {
                var rev = created.revision ?? 1
                do {
                    created = try await networkClient.addTracksToPlaylist(
                        uid: uid,
                        kind: created.kind,
                        revision: rev,
                        tracks: initialTracks,
                        at: 0
                    )
                } catch {
                    if isRevisionConflict(error) {
                        let details = try await networkClient.fetchPlaylistDetails(uid: uid, kind: created.kind)
                        rev = details.revision ?? created.revision ?? 1
                        created = try await networkClient.addTracksToPlaylist(
                            uid: uid,
                            kind: created.kind,
                            revision: rev,
                            tracks: initialTracks,
                            at: 0
                        )
                    } else {
                        throw error
                    }
                }
            } catch {
                addError = error
            }

            upsertPlaylist(created, insertAtTop: true)
            if let addError {
                throw addError
            }
            return created
        }

        upsertPlaylist(created, insertAtTop: true)
        return created
    }

    @discardableResult
    public func updatePlaylist(
        _ playlist: YMPlaylist,
        title: String,
        description: String,
        isPrivate: Bool
    ) async throws -> YMPlaylist {
        let uid = try resolvedOwnerUid(for: playlist)
        var latest = playlist

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanTitle.isEmpty && cleanTitle != playlist.title {
            latest = try await networkClient.updatePlaylistName(uid: uid, kind: playlist.kind, title: cleanTitle)
        }

        let cleanDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanDesc != (playlist.description ?? "") {
            do {
                latest = try await networkClient.updatePlaylistDescription(uid: uid, kind: playlist.kind, description: cleanDesc)
            } catch {
                upsertPlaylist(latest, insertAtTop: false)
                throw error
            }
        }

        let targetVisibility = isPrivate ? "private" : "public"
        if (playlist.visibility?.lowercased() ?? "public") != targetVisibility {
            latest = try await networkClient.updatePlaylistVisibility(uid: uid, kind: playlist.kind, visibility: targetVisibility)
        }

        upsertPlaylist(latest, insertAtTop: false)
        return latest
    }

    public func deletePlaylist(_ playlist: YMPlaylist) async throws {
        let uid = try resolvedOwnerUid(for: playlist)
        try await networkClient.deletePlaylist(uid: uid, kind: playlist.kind)
        playlists.removeAll { $0.id == playlist.id }
    }

    @discardableResult
    public func addTracks(_ tracks: [YMTrack], to playlist: YMPlaylist) async throws -> YMPlaylist {
        guard !tracks.isEmpty else { return playlist }
        let uid = try resolvedOwnerUid(for: playlist)

        var attempts = 0
        while true {
            attempts += 1
            let details = try await networkClient.fetchPlaylistDetails(uid: uid, kind: playlist.kind)
            let revision = details.revision ?? playlist.revision ?? 1
            do {
                let updated = try await networkClient.addTracksToPlaylist(
                    uid: uid,
                    kind: playlist.kind,
                    revision: revision,
                    tracks: tracks,
                    at: 0
                )
                upsertPlaylist(updated, insertAtTop: false)
                return updated
            } catch {
                if attempts < 2 && isRevisionConflict(error) {
                    continue
                }
                throw error
            }
        }
    }

    @discardableResult
    public func removeTrack(at index: Int, from playlist: YMPlaylist) async throws -> YMPlaylist {
        let uid = try resolvedOwnerUid(for: playlist)

        var attempts = 0
        while true {
            attempts += 1
            let details = try await networkClient.fetchPlaylistDetails(uid: uid, kind: playlist.kind)
            if let serverTracks = details.tracks {
                guard index >= 0 && index < serverTracks.count else {
                    throw YMAPIError.serverError(name: "index-out-of-bounds", message: "Трек уже удалён или список изменился")
                }
            } else {
                guard index >= 0 else {
                    throw YMAPIError.serverError(name: "invalid-index", message: "Invalid track index")
                }
            }
            let revision = details.revision ?? playlist.revision ?? 1
            do {
                let updated = try await networkClient.removeTrackFromPlaylist(
                    uid: uid,
                    kind: playlist.kind,
                    revision: revision,
                    at: index
                )
                upsertPlaylist(updated, insertAtTop: false)
                return updated
            } catch {
                if attempts < 2 && isRevisionConflict(error) {
                    continue
                }
                throw error
            }
        }
    }

    @discardableResult
    public func removeTrack(_ track: YMTrack, at index: Int, from playlist: YMPlaylist) async throws -> YMPlaylist {
        let uid = try resolvedOwnerUid(for: playlist)
        let targetCleanId = extractCleanId(from: track.id)

        var attempts = 0
        while true {
            attempts += 1
            let details = try await networkClient.fetchPlaylistDetails(uid: uid, kind: playlist.kind)
            let resolvedIndex: Int
            if let serverTracks = details.tracks {
                if index >= 0 && index < serverTracks.count && extractCleanId(from: serverTracks[index].id) == targetCleanId {
                    resolvedIndex = index
                } else if let foundIndex = serverTracks.firstIndex(where: { extractCleanId(from: $0.id) == targetCleanId }) {
                    resolvedIndex = foundIndex
                } else {
                    throw YMAPIError.serverError(name: "track-not-found", message: "Трек не найден в плейлисте")
                }
            } else {
                guard index >= 0 else {
                    throw YMAPIError.serverError(name: "invalid-index", message: "Invalid track index")
                }
                resolvedIndex = index
            }

            let revision = details.revision ?? playlist.revision ?? 1
            do {
                let updated = try await networkClient.removeTrackFromPlaylist(
                    uid: uid,
                    kind: playlist.kind,
                    revision: revision,
                    at: resolvedIndex
                )
                upsertPlaylist(updated, insertAtTop: false)
                return updated
            } catch {
                if attempts < 2 && isRevisionConflict(error) {
                    continue
                }
                throw error
            }
        }
    }

    public func upsertPlaylist(_ playlist: YMPlaylist, insertAtTop: Bool) {
        if let idx = playlists.firstIndex(where: { $0.id == playlist.id }) {
            playlists[idx] = playlist
        } else if insertAtTop {
            playlists.insert(playlist, at: 0)
        } else {
            playlists.append(playlist)
        }
    }

    public func presentQuickCreate(with track: YMTrack? = nil) {
        pendingInitialTrack = track
        isQuickCreateSheetPresented = true
    }

    public func showToast(_ message: String) {
        toastDismissTask?.cancel()
        toastMessage = message
        toastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            toastMessage = nil
        }
    }

    public func resetAll() {
        loadGeneration &+= 1
        playlists = []
        isLoading = false
        errorMessage = nil
        isQuickCreateSheetPresented = false
        pendingInitialTrack = nil
        toastDismissTask?.cancel()
        toastMessage = nil
    }
}
