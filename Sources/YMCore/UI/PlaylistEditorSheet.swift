import SwiftUI

/// Modal macOS sheet for creating a new playlist or editing an existing playlist's
/// title, description, and visibility (public / private), with optional initial tracks.
public struct PlaylistEditorSheet: View {
    public let editingPlaylist: YMPlaylist?
    public let initialTracks: [YMTrack]
    public let onDismiss: () -> Void
    public let onSaved: (YMPlaylist) -> Void

    @UIState private var playlistsService = PlaylistsService.shared
    @UIState private var audioEngine = AudioPlayerEngine.shared
    @UIState private var title: String
    @UIState private var descriptionText: String
    @UIState private var isPrivate: Bool
    @UIState private var includeCurrentTrack: Bool
    @UIState private var isSaving: Bool = false
    @UIState private var errorMessage: String? = nil

    public init(
        editingPlaylist: YMPlaylist? = nil,
        initialTracks: [YMTrack] = [],
        onDismiss: @escaping () -> Void,
        onSaved: @escaping (YMPlaylist) -> Void
    ) {
        self.editingPlaylist = editingPlaylist
        self.initialTracks = initialTracks
        self.onDismiss = onDismiss
        self.onSaved = onSaved
        self._title = UIState(initialValue: editingPlaylist?.title ?? "")
        self._descriptionText = UIState(initialValue: editingPlaylist?.description ?? "")
        self._isPrivate = UIState(initialValue: editingPlaylist?.isPrivate ?? false)
        self._includeCurrentTrack = UIState(initialValue: false)
    }

    private var isEditing: Bool { editingPlaylist != nil }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var tracksToInsertOnCreate: [YMTrack] {
        var result = initialTracks
        if includeCurrentTrack,
           let current = audioEngine.currentTrack,
           !result.contains(where: { $0.id == current.id }) {
            result.append(current)
        }
        return result
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(YMTheme.accent.opacity(0.16))
                        .frame(width: 38, height: 38)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(YMTheme.accent.opacity(0.32), lineWidth: 1)
                        )

                    Image(systemName: isEditing ? "slider.horizontal.3" : "music.note.list")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(YMTheme.accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(isEditing ? "Редактировать плейлист" : "Новый плейлист")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(YMTheme.fg)

                    Text(isEditing ? "Измените название, описание или приватность" : "Создайте собственную подборку в Яндекс Музыке")
                        .font(.system(size: 12))
                        .foregroundStyle(YMTheme.fg60)
                }

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(YMTheme.fg60)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(YMTheme.surfaceComponent))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }

            Divider()
                .overlay(YMTheme.border)

            // Title input
            VStack(alignment: .leading, spacing: 6) {
                Text("Название")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(YMTheme.fg80)

                TextField("Например: Ночной драйв", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(YMTheme.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(YMTheme.borderHover, lineWidth: 1)
                            )
                    )
                    .onSubmit {
                        if !trimmedTitle.isEmpty && !isSaving {
                            savePlaylist()
                        }
                    }
            }

            // Description input
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Описание")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(YMTheme.fg80)
                    Text("(необязательно)")
                        .font(.system(size: 11))
                        .foregroundStyle(YMTheme.fg40)
                    Spacer()
                    Text("\(descriptionText.count)/500")
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(descriptionText.count > 500 ? Color.red : YMTheme.fg40)
                }

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $descriptionText)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(height: 82)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(YMTheme.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .strokeBorder(YMTheme.border, lineWidth: 1)
                                )
                        )

                    if descriptionText.isEmpty {
                        Text("Расскажите о настроении, жанре или поводе для этого плейлиста...")
                            .font(.system(size: 13))
                            .foregroundStyle(YMTheme.fg40)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }
                }
            }

            // Visibility picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Доступность")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(YMTheme.fg80)

                HStack(spacing: 10) {
                    visibilityOptionCard(
                        title: "Публичный",
                        subtitle: "Доступен по ссылке и в профиле",
                        icon: "globe",
                        selected: !isPrivate
                    ) {
                        isPrivate = false
                    }

                    visibilityOptionCard(
                        title: "Приватный",
                        subtitle: "Виден только вам",
                        icon: "lock.fill",
                        selected: isPrivate
                    ) {
                        isPrivate = true
                    }
                }
            }

            // Optional initial tracks section (create mode only)
            if !isEditing {
                if !initialTracks.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(YMTheme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Сразу добавим в плейлист:")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(YMTheme.fg60)
                            Text(initialTracks.map { "\($0.displayTitle) — \($0.artistsString)" }.joined(separator: ", "))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(YMTheme.fg)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(YMTheme.accent.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(YMTheme.accent.opacity(0.24), lineWidth: 1)
                            )
                    )
                } else if let playingTrack = audioEngine.currentTrack {
                    Toggle(isOn: $includeCurrentTrack) {
                        HStack(spacing: 8) {
                            Image(systemName: "music.note")
                                .font(.system(size: 12))
                                .foregroundStyle(YMTheme.accent)
                            Text("Добавить текущий трек «\(playingTrack.displayTitle)»")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(YMTheme.fg80)
                                .lineLimit(1)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }

            if let error = errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(YMTheme.fg80)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.orange.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.orange.opacity(0.30), lineWidth: 1)
                        )
                )
            }

            // Footer buttons
            HStack(spacing: 10) {
                Spacer()

                Button("Отмена") {
                    onDismiss()
                }
                .buttonStyle(YMGlassPillButtonStyle(primary: false, height: 32))
                .disabled(isSaving)

                Button {
                    savePlaylist()
                } label: {
                    HStack(spacing: 6) {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isEditing ? "Сохранить" : "Создать плейлист")
                    }
                }
                .buttonStyle(YMGlassPillButtonStyle(primary: true, height: 32))
                .disabled(trimmedTitle.isEmpty || descriptionText.count > 500 || isSaving)
            }
        }
        .padding(22)
        .frame(width: 460)
        .background(YMTheme.bg)
    }

    @ViewBuilder
    private func visibilityOptionCard(
        title: String,
        subtitle: String,
        icon: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selected ? YMTheme.accent : YMTheme.fg40)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(YMTheme.fg)
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(YMTheme.fg40)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? YMTheme.accent.opacity(0.10) : YMTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(selected ? YMTheme.accent.opacity(0.55) : YMTheme.border, lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func savePlaylist() {
        let finalTitle = trimmedTitle
        guard !finalTitle.isEmpty else { return }
        let finalDescription = String(descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))

        isSaving = true
        errorMessage = nil

        Task {
            do {
                let saved: YMPlaylist
                if let existing = editingPlaylist {
                    saved = try await playlistsService.updatePlaylist(
                        existing,
                        title: finalTitle,
                        description: finalDescription,
                        isPrivate: isPrivate
                    )
                    playlistsService.showToast("Плейлист «\(saved.title)» обновлён")
                } else {
                    saved = try await playlistsService.createPlaylist(
                        title: finalTitle,
                        description: finalDescription.isEmpty ? nil : finalDescription,
                        isPrivate: isPrivate,
                        initialTracks: tracksToInsertOnCreate
                    )
                    playlistsService.showToast("Плейлист «\(saved.title)» создан")
                }
                isSaving = false
                onSaved(saved)
            } catch {
                isSaving = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Reusable context-menu submenu allowing the user to add any track to an existing playlist
/// or create a brand-new playlist containing that track.
public struct AddToPlaylistContextMenu: View {
    public let track: YMTrack
    @UIState private var playlistsService = PlaylistsService.shared

    public init(track: YMTrack) {
        self.track = track
    }

    public var body: some View {
        Menu("Добавить в плейлист") {
            Button {
                playlistsService.presentQuickCreate(with: track)
            } label: {
                Label("Новый плейлист...", systemImage: "plus")
            }

            if !playlistsService.playlists.isEmpty {
                Divider()
                ForEach(playlistsService.playlists) { playlist in
                    Button {
                        Task {
                            do {
                                _ = try await playlistsService.addTracks([track], to: playlist)
                                playlistsService.showToast("Добавлено в «\(playlist.title)»")
                            } catch {
                                playlistsService.showToast("Ошибка добавления: \(error.localizedDescription)")
                            }
                        }
                    } label: {
                        Text(playlist.title)
                    }
                }
            }
        }
    }
}
