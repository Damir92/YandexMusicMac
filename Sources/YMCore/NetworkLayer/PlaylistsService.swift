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

        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await networkClient.fetchUserPlaylists(
                uid: uid,
                cachePolicy: force ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
            )
            self.playlists = fetched
            self.isLoading = false
        } catch {
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
            let rev = created.revision ?? 1
            if let withTracks = try? await networkClient.addTracksToPlaylist(
                uid: uid,
                kind: created.kind,
                revision: rev,
                tracks: initialTracks,
                at: 0
            ) {
                created = withTracks
            }
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
        let uid = playlist.uid
        var latest = playlist

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanTitle.isEmpty && cleanTitle != playlist.title {
            latest = try await networkClient.updatePlaylistName(uid: uid, kind: playlist.kind, title: cleanTitle)
        }

        let cleanDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanDesc != (playlist.description ?? "") {
            if let updated = try? await networkClient.updatePlaylistDescription(uid: uid, kind: playlist.kind, description: cleanDesc) {
                latest = updated
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
        try await networkClient.deletePlaylist(uid: playlist.uid, kind: playlist.kind)
        playlists.removeAll { $0.id == playlist.id }
    }

    @discardableResult
    public func addTracks(_ tracks: [YMTrack], to playlist: YMPlaylist) async throws -> YMPlaylist {
        guard !tracks.isEmpty else { return playlist }
        // Always fetch fresh revision before mutating to avoid wrong-revision conflicts
        let details = try await networkClient.fetchPlaylistDetails(uid: playlist.uid, kind: playlist.kind)
        let revision = details.revision ?? playlist.revision ?? 1
        let updated = try await networkClient.addTracksToPlaylist(
            uid: playlist.uid,
            kind: playlist.kind,
            revision: revision,
            tracks: tracks,
            at: 0
        )
        upsertPlaylist(updated, insertAtTop: false)
        return updated
    }

    @discardableResult
    public func removeTrack(at index: Int, from playlist: YMPlaylist) async throws -> YMPlaylist {
        let details = try await networkClient.fetchPlaylistDetails(uid: playlist.uid, kind: playlist.kind)
        let revision = details.revision ?? playlist.revision ?? 1
        let updated = try await networkClient.removeTrackFromPlaylist(
            uid: playlist.uid,
            kind: playlist.kind,
            revision: revision,
            at: index
        )
        upsertPlaylist(updated, insertAtTop: false)
        return updated
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
        playlists = []
        isLoading = false
        errorMessage = nil
        isQuickCreateSheetPresented = false
        pendingInitialTrack = nil
        toastDismissTask?.cancel()
        toastMessage = nil
    }
}
