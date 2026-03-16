import SwiftUI
import VirtManagerCore

/// Multi-step wizard for creating a new virtual machine.
public struct VMCreationWizard: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var state = VMCreationState()
    @State private var currentStep = 0
    @State private var isCreating = false
    @State private var creationError: String?
    @State private var uploadProgress: Double?

    public let connectionID: UUID

    private let stepCount = 6
    private let stepTitles = [
        "Name & OS",
        "CPU & Memory",
        "Storage",
        "Network",
        "Installation",
        "Review",
    ]

    public init(connectionID: UUID) {
        self.connectionID = connectionID
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header with step indicator
            headerView

            Divider()

            // Step content
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Navigation buttons
            footerView
        }
        .frame(width: 600, height: 520)
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 8) {
            Text("New Virtual Machine")
                .font(.headline)

            HStack(spacing: 4) {
                ForEach(0..<stepCount, id: \.self) { step in
                    Circle()
                        .fill(step == currentStep ? Color.accentColor : (step < currentStep ? Color.green : Color.secondary.opacity(0.3)))
                        .frame(width: 8, height: 8)

                    if step < stepCount - 1 {
                        Rectangle()
                            .fill(step < currentStep ? Color.green : Color.secondary.opacity(0.3))
                            .frame(height: 2)
                            .frame(maxWidth: 30)
                    }
                }
            }

            Text("Step \(currentStep + 1) of \(stepCount): \(stepTitles[currentStep])")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case 0:
            WizardStep1NameOS(state: state)
        case 1:
            WizardStep2CPUMemory(state: state)
        case 2:
            WizardStep3Storage(state: state, connectionID: connectionID)
        case 3:
            WizardStep4Network(state: state)
        case 4:
            WizardStep5Install(state: state, connectionID: connectionID)
        case 5:
            WizardStep6Review(state: state)
        default:
            Text("Unknown step")
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
                    .frame(maxWidth: 300, alignment: .leading)
            }

            if let progress = uploadProgress {
                VStack(alignment: .leading, spacing: 2) {
                    ProgressView(value: progress)
                        .frame(width: 120)
                    Text("Uploading ISO...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Cancel") {
                appState.cancelUpload(connectionID: connectionID)
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            if currentStep > 0 {
                Button("Back") {
                    currentStep -= 1
                }
            }

            if currentStep < stepCount - 1 {
                Button("Next") {
                    currentStep += 1
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAdvance)
            } else {
                Button("Create") {
                    createVM()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canCreate || isCreating)
            }
        }
        .padding()
    }

    // MARK: - Validation

    private var canAdvance: Bool {
        switch currentStep {
        case 0: return !state.name.isEmpty
        default: return true
        }
    }

    private var canCreate: Bool {
        guard !state.name.isEmpty else { return false }
        if !state.createNewDisk && state.existingVolumePath.isEmpty { return false }
        return true
    }

    // MARK: - Create

    private func createVM() {
        isCreating = true
        creationError = nil
        uploadProgress = nil

        Task {
            do {
                try await appState.createVM(
                    state: state,
                    connectionID: connectionID,
                    onUploadProgress: { progress in
                        Task { @MainActor in
                            uploadProgress = progress
                        }
                    }
                )
                isCreating = false
                dismiss()
            } catch {
                isCreating = false
                creationError = error.localizedDescription
            }
        }
    }
}
