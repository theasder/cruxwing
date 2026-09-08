import Testing
import Foundation
@testable import MeetGPT

/// The role picker is a small first-party table. Prompt-specific methodology is
/// governed separately by the reviewed bundled-skill policy.
@Suite("Role skill matrix")
struct RoleSkillMatrixTests {
    @Test("guidance is generic role framing, independent of prompt id")
    func guidanceComposition() {
        #expect(RoleSkillMatrix.guidance(roleID: "not-a-role", promptID: "brainstorm") == nil)
        #expect(RoleSkillMatrix.guidance(roleID: nil, promptID: "brainstorm") == nil)
        let brainstorm = RoleSkillMatrix.guidance(
            roleID: "product-manager", promptID: "brainstorm")
        let factcheck = RoleSkillMatrix.guidance(
            roleID: "product-manager", promptID: "factcheck")
        #expect(brainstorm == factcheck)
        #expect(brainstorm?.contains("Продакт-менеджер") == true)
        #expect(brainstorm?.contains("product-discovery") == false)
    }

    @Test("custom role guidance frames the user's own description")
    func customRoleGuidance() {
        let saved = Config.userCustomRole
        defer { Config.userCustomRole = saved }

        Config.userCustomRole = "Head of Growth at a B2B fintech"
        let guidance = RoleSkillMatrix.guidance(roleID: RoleSkillMatrix.customRoleID,
                                                promptID: "brainstorm")
        #expect(guidance?.contains("Head of Growth at a B2B fintech") == true)

        // An empty description means no role layer — never an empty frame.
        Config.userCustomRole = "   "
        #expect(RoleSkillMatrix.guidance(roleID: RoleSkillMatrix.customRoleID,
                                         promptID: "brainstorm") == nil)
    }

    @Test("the first-party role table is explicit, unique and usable")
    func roleTable() {
        #expect(RoleSkillMatrix.positions.count == 10)
        #expect(Set(RoleSkillMatrix.positions.map(\.id)).count == 10)
        for position in RoleSkillMatrix.positions {
            #expect(!position.label.isEmpty)
            #expect(!position.symbol.isEmpty)
        }
    }
}
