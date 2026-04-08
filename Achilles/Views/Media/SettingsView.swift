// SettingsView.swift
// Extracted from ContentView.swift

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @ObservedObject var photoViewModel: PhotoViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var sumOfPastPhotosOnThisDay: Int? = nil
    @State private var showingDeleteConfirm = false

    private let statisticsService = SettingsStatisticsService()

    var body: some View {
        VStack(spacing: 20) {
            if let user = authVM.user, !user.isAnonymous {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Account")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text(user.email ?? "No email")
                        .font(.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
            }

            VStack(alignment: .center, spacing: 10) {
                Text("Memories in Numbers")
                    .font(.system(.title2, design: .rounded))
                    .fontWeight(.bold)
                    .padding(.top)
                Text(Date().monthDayWithOrdinalAndYear())
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 16)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "calendar.circle.fill")
                            .foregroundColor(.accentColor)
                        Text("# of Years with Photos: \(photoViewModel.availableYearsAgo.count)")
                    }
                    .font(.body)
                    Divider().padding(.horizontal, -8)
                    HStack {
                        Image(systemName: "photo.stack.fill")
                            .foregroundColor(.accentColor)
                        if let totalSum = sumOfPastPhotosOnThisDay {
                            Text("# of Photos on this Day : \(totalSum)")
                        } else {
                            Text("# of Photos on this Day : ")
                            ProgressView()
                        }
                    }
                    .font(.body)
                }
                .padding(.horizontal)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical)
            .background(Color(.systemGray6))
            .cornerRadius(12)

            Button(action: {
                authVM.signOut()
            }) {
                Text("Sign Out")
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
            }

            Spacer()

            if authVM.user?.isAnonymous == false {
                Button(action: {
                    showingDeleteConfirm = true
                }) {
                    Text("Delete Account")
                        .font(.footnote)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.3))
                        .cornerRadius(10)
                }
                .padding(.bottom)
            }
        }
        .padding()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let currentMonthDay = Calendar.current.dateComponents([.month, .day], from: Date())
            Task {
                let sum = await statisticsService.calculateTotalPhotosForCalendarDayFromPastYears(
                    availablePastYearOffsets: photoViewModel.availableYearsAgo,
                    currentMonthDayComponents: currentMonthDay
                )
                await MainActor.run {
                    self.sumOfPastPhotosOnThisDay = sum
                }
            }
        }
        .alert("Delete Account?", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    await authVM.deleteAccount()
                }
            }
        } message: {
            Text("Are you sure you want to permanently delete your account and all associated data? This action cannot be undone.")
        }
    }
}
