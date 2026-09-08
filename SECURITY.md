# Security Policy

## Supported Versions

Holmdel is pre-1.0 and ships as TestFlight betas (see `docs/releases/`). Only
the most recent release line receives security fixes.

## Reporting a Vulnerability

Please **do not** open a public GitHub issue for security vulnerabilities.

Instead, use
[GitHub's private vulnerability reporting](https://github.com/cascadiacollections/shoutkit/security/advisories/new)
for this repository, or email **kevin@cascadiacollections.com**. Include:

- A description of the issue and its potential impact
- Steps to reproduce (device/OS version, if relevant)
- Any relevant logs or crash traces (redact personal data)

We'll acknowledge reports within 5 business days and follow up with a fix
timeline once triaged.

## Scope

This policy covers the Holmdel app, its Swift packages under `Packages/`,
and CI/CD configuration in `.github/`. Third-party dependencies should be
reported upstream; see `THIRD_PARTY_LICENSES.md` for the list this project
consumes directly.
