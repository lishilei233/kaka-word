# Repository Guidelines

## Project Structure & Module Organization

- `ios/` contains the SwiftUI app and Xcode project: features in `ios/Features/`, shared components in `ios/App/`, and models/services in `ios/Core/`.
- `ios/PictureWordTests/` contains the iOS unit tests.
- `server/` contains the Node.js + Hono API. Routes are in `server/src/routes/`, business logic in `server/src/core/`, and migrations in `server/migrations/`.
- `ios/Assets.xcassets/` stores app images and icons. Read `docs/UI_GUIDELINES.md` before changing or adding user-facing UI.

## Build, Test, and Development Commands

From `server/`:

```bash
npm install                 # Install dependencies
npm run dev                 # Start the API with watch mode
npm run build               # Type-check and compile TypeScript
npm test                    # Run the Node test suite
npm run db:migrate          # Apply database migrations
```

For iOS, open `ios/PictureWord.xcodeproj` in Xcode and run the `PictureWord` scheme on an iPhone Simulator. Command-line checks include:

```bash
xcodebuild test -project ios/PictureWord.xcodeproj -scheme PictureWord -destination 'platform=iOS Simulator,name=<available device>'
git diff --check
```

## Coding Style & Naming Conventions

Use four-space indentation and small feature-focused SwiftUI views. Types use `UpperCamelCase`; properties, methods, and tests use `lowerCamelCase`. Prefer existing theme colors, buttons, headers, sheets, and modifiers. Keep server code typed TypeScript with `camelCase` values and clear route boundaries. No formatter or linter is configured; format touched code consistently.

## Testing Guidelines

Name Swift tests for the behavior under test, for example `WordLearningStoreTests`, and keep them beside the relevant feature. Run iOS unit tests and `npm test` for cross-stack changes. Check UI changes on small/large screens, Dynamic Type, VoiceOver, Reduce Motion, and empty/error states.

## Commit & Pull Request Guidelines

Use short, imperative English commit subjects such as `Optimize listening practice layout and navigation`. Keep commits focused. Pull requests should describe the user-visible change, affected areas, related TODO/issue, screenshots or a recording for UI changes, commands run, and environment limitations. Update `TODO.md` for TODO-driven work.

## Security & Configuration Tips

Never commit `.env` files, API keys, Apple credentials, private keys, or production database URLs. Use `server/.env.example` and Mock settings locally. Treat images and subscription identifiers as sensitive.

## Agent-Specific Instructions

For ordinary inner pages, use the root `NavigationStack` with `NavigationLink`/`navigationDestination`, a safe-area-inset header, and `InteractivePopGestureEnabler` for the follow-along back gesture. Reserve `fullScreenCover` for camera, recognition, and immersive results; use `sheet` for details/editing. Do not replace normal navigation with a custom edge-swipe gesture.
