import XCTest
import UniformTypeIdentifiers


public protocol Page {
    var application: String? { get }

    @PageBuilder var body: PageDescription { get }
}

public extension Page {
    var application: String? { nil }
}


extension Page {
    /// The name of the page which is displayed to the user, e.g. in error messages or debug output.
    var debugName: String {
        String(describing: type(of: self))
    }
}

extension Page {
    var xcuiapplication: XCUIApplication {
        if let application {
            return XCUIApplication(bundleIdentifier: application)
        } else {
            return XCUIApplication()
        }
    }
}


public struct PageExistsResults {
    public let missingElements: [PageElement]

    public var isExisting: Bool {
        missingElements.isEmpty
    }
}


public extension Page {
    func exists() -> PageExistsResults {
        XCTContext.runActivity(named: "Check if page \(debugName) exists") { activity in
            guard let snapshot = try? xcuiapplication.snapshot() else {
                return PageExistsResults(missingElements: body.elements)
            }
            let finder = ElementFinder(page: self, snapshot: snapshot)
            TestData.isEvaluatingBody = true
            defer {
                TestData.isEvaluatingBody = false
            }
            return PageExistsResults(missingElements: finder.check())
        }
    }

    func waitForExistence(
        timeout: CFTimeInterval = 15,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTContext.runActivity(named: "Wait max \(timeout)s for page \(debugName) to exist") { activity in
            let runLoop = RunLoop.current
            let deadline = Date(timeIntervalSinceNow: timeout)
            var results: PageExistsResults?
            repeat {
                // Wait for all activity indicators to disappear.
                guard xcuiapplication.activityIndicators.count == 0 else {
                    _ = runLoop.run(mode: .default, before: Date(timeIntervalSinceNow: 1))
                    continue
                }
                // Then we validate that the page exists.
                let currentResults = exists()
                guard !currentResults.isExisting else { return }
                results = currentResults
                _ = runLoop.run(mode: .default, before: Date(timeIntervalSinceNow: 1))
            } while Date() < deadline

            let debugPage = xcuiapplication.currentPage?.generatePageSource()
            if let data = debugPage?.data(using: .utf8) {
                activity.add(
                    XCTAttachment(
                        uniformTypeIdentifier: UTType.swiftSource.identifier,
                        name: "ActualPage.swift",
                        payload: data
                    )
                )
            }

            XCTFail(
                "Page \(debugName) didn't exist after \(timeout)s"
                + (results?.failureDescription ?? ""),
                file: file,
                line: line
            )
        }
    }
}

extension Page {
    func refreshElementCache() {
        guard let snapshot = try? xcuiapplication.snapshot() else {
            return
        }
        let finder = ElementFinder(page: self, snapshot: snapshot)
        _ = finder.check()
    }
}

var elementCache: [PageElementIdentifier: CacheEntry] = [:]

struct CacheEntry {
    let page: Page
    let path: [Snapshot.PathStep]
    let index: Int
}


private extension PageExistsResults {
    var failureDescription: String {
        missingElements.map {
            "\n⛔️ missing element \(type(of: $0)), defined at \($0.elementIdentifier.file) \($0.elementIdentifier.line):\($0.elementIdentifier.line)"
        }.joined()
    }
}
