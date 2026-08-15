# ``RadioDirectory``

Find internet radio stations, and model what one is.

## Overview

`RadioDirectory` is the domain layer: the ``Station`` model, the
``RadioDirectoryProviding`` boundary every source of stations conforms to, and concrete clients
for the [Radio-Browser](https://www.radio-browser.info) community directory and SHOUTcast.

Most adopters need two things: a client, and a decorator or two around it.

```swift
let directory = CachingRadioDirectory(
    base: RadioBrowserDirectoryClient(transport: URLSessionHTTPTransport.shared)
)
let stations = try await directory.topStations(limit: 50)
```

The provider protocol composes: ``CachingRadioDirectory``, ``PreferredRadioDirectory``, and
``BundledRadioDirectory`` all wrap another ``RadioDirectoryProviding``, so caching, editorial
pinning, and offline fallback stack in whatever order suits you.

### Typed throws

Every requirement on ``RadioDirectoryProviding`` is declared `throws(RadioDirectoryError)`.
That gives callers exhaustive, allocation-free error handling, at the cost of welding
conformances to this enum — a client for a directory this package doesn't know about must map
its failures into ``RadioDirectoryError`` rather than defining its own error type.

### Etiquette

Radio-Browser is volunteer-run and rate-limits by `User-Agent`. ``RadioBrowserDirectoryClient``
sends one, and mirrors across the hosts you supply. If you are shipping your own app, expect to
identify it as yours.

## Topics

### Domain Models

- ``Station``
- ``Genre``
- ``StreamEndpoint``
- ``StreamFormat``
- ``NowPlayingMetadata``
- ``StationSearchFilters``
- ``StationNameFormatter``

### The Directory Boundary

- ``RadioDirectoryProviding``
- ``RadioDirectoryError``

### Directory Clients

- ``RadioBrowserDirectoryClient``
- ``ShoutcastDirectoryClient``
- ``ShoutcastEndpoints``
- ``RetryPolicy``

### Composing Directories

Decorators over ``RadioDirectoryProviding``. Each wraps another provider, so they stack.

- ``CachingRadioDirectory``
- ``PreferredRadioDirectory``
- ``BundledRadioDirectory``
- ``PreferredStations``

### Caching and Snapshots

- ``DirectoryDiscoverySnapshot``
- ``DirectoryDiscoverySnapshotState``
- ``DirectoryDiscoveryCaching``
- ``DirectorySnapshotStoring``
- ``FileDirectorySnapshotStore``
- ``UnavailableDirectoryDiscoveryCache``

### Networking

- ``HTTPTransporting``
- ``URLSessionHTTPTransport``
- ``HTTPTransportError``

### Geographic Filtering

- ``RadioBrowserGeoFilter``
- ``RadioBrowserGeoFilterProviding``
- ``MutableRadioBrowserGeoFilterProvider``

### Deep Links and Reporting

- ``StationLink``
- ``StationPlayReporting``

### Test and Preview Support

Fixtures, not production types. They ship in the release library today; prefer injecting your
own doubles where you can.

- ``PreviewRadioDirectory``
