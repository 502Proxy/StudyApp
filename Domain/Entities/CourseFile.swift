import Foundation

/// Eine Datei aus dem Stud.IP-Dateibereich eines Moduls, mit Stand der lokalen Kopie.
struct CourseFile: Identifiable, Hashable, Codable, Sendable {
    let moduleID: UUID
    /// ID der Datei in Stud.IP.
    let remoteID: String
    var name: String
    var folderPath: String
    var size: Int?
    var version: String
    var changedAt: Date?
    var mimeType: String?
    /// Pfad im App-Speicher, sobald die Datei heruntergeladen ist.
    var localFileName: String?
    var downloadedVersion: String?

    /// Eindeutig auch dann, wenn zwei Module dieselbe Veranstaltung nutzen.
    var id: String { "\(moduleID.uuidString)/\(remoteID)" }

    var isDownloaded: Bool { localFileName != nil }
    /// In Stud.IP gibt es eine neuere Fassung als die heruntergeladene.
    var isOutdated: Bool { localFileName != nil && downloadedVersion != version }

    var fileExtension: String {
        (name as NSString).pathExtension.lowercased()
    }

    var isPDF: Bool {
        mimeType?.lowercased().contains("pdf") == true || fileExtension == "pdf"
    }

    init(
        moduleID: UUID,
        remoteID: String,
        name: String,
        folderPath: String = "",
        size: Int? = nil,
        version: String,
        changedAt: Date? = nil,
        mimeType: String? = nil,
        localFileName: String? = nil,
        downloadedVersion: String? = nil
    ) {
        self.moduleID = moduleID
        self.remoteID = remoteID
        self.name = name
        self.folderPath = folderPath
        self.size = size
        self.version = version
        self.changedAt = changedAt
        self.mimeType = mimeType
        self.localFileName = localFileName
        self.downloadedVersion = downloadedVersion
    }

    init(_ file: StudIPFile, moduleID: UUID) {
        self.init(
            moduleID: moduleID,
            remoteID: file.id,
            name: file.name,
            folderPath: file.folderPath,
            size: file.size,
            version: file.version,
            changedAt: file.changedAt,
            mimeType: file.mimeType
        )
    }
}
