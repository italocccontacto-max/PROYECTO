# IRROVICAS architecture baseline

## Boundaries

### SYSTEM
Owns:
- Principles
- Identity / Antiidentity
- Direction / Plan
- Decisions / Protocols / Execution intent
- Archive / Knowledge

Must not directly invoke Android enforcement APIs.

### BLOCKADE
Owns:
- App/site/content blocking
- Usage and opening limits
- Schedules and conditions
- Quick Block / Pomodoro
- Allowlist
- Strict Mode
- Device enforcement services
- Local enforcement statistics

The privileged Android surface is isolated here.

### METRICS
Owns:
- Observation
- Compliance events
- Evidence
- Trends
- Daily/weekly reporting
- Dashboards for authorized viewers

METRICS consumes events/data through explicit contracts and does not directly mutate BLOCKADE policy state.

## Communication rule

Cross-app communication should use explicit contracts only. Do not share another app's private database, preferences, files, or implementation classes.

Recommended future contracts:
1. Explicit intents / deep links for user-directed actions.
2. Versioned event envelopes for telemetry.
3. Firebase Realtime Database / Functions for authorized remote synchronization.
4. Firebase Cloud Messaging for event-driven notifications.
5. Storage for evidence/report artifacts where remote retention is explicitly enabled.

## Data ownership

- SYSTEM: Room/DataStore for personal intent and configuration.
- BLOCKADE: Room/DataStore for policies, schedules, enforcement state and local statistics.
- METRICS: Room/DataStore for local projections; Firebase for authorized remote reporting when configured.

No raw personal data should leave the device unless a feature explicitly requires remote supervision and authorization is established.
