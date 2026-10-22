import Darwin
import Foundation
import Testing
@testable import Macphin

struct FileItemTests {
    @Test func readsPermissionsOwnerAndLocation() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "macphin-fileitem-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let url = folder.appending(path: "notes.txt")
        try Data().write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: url.path)

        let item = FileItem(url: url)
        #expect(item.permissions == "rw-r-----")
        #expect(item.owner == NSUserName())
        #expect(item.location == folder.path)
    }

    @Test func recognizesPermissionErrors() {
        #expect(Privacy.isPermissionError(CocoaError(.fileReadNoPermission)))
        #expect(Privacy.isPermissionError(NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))))
        #expect(!Privacy.isPermissionError(CocoaError(.fileNoSuchFile)))

        let underlying = NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError,
                              userInfo: [NSUnderlyingErrorKey: underlying])
        #expect(Privacy.isPermissionError(wrapped))
    }
}
