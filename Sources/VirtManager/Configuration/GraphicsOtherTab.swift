import SwiftUI
import LibvirtSwift

public struct GraphicsOtherTab: View {
    @Binding var config: DomainConfig

    public init(config: Binding<DomainConfig>) {
        self._config = config
    }

    public var body: some View {
        Form {
            // MARK: - Graphics
            Section("Graphics") {
                if config.graphics.isEmpty {
                    Text("No graphics devices configured")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(config.graphics.enumerated()), id: \.element.id) { index, gfx in
                        HStack {
                            Picker("Type", selection: graphicsTypeBinding(index: index)) {
                                Text("VNC").tag("vnc")
                                Text("SPICE").tag("spice")
                            }
                            .frame(width: 200)
                            Spacer()
                            Button(role: .destructive) {
                                config.graphics.remove(at: index)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                Button("Add Graphics") {
                    config.graphics.append(GraphicsDevice(type: "vnc", autoport: true))
                }
            }

            // MARK: - Video
            Section("Video") {
                if config.videoDevices.isEmpty {
                    Text("No video devices configured")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(config.videoDevices.enumerated()), id: \.element.id) { index, video in
                        HStack {
                            Picker("Model", selection: videoModelBinding(index: index)) {
                                Text("Virtio").tag("virtio")
                                Text("QXL").tag("qxl")
                                Text("VGA").tag("vga")
                                Text("Cirrus").tag("cirrus")
                                Text("Bochs").tag("bochs")
                            }
                            .frame(width: 200)
                            Spacer()
                            Button(role: .destructive) {
                                config.videoDevices.remove(at: index)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                Button("Add Video Device") {
                    config.videoDevices.append(VideoDevice(modelType: "virtio"))
                }
            }

            // MARK: - Input Devices
            Section("Input Devices") {
                ForEach(Array(config.inputDevices.enumerated()), id: \.element.id) { index, input in
                    HStack {
                        Text("\(input.type)")
                        if let bus = input.bus {
                            Text("(\(bus))").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            config.inputDevices.remove(at: index)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Menu("Add Input Device") {
                    Button("USB Tablet") { config.inputDevices.append(InputDevice(type: "tablet", bus: "usb")) }
                    Button("USB Mouse") { config.inputDevices.append(InputDevice(type: "mouse", bus: "usb")) }
                    Button("USB Keyboard") { config.inputDevices.append(InputDevice(type: "keyboard", bus: "usb")) }
                    Button("Virtio Keyboard") { config.inputDevices.append(InputDevice(type: "keyboard", bus: "virtio")) }
                }
            }

            // MARK: - Sound Devices
            Section("Sound Devices") {
                ForEach(Array(config.soundDevices.enumerated()), id: \.element.id) { index, sound in
                    HStack {
                        Text(sound.model)
                        Spacer()
                        Button(role: .destructive) {
                            config.soundDevices.remove(at: index)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Menu("Add Sound Device") {
                    Button("ICH9") { config.soundDevices.append(SoundDevice(model: "ich9")) }
                    Button("ICH6") { config.soundDevices.append(SoundDevice(model: "ich6")) }
                    Button("AC97") { config.soundDevices.append(SoundDevice(model: "ac97")) }
                    Button("SB16") { config.soundDevices.append(SoundDevice(model: "sb16")) }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func graphicsTypeBinding(index: Int) -> Binding<String> {
        Binding(
            get: { config.graphics[index].type },
            set: { config.graphics[index].type = $0 }
        )
    }

    private func videoModelBinding(index: Int) -> Binding<String> {
        Binding(
            get: { config.videoDevices[index].modelType },
            set: { config.videoDevices[index].modelType = $0 }
        )
    }
}
