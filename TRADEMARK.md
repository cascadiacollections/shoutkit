# Trademark and branding policy

The source code in this repository is free software (see [LICENSE](LICENSE) and the
per-package `LICENSE` files). This policy covers what the code licenses do
**not** grant: the project's identity.

The repo uses two names for two different things: **"ShoutKit"** names the reusable library
layer (`Packages/`) — the SDK, its packages, and their public symbols. **"Holmdel"** names the
distributed app built from that SDK (the `HolmdelApp` target and everything a user installs from
the App Store or TestFlight). The policy below applies to both, separately.

## What is reserved

- The name **"Holmdel"** as the name of an app or distributed product
- The name **"ShoutKit"** as the name of an app or distributed product (distinct from its free
  use as a library/SDK name — see below)
- The Holmdel app icon, the ShoutKit wordmark, and any other project logos

These remain the property of Kevin T. Coughlin and may not be used to name,
brand, or market a fork or derived product without written permission.

## What you can do freely

- Fork, modify, build, and redistribute the code under its licenses —
  **under a different app name and icon**
- Use the names "ShoutKit" and "Holmdel" nominatively: to refer to this project, in articles,
  package dependencies, compatibility notes ("built on ShoutKit", "works with Holmdel"), and
  attribution
- Depend on the `ShoutKit`-branded MIT packages under their own package/module names in your own
  project — that is exactly what they're for

## Why

This is the standard FOSS arrangement (used by Firefox, VLC, and many others):
the code is free, the identity is not. It protects users from confusing or
misleading clones — including repackaged copies sold on app stores — without
restricting any freedom the licenses grant.

## Third-party names

SHOUTcast is a trademark of its respective owner; Radio-Browser and station
names (e.g. KEXP) belong to their operators. Holmdel references them
nominatively as data sources and directory entries and is not affiliated with
or endorsed by any of them.
