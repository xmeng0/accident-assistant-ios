//
//  IdentityStore.swift
//  AccidentAssistant
//
//  Created by Sean Meng on 4/25/26.
//

import Foundation

struct UserProfile: Codable {
    var driverName: String
    var fleetID: String
    var insuranceProvider: String
}

final class IdentityStore {
    static let shared = IdentityStore()
    private init() {}

    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func profileURL() -> URL {
        getDocumentsDirectory().appendingPathComponent("user_profile.json")
    }

    func saveProfile(_ profile: UserProfile) {
        do {
            let data = try JSONEncoder().encode(profile)
            try data.write(to: profileURL(), options: [.atomic])
            print("👤 Profile saved to: \(profileURL().path)")
        } catch {
            print("👤 saveProfile failed: \(error.localizedDescription)")
        }
    }

    func loadProfile() -> UserProfile? {
        let url = profileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(UserProfile.self, from: data)
        } catch {
            print("👤 loadProfile failed: \(error.localizedDescription)")
            return nil
        }
    }
}
