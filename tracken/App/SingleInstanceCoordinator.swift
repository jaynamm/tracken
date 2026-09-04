//
//  SingleInstanceCoordinator.swift
//  tracken
//

import AppKit
import Darwin

/// Cleans up stale debug builds that can otherwise leave duplicate menu items.
final class SingleInstanceCoordinator {
    func terminatePreviousInstances() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let previousInstances = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != currentPID }

        for instance in previousInstances {
            terminate(instance)
        }
    }

    private func terminate(_ application: NSRunningApplication) {
        application.forceTerminate()

        let pid = application.processIdentifier
        let debuggerPID = debuggerParentPID(of: pid)
        kill(pid, SIGTERM)

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            guard kill(pid, 0) == 0 else { return }
            kill(pid, SIGKILL)

            // A process being traced cannot always receive the signal until
            // LLDB detaches. Never signal a parent that is not debugserver.
            if let debuggerPID {
                kill(debuggerPID, SIGTERM)
            }
        }
    }

    private func debuggerParentPID(of pid: pid_t) -> pid_t? {
        var processInfo = proc_bsdinfo()
        let infoSize = Int32(MemoryLayout<proc_bsdinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &processInfo, infoSize) == infoSize else {
            return nil
        }

        let parentPID = pid_t(processInfo.pbi_ppid)
        var name = [CChar](repeating: 0, count: Int(MAXCOMLEN * 2))
        guard proc_name(parentPID, &name, UInt32(name.count)) > 0 else { return nil }
        return String(cString: name) == "debugserver" ? parentPID : nil
    }
}
