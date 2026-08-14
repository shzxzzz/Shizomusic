import Foundation
import Testing

@testable import ShizoMusic

struct TrackTests {
    @Test func sourceStateIsExplicit() {
        let track = Track(id: UUID(), title: "Local track", duration: 120, sourceState: .local)
        #expect(track.sourceState == .local)
    }
}
