import SwiftUI
import UIKit
import CoreBluetooth

// --- COSTANTI GLOBALI (LA "STRETTA DI MANO SEGRETA") ---
// Questi UUID devono coincidere ESATTAMENTE con quelli che metteremo nell'ESP32
let SYNAPSE_SERVICE_UUID = CBUUID(string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")
let SYNAPSE_CHAR_UUID    = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a8")

// --- 0. IL CERVELLO REALE (CORE BLUETOOTH ENGINE) ---
class SynapseEngine: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    // Variabili Pubbliche per la UI
    @Published var isConnected = false
    @Published var connectionStatus = "DISCONNECTED"
    @Published var bluetoothState = "UNKNOWN"
    
    // Variabili Interne CoreBluetooth
    private var centralManager: CBCentralManager!
    private var synapsePeripheral: CBPeripheral?
    private var inputCharacteristic: CBCharacteristic?
    
    override init() {
        super.init()
        // Inizializza il gestore Bluetooth del telefono
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // --- AZIONI UTENTE ---
    
    func toggleConnection() {
        if isConnected {
            disconnect()
        } else {
            startScanning()
        }
    }
    
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            connectionStatus = "BLUETOOTH OFF"
            return
        }
        
        connectionStatus = "SCANNING..."
        print("[BLE] Inizio scansione per UUID: \(SYNAPSE_SERVICE_UUID)")
        
        // IL FILTRO MAGICO: Cerca SOLO dispositivi con il nostro Service UUID
        centralManager.scanForPeripherals(withServices: [SYNAPSE_SERVICE_UUID], options: nil)
    }
    
    func disconnect() {
        if let p = synapsePeripheral {
            centralManager.cancelPeripheralConnection(p)
        }
        connectionStatus = "DISCONNECTING..."
    }
    
    // --- INVIO DATI REALE ---
    
    func sendKey(_ key: String) {
        guard isConnected, let characteristic = inputCharacteristic, let peripheral = synapsePeripheral else {
            print("[BLE ERROR] Non connesso o caratteristica non trovata per: \(key)")
            return
        }
        
        // Convertiamo la stringa in dati (questo cambierà quando definiremo il protocollo esatto)
        if let data = key.data(using: .utf8) {
            peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
            print("[BLE SENT] \(key)")
        }
    }
    
    func triggerMacro(id: Int) {
        sendKey("MACRO:\(id)")
    }
    
    func sendClick(type: String) {
        sendKey("CLICK:\(type)")
    }
    
    func toggleFeature(name: String, active: Bool) {
        sendKey("CFG:\(name):\(active ? 1 : 0)")
    }
    
    // --- DELEGATI CORE BLUETOOTH (Cosa succede "sotto il cofano") ---
    
    // 1. Monitoraggio stato antenna Bluetooth
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            bluetoothState = "ON"
            print("[BLE STATE] Bluetooth acceso. Pronto.")
        case .poweredOff:
            bluetoothState = "OFF"
            connectionStatus = "TURN ON BT"
            isConnected = false
        case .unauthorized:
            connectionStatus = "NO PERMISSION"
        default:
            connectionStatus = "ERROR"
        }
    }
    
    // 2. Trovato un dispositivo!
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print("[BLE] Trovato dispositivo Synapse: \(peripheral.name ?? "Unknown")")
        
        // Smettiamo di cercare (risparmia batteria)
        centralManager.stopScan()
        
        // Salviamo il riferimento e connettiamo
        synapsePeripheral = peripheral
        synapsePeripheral?.delegate = self
        centralManager.connect(peripheral, options: nil)
        connectionStatus = "CONNECTING..."
    }
    
    // 3. Connessione avvenuta
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        connectionStatus = "CONNECTED"
        print("[BLE] Connesso! Cerco i servizi...")
        peripheral.discoverServices([SYNAPSE_SERVICE_UUID])
    }
    
    // 4. Disconnessione (o errore)
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        connectionStatus = "DISCONNECTED"
        synapsePeripheral = nil
        print("[BLE] Disconnesso.")
    }
    
    // 5. Servizi trovati, ora cerchiamo la "Caratteristica" di scrittura
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            if service.uuid == SYNAPSE_SERVICE_UUID {
                print("[BLE] Servizio Synapse trovato. Cerco caratteristiche...")
                peripheral.discoverCharacteristics([SYNAPSE_CHAR_UUID], for: service)
            }
        }
    }
    
    // 6. Caratteristica trovata! Siamo pronti a scrivere.
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for char in characteristics {
            if char.uuid == SYNAPSE_CHAR_UUID {
                print("[BLE] Canale di scrittura aperto! READY.")
                inputCharacteristic = char
            }
        }
    }
}

// --- 1. STRUTTURA UI (UI Rimasta quasi identica, cambia solo il collegamento al motore) ---
struct ContentView: View {
    @StateObject var engine = SynapseEngine()
    
    init() {
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
        .accentColor(Color(red: 0.0, green: 0.85, blue: 0.95))
    }
}

// --- 2. DASHBOARD ---
struct DashboardView: View {
    @ObservedObject var engine: SynapseEngine
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 25) {
                        // Header con LOGO
                        HStack(spacing: 15) {
                            // --- INIZIO LOGO ---
                            ZStack {
                                // Cerchio di sfondo con gradiente Cyber
                                Circle()
                                    .fill(LinearGradient(colors: [.cyan.opacity(0.3), .blue.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 50, height: 50)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.cyan.opacity(0.5), lineWidth: 1)
                                    )
                                
                                // Icona (Sinapsi/Cervello)
                                // Se vuoi usare una tua immagine PNG, commenta la riga sotto e usa:
                                // Image("IlTuoLogo").resizable().aspectRatio(contentMode: .fit).frame(width: 30)
                                Image(systemName: "brain.head.profile")
                                    .font(.system(size: 26))
                                    .foregroundColor(.cyan)
                                    .shadow(color: .cyan, radius: 3)
                            }
                            // --- FINE LOGO ---

                            Text("SYNAPSE")
                                .font(.system(size: 30, weight: .heavy, design: .monospaced))
                                .tracking(2)
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            // Pallino di stato (spostato a destra)
                            Circle()
                                .fill(engine.isConnected ? Color.green : (engine.connectionStatus.contains("SCAN") ? Color.orange : Color.red))
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
                                    
                                    Text(engine.connectionStatus)
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(getStatusColor())
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.5)
                                    
                                    Text(engine.isConnected ? "Target: Synapse Dongle" : "UUID Filter Active")
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
                                        .foregroundColor(getButtonColor())
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
    
    // Helper colors
    func getStatusColor() -> Color {
        if engine.isConnected { return .green }
        if engine.connectionStatus.contains("SCAN") { return .orange }
        return .gray
    }
    
    func getButtonColor() -> Color {
        if engine.isConnected { return .yellow }
        if engine.connectionStatus.contains("SCAN") { return .orange.opacity(0.5) }
        return .gray.opacity(0.3)
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

// --- 3. INPUT ---
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
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(white: 0.05))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        print("[MOUSE LOGIC] Invio coordinate delta: \(value.translation)")
                                        // Qui implementeremo l'invio binario delle coordinate
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

// --- 4. MAGIC ---
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
