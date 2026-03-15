import Foundation
import Testing
@testable import VirtManagerCore

@Suite("VMState Tests")
struct VMStateTests {

    @Test("Running state properties")
    func runningState() {
        let state = VMInfo.VMState.running
        #expect(state.isRunning == true)
        #expect(state.canStart == false)
        #expect(state.canShutdown == true)
        #expect(state.canForceOff == true)
        #expect(state.canPause == true)
        #expect(state.canResume == false)
        #expect(state.canReboot == true)
        #expect(state.canOpenConsole == true)
        #expect(state.displayName == "Running")
    }

    @Test("Shut off state properties")
    func shutOffState() {
        let state = VMInfo.VMState.shutOff
        #expect(state.isRunning == false)
        #expect(state.canStart == true)
        #expect(state.canShutdown == false)
        #expect(state.canForceOff == false)
        #expect(state.canPause == false)
        #expect(state.canResume == false)
        #expect(state.canReboot == false)
        #expect(state.canOpenConsole == false)
    }

    @Test("Paused state properties")
    func pausedState() {
        let state = VMInfo.VMState.paused
        #expect(state.isRunning == false)
        #expect(state.canStart == false)
        #expect(state.canShutdown == false)
        #expect(state.canForceOff == true)
        #expect(state.canPause == false)
        #expect(state.canResume == true)
        #expect(state.canReboot == false)
    }

    @Test("Crashed state properties")
    func crashedState() {
        let state = VMInfo.VMState.crashed
        #expect(state.canStart == true)
        #expect(state.canForceOff == true)
        #expect(state.canShutdown == false)
    }

    @Test("Suspended state properties")
    func suspendedState() {
        let state = VMInfo.VMState.suspended
        #expect(state.canResume == true)
        #expect(state.canForceOff == true)
        #expect(state.canStart == false)
    }

    @Test("All states have display names")
    func allStatesHaveDisplayNames() {
        for state in VMInfo.VMState.allCases {
            #expect(!state.displayName.isEmpty)
        }
    }

    @Test("All states have SF symbols")
    func allStatesHaveSFSymbols() {
        for state in VMInfo.VMState.allCases {
            #expect(!state.sfSymbol.isEmpty)
        }
    }
}
