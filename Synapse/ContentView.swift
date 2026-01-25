import SwiftUI
import UIKit
import CoreBluetooth
import CoreMotion

// --- COSTANTI ---
let SYNAPSE_SERVICE_UUID = CBUUID(string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")
let SYNAPSE_CHAR_UUID    = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a8")

// --- ENGINE ---
class SynapseEngine: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    @Published var isConnected = false
    @Published var connectionStatus = "DISCONNECTED"
    @Published var logs: [String] = ["System Ready."]
    @Published var rssiLevel: Int = 0
    
    private var centralManager: CBCentralManager!
    private var synapsePeripheral: CBPeripheral?
    private var inputCharacteristic: CBCharacteristic?
    
    // Sensori
    private let motionManager = CMMotionManager()
    @Published var isGyroActive = false
    @Published var isProximityActive = false
    private var rssiTimer: Timer?
    
    // Variabili per fluidità Gyro (Accumulatori)
    private var gyroResidualX: Double = 0.0
    private var gyroResidualY: Double = 0.0
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func log(_ msg: String) {
        print(msg)
        DispatchQueue.main.async {
            let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            self.logs.insert("[\(time)] \(msg)", at: 0)
            if self.logs.count > 50 { self.logs.removeLast() }
        }
    }
    
    // --- CONNESSIONE ---
    func toggleConnection() { isConnected ? disconnect() : startScanning() }
    
    func startScanning() {
        guard centralManager.state == .poweredOn else { log("❌ BT Off"); return }
        connectionStatus = "SCANNING..."
        log("🔍 Scanning...")
        centralManager.scanForPeripherals(withServices: [SYNAPSE_SERVICE_UUID], options: nil)
    }
    
    func disconnect() {
        if let p = synapsePeripheral { centralManager.cancelPeripheralConnection(p) }
    }
    
    // --- INVIO DATI ---
    func sendKey(_ key: String) {
        guard isConnected, let char = inputCharacteristic, let p = synapsePeripheral else { return }
        if let data = key.data(using: .utf8) {
            p.writeValue(data, for: char, type: .withoutResponse)
            log("📤 \(key)")
        }
    }
    
    func sendMouseMove(x: Int, y: Int) {
        if x == 0 && y == 0 { return }
        sendKey("MOVE:\(x):\(y)")
    }
    
    func sendClick(type: String) { sendKey("CLICK:\(type)") }
    
    // --- MAGIC FEATURES ---
    
    // 1. Gyro Mouse (Fixato e Potenziato)
    func toggleGyro(active: Bool) {
        isGyroActive = active
        if active {
            log("🌀 Gyro ON"); startGyro()
        } else {
            log("🛑 Gyro OFF"); stopGyro()
        }
    }
    
    private func startGyro() {
        guard motionManager.isDeviceMotionAvailable else { log("⚠️ No Gyro Sensor"); return }
        
        // Aumentiamo frequenza aggiornamento per fluidità (60Hz)
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] (data, error) in
            guard let self = self, let data = data else { return }
            
            // Sensibilità aumentata
            let sensitivity: Double = 40.0
            
            // Calcolo grezzo
            // Nota: RotationRate Y è solitamente l'asse orizzontale (Yaw/Roll) quando si tiene il telefono verticale
            let rawX = data.rotationRate.y * sensitivity
            let rawY = data.rotationRate.x * sensitivity
            
            // Aggiungiamo il residuo precedente (per non perdere i movimenti lenti)
            let totalX = rawX + self.gyroResidualX
            let totalY = rawY + self.gyroResidualY
            
            // Estraiamo la parte intera da inviare
            let sendX = Int(totalX)
            let sendY = Int(totalY)
            
            // Salviamo il resto per il prossimo frame
            self.gyroResidualX = totalX - Double(sendX)
            self.gyroResidualY = totalY - Double(sendY)
            
            if sendX != 0 || sendY != 0 {
                self.sendMouseMove(x: sendX, y: sendY)
            }
        }
    }
    private func stopGyro() {
        motionManager.stopDeviceMotionUpdates()
        gyroResidualX = 0
        gyroResidualY = 0
    }
    
    // 2. Jiggler
    func toggleJiggler(active: Bool) {
        sendKey("CFG:Jiggler:\(active ? 1 : 0)")
        log(active ? "☕️ Jiggler ON" : "💤 Jiggler OFF")
    }
    
    // 3. Proximity Monitor
    func toggleProximity(active: Bool) {
        isProximityActive = active
        if active {
            log("📡 Proximity Monitor ON")
            rssiTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                self.synapsePeripheral?.readRSSI()
            }
        } else {
            log("📡 Proximity Monitor OFF")
            rssiTimer?.invalidate()
            rssiTimer = nil
        }
    }

    // --- DELEGATI ---
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOff { isConnected = false; connectionStatus = "TURN ON BT" }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        centralManager.stopScan()
        synapsePeripheral = peripheral
        synapsePeripheral?.delegate = self
        centralManager.connect(peripheral, options: nil)
        connectionStatus = "CONNECTING..."
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        connectionStatus = "CONNECTED"
        log("✅ Connected")
        peripheral.discoverServices([SYNAPSE_SERVICE_UUID])
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false; connectionStatus = "DISCONNECTED"; stopGyro(); rssiTimer?.invalidate()
        log("❌ Disconnected")
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            if service.uuid == SYNAPSE_SERVICE_UUID {
                peripheral.discoverCharacteristics([SYNAPSE_CHAR_UUID], for: service)
            }
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for char in characteristics {
            if char.uuid == SYNAPSE_CHAR_UUID {
                inputCharacteristic = char
                log("🚀 Ready")
            }
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        rssiLevel = RSSI.intValue
        if isProximityActive && rssiLevel < -85 {
            log("🔒 Utente lontano (\(rssiLevel)). Blocco PC.")
            sendKey("KEY:WIN+L")
            toggleProximity(active: false)
        }
    }
}

// --- UI ---
struct ContentView: View {
    @StateObject var engine = SynapseEngine()
    
    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1.0)
        UITabBar.appearance().standardAppearance = appearance
        if #available(iOS 15.0, *) { UITabBar.appearance().scrollEdgeAppearance = appearance }
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
            SettingsView(engine: engine)
                .tabItem { Label("Core", systemImage: "cpu") }
        }
        .preferredColorScheme(.dark)
        .accentColor(Color(red: 0.0, green: 0.85, blue: 0.95))
    }
}

struct DashboardView: View {
    @ObservedObject var engine: SynapseEngine
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                ScrollView {
                    VStack(spacing: 25) {
                        HStack(spacing: 15) {
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(colors: [.cyan.opacity(0.3), .blue.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 50, height: 50)
                                    .overlay(Circle().stroke(Color.cyan.opacity(0.5), lineWidth: 1))
                                Image(systemName: "brain.head.profile").font(.system(size: 26)).foregroundColor(.cyan).shadow(color: .cyan, radius: 3)
                            }
                            Text("SYNAPSE").font(.system(size: 30, weight: .heavy, design: .monospaced)).tracking(2).foregroundColor(.white)
                            Spacer()
                            Circle().fill(engine.isConnected ? Color.green : Color.red).frame(width: 10, height: 10).shadow(radius: 5)
                        }.padding(.horizontal).padding(.top, 10)
                        
                        ZStack {
                            RoundedRectangle(cornerRadius: 20).fill(Color(white: 0.1)).overlay(RoundedRectangle(cornerRadius: 20).stroke(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("STATUS LINK").font(.caption2).foregroundColor(.gray)
                                    Text(engine.connectionStatus).font(.title2).fontWeight(.bold).foregroundColor(engine.isConnected ? .green : .gray)
                                    Text(engine.isConnected ? "Target: Synapse Dongle" : "Ready").font(.caption).foregroundColor(.white.opacity(0.7))
                                }
                                Spacer()
                                Button(action: { withAnimation { engine.toggleConnection() } }) {
                                    Image(systemName: "bolt.horizontal.circle.fill").font(.system(size: 40)).foregroundColor(engine.isConnected ? .yellow : .gray.opacity(0.3))
                                }
                            }.padding(20)
                        }.frame(height: 120).padding(.horizontal)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                            SynapseWidget(icon: "lock.shield.fill", title: "Lock PC", color: .orange, action: { engine.sendKey("KEY:WIN+L") })
                            SynapseWidget(icon: "play.rectangle.fill", title: "Media Play", color: .pink, action: { engine.sendKey("MEDIA:PLAY") })
                            SynapseWidget(icon: "waveform.path.ecg", title: "Jiggler", color: .green, action: { engine.toggleJiggler(active: true) })
                            SynapseWidget(icon: "power", title: "Kill App", color: .red, action: { engine.sendKey("KEY:ALT+F4") })
                        }.padding(.horizontal)
                    }
                }
            }.navigationBarHidden(true)
        }
    }
}

// --- INPUT VIEW (FIX TASTIERA & BACKSPACE) ---
struct InputView: View {
    @ObservedObject var engine: SynapseEngine
    @State private var inputMode = 0
    @State private var lastDragLocation: CGPoint? = nil
    
    // BACKSPACE FIX: Inizializziamo con uno spazio
    @State private var hiddenText: String = " "
    @FocusState private var isKeyboardFocused: Bool
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            VStack {
                Picker("Mode", selection: $inputMode) {
                    Text("KEYBOARD").tag(0)
                    Text("TRACKPAD").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding().background(Color.black)
                
                if inputMode == 0 {
                    Spacer()
                    ZStack {
                        RoundedRectangle(cornerRadius: 15)
                            .fill(Color(white: 0.1))
                            .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                        
                        VStack {
                            Image(systemName: "keyboard").font(.system(size: 60)).foregroundColor(.cyan.opacity(0.6))
                            Text("TAP TO TYPE").font(.headline).fontWeight(.bold).foregroundColor(.white).padding(.top, 10)
                            Text("Keyboard Ready").font(.caption).foregroundColor(.gray)
                        }
                        
                        // TEXTFIELD FIXATO PER BACKSPACE
                        TextField("", text: $hiddenText)
                            .focused($isKeyboardFocused)
                            .accentColor(.clear)
                            .foregroundColor(.clear)
                            .onChange(of: hiddenText) { newValue in
                                // LOGICA BACKSPACE
                                if newValue.isEmpty {
                                    // Se la stringa è vuota, significa che l'utente ha cancellato lo spazio iniziale
                                    engine.sendKey("\u{08}") // Invia codice ASCII Backspace
                                    hiddenText = " " // Resetta subito allo spazio
                                }
                                else if newValue.count > 1 {
                                    // Se c'è più di un carattere, prende l'ultimo inserito
                                    if let lastChar = newValue.last {
                                        engine.sendKey(String(lastChar))
                                    }
                                    hiddenText = " " // Resetta allo spazio
                                }
                            }
                    }
                    .frame(height: 250)
                    .padding()
                    .onTapGesture {
                        // Assicurati che ci sia sempre lo spazio quando apri la tastiera
                        if hiddenText.isEmpty { hiddenText = " " }
                        isKeyboardFocused = true
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 15) {
                        CyberButton(label: "ESC", action: { engine.sendKey("KEY:ESC") })
                        CyberButton(label: "TAB", action: { engine.sendKey("KEY:TAB") })
                        CyberButton(label: "WIN", action: { engine.sendKey("KEY:WIN+L") })
                        CyberButton(label: "ENTER", color: .green, action: { engine.sendKey("KEY:ENTER") })
                    }.padding()
                    
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 15)
                            .fill(Color(white: 0.08))
                            .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.cyan.opacity(0.3), lineWidth: 1))
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let current = value.location
                                        if let last = self.lastDragLocation {
                                            let dx = Int((current.x - last.x) * 1.5)
                                            let dy = Int((current.y - last.y) * 1.5)
                                            engine.sendMouseMove(x: dx, y: dy)
                                        }
                                        self.lastDragLocation = current
                                    }
                                    .onEnded { _ in self.lastDragLocation = nil }
                            )
                        VStack {
                            Image(systemName: "hand.draw.fill").font(.largeTitle).foregroundColor(.cyan.opacity(0.1))
                            Text("TOUCH SURFACE").font(.caption2).foregroundColor(.gray.opacity(0.5)).padding(.top, 5)
                        }
                    }.padding()
                    HStack(spacing: 20) {
                        CyberButton(label: "L-CLICK", color: .gray, action: { engine.sendClick(type: "LEFT") })
                        CyberButton(label: "R-CLICK", color: .gray, action: { engine.sendClick(type: "RIGHT") })
                    }.padding(.horizontal).padding(.bottom)
                }
            }
        }
    }
}

// --- MAGIC VIEW ---
struct MagicView: View {
    @ObservedObject var engine: SynapseEngine
    @State private var showGamepad = false
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("MOTION")) {
                    GyroRow(icon: "gyroscope", title: "Gyro Air Mouse", desc: "Tilt to move", engine: engine)
                }
                Section(header: Text("AUTOMATION")) {
                    MagicRow(icon: "waveform.path.ecg", title: "Jiggler Mode", desc: "Anti-Sleep", engine: engine, feature: "Jiggler")
                    MagicRow(icon: "wave.3.right", title: "Proximity Lock", desc: "Auto-lock when far", engine: engine, feature: "Proximity")
                }
                Section(header: Text("GAMEPAD")) {
                    Button(action: { showGamepad = true }) {
                        HStack {
                            Image(systemName: "gamecontroller.fill").foregroundColor(.orange)
                            Text("Open Gamepad").foregroundColor(.white)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundColor(.gray)
                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle()).navigationTitle("Magic")
            .sheet(isPresented: $showGamepad) { GamepadView(engine: engine) }
        }
    }
}

struct GamepadView: View {
    @ObservedObject var engine: SynapseEngine
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            VStack {
                HStack {
                    Button("Close") { presentationMode.wrappedValue.dismiss() }
                        .foregroundColor(.gray)
                    Spacer()
                }.padding()
                
                Spacer()
                
                HStack(spacing: 40) {
                    VStack {
                        CyberButton(label: "UP", action: { engine.sendKey("KEY:W") }).frame(width: 60)
                        HStack {
                            CyberButton(label: "L", action: { engine.sendKey("KEY:A") }).frame(width: 60)
                            CyberButton(label: "R", action: { engine.sendKey("KEY:D") }).frame(width: 60)
                        }
                        CyberButton(label: "DN", action: { engine.sendKey("KEY:S") }).frame(width: 60)
                    }
                    VStack(spacing: 10) {
                        HStack {
                            Spacer()
                            CyberButton(label: "Y", color: .yellow, action: { engine.sendKey("KEY:Y") }).frame(width: 60)
                            Spacer()
                        }
                        HStack {
                            CyberButton(label: "X", color: .blue, action: { engine.sendKey("KEY:X") }).frame(width: 60)
                            Spacer()
                            CyberButton(label: "B", color: .red, action: { engine.sendKey("KEY:B") }).frame(width: 60)
                        }
                        HStack {
                            Spacer()
                            CyberButton(label: "A", color: .green, action: { engine.sendKey("KEY:A") }).frame(width: 60)
                            Spacer()
                        }
                    }
                }
                Spacer()
            }
        }
    }
}

// --- DECK & SETTINGS ---
struct DeckView: View {
    @ObservedObject var engine: SynapseEngine
    let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 15) {
                    ForEach(1...12, id: \.self) { index in
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            if index == 1 { engine.sendKey("MEDIA:VOL_UP") }
                            else if index == 2 { engine.sendKey("MEDIA:VOL_DN") }
                            else { engine.sendKey("KEY:M\(index)") }
                        }) {
                            VStack {
                                Image(systemName: "command").font(.title2).foregroundColor(.white)
                                Text("M\(index)").font(.caption2).fontWeight(.bold).foregroundColor(.gray)
                            }
                            .frame(height: 85).frame(maxWidth: .infinity).background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.12)))
                        }
                    }
                }
                .padding()
            }.navigationTitle("Macro Deck")
        }
    }
}

struct SettingsView: View {
    @ObservedObject var engine: SynapseEngine
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("DEVICE INFO")) {
                    HStack { Text("Model"); Spacer(); Text("Synapse v1.0").foregroundColor(.gray) }
                }
                Section(header: Text("DEBUG CONSOLE")) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(engine.logs, id: \.self) { log in
                                Text(log).font(.system(size: 10, design: .monospaced)).foregroundColor(.green)
                            }
                        }
                    }.frame(height: 150).background(Color.black)
                }
                Section(header: Text("CREDITS")) {
                    VStack(alignment: .leading) {
                        Text("Developed by Singh Probjot").font(.headline)
                        Link("View Repo on GitHub", destination: URL(string: "https://github.com/SinghProbjot/Synapse")!).foregroundColor(.cyan)
                    }
                }
            }.listStyle(InsetGroupedListStyle()).navigationTitle("Core System")
        }
    }
}

// --- COMPONENTI ---
struct GyroRow: View {
    let icon: String; let title: String; let desc: String; @ObservedObject var engine: SynapseEngine; @State private var isOn = false
    var body: some View { HStack { Image(systemName: icon).foregroundColor(.cyan); VStack(alignment: .leading) { Text(title).foregroundColor(.white); Text(desc).font(.caption).foregroundColor(.gray) }; Spacer(); Toggle("", isOn: $isOn).onChange(of: isOn) { val in engine.toggleGyro(active: val) } } }
}
struct MagicRow: View {
    let icon: String; let title: String; let desc: String; @ObservedObject var engine: SynapseEngine; let feature: String; @State private var isOn = false
    var body: some View { HStack { Image(systemName: icon).foregroundColor(.green); VStack(alignment: .leading) { Text(title).foregroundColor(.white); Text(desc).font(.caption).foregroundColor(.gray) }; Spacer(); Toggle("", isOn: $isOn).onChange(of: isOn) { val in if feature == "Jiggler" { engine.toggleJiggler(active: val) } else if feature == "Proximity" { engine.toggleProximity(active: val) } } } }
}
struct SynapseWidget: View {
    let icon: String; let title: String; let color: Color; let action: () -> Void
    var body: some View { Button(action: { UIImpactFeedbackGenerator(style: .medium).impactOccurred(); action() }) { VStack { Circle().fill(color.opacity(0.15)).frame(width: 50, height: 50).overlay(Image(systemName: icon).font(.system(size: 22)).foregroundColor(color)).padding(.bottom, 8); Text(title).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundColor(.white.opacity(0.9)) }.frame(maxWidth: .infinity).frame(height: 110).background(Color(white: 0.12)).cornerRadius(18) } }
}
struct CyberButton: View {
    let label: String; var color: Color = .cyan; var action: () -> Void
    var body: some View { Button(action: { let gen = UIImpactFeedbackGenerator(style: .light); gen.impactOccurred(); action() }) { Text(label).font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 55).background(color.opacity(0.15)).cornerRadius(12).overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.5), lineWidth: 1)) } }
}

struct ContentView_Previews: PreviewProvider { static var previews: some View { ContentView() } }
