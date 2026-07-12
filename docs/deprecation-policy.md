# Deprecation Policy

## Rules

1. Additive contracts may ship without a deprecation window when existing valid documents and target behavior continue to pass.
2. A renamed or removed profile, pack, adapter, field, script parameter, or persisted path requires a change declaration and compatibility note.
3. Persisted manifest or loop-state changes require an explicit migration disposition and executable positive/negative fixtures.
4. Readers support at least the documented compatibility range; unsupported future versions fail before writes.
5. Compatibility flags must be explicit, narrowly named, documented, and removable only through a later declaration.
6. Breaking changes require a new ADR or a superseding ADR, changelog entry, migration instructions, and a major version decision.

## Lifecycle

- **Announce:** document the replacement and warning surface.
- **Dual support:** retain the old reader or explicit compatibility mode where preservation is feasible.
- **Remove:** update schemas, migrations, tests, compatibility matrix, ADR disposition, and release notes together.

No target content is rewritten merely to silence a deprecation warning.
