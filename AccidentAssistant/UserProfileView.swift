//
//  UserProfileView.swift
//  AccidentAssistant
//
//  Created by Sean Meng on 4/25/26.
//

import SwiftUI

struct UserProfileView: View {
    @State private var driverName: String = ""
    @State private var fleetID: String = ""
    @State private var insuranceProvider: String = ""
    @State private var showSavedMessage: Bool = false
    
    var body: some View {
        Form {
            Section(header: Text("Driver Information")) {
                TextField("Full Name", text: $driverName)
                TextField("Fleet ID", text: $fleetID)
                TextField("Insurance Provider", text: $insuranceProvider)
            }
            
            Button(action: {
                let profile = UserProfile(driverName: driverName, fleetID: fleetID, insuranceProvider: insuranceProvider)
                IdentityStore.shared.saveProfile(profile)
                
                // Show a quick saved confirmation
                withAnimation {
                    showSavedMessage = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation {
                        showSavedMessage = false
                    }
                }
            }) {
                Text(showSavedMessage ? "Saved!" : "Save Profile")
                    .frame(maxWidth: .infinity)
                    .foregroundColor(showSavedMessage ? .green : .blue)
            }
        }
        .navigationTitle("Driver Profile")
        .onAppear {
            if let profile = IdentityStore.shared.loadProfile() {
                driverName = profile.driverName
                fleetID = profile.fleetID
                insuranceProvider = profile.insuranceProvider
            }
        }
    }
}
