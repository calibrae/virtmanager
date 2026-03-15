import os

public enum Log {
    public static let connection = Logger(subsystem: "com.virtmanager", category: "connection")
    public static let libvirt = Logger(subsystem: "com.virtmanager", category: "libvirt")
    public static let vnc = Logger(subsystem: "com.virtmanager", category: "vnc")
    public static let spice = Logger(subsystem: "com.virtmanager", category: "spice")
    public static let serial = Logger(subsystem: "com.virtmanager", category: "serial")
    public static let ui = Logger(subsystem: "com.virtmanager", category: "ui")
    public static let keychain = Logger(subsystem: "com.virtmanager", category: "keychain")
}
