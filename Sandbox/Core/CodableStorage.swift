//
//  CodableStorage.swift
//  Sandbox
//
//  Lets SDK models be persisted directly with @AppStorage by giving them a
//  JSON-backed RawRepresentable conformance.
//

import Foundation
import IVSDK

protocol CodableStorage: Codable, RawRepresentable {}

extension CodableStorage {
    public var rawValue: String {
        guard let data = try? JSONEncoder().encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    public init?(rawValue: String) {
        guard let value = try? JSONDecoder().decode(Self.self, from: Data(rawValue.utf8)) else {
            return nil
        }
        self = value
    }
}

extension UserModel: @retroactive RawRepresentable {}
extension UserModel: CodableStorage {}
extension LastLoggedInUserModel: @retroactive RawRepresentable {}
extension LastLoggedInUserModel: CodableStorage {}
extension SpaceModel: @retroactive RawRepresentable {}
extension SpaceModel: CodableStorage {}

enum UserLoginType: String {
    case email, google, apple
}
