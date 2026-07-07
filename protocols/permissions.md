# Permissions Protocol

Humans own this file in target projects. Agents may propose changes but should not silently modify it.

## Always allowed

- Read project files.
- Run read-only inspection commands.
- Run tests and type checks.
- Create or update target-local `.agent/memory/working` notes.

## Requires explicit approval

- Push to a remote repository.
- Deploy to staging or production.
- Run remote database migrations.
- Install, remove, or upgrade dependencies.
- Modify CI/CD configuration.
- Delete files outside generated scratch or working-memory paths.
- Change secrets, tokens, or remote service configuration.

## Never allowed

- Force push protected branches.
- Print or commit secrets.
- Store credentials in memory files.
- Bypass approval gates.
- Rewrite project history without explicit instruction.
- Treat financial, legal, medical, or security-sensitive output as verified without source checks.
