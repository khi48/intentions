# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Intent** is an iOS app designed to promote mindful phone usage by blocking all apps by default. When users unlock their phone, they must explicitly state their intention (which apps they need and for how long) to gain access to specific apps. This creates friction that encourages intentional app usage rather than mindless scrolling.

### Core Concept & Workflow
1. **Default State**: All apps are blocked using Apple's Screen Time API
2. **Unlock Trigger**: Phone unlock displays a full-screen intention prompt
3. **Intention Selection**: User selects specific apps/groups and time duration via UI (no natural language parsing)
4. **Temporary Access**: Selected apps unlock for the specified time period
5. **Auto-Relock**: Apps automatically relock when the session expires

### Development Status
This project is currently **incomplete** but follows a structured 30-task development plan. The existing code represents the foundation layer with core models, services, and basic UI components implemented.

## Development Notes

When working on this project, remember:
- Always test Family Controls functionality on a physical device
- Use the mock services for development and testing when Screen Time APIs aren't available
- Follow the task-based development structure to maintain architectural consistency
- Reference the master context document for complete technical specifications
- Maintain `Sendable` compliance for all new types in Swift 6
- This project uses **folder-based structure** (Xcode 16+) — new files created on disk are automatically discovered by Xcode. No manual adding required.
- Always try build after code changes to confirm code is still viable
- See [[cross-project/ios-development|iOS Development]] in the vault for full iOS dev guidelines
- **Simulator management**: Only the main conversation thread should run simulator builds/tests. Subagents must NEVER launch simulators (`xcodebuild test`, `xcodebuildmcp simulator build-and-run`, etc.) — multiple concurrent simulators overwhelm the machine. Subagents should use `xcodebuild build` (compile-only) or `xcodebuild build-for-testing` instead.
- Avoid running multiple sequential simulator builds in quick succession — give the system time to release resources between runs

[Rest of the file remains unchanged...]
# Project Notes

For project context, notes, and decisions, see .project-notes/
