# App Store listing draft

Drafted 2026-11-20 for the first public release (0.5.1). Nothing here has been entered in App
Store Connect. Every claim below was checked against the tree on that date; recheck the
feature list if the build you submit differs. The steps around it are in
[`RELEASING.md`](RELEASING.md).

## Text

| Field | Limit | Draft |
|---|---|---|
| Name | 30 | `ShoutKit` (fall back to `ShoutKit Radio` if the plain name is taken) |
| Subtitle | 30 | `Free radio. No account, no ads` |
| Promotional text | 170 | `Free, open-source internet radio. Tens of thousands of stations from the community Radio-Browser directory, with no ads, no account and no tracking.` |
| Keywords | 100 | `radio,internet radio,fm,stations,stream,music,news,jazz,kexp,open source,shoutcast,icecast,live` |
| Primary category | | Music |
| Secondary category | | News, or none |
| Price | | Free, no in-app purchases |

Check the name is free in App Store Connect before anything else: the listing, the screenshots
and the site all depend on it.

**Description**

```text
ShoutKit is free, open-source internet radio. Pick a station and it plays. There are no ads from us, no account to create and nothing tracking what you listen to.

FIND SOMETHING TO LISTEN TO
• Stations from Radio-Browser, a free directory run by its community
• Listen Now starts with the most-played stations in your region
• Search by name, or narrow by genre, country and bitrate
• Browse by genre

LISTEN YOUR WAY
• Live track titles and album art for the song on air
• Lock Screen and Control Center controls, and playback in the background
• Favorites, recently played stations and the tracks you heard
• Sleep timer, equalizer presets and a live level meter
• Opt-in Spatial Audio for supported headphones

EVERYWHERE ON YOUR DEVICES
• Quick Play widget for your Home Screen
• "Play KEXP on ShoutKit" with Siri and Shortcuts
• Apple Watch app with a Play Last complication
• iPad layouts with a sidebar, Split View and Stage Manager

PRIVATE BY DESIGN
• No analytics, no ads and no accounts
• The app talks only to what radio needs: the station directory, the streams you play, Apple's iTunes Search for album art, and anonymous play counts that help the directory rank stations. The last two can be turned off in Settings.
• Favorites and history stay on your device. Back up favorites to a file whenever you like.

OPEN SOURCE
ShoutKit's source is public under GPL-3.0 at github.com/cascadiacollections/shoutkit. You can read exactly what it does.

Stations are provided by their broadcasters. ShoutKit doesn't host or control their content, and some stations carry their own ads.
```

Left out on purpose: CarPlay (not reachable without the entitlement), Apple TV and Mac
(not part of this submission), and Handoff and the "View in Apple Music" link (true, but not
worth a line).

**What's New (0.5.1)**

```text
The first App Store release. Since the beta:
• Stations start playing in about half the time
• A live level meter on Now Playing and the mini player
• The Quick Play widget shows what's playing
• Listen Now starts with popular stations in your region
• A smaller download
• The app is now called ShoutKit
```

## URLs

| Field | Value |
|---|---|
| Support URL | `https://github.com/cascadiacollections/shoutkit/issues` |
| Marketing URL | `https://cascadiacollections.github.io/shoutkit/` |
| Privacy Policy URL | `https://cascadiacollections.github.io/shoutkit/#privacy` |

## App privacy questionnaire

Suggested answer: **Data Not Collected**. This is a judgment call that is Kevin's to make, so
the reasoning is spelled out.

Apple counts data as collected when it is sent off the device in a way that lets the developer
or a partner keep it beyond serving the request. ShoutKit has no server, no analytics SDK and
no account, so the developer receives nothing. The app's own privacy manifests declare no
collected data types and no tracking. What does leave the device goes straight to public
third-party services, with no identifier attached:

| Request | Goes to | Contains | Can be turned off |
|---|---|---|---|
| Directory queries | Radio-Browser mirrors (or SHOUTcast with a developer key) | Search terms, genre names, station ids | No |
| Streams and station artwork | The station you chose | A plain HTTP request | No |
| Play reports | Radio-Browser | The station's public id | Yes, Settings → Privacy |
| Album-art lookups | Apple's iTunes Search API | Artist and title of the track on air | Yes, Settings → Privacy |
| iCloud sync | The listener's own private iCloud database | Favorites, recently played stations, listening history | Yes, Settings → iCloud |

iCloud sync is not collection either, by the same definition: the data goes to the listener's
private CloudKit database, which the developer cannot read. The privacy manifests stay at zero
collected data types.

Each of those services sees the device's IP address, as any server does. If Apple or a
reviewer reads "search terms sent to a third party" as collecting Search History, the
fallback answer is Search History, not linked to identity, not used for tracking, purpose App
Functionality.

Tracking: **No**.

## Age rating

A suggestion, not a ruling: answer "None" to every content question except these two, and
expect a rating around 12+.

- Mature or suggestive themes: Infrequent/Mild. Stations are live, third-party broadcasts and
  some play music with explicit lyrics.
- Profanity or crude humor: Infrequent/Mild, for the same reason.

Unrestricted web access: No. The app plays audio streams and has no browser.

## App Review notes

```text
ShoutKit is an internet radio player. There is no account and no login, so no demo credentials are needed.

To test: open the app, tap any station on Listen Now, and playback starts within a few seconds. Lock the device to confirm background audio and the Lock Screen controls; this is why the app declares the audio background mode.

Stations come from Radio-Browser (radio-browser.info), a public community directory. The streams belong to their broadcasters; the app does not host, record or redistribute them.

The app is open source under GPL-3.0 with an additional permission for App Store distribution: https://github.com/cascadiacollections/shoutkit

The Apple Watch app is included. Motion access is requested only if the user turns on Spatial Audio in Settings.
```

## Screenshots

None are in the repo. Take them from the build you submit, so they show the ShoutKit name:
Listen Now, Now Playing with the level meter and album art, Search with filters open,
Favorites, and the Quick Play widget. Check App Store Connect for the iPhone and iPad sizes
it currently requires. Don't show CarPlay.
