# @ff/config Essentials (Node Services)

## Core concepts

- **Schema per key**: each config entry has `value`, `schema`, `mod`, and optional metadata.
- **Access modes**:
  - `LOCK`: env-only, not remote-updatable
  - `READ`: readable in runtime
  - `WRITE`: allows runtime updates via remote config

## Basic module setup

```ts
RemoteConfigModule.forRoot({
  config: {
    ...APP,
    ...REDIS,
    FEATURE_FLAG_NEW_UI: {
      value: false,
      schema: Joi.boolean().required(),
      mod: READ | WRITE,
    },
  },
})
```

## DIConfig usage

```ts
constructor(@Inject(DIConfig) private readonly config: Config) {}

const name = this.config.NAME;
const port = this.config.PORT;
```

`Config` is the exported type from the service's `src/config.ts`:

```ts
import { Config } from 'src/config';
```

## Env integration

- Env vars seed initial config values.
- Joi schemas validate env values.
- Updates can be applied remotely for READ/WRITE keys and observed at runtime.

## Reactive updates (onChange)

```ts
this.config.onChange().subscribe((change) => {
  console.log(`Configuration ${change.key} changed to:`, change.value);
});

// Listen to specific configuration changes
this.config.onChangeValue('FEATURE_FLAG_NEW_UI').subscribe((change) => {
  this.handleUIFeatureToggle(change.value as boolean);
});
```

## When editing config

- Add missing defaults for new keys.
- Keep `LOCK` for secrets or values that must not be remote-updated.
- Avoid forcing env for dev-only seed data unless required for prod.

## Adding or modifying config keys

1. Update `src/config.ts`:
   - Add a new entry under `CONFIG`.
   - Set a sensible default `value`.
   - Provide a Joi `schema`.
   - Set the correct `mod` (READ/WRITE/LOCK).
2. Update types:
   - Ensure `export type Config = RemoteConfigServiceType<typeof CONFIG>;` remains accurate.
3. Wire into code:
   - Inject `Config` with `@Inject(DIConfig)`.
   - Use `this.config.<KEY>` (proxy access).
4. Document and seed:
   - Add env docs if needed.
   - Do not require env for dev-only seeds unless required for prod.
