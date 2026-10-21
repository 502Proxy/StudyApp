import Foundation
import SwiftData

/// SwiftData-Modell des Stud.IP-Dateikatalogs. `key` verbindet Modul und Stud.IP-Datei.
@Model
final class CourseFileRecord {
    @Attribute(.unique) var key: String
    var moduleID: UUID
    var remoteID: String
    var name: String
    var folderPath: String
    var size: Int?
    var version: String
    var changedAt: Date?
    var mimeType: String?
    var localFileName: String?
    var downloadedVersion: String?

    init(_ file: CourseFile) {
        key = file.id
        moduleID = file.moduleID
        remoteID = file.remoteID
        name = file.name
        folderPath = file.folderPath
        size = file.size
        version = file.version
        changedAt = file.changedAt
        mimeType = file.mimeType
        localFileName = file.localFileName
        downloadedVersion = file.downloadedVersion
    }

    func toDomain() -> CourseFile {
        CourseFile(
            moduleID: moduleID, remoteID: remoteID, name: name, folderPath: folderPath, size: size,
            version: version, changedAt: changedAt, mimeType: mimeType,
            localFileName: localFileName, downloadedVersion: downloadedVersion
        )
    }

    /// Übernimmt den Stand aus Stud.IP; die lokale Kopie bleibt unberührt.
    func applyRemote(_ file: CourseFile) {
        name = file.name
        folderPath = file.folderPath
        size = file.size
        version = file.version
        changedAt = file.changedAt
        mimeType = file.mimeType
    }
}
