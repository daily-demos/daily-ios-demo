import Foundation

public struct PrebuiltChatAppMessage: Codable {
    public static let notificationIdentifier: String = "prebuilt-chat-app-message"

    public let date: Date
    public let message: String
    public let senderName: String
    public let roomName: String
    public let event: String
    
    public init(
        message: String,
        senderName: String,
        roomName: String,
        date: Date = .init()
    ) {
        self.event = "chat-msg"
        self.senderName = senderName
        self.roomName = roomName
        self.message = message
        self.date = date
    }
    
    enum CodingKeys: String, CodingKey {
        case date
        case message
        case event
        case senderName = "name"
        case roomName = "room"
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.date = try container.decode(Date.self, forKey: .date)
        self.message = try container.decode(String.self, forKey: .message)
        self.event = try container.decode(String.self, forKey: .event)
        self.senderName = try container.decode(String.self, forKey: .senderName)
        self.roomName = try container.decode(String.self, forKey: .roomName)
    }
    
    enum PrebuiltChatAppMessageError: Error {
        case invalidEventKind
    }
}
