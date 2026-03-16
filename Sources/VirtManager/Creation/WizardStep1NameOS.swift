import SwiftUI
import VirtManagerCore

/// Wizard step 1: VM name, OS type, and OS variant selection.
public struct WizardStep1NameOS: View {
    @Bindable var state: VMCreationState

    private let osTypes = [
        ("linux", "Linux"),
        ("windows", "Windows"),
        ("bsd", "BSD"),
        ("other", "Other"),
    ]

    public init(state: VMCreationState) {
        self.state = state
    }

    public var body: some View {
        Form {
            Section("Virtual Machine Name") {
                TextField("Name", text: $state.name)
                    .textFieldStyle(.roundedBorder)
            }

            Section("Operating System") {
                Picker("OS Type", selection: $state.osType) {
                    ForEach(osTypes, id: \.0) { id, label in
                        Text(label).tag(id)
                    }
                }
                .onChange(of: state.osType) { _, _ in
                    // Reset variant when type changes
                    let variants = OSVariants.variants(forOSType: state.osType)
                    state.osVariant = variants.first?.id ?? ""
                    state.applyOSDefaults()
                }

                let variants = OSVariants.variants(forOSType: state.osType)
                if !variants.isEmpty {
                    Picker("OS Variant", selection: $state.osVariant) {
                        Text("Generic").tag("")
                        ForEach(variants, id: \.id) { id, label in
                            Text(label).tag(id)
                        }
                    }
                    .onChange(of: state.osVariant) { _, _ in
                        state.applyOSDefaults()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if state.osVariant.isEmpty {
                let variants = OSVariants.variants(forOSType: state.osType)
                state.osVariant = variants.first?.id ?? ""
            }
        }
    }
}
