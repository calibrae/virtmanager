import SwiftUI
import LibvirtSwift

/// Port forwarding rules tab. Only meaningful for NAT-mode networks.
public struct PortForwardingTab: View {
    @Binding var config: NetworkConfig
    @State private var ruleToRemove: PortForwardRule?

    public init(config: Binding<NetworkConfig>) {
        self._config = config
    }

    public var body: some View {
        VStack(spacing: 0) {
            if config.forward.mode != .nat {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Port forwarding is only available for NAT networks.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                List {
                    ForEach(Array(config.portForwarding.rules.enumerated()), id: \.element.id) { ruleIndex, rule in
                        ruleSection(rule: rule, ruleIndex: ruleIndex)
                    }

                    if config.portForwarding.rules.isEmpty {
                        Text("No port forwarding rules configured.")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }
                }

                Divider()

                HStack {
                    Button("Add TCP Rule") { addRule(proto: "tcp") }
                    Button("Add UDP Rule") { addRule(proto: "udp") }
                    Spacer()
                    Text("\(config.portForwarding.rules.count) rule(s)")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                .padding(8)
            }
        }
        .alert("Remove Rule", isPresented: .init(
            get: { ruleToRemove != nil },
            set: { if !$0 { ruleToRemove = nil } }
        )) {
            Button("Cancel", role: .cancel) { ruleToRemove = nil }
            Button("Remove", role: .destructive) {
                if let rule = ruleToRemove {
                    var pf = config.portForwarding
                    pf.rules.removeAll { $0.id == rule.id }
                    config.portForwarding = pf
                    ruleToRemove = nil
                }
            }
        } message: {
            Text("Remove this port forwarding rule?")
        }
    }

    // MARK: - Rule Section

    @ViewBuilder
    private func ruleSection(rule: PortForwardRule, ruleIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "arrow.right.arrow.left.square")
                Text(rule.proto.uppercased())
                    .fontWeight(.medium)
                if let addr = rule.address, !addr.isEmpty {
                    Text("on \(addr)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive) {
                    ruleToRemove = rule
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            ForEach(Array(rule.ranges.enumerated()), id: \.element.id) { rangeIndex, _ in
                HStack(spacing: 8) {
                    TextField("Host Port", text: rangeStartBinding(ruleIndex, rangeIndex))
                        .frame(width: 80)
                    Text("-")
                    TextField("End", text: rangeEndBinding(ruleIndex, rangeIndex))
                        .frame(width: 80)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                    TextField("Guest Addr", text: rangeToAddrBinding(ruleIndex, rangeIndex))
                        .frame(width: 120)
                    TextField("Guest Port", text: rangeToBinding(ruleIndex, rangeIndex))
                        .frame(width: 80)
                    Button(role: .destructive) {
                        removeRange(ruleIndex: ruleIndex, rangeIndex: rangeIndex)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
                .font(.callout)
            }

            Button("Add Port Range") {
                addRange(ruleIndex: ruleIndex)
            }
            .font(.callout)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func addRule(proto: String) {
        var pf = config.portForwarding
        pf.rules.append(PortForwardRule(proto: proto, ranges: [PortForwardRange()]))
        config.portForwarding = pf
    }

    private func addRange(ruleIndex: Int) {
        var pf = config.portForwarding
        pf.rules[ruleIndex].ranges.append(PortForwardRange())
        config.portForwarding = pf
    }

    private func removeRange(ruleIndex: Int, rangeIndex: Int) {
        var pf = config.portForwarding
        pf.rules[ruleIndex].ranges.remove(at: rangeIndex)
        config.portForwarding = pf
    }

    // MARK: - Range Bindings

    private func rangeStartBinding(_ ri: Int, _ idx: Int) -> Binding<String> {
        Binding(
            get: { config.portForwarding.rules[safe: ri]?.ranges[safe: idx].map { String($0.start) } ?? "" },
            set: {
                var pf = config.portForwarding
                pf.rules[ri].ranges[idx].start = UInt16($0) ?? 0
                config.portForwarding = pf
            }
        )
    }

    private func rangeEndBinding(_ ri: Int, _ idx: Int) -> Binding<String> {
        Binding(
            get: { config.portForwarding.rules[safe: ri]?.ranges[safe: idx]?.end.map { String($0) } ?? "" },
            set: {
                var pf = config.portForwarding
                pf.rules[ri].ranges[idx].end = UInt16($0)
                config.portForwarding = pf
            }
        )
    }

    private func rangeToBinding(_ ri: Int, _ idx: Int) -> Binding<String> {
        Binding(
            get: { config.portForwarding.rules[safe: ri]?.ranges[safe: idx]?.to.map { String($0) } ?? "" },
            set: {
                var pf = config.portForwarding
                pf.rules[ri].ranges[idx].to = UInt16($0)
                config.portForwarding = pf
            }
        )
    }

    private func rangeToAddrBinding(_ ri: Int, _ idx: Int) -> Binding<String> {
        Binding(
            get: { config.portForwarding.rules[safe: ri]?.ranges[safe: idx]?.toAddr ?? "" },
            set: {
                var pf = config.portForwarding
                pf.rules[ri].ranges[idx].toAddr = $0.isEmpty ? nil : $0
                config.portForwarding = pf
            }
        )
    }
}
