import CLibvirt
import Foundation
import VirtManagerCore

extension LibvirtConnection {

    /// Uploads a local file into a storage volume using a libvirt stream.
    /// - Parameters:
    ///   - poolName: The name of the storage pool containing the volume.
    ///   - volumeName: The name of the volume to upload into.
    ///   - fileURL: The local file URL to upload.
    ///   - onProgress: Called with a value from 0.0 to 1.0 indicating upload progress.
    public func uploadVolume(
        poolName: String,
        volumeName: String,
        fileURL: URL,
        onProgress: @escaping (Double) -> Void
    ) throws {
        try withConnection { conn in
            // Look up the pool
            guard let pool = virStoragePoolLookupByName(conn, poolName) else {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "uploadVolume/lookupPool", reason: err)
            }
            defer { virStoragePoolFree(pool) }

            // Look up the volume
            guard let vol = virStorageVolLookupByName(pool, volumeName) else {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "uploadVolume/lookupVol", reason: err)
            }
            defer { virStorageVolFree(vol) }

            // Get file size
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            guard let fileSize = fileAttributes[.size] as? UInt64 else {
                throw LibvirtError.operationFailed(operation: "uploadVolume", reason: "Cannot determine file size")
            }

            // Create a blocking stream
            guard let stream = virStreamNew(conn, 0) else {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                throw LibvirtError.operationFailed(operation: "uploadVolume/streamNew", reason: err)
            }

            // Start the upload
            if virStorageVolUpload(vol, stream, 0, CUnsignedLongLong(fileSize), 0) < 0 {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                virStreamFree(stream)
                throw LibvirtError.operationFailed(operation: "uploadVolume/volUpload", reason: err)
            }

            // Open the local file for reading
            guard let fileHandle = FileHandle(forReadingAtPath: fileURL.path) else {
                virStreamFinish(stream)
                virStreamFree(stream)
                throw LibvirtError.operationFailed(operation: "uploadVolume", reason: "Cannot open file for reading")
            }
            defer { fileHandle.closeFile() }

            let chunkSize = 1_048_576 // 1 MB
            var totalSent: UInt64 = 0

            while totalSent < fileSize {
                let data = fileHandle.readData(ofLength: chunkSize)
                if data.isEmpty { break }

                let bytesSent = data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> Int32 in
                    guard let baseAddress = ptr.baseAddress else { return -1 }
                    return virStreamSend(
                        stream,
                        baseAddress.assumingMemoryBound(to: CChar.self),
                        data.count
                    )
                }

                if bytesSent < 0 {
                    let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                    virStreamAbort(stream)
                    virStreamFree(stream)
                    throw LibvirtError.operationFailed(operation: "uploadVolume/streamSend", reason: err)
                }

                totalSent += UInt64(bytesSent)
                let progress = Double(totalSent) / Double(fileSize)
                onProgress(min(progress, 1.0))
            }

            if virStreamFinish(stream) < 0 {
                let err = virGetLastErrorMessage().flatMap { String(cString: $0) } ?? "Unknown"
                virStreamFree(stream)
                throw LibvirtError.operationFailed(operation: "uploadVolume/streamFinish", reason: err)
            }
            virStreamFree(stream)

            Log.libvirt.info("Upload complete: \(fileURL.lastPathComponent) -> \(poolName)/\(volumeName)")
        }
    }
}
