import SwiftUI
import LibvirtSwift

/// QoS / Bandwidth configuration tab: inbound and outbound limits.
public struct QoSTab: View {
    @Binding var config: NetworkConfig

    public init(config: Binding<NetworkConfig>) {
        self._config = config
    }

    public var body: some View {
        Form {
            Section("Inbound Bandwidth") {
                if let inbound = config.bandwidth?.inbound {
                    LabeledContent("Current", value: inbound.displayString)
                        .foregroundStyle(.secondary)
                }
                TextField("Average (KB/s)", text: inboundAvgBinding)
                    .help("Required. Average bandwidth in KB/s.")
                TextField("Peak (KB/s)", text: inboundPeakBinding)
                    .help("Optional. Maximum burst rate in KB/s.")
                TextField("Burst (KB)", text: inboundBurstBinding)
                    .help("Optional. Burst size in KB.")

                if config.bandwidth?.inbound != nil {
                    Button("Clear Inbound Limit") {
                        var bw = config.bandwidth ?? BandwidthConfig()
                        bw.inbound = nil
                        config.bandwidth = bw.isEmpty ? nil : bw
                    }
                }
            }

            Section("Outbound Bandwidth") {
                if let outbound = config.bandwidth?.outbound {
                    LabeledContent("Current", value: outbound.displayString)
                        .foregroundStyle(.secondary)
                }
                TextField("Average (KB/s)", text: outboundAvgBinding)
                    .help("Required. Average bandwidth in KB/s.")
                TextField("Peak (KB/s)", text: outboundPeakBinding)
                    .help("Optional. Maximum burst rate in KB/s.")
                TextField("Burst (KB)", text: outboundBurstBinding)
                    .help("Optional. Burst size in KB.")

                if config.bandwidth?.outbound != nil {
                    Button("Clear Outbound Limit") {
                        var bw = config.bandwidth ?? BandwidthConfig()
                        bw.outbound = nil
                        config.bandwidth = bw.isEmpty ? nil : bw
                    }
                }
            }

            if config.bandwidth != nil {
                Section {
                    Button("Remove All Bandwidth Limits", role: .destructive) {
                        config.bandwidth = nil
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Inbound Bindings

    private var inboundAvgBinding: Binding<String> {
        Binding(
            get: { config.bandwidth?.inbound?.average.description ?? "" },
            set: { applyInbound(average: UInt64($0), peak: config.bandwidth?.inbound?.peak, burst: config.bandwidth?.inbound?.burst) }
        )
    }

    private var inboundPeakBinding: Binding<String> {
        Binding(
            get: { config.bandwidth?.inbound?.peak?.description ?? "" },
            set: { applyInbound(average: config.bandwidth?.inbound?.average, peak: UInt64($0), burst: config.bandwidth?.inbound?.burst) }
        )
    }

    private var inboundBurstBinding: Binding<String> {
        Binding(
            get: { config.bandwidth?.inbound?.burst?.description ?? "" },
            set: { applyInbound(average: config.bandwidth?.inbound?.average, peak: config.bandwidth?.inbound?.peak, burst: UInt64($0)) }
        )
    }

    private func applyInbound(average: UInt64?, peak: UInt64?, burst: UInt64?) {
        var bw = config.bandwidth ?? BandwidthConfig()
        if let avg = average, avg > 0 {
            bw.inbound = BandwidthLimit(average: avg, peak: peak, burst: burst)
        } else {
            bw.inbound = nil
        }
        config.bandwidth = bw.isEmpty ? nil : bw
    }

    // MARK: - Outbound Bindings

    private var outboundAvgBinding: Binding<String> {
        Binding(
            get: { config.bandwidth?.outbound?.average.description ?? "" },
            set: { applyOutbound(average: UInt64($0), peak: config.bandwidth?.outbound?.peak, burst: config.bandwidth?.outbound?.burst) }
        )
    }

    private var outboundPeakBinding: Binding<String> {
        Binding(
            get: { config.bandwidth?.outbound?.peak?.description ?? "" },
            set: { applyOutbound(average: config.bandwidth?.outbound?.average, peak: UInt64($0), burst: config.bandwidth?.outbound?.burst) }
        )
    }

    private var outboundBurstBinding: Binding<String> {
        Binding(
            get: { config.bandwidth?.outbound?.burst?.description ?? "" },
            set: { applyOutbound(average: config.bandwidth?.outbound?.average, peak: config.bandwidth?.outbound?.peak, burst: UInt64($0)) }
        )
    }

    private func applyOutbound(average: UInt64?, peak: UInt64?, burst: UInt64?) {
        var bw = config.bandwidth ?? BandwidthConfig()
        if let avg = average, avg > 0 {
            bw.outbound = BandwidthLimit(average: avg, peak: peak, burst: burst)
        } else {
            bw.outbound = nil
        }
        config.bandwidth = bw.isEmpty ? nil : bw
    }
}
