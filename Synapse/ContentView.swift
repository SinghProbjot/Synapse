//
//  ContentView.swift
//  Synapse
//
//  Created by Probjot Singh on 13/01/26.
//

import SwiftUI

// --- 1. STRUTTURA PRINCIPALE (TAB BAR) ---
struct ContentView: View {
    // Synapse: Il ponte neurale tra te e la tua macchina.
    
    init() {
        // Personalizziamo l'aspetto della TabBar per renderla "stealth"
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1.0) // Quasi nero
        
        UITabBar.appearance().standardAppearance = appearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }

    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Synapse", systemImage: "dot.radiowaves.left.and.right")
                }
            
            InputView()
                .tabItem {
                    Label("Input", systemImage: "keyboard.fill")
                }
            
            MagicView()
                .tabItem {
                    Label("Magic", systemImage: "wand.and.stars")
                }
            
            DeckView()
                .tabItem {
                    Label("Deck", systemImage: "square.grid.3x3.fill")
                }
            
            SettingsView()
                .tabItem {
                    Label("Core", systemImage: "cpu")
                }
        }
        .preferredColorScheme(.dark) // Obbligatoria la Dark Mode
        .accentColor(Color(red: 0.0, green: 0.85, blue: 0.95)) // "Synapse Cyan"
    }
}

// --- 2. DASHBOARD (MISSION CONTROL) ---
struct DashboardView: View {
    @State private var isConnected = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all) // Sfondo nero profondo
                
                ScrollView {
                    VStack(spacing: 25) {
                        // Header "Brand"
                        HStack {
                            Text("SYNAPSE")
                                .font(.system(size: 30, weight: .heavy, design: .monospaced))
                                .tracking(2) // Spaziatura lettere
                                .foregroundColor(.white)
                            Spacer()
                            Circle()
                                .fill(isConnected ? Color.green : Color.red)
                                .frame(width: 10, height: 10)
                                .shadow(color: isConnected ? .green : .red, radius: 5)
                        }
                        .padding(.horizontal)
                        .padding(.top, 10)
                        
                        // Card di Stato Connessione (Stile Cyber)
                        ZStack {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color(white: 0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                                )
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("STATUS LINK")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                        .tracking(1)
                                    
                                    Text(isConnected ? "ONLINE" : "OFFLINE")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(isConnected ? .green : .gray)
                                    
                                    Text(isConnected ? "Target: Workstation" : "Cerca Dispositivo...")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                }
                                Spacer()
                                Image(systemName: "bolt.horizontal.circle.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(isConnected ? .yellow : .gray.opacity(0.3))
                            }
                            .padding(20)
                        }
                        .frame(height: 120)
                        .padding(.horizontal)
                        .onTapGesture {
                            withAnimation(.spring()) { isConnected.toggle() }
                            // Qui aggiungeremo il feedback tattile (Haptic)
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                        }
                        
                        // Griglia Widget Rapidi
                        VStack(alignment: .leading) {
                            Text("QUICK ACTIONS")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.gray)
                                .padding(.leading)
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                                SynapseWidget(icon: "lock.shield.fill", title: "Secure Lock", color: .orange)
                                SynapseWidget(icon: "play.rectangle.fill", title: "Media Mode", color: .pink)
                                SynapseWidget(icon: "waveform.path.ecg", title: "Anti-Sleep", color: .green)
                                SynapseWidget(icon: "power", title: "Kill Switch", color: .red)
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .navigationBarHidden(true)
        }
    }
}

// Widget personalizzato stile Synapse
struct SynapseWidget: View {
    let icon: String
    let title: String
    let color: Color
    
    var body: some View {
        VStack {
            Circle()
                .fill(color.opacity(0.15))
                .frame(width: 50, height: 50)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundColor(color)
                )
                .padding(.bottom, 8)
            
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 110)
        .background(Color(white: 0.12))
        .cornerRadius(18)
    }
}

// --- 3. INPUT (TASTIERA + MOUSE) ---
struct InputView: View {
    @State private var inputMode = 0
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            VStack {
                // Selettore futuristico
                Picker("Mode", selection: $inputMode) {
                    Text("KEYBOARD").tag(0)
                    Text("TRACKPAD").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                .background(Color.black)
                
                if inputMode == 0 {
                    // Placeholder Tastiera
                    Spacer()
                    Image(systemName: "keyboard.badge.ellipsis")
                        .font(.system(size: 80))
                        .foregroundColor(.gray.opacity(0.5))
                        .padding()
                    Text("WAITING FOR BLE SIGNAL")
                        .font(.caption)
                        .tracking(2)
                        .foregroundColor(.gray)
                    Spacer()
                    
                    // Barra tasti rapidi
                    HStack(spacing: 15) {
                        CyberButton(label: "ESC")
                        CyberButton(label: "TAB")
                        CyberButton(label: "WIN")
                        CyberButton(label: "ALT")
                    }
                    .padding()
                    
                } else {
                    // Trackpad Area
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(white: 0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                        
                        VStack {
                            Image(systemName: "dot.arrowtriangles.up.right.down.left.circle")
                                .font(.largeTitle)
                                .foregroundColor(.cyan.opacity(0.3))
                            Text("TOUCH SURFACE")
                                .font(.caption2)
                                .foregroundColor(.gray.opacity(0.5))
                                .padding(.top, 5)
                        }
                    }
                    .padding()
                    
                    HStack {
                        CyberButton(label: "L-CLICK", color: .gray)
                        CyberButton(label: "R-CLICK", color: .gray)
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
        }
    }
}

// --- 4. MAGIC (FEATURES) ---
struct MagicView: View {
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                List {
                    Section(header: Text("SENSORS").font(.caption).foregroundColor(.cyan)) {
                        MagicRow(icon: "gyroscope", title: "Gyro Mouse", desc: "Muovi il telefono per puntare")
                        MagicRow(icon: "mic.fill", title: "Voice Bridge", desc: "Dettatura vocale su PC")
                    }
                    .listRowBackground(Color(white: 0.1))
                    
                    Section(header: Text("AUTOMATION").font(.caption).foregroundColor(.cyan)) {
                        MagicRow(icon: "wave.3.right", title: "Proximity Unlock", desc: "Sblocca quando ti avvicini")
                        MagicRow(icon: "gamecontroller.fill", title: "Gamepad Emulation", desc: "Layout Xbox Controller")
                    }
                    .listRowBackground(Color(white: 0.1))
                }
                .listStyle(InsetGroupedListStyle())
            }
            .navigationTitle("Magic")
        }
    }
}

struct MagicRow: View {
    let icon: String
    let title: String
    let desc: String
    @State private var isOn = false
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 30)
                .foregroundColor(.cyan)
            
            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            Spacer()
            Toggle("", isOn: $isOn)
        }
        .padding(.vertical, 4)
    }
}

// --- 5. DECK (MACRO) ---
struct DeckView: View {
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 15) {
                        ForEach(1...12, id: \.self) { index in
                            VStack {
                                Image(systemName: "command")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                Text("M\(index)")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.gray)
                            }
                            .frame(height: 85)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(white: 0.12))
                                    .shadow(color: .black, radius: 2, x: 0, y: 2)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.cyan.opacity(0.1), lineWidth: 1)
                            )
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Macro Deck")
        }
    }
}

// --- 6. SETTINGS (CORE) ---
struct SettingsView: View {
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("DEVICE INFO")) {
                    HStack {
                        Text("Model")
                        Spacer()
                        Text("Synapse Dongle v1")
                            .foregroundColor(.gray)
                    }
                    HStack {
                        Text("Connection")
                        Spacer()
                        Text("BLE 5.0 Encrypted")
                            .foregroundColor(.green)
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Core System")
        }
    }
}

// --- UI COMPONENTS ---
struct CyberButton: View {
    let label: String
    var color: Color = .cyan
    
    var body: some View {
        Button(action: {
            // Haptic Feedback simulato
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }) {
            Text(label)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 55)
                .background(color.opacity(0.15))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(color.opacity(0.5), lineWidth: 1)
                )
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
