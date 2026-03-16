import SwiftUI
import LibvirtSwift

/// Multi-step wizard for creating a new virtual network.
public struct NetworkCreationWizard: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var state = NetworkWizardState()
    @State private var currentStepIndex = 0
    @State private var isCreating = false
    @State private var creationError: String?

    public let connectionID: UUID

    public init(connectionID: UUID) {
        self.connectionID = connectionID
    }

    private var steps: [WizardStepKind] { state.visibleSteps }
    private var stepCount: Int { steps.count }

    public var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footerView
        }
        .frame(width: 540, height: 460)
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 8) {
            Text("New Virtual Network")
                .font(.headline)

            HStack(spacing: 4) {
                ForEach(0..<stepCount, id: \.self) { index in
                    Circle()
                        .fill(stepDotColor(for: index))
                        .frame(width: 8, height: 8)
                    if index < stepCount - 1 {
                        Rectangle()
                            .fill(index < currentStepIndex ? Color.green : Color.secondary.opacity(0.3))
                            .frame(height: 2)
                            .frame(maxWidth: 30)
                    }
                }
            }

            Text("Step \(currentStepIndex + 1) of \(stepCount): \(steps[currentStepIndex].rawValue)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func stepDotColor(for index: Int) -> Color {
        if index == currentStepIndex { return .accentColor }
        if index < currentStepIndex { return .green }
        return .secondary.opacity(0.3)
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        switch steps[currentStepIndex] {
        case .nameMode:
            NetworkWizardStep1NameMode(state: state)
        case .ipv4:
            NetworkWizardStep2IPv4(state: state)
        case .ipv6:
            NetworkWizardStep3IPv6(state: state)
        case .dnsDhcp:
            NetworkWizardStep4DNSDHCP(state: state)
        case .review:
            NetworkWizardStep5Review(state: state)
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            if let error = creationError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .lineLimit(2)
                    .frame(maxWidth: 280, alignment: .leading)
            }

            Spacer()

            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)

            if currentStepIndex > 0 {
                Button("Back") { currentStepIndex -= 1 }
            }

            if currentStepIndex < stepCount - 1 {
                Button("Next") { currentStepIndex += 1 }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAdvance)
            } else {
                Button("Create") { createNetwork(start: false) }
                    .disabled(!canCreate || isCreating)

                Button("Create & Start") { createNetwork(start: true) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canCreate || isCreating)
            }
        }
        .padding()
    }

    // MARK: - Validation

    private var canAdvance: Bool {
        switch steps[currentStepIndex] {
        case .nameMode: return !state.name.isEmpty
        default: return true
        }
    }

    private var canCreate: Bool {
        !state.name.isEmpty
    }

    // MARK: - Create

    private func createNetwork(start: Bool) {
        isCreating = true
        creationError = nil

        Task {
            do {
                let xml = state.generateNetworkXML()
                try await appState.createNetwork(xml: xml, connectionID: connectionID)
                if start {
                    try? await appState.startNetwork(name: state.name, connectionID: connectionID)
                }
                isCreating = false
                dismiss()
            } catch {
                isCreating = false
                creationError = error.localizedDescription
            }
        }
    }
}
