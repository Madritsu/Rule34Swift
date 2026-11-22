import Foundation

struct Rule34Comment: Identifiable, Hashable {
    let id: String
    let postID: String?
    let creator: String
    let creatorID: String?
    let createdAt: String?
    let body: String
}
