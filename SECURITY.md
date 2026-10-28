# Security policy

## Supported versions

Only the latest release receives fixes. StudyApp updates itself through Sparkle, so please update before reporting.

## Reporting a vulnerability

Please do **not** open a public issue. Report it privately through [GitHub security advisories](https://github.com/502Proxy/StudyApp/security/advisories/new) with steps to reproduce and the affected version. You will get an answer within a week.

Relevant areas are the Stud.IP sign-in (credentials and session in the keychain), backup archives (paths inside an archive are validated before extraction) and the update feed (DMGs are signed with EdDSA).
