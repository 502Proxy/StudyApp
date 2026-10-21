import Foundation

/// Spricht die JSON:API einer Stud.IP-Installation (`<Server>/jsonapi.php/v1/…`) mit HTTP-Basic-Anmeldung.
struct StudIPJSONAPIClient: StudIPService {
    var session: URLSession = .shared
    /// Schutz gegen endlos verkettete Seiten-Links.
    private let maximumPages = 50

    func verify(_ credentials: StudIPCredentials) async throws -> String {
        try StudIPJSONAPIParser.currentUser(try await get("users/me", credentials)).name
    }

    func courses(_ credentials: StudIPCredentials) async throws -> [StudIPCourse] {
        let user = try StudIPJSONAPIParser.currentUser(try await get("users/me", credentials))
        // Semestertitel gibt es nur über eine eigene Liste; ohne sie fehlt nur die Semesterangabe.
        let semesters = (try? await allResources("semesters", credentials)) ?? []
        let titles = StudIPJSONAPIParser.semesterTitles(semesters)
        let path = "users/\(user.id)/courses"
        return try await allResources(path, credentials)
            .compactMap { StudIPJSONAPIParser.course($0, semesterTitles: titles) }
    }

    func files(inCourse courseID: String, _ credentials: StudIPCredentials) async throws -> [StudIPFile] {
        let resources = try await allResources("courses/\(courseID)/file-refs", credentials)
        // Ohne Ordnerliste landen alle Dateien im Hauptordner – kein Grund, den Abgleich abzubrechen.
        let folders = (try? await allResources("courses/\(courseID)/folders", credentials)) ?? []
        let paths = StudIPJSONAPIParser.folderPaths(folders)
        return resources.compactMap { resource in
            guard var file = StudIPJSONAPIParser.file(resource) else { return nil }
            file.folderPath = StudIPJSONAPIParser.parentFolderID(resource).flatMap { paths[$0] } ?? ""
            return file
        }
    }

    func download(_ file: StudIPFile, _ credentials: StudIPCredentials) async throws -> Data {
        try await get("file-refs/\(file.id)/content", credentials, accept: "*/*")
    }

    // MARK: HTTP

    private func allResources(_ path: String, _ credentials: StudIPCredentials) async throws -> [StudIPJSONAPIParser.Resource] {
        var url: URL? = try endpoint(path, credentials, query: [URLQueryItem(name: "page[limit]", value: "100")])
        var resources: [StudIPJSONAPIParser.Resource] = []
        var pages = 0
        while let current = url, pages < maximumPages {
            let page = try StudIPJSONAPIParser.page(try await get(current, credentials))
            resources += page.resources
            pages += 1
            url = page.next.flatMap { Self.resolve($0, server: credentials.account.serverURL) }
            if url == current { break }
        }
        return resources
    }

    private func get(_ path: String, _ credentials: StudIPCredentials, accept: String = "application/vnd.api+json") async throws -> Data {
        try await get(try endpoint(path, credentials), credentials, accept: accept)
    }

    private func get(_ url: URL, _ credentials: StudIPCredentials, accept: String = "application/vnd.api+json") async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue(accept, forHTTPHeaderField: "Accept")
        let token = Data("\(credentials.account.username):\(credentials.password)".utf8).base64EncodedString()
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where Self.isOffline(error) {
            throw StudIPError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw StudIPError.invalidResponse }
        switch http.statusCode {
        case 200...299: return data
        case 401: throw StudIPError.unauthorized
        case 404: throw StudIPError.notFound
        default: throw StudIPError.server(statusCode: http.statusCode)
        }
    }

    /// `appendingPathComponent` kodiert Sonderzeichen in IDs selbst.
    private func endpoint(_ path: String, _ credentials: StudIPCredentials, query: [URLQueryItem] = []) throws -> URL {
        let base = credentials.account.serverURL.appendingPathComponent("jsonapi.php/v1/" + path)
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw StudIPError.invalidServerURL
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw StudIPError.invalidServerURL }
        return url
    }

    /// Stud.IP liefert Seiten-Links mal absolut, mal als Pfad ab dem Server-Wurzelverzeichnis.
    static func resolve(_ link: String, server: URL) -> URL? {
        if link.hasPrefix("http://") || link.hasPrefix("https://") { return URL(string: link) }
        guard var origin = URLComponents(url: server, resolvingAgainstBaseURL: false) else { return nil }
        origin.path = ""
        origin.query = nil
        return URL(string: link, relativeTo: origin.url)?.absoluteURL
    }

    private static func isOffline(_ error: URLError) -> Bool {
        [.notConnectedToInternet, .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed]
            .contains(error.code)
    }
}
