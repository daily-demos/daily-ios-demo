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

// The below is useful for checking whether an app message should be attempted
// to be deserialized as a Prebuilt chat message or whether it's another kind of
// app message entirely.
extension PrebuiltChatAppMessage {
    private struct PrebuiltAppMessage: Decodable {
        let event: String
    }
    
    public static func shouldExpectAppMessageToBePrebuiltChatMessage(_ jsonData: Data) -> Bool {
        let decoder = JSONDecoder()
        do {
            let appMessage = try decoder.decode(
                PrebuiltAppMessage.self,
                from: jsonData
            )
            return appMessage.event == "chat-msg"
        }
        catch {
            return false
        }
    }
}
