import Testing
import CLibvirt
import Darwin
import Foundation
import LibvirtSwift
import VirtManagerCore

@Suite("Jolyne Integration Tests", .serialized)
struct JolyneConnectionTests {
    let uri = "qemu+ssh://cali@jolyne/system"

    @Test("Connect and list VMs using raw C API within Swift Testing")
    func rawCAPIInSwiftTesting() throws {
        virInitialize()
        guard let conn = virConnectOpen(uri) else {
            Issue.record("Failed to connect")
            return
        }

        var domainsPtr: UnsafeMutablePointer<virDomainPtr?>?
        let count = virConnectListAllDomains(conn, &domainsPtr, 0)
        #expect(count >= 4)

        var vmNames: [String] = []
        if count > 0, let domains = domainsPtr {
            for i in 0..<Int(count) {
                if let d = domains[i] {
                    if let namePtr = virDomainGetName(d) {
                        let name = String(cString: namePtr)
                        vmNames.append(name)

                        var info = virDomainInfo()
                        virDomainGetInfo(d, &info)
                        #expect(info.nrVirtCpu > 0)
                        #expect(info.memory > 0)

                        // Parse XML for graphics
                        if let xmlPtr = virDomainGetXMLDesc(d, 0) {
                            let xml = String(cString: xmlPtr)
                            free(xmlPtr)
                            let gfx = XMLHelpers.extractGraphicsType(from: xml)
                            let serial = XMLHelpers.hasSerialConsole(in: xml)

                            if name == "opnsense" {
                                #expect(VMDomainInfo.stateFromLibvirt(Int32(info.state)) == .running)
                                #expect(gfx == "vnc")
                                #expect(serial)
                            }
                            if name == "fedora-workstation" {
                                #expect(VMDomainInfo.stateFromLibvirt(Int32(info.state)) == .shutOff)
                                #expect(gfx == "spice")
                            }
                            if name == "hass.calii.lan" {
                                #expect(VMDomainInfo.stateFromLibvirt(Int32(info.state)) == .running)
                                #expect(serial)
                            }
                        }
                    }
                    virDomainFree(d)
                }
            }
            free(domains)
        }

        #expect(vmNames.contains("opnsense"))
        #expect(vmNames.contains("hass.calii.lan"))
        #expect(vmNames.contains("PROD-Brokers-41"))
        #expect(vmNames.contains("unifi-new"))
        #expect(vmNames.contains("fedora-workstation"))

        // Test VMState properties
        #expect(VMInfo.VMState.running.canShutdown)
        #expect(VMInfo.VMState.running.canOpenConsole)
        #expect(!VMInfo.VMState.running.canStart)
        #expect(VMInfo.VMState.shutOff.canStart)
        #expect(!VMInfo.VMState.shutOff.canShutdown)

        virConnectClose(conn)
    }
}
