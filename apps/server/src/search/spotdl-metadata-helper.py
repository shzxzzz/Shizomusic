import json
import sys
from spotdl.types.album import Album
from spotdl.types.artist import Artist
from spotdl.utils.spotify import SpotifyClient

def spotify_id(url):
    return (url or "").split("?")[0].rstrip("/").split("/")[-1] or None

def song_payload(song):
    data = song.json
    return {"id": data.get("song_id") or spotify_id(data.get("url")), "title": data.get("name"),
            "artist": ", ".join(data.get("artists") or []) or data.get("artist"), "url": data.get("url"),
            "duration": data.get("duration"), "artworkURL": data.get("cover_url"), "discNumber": data.get("disc_number"),
            "trackNumber": data.get("track_number"), "explicit": data.get("explicit") is True}

def release_payload(url):
    album = Album.from_url(url, fetch_songs=False); songs = list(album.songs); first = songs[0].json if songs else {}
    return {"id": first.get("album_id") or spotify_id(album.url), "title": album.name,
            "artist": first.get("album_artist") or first.get("artist"), "url": album.url,
            "releaseType": first.get("album_type") or "unknown", "releaseDate": first.get("date"),
            "artworkURL": first.get("cover_url"), "tracks": [song_payload(song) for song in songs]}

def main():
    if len(sys.argv) != 3 or sys.argv[1] not in {"artist", "release"}: raise SystemExit("invalid arguments")
    # The spotDL CLI performs this initialization internally. The helper uses
    # spotDL as a library and deliberately selects its credential-free client.
    SpotifyClient.init("", "", use_official_api=False)
    if sys.argv[1] == "artist":
        artist = Artist.from_search_term(f"artist:{sys.argv[2]}", fetch_songs=False)
        payload = {"artist": {"id": spotify_id(artist.url), "name": artist.name, "url": artist.url},
                   "releases": [release_payload(url) for url in artist.albums]}
    else:
        release = release_payload(f"https://open.spotify.com/album/{sys.argv[2]}")
        payload = {"release": release, "tracks": release["tracks"]}
    print(json.dumps(payload, ensure_ascii=False))

if __name__ == "__main__": main()
