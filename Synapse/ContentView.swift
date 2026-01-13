import SwiftUI
import UIKit

// LOGIC ENGINE ---
// Questa classe gestirà tutte le comunicazioni.
// Per ora simula le azioni stampandole nella Console di Xcode.
class SynapseEngine: ObservableObject {
    @Published var isConnected = false
    @Published var connectionStatus = "DISCONNECTED"
    
    // Funzione per connettere (Simulazione)
    func toggleConnection() {
        if isConnected {
            isConnected = false
            connectionStatus = "DISCONNECTED"
            print("[BLE] Disconnesso.")
        } else {
            // Qui andrà la scansione Bluetooth reale
            isConnected = true
            connectionStatus = "CONNECTED TO ESP32-S3"
            print("[BLE] Connesso al dispositivo Synapse.")
        }
    }
    
    // Invia un tasto singolo
    func sendKey(_ key: String) {
        print("[ACTION] Tasto premuto: \(key)")
        // TODO: Inserire qui codice: peripheral.writeValue(key...)
    }
    
    // Invia una Macro
    func triggerMacro(id: Int) {
        print("[MACRO] Eseguita Macro #\(id)")
    }
    
    // Invia click del mouse
    func sendClick(type: String) {
        print("[MOUSE] Click: \(type)")
    }
    
    // Attiva/Disattiva funzioni Magic
    func toggleFeature(name: String, active: Bool) {
        print("[MAGIC] Funzione \(name) impostata su: \(active)")
    }
}

// --- STRUTTURA PRINCIPALE (TAB BAR) ---
struct ContentView: View {
    // Creiamo un'istanza condivisa del motore
    @StateObject var engine = SynapseEngine()
    
    init() {
        // Look "Stealth" per la TabBar
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1.0)
        
        UITabBar.appearance().standardAppearance = appearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }

    var body: some View {
        TabView {
            DashboardView(engine: engine)
                .tabItem { Label("Synapse", systemImage: "dot.radiowaves.left.and.right") }
            
            InputView(engine: engine)
                .tabItem { Label("Input", systemImage: "keyboard.fill") }
            
            MagicView(engine: engine)
                .tabItem { Label("Magic", systemImage: "wand.and.stars") }
            
            DeckView(engine: engine)
                .tabItem { Label("Deck", systemImage: "square.grid.3x3.fill") }
            
            SettingsView()
                .tabItem { Label("Core", systemImage: "cpu") }
        }
        .preferredColorScheme(.dark)
        .accentColor(Color(red: 0.0, green: 0.85, blue: 0.95)) // "Synapse Cyan"
    }
}

// ---  DASHBOARD ---
struct DashboardView: View {
    @ObservedObject var engine: SynapseEngine
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 25) {
                        // Header
                        HStack {
                            Text("SYNAPSE")
                                .font(.system(size: 30, weight: .heavy, design: .monospaced))
                                .tracking(2)
                                .foregroundColor(.white)
                            Spacer()
                            Circle()
                                .fill(engine.isConnected ? Color.green : Color.red)
                                .frame(width: 10, height: 10)
                                .shadow(color: engine.isConnected ? .green : .red, radius: 5)
                        }
                        .padding(.horizontal)
                        .padding(.top, 10)
                        
                        // Status Card
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
                                    
                                    Text(engine.isConnected ? "ONLINE" : "OFFLINE")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(engine.isConnected ? .green : .gray)
                                    
                                    Text(engine.connectionStatus)
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                }
                                Spacer()
                                Button(action: {
                                    withAnimation(.spring()) { engine.toggleConnection() }
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                }) {
                                    Image(systemName: "bolt.horizontal.circle.fill")
                                        .font(.system(size: 40))
                                        .foregroundColor(engine.isConnected ? .yellow : .gray.opacity(0.3))
                                }
                            }
                            .padding(20)
                        }
                        .frame(height: 120)
                        .padding(.horizontal)
                        
                        // Quick Actions
                        VStack(alignment: .leading) {
                            Text("QUICK ACTIONS")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.gray)
                                .padding(.leading)
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                                SynapseWidget(icon: "lock.shield.fill", title: "Secure Lock", color: .orange, action: { engine.sendKey("WIN+L") })
                                SynapseWidget(icon: "play.rectangle.fill", title: "Netflix Mode", color: .pink, action: { engine.triggerMacro(id: 99) })
                                SynapseWidget(icon: "waveform.path.ecg", title: "Anti-Sleep", color: .green, action: { engine.toggleFeature(name: "Jiggler", active: true) })
                                SynapseWidget(icon: "power", title: "Kill Switch", color: .red, action: { engine.sendKey("ALT+F4") })
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

struct SynapseWidget: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        }) {
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
}

// ---  INPUT ---
struct InputView: View {
    @ObservedObject var engine: SynapseEngine
    @State private var inputMode = 0
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            VStack {
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
                    Text("KEYBOARD SURFACE")
                        .font(.caption)
                        .tracking(2)
                        .foregroundColor(.gray)
                    Spacer()
                    
                    HStack(spacing: 15) {
                        CyberButton(label: "ESC", action: { engine.sendKey("ESC") })
                        CyberButton(label: "TAB", action: { engine.sendKey("TAB") })
                        CyberButton(label: "WIN", action: { engine.sendKey("GUI") })
                        CyberButton(label: "ENTER", color: .green, action: { engine.sendKey("ENTER") })
                    }
                    .padding()
                    
                } else {
                    // Trackpad Area
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(white: 0.05))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        // Simulazione invio coordinate mouse
                                        print("[MOUSE] X:\(value.translation.width) Y:\(value.translation.height)")
                                    }
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
                        CyberButton(label: "L-CLICK", color: .gray, action: { engine.sendClick(type: "LEFT") })
                        CyberButton(label: "R-CLICK", color: .gray, action: { engine.sendClick(type: "RIGHT") })
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
        }
    }
}

// ---  MAGIC ---
struct MagicView: View {
    @ObservedObject var engine: SynapseEngine
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                List {
                    Section(header: Text("SENSORS").font(.caption).foregroundColor(.cyan)) {
                        MagicRow(icon: "gyroscope", title: "Gyro Mouse", desc: "Muovi il telefono per puntare", engine: engine)
                        MagicRow(icon: "mic.fill", title: "Voice Bridge", desc: "Dettatura vocale su PC", engine: engine)
                    }
                    .listRowBackground(Color(white: 0.1))
                    
                    Section(header: Text("AUTOMATION").font(.caption).foregroundColor(.cyan)) {
                        MagicRow(icon: "wave.3.right", title: "Proximity Unlock", desc: "Sblocca quando ti avvicini", engine: engine)
                        MagicRow(icon: "gamecontroller.fill", title: "Gamepad Emulation", desc: "Layout Xbox Controller", engine: engine)
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
    @ObservedObject var engine: SynapseEngine
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
                .onChange(of: isOn) { value in
                    engine.toggleFeature(name: title, active: value)
                }
        }
        .padding(.vertical, 4)
    }
}

// --- 5. DECK ---
struct DeckView: View {
    @ObservedObject var engine: SynapseEngine
    let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 15) {
                        ForEach(1...12, id: \.self) { index in
                            Button(action: {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                engine.triggerMacro(id: index)
                            }) {
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
                                .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.12)))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.cyan.opacity(0.1), lineWidth: 1))
                            }
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
                
                // --- CREDITI E GITHUB ---
                Section(header: Text("CREDITS")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Developed by Singh Probjot")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Link(destination: URL(string: "https://github.com/SinghProbjot/Synapse")!) {
                            HStack {
                                Image(systemName: "link.circle.fill")
                                Text("View Repo on GitHub")
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.cyan)
                        }
                    }
                    .padding(.vertical, 5)
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Core System")
        }
    }
}

// --- COMPONENTI UI ---
struct CyberButton: View {
    let label: String
    var color: Color = .cyan
    var action: () -> Void
    
    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            action()
        }) {
            Text(label)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 55)
                .background(color.opacity(0.15))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.5), lineWidth: 1))
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
