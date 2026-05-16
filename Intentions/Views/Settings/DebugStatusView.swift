//
//  DebugStatusView.swift
//  Intentions
//
//  On-device diagnostic surface. Read-only view of the live shield-state
//  machine: the persisted `IntentLog`, the in-memory `ManagedSettingsStore`,
//  authorization state, registered DeviceActivity monitors, and the last
//  set of `DebugBreadcrumbs`. Intended for triaging "apps aren't shielding"
//  reports without an Xcode console attached.
//
//  Two mutating actions are exposed (clearly labelled): a "Reapply now"
//  button that invokes `ShieldEngine.mainApp().catchUpOnForeground()` and
//  re-snapshots, and a "Copy to clipboard" button so the user can paste
//  the snapshot into a GitHub issue.
//

import SwiftUI
import UIKit
@preconcurrency import FamilyControls
@preconcurrency import ManagedSettings
@preconcurrency import DeviceActivity

// MARK: - Snapshot

/// Point-in-time capture of every diagnostic value the debug view renders.
/// Built on `.task { ... }` and on demand from "Reapply now". Sendable so
/// it can be passed cleanly across actor hops if we ever capture off-main.
struct DebugStatusSnapshot: Sendable {
    let capturedAt: Date

    // IntentLog
    let activeSessionId: String?
    let activeSessionStartedAt: Date?
    let activeSessionEndsAt: Date?
    let activeSessionAppCount: Int
    let activeSessionDomainCount: Int
    let knownAppTokenCount: Int
    let knownDomainTokenCount: Int

    // ScheduleSnapshot in IntentLog
    let scheduleIsEnabled: Bool?
    let scheduleRoutineCount: Int?
    let scheduleTimeZone: String?
    let scheduleIsFreeTimeNow: Bool?
    let scheduleNextBoundary: Date?

    // Live compute
    let computeOutput: String

    // ManagedSettingsStore
    let storeApplications: String
    let storeApplicationCategories: String
    let storeWebDomains: String
    let storeWebDomainCategories: String
    let storeWebContentBlockedByFilter: String

    // Authorization
    let authorizationStatus: String

    // DeviceActivity
    let activeMonitors: [String]

    // Ring-buffer breadcrumb history (cap 100, chronological).
    /// Live ring as of capture.
    let historyDump: String
    /// Frozen ring snapshot taken once per process at `IntentApp.init()`,
    /// before any main-app reconcile begins overwriting the live ring.
    let frozenHistoryDump: String
}

extension DebugStatusSnapshot {
    /// Capture every diagnostic value. MainActor-only because the view is
    /// `@MainActor` and FamilyControls/ManagedSettings calls are routinely
    /// invoked from main isolation in this codebase.
    @MainActor
    static func capture() -> DebugStatusSnapshot {
        let now = Date()
        let store = IntentLogStore()
        let log = store.load()

        // IntentLog scalars
        let session = log.activeSession
        let activeId = session?.id.uuidString
        let appCount = session?.apps.applicationTokens.count ?? 0
        let domainCount = session?.apps.webDomainTokens.count ?? 0

        // Schedule snapshot
        let snapshot = log.weeklySchedule
        let isFreeTimeNow = snapshot.map { $0.isFreeTime(at: now) }
        let nextBoundary: Date? = {
            guard let snapshot else { return nil }
            return snapshot.nextBoundary(after: now)
        }()

        // Compute
        let configText = describeConfig(compute(log, at: now))

        // ManagedSettingsStore (live in-memory state)
        let mss = ManagedSettingsStore()
        let storeApps = describeAppsField(mss.shield.applications)
        let storeAppCats = String(describing: mss.shield.applicationCategories as Any)
        let storeWebDomains = describeWebDomainsField(mss.shield.webDomains)
        let storeWebDomainCats = String(describing: mss.shield.webDomainCategories as Any)
        let storeFilter = String(describing: mss.webContent.blockedByFilter as Any)

        // Authorization
        let authText = describeAuthStatus(AuthorizationCenter.shared.authorizationStatus)

        // DeviceActivity
        let monitors = DeviceActivityCenter().activities.map { $0.rawValue }.sorted()

        // Breadcrumbs (ring buffer)
        let history = DebugBreadcrumbs.dumpHistory()
        let frozenHistory = DebugBreadcrumbs.dumpFrozenHistory()

        return DebugStatusSnapshot(
            capturedAt: now,
            activeSessionId: activeId,
            activeSessionStartedAt: session?.startedAt,
            activeSessionEndsAt: session?.endsAt,
            activeSessionAppCount: appCount,
            activeSessionDomainCount: domainCount,
            knownAppTokenCount: log.knownApplicationTokens.count,
            knownDomainTokenCount: log.knownWebDomainTokens.count,
            scheduleIsEnabled: snapshot?.isEnabled,
            scheduleRoutineCount: snapshot?.routines.count,
            scheduleTimeZone: snapshot?.timeZoneIdentifier,
            scheduleIsFreeTimeNow: isFreeTimeNow,
            scheduleNextBoundary: nextBoundary,
            computeOutput: configText,
            storeApplications: storeApps,
            storeApplicationCategories: storeAppCats,
            storeWebDomains: storeWebDomains,
            storeWebDomainCategories: storeWebDomainCats,
            storeWebContentBlockedByFilter: storeFilter,
            authorizationStatus: authText,
            activeMonitors: monitors,
            historyDump: history,
            frozenHistoryDump: frozenHistory
        )
    }

    /// Plain-text dump for clipboard / GitHub paste. Mirrors the on-screen
    /// layout but trims SwiftUI styling.
    var clipboardText: String {
        var out: [String] = []
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        out.append("=== Intent Debug Status — \(f.string(from: capturedAt)) ===")
        out.append("")
        out.append("[IntentLog]")
        if let id = activeSessionId {
            out.append("  activeSession.id:            \(id)")
            out.append("  activeSession.startedAt:     \(activeSessionStartedAt.map { f.string(from: $0) } ?? "nil")")
            out.append("  activeSession.endsAt:        \(activeSessionEndsAt.map { f.string(from: $0) } ?? "nil")")
            out.append("  activeSession.apps:          \(activeSessionAppCount) tokens")
            out.append("  activeSession.webDomains:    \(activeSessionDomainCount) tokens")
        } else {
            out.append("  activeSession:               nil")
        }
        out.append("  knownApplicationTokens.count: \(knownAppTokenCount)")
        out.append("  knownWebDomainTokens.count:   \(knownDomainTokenCount)")
        out.append("")
        out.append("[Schedule snapshot]")
        if let isEnabled = scheduleIsEnabled {
            out.append("  isEnabled:                   \(isEnabled)")
            out.append("  routines.count:              \(scheduleRoutineCount ?? -1)")
            out.append("  timeZone:                    \(scheduleTimeZone ?? "nil")")
            out.append("  isFreeTime(now):             \(scheduleIsFreeTimeNow.map { String($0) } ?? "n/a")")
            out.append("  nextBoundary(after now):     \(scheduleNextBoundary.map { f.string(from: $0) } ?? "nil")")
        } else {
            out.append("  (no schedule snapshot in IntentLog)")
        }
        out.append("")
        out.append("[Live compute(log, at: now)]")
        out.append("  \(computeOutput)")
        out.append("")
        out.append("[ManagedSettingsStore]")
        out.append("  shield.applications:           \(storeApplications)")
        out.append("  shield.applicationCategories:  \(storeApplicationCategories)")
        out.append("  shield.webDomains:             \(storeWebDomains)")
        out.append("  shield.webDomainCategories:    \(storeWebDomainCategories)")
        out.append("  webContent.blockedByFilter:    \(storeWebContentBlockedByFilter)")
        out.append("")
        out.append("[FamilyControls.AuthorizationCenter]")
        out.append("  status: \(authorizationStatus)")
        out.append("")
        out.append("[DeviceActivityCenter.activities]")
        if activeMonitors.isEmpty {
            out.append("  (no active monitors)")
        } else {
            for name in activeMonitors {
                out.append("  - \(name)")
            }
        }
        out.append("")
        out.append("[DebugBreadcrumbs — frozen (pre-foreground)]")
        out.append(frozenHistoryDump)
        out.append("")
        out.append("[DebugBreadcrumbs — live (last 100)]")
        out.append(historyDump)
        return out.joined(separator: "\n")
    }
}

// MARK: - Pretty printers

private func describeConfig(_ config: ShieldConfig) -> String {
    switch config {
    case .none:
        return ".none — nothing shielded"
    case .all:
        return ".all — every app shielded"
    case .allExcept(let selection):
        return ".allExcept — \(selection.applicationTokens.count) app token(s), \(selection.webDomainTokens.count) web domain(s)"
    }
}

private func describeAppsField(_ value: Set<ApplicationToken>?) -> String {
    guard let value else { return "nil" }
    return ".specific(\(value.count))"
}

private func describeWebDomainsField(_ value: Set<WebDomainToken>?) -> String {
    guard let value else { return "nil" }
    return ".specific(\(value.count))"
}

private func describeAuthStatus(_ status: AuthorizationStatus) -> String {
    switch status {
    case .notDetermined: return "notDetermined"
    case .denied:        return "denied"
    case .approved:      return "approved"
    @unknown default:    return "unknown(\(status.rawValue))"
    }
}

// MARK: - View

struct DebugStatusView: View {
    @State private var snapshot: DebugStatusSnapshot?
    @State private var lastReapplyAt: Date?
    @State private var copyConfirmation: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let snapshot {
                    sections(for: snapshot)
                } else {
                    ProgressView("Capturing diagnostic…")
                        .foregroundColor(AppConstants.Colors.text)
                        .padding(.top, 60)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
        .background(AppConstants.Colors.background)
        .navigationTitle("Debug Status")
        .navigationBarTitleDisplayMode(.large)
        .task {
            snapshot = DebugStatusSnapshot.capture()
        }
    }

    @ViewBuilder
    private func sections(for snap: DebugStatusSnapshot) -> some View {
        capturedAtRow(snap)
        actionsSection(snap)

        SettingsSectionHeader(title: "IntentLog")
        intentLogSection(snap)

        SettingsSectionHeader(title: "Schedule Snapshot")
        scheduleSection(snap)

        SettingsSectionHeader(title: "Live compute(log, now)")
        SettingsStatusRow("Result", value: snap.computeOutput, valueColor: AppConstants.Colors.text)

        SettingsSectionHeader(title: "ManagedSettingsStore")
        managedSettingsSection(snap)

        SettingsSectionHeader(title: "Authorization")
        SettingsStatusRow(
            "AuthorizationCenter.shared.status",
            value: snap.authorizationStatus,
            valueColor: snap.authorizationStatus == "approved" ? AppConstants.Colors.positive : AppConstants.Colors.destructive
        )

        SettingsSectionHeader(title: "DeviceActivity Monitors")
        deviceActivitySection(snap)

        SettingsSectionHeader(title: "DebugBreadcrumbs — frozen (pre-foreground)")
        breadcrumbsSection(snap, dump: snap.frozenHistoryDump)

        SettingsSectionHeader(title: "DebugBreadcrumbs — live (last 100)")
        breadcrumbsSection(snap, dump: snap.historyDump)
    }

    // MARK: Header rows

    private func capturedAtRow(_ snap: DebugStatusSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Snapshot captured")
                .font(.caption)
                .foregroundColor(AppConstants.Colors.textSecondary)
            Text(formatted(snap.capturedAt))
                .font(.subheadline)
                .foregroundColor(AppConstants.Colors.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: Actions

    private func actionsSection(_ snap: DebugStatusSnapshot) -> some View {
        VStack(spacing: 12) {
            SettingsPrimaryButton(
                "Reapply Now (mutating)",
                systemImage: "arrow.triangle.2.circlepath"
            ) {
                let engine = ShieldEngine.mainApp()
                engine.catchUpOnForeground()
                lastReapplyAt = Date()
                snapshot = DebugStatusSnapshot.capture()
            }

            SettingsPrimaryButton(
                "Copy Diagnostic to Clipboard",
                systemImage: "doc.on.doc"
            ) {
                UIPasteboard.general.string = snap.clipboardText
                copyConfirmation = "Copied at \(formatted(Date()))"
            }

            if let lastReapplyAt {
                Text("Last reapply: \(formatted(lastReapplyAt))")
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let copyConfirmation {
                Text(copyConfirmation)
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.positive)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 12)
    }

    // MARK: IntentLog

    @ViewBuilder
    private func intentLogSection(_ snap: DebugStatusSnapshot) -> some View {
        if let id = snap.activeSessionId {
            SettingsStatusRow("activeSession.id", value: shortened(id))
            if let started = snap.activeSessionStartedAt {
                SettingsStatusRow("activeSession.startedAt", value: formatted(started))
            }
            if let ends = snap.activeSessionEndsAt {
                SettingsStatusRow("activeSession.endsAt", value: formatted(ends))
            }
            SettingsStatusRow("activeSession.apps", value: "\(snap.activeSessionAppCount) tokens")
            SettingsStatusRow("activeSession.webDomains", value: "\(snap.activeSessionDomainCount) tokens")
        } else {
            SettingsStatusRow("activeSession", value: "nil")
        }
        SettingsStatusRow("knownApplicationTokens.count", value: "\(snap.knownAppTokenCount)")
        SettingsStatusRow("knownWebDomainTokens.count", value: "\(snap.knownDomainTokenCount)")
    }

    // MARK: Schedule

    @ViewBuilder
    private func scheduleSection(_ snap: DebugStatusSnapshot) -> some View {
        if let isEnabled = snap.scheduleIsEnabled {
            SettingsStatusRow("isEnabled", value: "\(isEnabled)")
            SettingsStatusRow("routines.count", value: "\(snap.scheduleRoutineCount ?? -1)")
            SettingsStatusRow("timeZone", value: snap.scheduleTimeZone ?? "nil")
            if let isFree = snap.scheduleIsFreeTimeNow {
                SettingsStatusRow(
                    "isFreeTime(now)",
                    value: "\(isFree)",
                    valueColor: isFree ? AppConstants.Colors.positive : AppConstants.Colors.destructive
                )
            }
            SettingsStatusRow(
                "nextBoundary(after now)",
                value: snap.scheduleNextBoundary.map { formatted($0) } ?? "nil"
            )
        } else {
            SettingsStatusRow("schedule snapshot", value: "absent — pre-snapshot log")
        }
    }

    // MARK: ManagedSettingsStore

    @ViewBuilder
    private func managedSettingsSection(_ snap: DebugStatusSnapshot) -> some View {
        SettingsStatusRow("shield.applications", value: snap.storeApplications)
        SettingsStatusRow("shield.applicationCategories", value: snap.storeApplicationCategories)
        SettingsStatusRow("shield.webDomains", value: snap.storeWebDomains)
        SettingsStatusRow("shield.webDomainCategories", value: snap.storeWebDomainCategories)
        SettingsStatusRow("webContent.blockedByFilter", value: snap.storeWebContentBlockedByFilter)
    }

    // MARK: DeviceActivity

    @ViewBuilder
    private func deviceActivitySection(_ snap: DebugStatusSnapshot) -> some View {
        if snap.activeMonitors.isEmpty {
            SettingsStatusRow("activities", value: "(none)")
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(snap.activeMonitors.enumerated()), id: \.offset) { _, name in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundColor(AppConstants.Colors.positive)
                            .padding(.top, 6)
                        Text(name)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(AppConstants.Colors.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) { SettingsRowDivider() }
                }
            }
        }
    }

    // MARK: Breadcrumbs

    @ViewBuilder
    private func breadcrumbsSection(_ snap: DebugStatusSnapshot, dump: String) -> some View {
        let crumbs = lastNLines(dump, n: 50)
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: true) {
                Text(crumbs)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(AppConstants.Colors.text)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(minWidth: 0, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppConstants.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppConstants.Colors.textSecondary.opacity(0.15), lineWidth: 1)
        )
        .padding(.vertical, 8)
    }

    // MARK: Formatters

    private func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: date)
    }

    private func shortened(_ uuid: String) -> String {
        guard uuid.count > 13 else { return uuid }
        return String(uuid.prefix(8)) + "…" + String(uuid.suffix(4))
    }

    private func lastNLines(_ text: String, n: Int) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > n else { return text }
        return lines.suffix(n).joined(separator: "\n")
    }
}

#Preview {
    NavigationStack {
        DebugStatusView()
    }
    .preferredColorScheme(.dark)
}
