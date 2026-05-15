# Intent

iOS app for mindful phone use. All apps blocked by default (Screen Time API). On phone unlock, user picks apps + duration → temporary access → auto-relock when session expires.

## Status

Pre-release. Reshield logic validated on iOS 26.5. Blocked on Apple Family Controls Distribution cap before TestFlight. See `.project-notes/overview.md` for current state.

## Development Notes

- Test Family Controls on physical device — Screen Time APIs unavailable in simulator
- Mock services exist for dev when APIs not reachable
- Maintain `Sendable` compliance (Swift 6)
- Folder-based Xcode 16+ structure — files on disk auto-discovered, no manual add
- Build after code changes to confirm viable
- Read iOS guidelines first: `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Mind/knowledge/ios-development.md` (sim management, Screen Time constraints, Swift 6 concurrency, ManagedSettingsStore, device deploy)
- **Subagents must NOT launch simulators** — only main thread. Subagents use `xcodebuild build` (compile-only) or `build-for-testing`. Multiple concurrent sims overwhelm machine.
- Avoid back-to-back simulator builds — let system release resources
