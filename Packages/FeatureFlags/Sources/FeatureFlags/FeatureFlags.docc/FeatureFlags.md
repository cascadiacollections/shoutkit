# ``FeatureFlags``

Gate work in progress behind a named, overridable flag.

## Overview

A ``Feature`` is a value: a stable ``Feature/key``, display text, a ``FeatureStage``, and a
default. A ``FeatureFlagProviding`` resolves one to a `Bool`.

```swift
let flags = DefaultsFeatureFlagService(features: MyFlags.all)
if flags.isEnabled(MyFlags.newBrowseSurface) {
    // ...
}
```

### Resolution order

``DefaultsFeatureFlagService`` resolves in one step: a stored ``FeatureOverride`` of `.enabled`
or `.disabled` wins outright, and `.useDefault` — the absence of an override — falls through to
``Feature/defaultEnabled``. Overrides persist in `UserDefaults` under
`featureFlags.<key>.override`, so they survive relaunch and can be inspected with
`defaults read`.

### Registration is required

The service resolves against the feature list handed to its initializer. A ``Feature`` whose key
is not in that list is inert: ``DefaultsFeatureFlagService/setOverride(_:for:)`` does nothing,
``DefaultsFeatureFlagService/override(for:)`` always reports `.useDefault`, and a debug toggle
bound to it will appear to work and change nothing. Pass every flag you intend to use.

### Identity

``Feature`` synthesizes `Hashable` across all its stored properties, but every lookup keys on
``Feature/key`` alone. Two `Feature` values that differ only in their title or default are
therefore unequal while sharing one stored override. Treat `key` as the identity and construct
each flag exactly once.

### The default catalog is ShoutKit's

``FeatureCatalog`` holds this app's flags, and it is the default argument for
``DefaultsFeatureFlagService``'s `features:` parameter. Adopters should pass their own list
rather than inheriting it.

## Topics

### Declaring Flags

- ``Feature``
- ``FeatureStage``
- ``FeatureCatalog``

### Resolving Flags

- ``FeatureFlagProviding``
- ``DefaultsFeatureFlagService``
- ``FeatureOverride``
