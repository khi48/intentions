# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Intentions** is an iOS app designed to promote mindful phone usage by blocking all apps by default. When users unlock their phone, they must explicitly state their intention (which apps they need and for how long) to gain access to specific apps. This creates friction that encourages intentional app usage rather than mindless scrolling.

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
- **New files need to be added to the project manually. Once a new file and code is created, prompt me to add it to the project before trying to build or run unit tests**
- Always try build after code changes to confirm code is still viable

[Rest of the file remains unchanged...]