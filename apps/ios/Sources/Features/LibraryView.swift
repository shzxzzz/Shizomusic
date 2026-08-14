import SwiftUI

struct LibraryView: View {
    @State private var query = ""

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Музыка не добавлена",
                systemImage: "music.note.list",
                description: Text("Импортируйте аудиофайлы через Files или Share Sheet.")
            )
            .navigationTitle("Библиотека")
            .searchable(text: $query, prompt: "Треки, исполнители, альбомы")
        }
    }
}
