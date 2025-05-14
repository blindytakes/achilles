// DailyWelcomeView.swift
import SwiftUI

struct DailyWelcomeView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var fadeIn = false
    @State private var scaleEffect: CGFloat = 0.9
    
    // You might want to add different greetings or quotes
    private let greetings = [
        "Welcome back!",
        "Ready for today's memories?",
        "Let's explore the past!",
        "Time to reminisce!",
        "Your memories await!"
    ]
    
    private var randomGreeting: String {
        greetings.randomElement() ?? "Welcome back!"
    }
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Spacer()
                
                // App icon or logo placeholder
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 80))
                    .foregroundColor(.accentColor)
                    .scaleEffect(scaleEffect)
                
                VStack(spacing: 12) {
                    Text(randomGreeting)
                        .font(.largeTitle.bold())
                        .foregroundColor(.primary)
                    
                    Text("See what happened on this day in past years")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .opacity(fadeIn ? 1 : 0)
                
                Spacer()
                
                Button(action: {
                    // Navigate to main app without marking daily welcome as done
                    // since we want to show it every time
                    authVM.navigateToMainApp()
                }) {
                    HStack {
                        Text("View Memories")
                        Image(systemName: "arrow.right")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.accentColor)
                    )
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 8, y: 4)
                }
                .padding(.horizontal, 40)
                .opacity(fadeIn ? 1 : 0)
                
                Spacer()
            }
            .padding(.vertical, 40)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6)) {
                fadeIn = true
                scaleEffect = 1.0
            }
        }
    }
}
