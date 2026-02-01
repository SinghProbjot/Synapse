import SwiftUI
import UIKit
import CoreBluetooth
import CoreMotion
import AVFoundation

// --- COSTANTI ---
let SYNAPSE_SERVICE_UUID = CBUUID(string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")
let SYNAPSE_CHAR_UUID    = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a8")

// --- ENGINE ---
class SynapseEngine: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    @Published var isConnected = false
    @Published var connectionStatus = "DISCONNECTED"
    @Published var logs: [String] = ["System Ready."]
    @Published var rssiLevel: Int = 0
    
    // STATI FUNZIONALITÀ
    @Published var isJigglerActive = false
    @Published var isGyroActive = false
    @Published var isProximityActive = false
    
    // CONFIGURAZIONI UTENTE (Salvataggio automatico)
    @AppStorage("targetOS") var targetOS: String = "Windows" // "Windows" o "Mac"
    @AppStorage("userEmail") var userEmail: String = ""
    @AppStorage("gyroSensitivity") var gyroSensitivity: Double = 50.0
    @AppStorage("invertGyroX") var invertGyroX: Bool = false
    @AppStorage("invertGyroY") var invertGyroY: Bool = false
    
    private var centralManager: CBCentralManager!
    private var synapsePeripheral: CBPeripheral?
    private var inputCharacteristic: CBCharacteristic?
    
    // Sensori
    private let motionManager = CMMotionManager()
    private var rssiTimer: Timer?
    
    // Variabili tecniche Gyro
    private var gyroResidualX: Double = 0.0
    private var gyroResidualY: Double = 0.0
    private var debugCounter = 0
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func log(_ msg: String) {
        print(msg)
        DispatchQueue.main.async {
            let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            self.logs.insert("[\(time)] \(msg)", at: 0)
            if self.logs.count > 100 { self.logs.removeLast() }
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
    
    // Funzione intelligente per inviare frasi intere (Bulk)
    func sendText(_ text: String) {
        log("📝 Typing bulk text...")
        for (index, char) in text.enumerated() {
            // Piccolo delay tra i caratteri per non intasare il buffer
            DispatchQueue.main.asyncAfter(deadline: .now() + (Double(index) * 0.02)) {
                self.sendKey(String(char))
            }
        }
    }
    
    // Gestione Shortcuts OS-Specifiche
    func sendShortcut(_ action: String) {
        if action == "CLOSE_APP" {
            if targetOS == "Windows" { sendKey("KEY:ALT+F4") }
            else { sendKey("KEY:WIN+Q") } // Su tastiera PC, WIN è Command. Quindi WIN+Q = CMD+Q
        }
        else if action == "LOCK_PC" {
            if targetOS == "Windows" { sendKey("KEY:WIN+L") }
            else {
                // Mac Lock è CTRL+CMD+Q. Firmware attuale supporta solo WIN+L.
                // Usiamo un workaround o mappiamo WIN+L a Lock anche su Mac (via impostazioni sistema Mac)
                sendKey("KEY:WIN+L")
            }
        }
        else if action == "COPY" {
            // Nota: Firmware attuale non ha COPY preimpostato, inviamo combinazione se possibile
            // Per ora placeholder
            log("Copy command sent")
        }
    }
    
    func sendMouseMove(x: Int, y: Int) {
        if x == 0 && y == 0 { return }
        sendKey("MOVE:\(x):\(y)")
    }
    
    func sendClick(type: String) { sendKey("CLICK:\(type)") }
    
    // --- FEATURES ---
    
    func toggleGyro(active: Bool) {
        isGyroActive = active
        if active {
            log("🌀 Gyro ON")
            startGyro()
        } else {
            log("🛑 Gyro OFF")
            stopGyro()
        }
    }
    
    private func startGyro() {
        guard motionManager.isDeviceMotionAvailable else { log("⚠️ No Gyro Sensor"); return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] (data, error) in
            guard let self = self, let data = data else { return }
            let sensitivity = self.gyroSensitivity
            let multX = self.invertGyroX ? -1.0 : 1.0
            let multY = self.invertGyroY ? -1.0 : 1.0
            
            let rawX = data.rotationRate.y * sensitivity * multX
            let rawY = data.rotationRate.x * sensitivity * multY
            
            let totalX = rawX + self.gyroResidualX
            let totalY = rawY + self.gyroResidualY
            
            let sendX = Int(totalX)
            let sendY = Int(totalY)
            
            self.gyroResidualX = totalX - Double(sendX)
            self.gyroResidualY = totalY - Double(sendY)
            
            if sendX != 0 || sendY != 0 {
                self.sendMouseMove(x: sendX, y: sendY)
            }
        }
    }
    private func stopGyro() {
        motionManager.stopDeviceMotionUpdates()
        gyroResidualX = 0; gyroResidualY = 0
    }
    
    func toggleJiggler() {
        isJigglerActive.toggle()
        sendKey("CFG:Jiggler:\(isJigglerActive ? 1 : 0)")
        log(isJigglerActive ? "☕️ Jiggler ACTIVE" : "💤 Jiggler STOPPED")
    }
    
    func toggleProximity(active: Bool) {
        isProximityActive = active
        if active {
            log("📡 Proximity ON")
            rssiTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                self.synapsePeripheral?.readRSSI()
            }
        } else {
            log("📡 Proximity OFF")
            rssiTimer?.invalidate()
        }
    }

    // --- DELEGATI BLE ---
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
        isConnected = false; connectionStatus = "DISCONNECTED"; stopGyro(); rssiTimer?.invalidate(); isJigglerActive = false
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
            sendShortcut("LOCK_PC")
            toggleProximity(active: false)
        }
    }
}

// --- VOLUME LISTENER ---
class VolumeObserver: NSObject, ObservableObject {
    @Published var volume: Float = 0.0
    private var audioSession = AVAudioSession.sharedInstance()
    private var observer: NSKeyValueObservation?
    var onVolumeUp: (() -> Void)?; var onVolumeDown: (() -> Void)?
    override init() {
        super.init()
        do { try audioSession.setCategory(.ambient, options: .mixWithOthers); try audioSession.setActive(true) } catch {}
        volume = audioSession.outputVolume
        observer = audioSession.observe(\.outputVolume) { [weak self] (session, _) in
            guard let self = self else { return }
            let newVol = session.outputVolume
            if newVol > self.volume { self.onVolumeUp?() } else if newVol < self.volume { self.onVolumeDown?() } else { if newVol == 1.0 { self.onVolumeUp?() }; if newVol == 0.0 { self.onVolumeDown?() } }
            self.volume = newVol
        }
    }
    deinit { observer?.invalidate() }
}

// --- UI PRINCIPALE ---
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

// --- DASHBOARD ---
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
                                Circle().fill(LinearGradient(colors: [.cyan.opacity(0.3), .blue.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 50, height: 50).overlay(Circle().stroke(Color.cyan.opacity(0.5), lineWidth: 1))
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
                            SynapseWidget(icon: "lock.shield.fill", title: "Lock PC", color: .orange, action: { engine.sendShortcut("LOCK_PC") })
                            SynapseWidget(icon: "play.rectangle.fill", title: "Media Play", color: .pink, action: { engine.sendKey("MEDIA:PLAY") })
                            
                            // WIDGET JIGGLER CON STATO
                            Button(action: { UIImpactFeedbackGenerator(style: .medium).impactOccurred(); engine.toggleJiggler() }) {
                                VStack {
                                    Circle().fill(engine.isJigglerActive ? Color.green : Color.green.opacity(0.15)).frame(width: 50, height: 50)
                                        .overlay(Image(systemName: "waveform.path.ecg").font(.system(size: 22)).foregroundColor(engine.isJigglerActive ? .white : .green)).padding(.bottom, 8)
                                    Text(engine.isJigglerActive ? "Jiggler ON" : "Jiggler OFF").font(.system(size: 12, weight: .medium, design: .rounded)).foregroundColor(.white.opacity(0.9))
                                }
                                .frame(maxWidth: .infinity).frame(height: 110).background(Color(white: 0.12)).cornerRadius(18)
                                .overlay(RoundedRectangle(cornerRadius: 18).stroke(engine.isJigglerActive ? Color.green : Color.clear, lineWidth: 2))
                            }
                            
                            SynapseWidget(icon: "power", title: "Close App", color: .red, action: { engine.sendShortcut("CLOSE_APP") })
                        }.padding(.horizontal)
                    }
                }
            }.navigationBarHidden(true)
        }
    }
    func getStatusColor() -> Color { return engine.isConnected ? .green : (engine.connectionStatus.contains("SCAN") ? .orange : .gray) }
}

// --- INPUT VIEW (BULK TEXT + TASTIERA + TRACKPAD) ---
struct InputView: View {
    @ObservedObject var engine: SynapseEngine
    @State private var inputMode = 0
    @State private var lastDragLocation: CGPoint? = nil
    @State private var hiddenText: String = " "
    @State private var bulkText: String = "" // Per il testo lungo
    @FocusState private var isKeyboardFocused: Bool
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            VStack {
                Picker("Mode", selection: $inputMode) { Text("KEYBOARD").tag(0); Text("TRACKPAD").tag(1) }
                    .pickerStyle(SegmentedPickerStyle()).padding().background(Color.black)
                
                if inputMode == 0 {
                    // --- MODALITÀ TASTIERA ---
                    ScrollView {
                        VStack(spacing: 20) {
                            
                            // SEZIONE 1: LIVE TYPING
                            ZStack {
                                RoundedRectangle(cornerRadius: 15).fill(Color(white: 0.1)).overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.cyan.opacity(0.3), lineWidth: 1))
                                VStack {
                                    Image(systemName: "keyboard").font(.system(size: 40)).foregroundColor(.cyan.opacity(0.6))
                                    Text("TAP TO TYPE (LIVE)").font(.headline).fontWeight(.bold).foregroundColor(.white)
                                    Text("Layout: ITALIAN").font(.caption).foregroundColor(.gray)
                                }
                                TextField("", text: $hiddenText)
                                    .focused($isKeyboardFocused).accentColor(.clear).foregroundColor(.clear)
                                    .onChange(of: hiddenText) { newValue in
                                        if newValue.isEmpty { engine.sendKey("\u{08}"); hiddenText = " " }
                                        else if newValue.count > 1 { if let lastChar = newValue.last { engine.sendKey(String(lastChar)) }; hiddenText = " " }
                                    }
                            }
                            .frame(height: 120).onTapGesture { if hiddenText.isEmpty { hiddenText = " " }; isKeyboardFocused = true }
                            
                            // SEZIONE 2: BULK TEXT (Testo Lungo)
                            VStack(alignment: .leading) {
                                Text("BULK TEXT ENTRY").font(.caption).fontWeight(.bold).foregroundColor(.gray).padding(.leading)
                                ZStack(alignment: .topLeading) {
                                    RoundedRectangle(cornerRadius: 15).fill(Color(white: 0.15))
                                    if bulkText.isEmpty { Text("Paste long text here...").foregroundColor(.gray).padding(12) }
                                    if #available(iOS 16.0, *) {
                                        TextEditor(text: $bulkText).scrollContentBackground(.hidden).background(Color.clear).foregroundColor(.white).padding(5)
                                    } else {
                                        // Fallback on earlier versions
                                    }
                                }.frame(height: 150)
                                
                                Button(action: {
                                    if !bulkText.isEmpty {
                                        engine.sendText(bulkText)
                                        bulkText = ""
                                        let gen = UINotificationFeedbackGenerator(); gen.notificationOccurred(.success)
                                    }
                                }) {
                                    HStack { Image(systemName: "paperplane.fill"); Text("SEND TEXT") }
                                    .font(.headline).foregroundColor(.black).frame(maxWidth: .infinity).frame(height: 50).background(Color.cyan).cornerRadius(12)
                                }
                            }
                            
                            // TASTI SPECIALI
                            HStack(spacing: 15) {
                                CyberButton(label: "ESC", action: { engine.sendKey("KEY:ESC") })
                                CyberButton(label: "TAB", action: { engine.sendKey("KEY:TAB") })
                                CyberButton(label: "WIN/CMD", action: { engine.sendKey("KEY:WIN+L") }) // Modificare in futuro se serve solo CMD
                                CyberButton(label: "ENTER", color: .green, action: { engine.sendKey("KEY:ENTER") })
                            }
                        }.padding()
                    }
                    
                } else {
                    // --- MODALITÀ TRACKPAD ---
                    ZStack {
                        RoundedRectangle(cornerRadius: 15).fill(Color(white: 0.08)).overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.cyan.opacity(0.3), lineWidth: 1))
                            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                                let current = value.location
                                if let last = self.lastDragLocation {
                                    let dx = Int((current.x - last.x) * 1.5)
                                    let dy = Int((current.y - last.y) * 1.5)
                                    engine.sendMouseMove(x: dx, y: dy)
                                }
                                self.lastDragLocation = current
                            }.onEnded { _ in self.lastDragLocation = nil })
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

// --- DECK VIEW (MACRO SYSTEM + PROFILO) ---
struct DeckView: View {
    @ObservedObject var engine: SynapseEngine
    let columns = [GridItem(.flexible()), GridItem(.flexible())]
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 15) {
                    // Macro 1: Email Utente
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        if !engine.userEmail.isEmpty { engine.sendText(engine.userEmail) }
                        else { engine.log("⚠️ Set email in Settings first") }
                    }) {
                        VStack {
                            Image(systemName: "envelope.fill").font(.title).foregroundColor(.white).padding(.bottom, 5)
                            Text("My Email").font(.caption).fontWeight(.bold).foregroundColor(.white.opacity(0.8))
                        }
                        .frame(height: 100).frame(maxWidth: .infinity).background(Color.blue.opacity(0.2)).cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.blue.opacity(0.5), lineWidth: 1))
                    }
                    
                    // Altre Macro
                    MacroBtn(icon: "lock.fill", title: "Lock PC", color: .orange) { engine.sendShortcut("LOCK_PC") }
                    MacroBtn(icon: "speaker.wave.3.fill", title: "Max Vol", color: .green) { engine.sendKey("MEDIA:VOL_UP"); engine.sendKey("MEDIA:VOL_UP"); engine.sendKey("MEDIA:VOL_UP") }
                    MacroBtn(icon: "speaker.slash.fill", title: "Mute", color: .red) { engine.sendKey("MEDIA:MUTE") }
                    MacroBtn(icon: "xmark.circle.fill", title: "Close App", color: .purple) { engine.sendShortcut("CLOSE_APP") }
                    MacroBtn(icon: "play.pause.circle.fill", title: "Play/Pause", color: .pink) { engine.sendKey("MEDIA:PLAY") }
                    MacroBtn(icon: "doc.on.clipboard", title: "Paste", color: .gray) {
                        // Invia CTRL+V (Win) o CMD+V (Mac)
                        // Nota: il firmware non ha combinazione COPY nativa, ma su Mac CMD+V spesso incolla.
                        // Per ora mandiamo testo di prova
                        engine.log("Shortcut Paste sent")
                    }
                    MacroBtn(icon: "terminal.fill", title: "Terminal", color: .black) { engine.sendText("cmd") }
                }
                .padding()
            }
            .navigationTitle("Macro Deck")
        }
    }
}

// Helper per pulsanti Deck
struct MacroBtn: View {
    let icon: String; let title: String; let color: Color; let action: () -> Void
    var body: some View {
        Button(action: { UIImpactFeedbackGenerator(style: .medium).impactOccurred(); action() }) {
            VStack { Image(systemName: icon).font(.title).foregroundColor(.white).padding(.bottom, 5); Text(title).font(.caption).fontWeight(.bold).foregroundColor(.white.opacity(0.8)) }
            .frame(height: 100).frame(maxWidth: .infinity).background(color.opacity(0.2)).cornerRadius(16).overlay(RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.5), lineWidth: 1))
        }
    }
}

// --- MAGIC VIEW (TV REMOTE & TOOLS) ---
struct MagicView: View {
    @ObservedObject var engine: SynapseEngine
    @State private var showGamepad = false
    @State private var showGyroController = false
    @State private var showTVRemote = false
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("CONTROLLERS")) {
                    Button(action: { showTVRemote = true }) {
                        HStack { Image(systemName: "tv.fill").foregroundColor(.purple); Text("TV Remote Control").foregroundColor(.white); Spacer(); Image(systemName: "chevron.right").foregroundColor(.gray) }
                    }
                    Button(action: { showGyroController = true }) {
                        HStack { Image(systemName: "gyroscope").foregroundColor(.cyan); Text("Air Mouse Mode").foregroundColor(.white); Spacer(); Image(systemName: "chevron.right").foregroundColor(.gray) }
                    }
                    Button(action: { showGamepad = true }) {
                        HStack { Image(systemName: "gamecontroller.fill").foregroundColor(.orange); Text("Gamepad Mode").foregroundColor(.white); Spacer(); Image(systemName: "chevron.right").foregroundColor(.gray) }
                    }
                }
                Section(header: Text("AUTOMATION")) {
                    // Jiggler con stato visivo
                    HStack {
                        Image(systemName: "waveform.path.ecg").foregroundColor(engine.isJigglerActive ? .green : .gray)
                        VStack(alignment: .leading) { Text("Jiggler Mode").foregroundColor(.white); Text("Status: \(engine.isJigglerActive ? "ON" : "OFF")").font(.caption).foregroundColor(.gray) }
                        Spacer()
                        Toggle("", isOn: $engine.isJigglerActive).onChange(of: engine.isJigglerActive) { _ in engine.toggleJiggler() }
                    }
                    MagicRow(icon: "wave.3.right", title: "Proximity Lock", desc: "Auto-lock when far", engine: engine, feature: "Proximity")
                }
            }
            .listStyle(InsetGroupedListStyle()).navigationTitle("Magic")
            .sheet(isPresented: $showGamepad) { GamepadView(engine: engine) }
            .fullScreenCover(isPresented: $showGyroController) { GyroControllerView(engine: engine) }
            .sheet(isPresented: $showTVRemote) { TVRemoteView(engine: engine) }
        }
    }
}

// --- NUOVA VISTA: TV REMOTE ---
struct TVRemoteView: View {
    @ObservedObject var engine: SynapseEngine
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            VStack(spacing: 30) {
                // Header
                HStack { Button("Close") { presentationMode.wrappedValue.dismiss() }.foregroundColor(.gray); Spacer() }.padding()
                
                // Power
                Button(action: { engine.sendKey("KEY:ALT+F4") }) { // Molte TV usano questo o Power dedicato, per ora usiamo AltF4 o inviamo nulla
                    Image(systemName: "power").font(.largeTitle).foregroundColor(.red).padding(20)
                        .background(Color.white.opacity(0.1)).clipShape(Circle())
                }
                
                Spacer()
                
                // D-Pad Navigazione
                VStack(spacing: 5) {
                    Button(action: { engine.sendKey("KEY:W") }) { Image(systemName: "chevron.up").padding(20).background(Color.gray.opacity(0.3)).cornerRadius(10) }
                    HStack(spacing: 40) {
                        Button(action: { engine.sendKey("KEY:A") }) { Image(systemName: "chevron.left").padding(20).background(Color.gray.opacity(0.3)).cornerRadius(10) }
                        Button(action: { engine.sendKey("KEY:ENTER") }) { Text("OK").fontWeight(.bold).padding(20).background(Color.white.opacity(0.2)).clipShape(Circle()) }
                        Button(action: { engine.sendKey("KEY:D") }) { Image(systemName: "chevron.right").padding(20).background(Color.gray.opacity(0.3)).cornerRadius(10) }
                    }
                    Button(action: { engine.sendKey("KEY:S") }) { Image(systemName: "chevron.down").padding(20).background(Color.gray.opacity(0.3)).cornerRadius(10) }
                }.foregroundColor(.white)
                
                Spacer()
                
                // Vol / Channel
                HStack(spacing: 60) {
                    VStack {
                        Button(action: { engine.sendKey("MEDIA:VOL_UP") }) { Image(systemName: "plus").frame(width: 60, height: 60).background(Color.gray.opacity(0.2)).cornerRadius(30) }
                        Text("VOL").font(.caption).fontWeight(.bold).foregroundColor(.gray)
                        Button(action: { engine.sendKey("MEDIA:VOL_DN") }) { Image(systemName: "minus").frame(width: 60, height: 60).background(Color.gray.opacity(0.2)).cornerRadius(30) }
                    }
                    VStack {
                        Button(action: { engine.sendKey("MEDIA:NEXT") }) { Image(systemName: "chevron.up").frame(width: 60, height: 60).background(Color.gray.opacity(0.2)).cornerRadius(30) }
                        Text("CH").font(.caption).fontWeight(.bold).foregroundColor(.gray)
                        Button(action: { engine.sendKey("MEDIA:PREV") }) { Image(systemName: "chevron.down").frame(width: 60, height: 60).background(Color.gray.opacity(0.2)).cornerRadius(30) }
                    }
                }.foregroundColor(.white)
                
                Spacer()
                
                // Media Controls
                HStack(spacing: 40) {
                    Button(action: { engine.sendKey("MEDIA:PREV") }) { Image(systemName: "backward.end.fill").font(.title2) }
                    Button(action: { engine.sendKey("MEDIA:PLAY") }) { Image(systemName: "play.pause.fill").font(.largeTitle) }
                    Button(action: { engine.sendKey("MEDIA:NEXT") }) { Image(systemName: "forward.end.fill").font(.title2) }
                }.foregroundColor(.white).padding(.bottom, 40)
            }
        }
    }
}

// --- SETTINGS VIEW (PROFILO & OS) ---
struct SettingsView: View {
    @ObservedObject var engine: SynapseEngine
    
    var body: some View {
        NavigationView {
            List {
                // SEZIONE 1: CONFIGURAZIONE OS
                Section(header: Text("TARGET SYSTEM")) {
                    Picker("Operating System", selection: $engine.targetOS) {
                        Text("Windows").tag("Windows")
                        Text("macOS").tag("Mac")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    Text("Current Mode: \(engine.targetOS)").font(.caption).foregroundColor(.gray)
                }
                
                // SEZIONE 2: PROFILO UTENTE
                Section(header: Text("USER PROFILE")) {
                    TextField("Your Name", text: .constant("")) // Placeholder per future espansioni
                    TextField("Your Email (for Macro)", text: $engine.userEmail)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                }
                
                Section(header: Text("GYRO CALIBRATION")) {
                    VStack(alignment: .leading) {
                        Text("Sensitivity: \(Int(engine.gyroSensitivity))")
                        Slider(value: $engine.gyroSensitivity, in: 10...300, step: 10)
                    }
                    Toggle("Invert Vertical (Y) Axis", isOn: $engine.invertGyroY)
                    Toggle("Invert Horizontal (X) Axis", isOn: $engine.invertGyroX)
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

// --- ALTRE VISTE AUSILIARIE ---
struct GyroControllerView: View {
    @ObservedObject var engine: SynapseEngine
    @Environment(\.presentationMode) var presentationMode
    @StateObject var volObserver = VolumeObserver()
    @State private var isDragging = false
    var body: some View {
        ZStack { Color.black.edgesIgnoringSafeArea(.all); VStack(spacing: 30) { HStack { Button("EXIT") { engine.toggleGyro(active: false); presentationMode.wrappedValue.dismiss() }.font(.headline).foregroundColor(.red).padding(); Spacer(); Text("AIR MOUSE ACTIVE").font(.caption).fontWeight(.bold).foregroundColor(.green).padding() }; Spacer(); Image(systemName: "iphone.radiowaves.left.and.right").font(.system(size: 80)).foregroundColor(.cyan).padding(); Text("Move phone to aim").font(.headline).foregroundColor(.gray); Divider().background(Color.gray).padding(); HStack(spacing: 40) { VStack { Image(systemName: "speaker.plus.fill"); Text("VOL UP").font(.caption2); Text("Left Click").fontWeight(.bold).foregroundColor(.cyan) }; VStack { Image(systemName: "speaker.minus.fill"); Text("VOL DOWN").font(.caption2); Text("Right Click").fontWeight(.bold).foregroundColor(.orange) } }.foregroundColor(.white).padding(); Image(systemName: isDragging ? "hand.draw.fill" : "hand.draw").font(.system(size: 50)).foregroundColor(isDragging ? .white : .cyan).frame(width: 250, height: 120).background(isDragging ? Color.cyan : Color.white.opacity(0.1)).cornerRadius(20).overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.cyan, lineWidth: 2)).gesture(DragGesture(minimumDistance: 0).onChanged { _ in if !isDragging { isDragging = true; engine.log("✊ Dragging (Simulated)") } }.onEnded { _ in isDragging = false; engine.log("✋ Drag Released") }).overlay(Text("HOLD TO DRAG").font(.caption).fontWeight(.bold).offset(y: 40)); Spacer() } }.onAppear { engine.toggleGyro(active: true); volObserver.onVolumeUp = { engine.sendClick(type: "LEFT"); let gen = UIImpactFeedbackGenerator(style: .heavy); gen.impactOccurred() }; volObserver.onVolumeDown = { engine.sendClick(type: "RIGHT"); let gen = UIImpactFeedbackGenerator(style: .medium); gen.impactOccurred() } }.onDisappear { engine.toggleGyro(active: false) }
    }
}
struct GamepadView: View {
    @ObservedObject var engine: SynapseEngine
    @Environment(\.presentationMode) var presentationMode
    var body: some View { ZStack { Color.black.edgesIgnoringSafeArea(.all); VStack { HStack { Button("Close") { presentationMode.wrappedValue.dismiss() }.foregroundColor(.gray); Spacer() }.padding(); Spacer(); HStack(spacing: 40) { VStack { CyberButton(label: "UP", action: { engine.sendKey("KEY:W") }).frame(width: 60); HStack { CyberButton(label: "L", action: { engine.sendKey("KEY:A") }).frame(width: 60); CyberButton(label: "R", action: { engine.sendKey("KEY:D") }).frame(width: 60) }; CyberButton(label: "DN", action: { engine.sendKey("KEY:S") }).frame(width: 60) }; VStack(spacing: 10) { HStack { Spacer(); CyberButton(label: "Y", color: .yellow, action: { engine.sendKey("KEY:Y") }).frame(width: 60); Spacer() }; HStack { CyberButton(label: "X", color: .blue, action: { engine.sendKey("KEY:X") }).frame(width: 60); Spacer(); CyberButton(label: "B", color: .red, action: { engine.sendKey("KEY:B") }).frame(width: 60) }; HStack { Spacer(); CyberButton(label: "A", color: .green, action: { engine.sendKey("KEY:A") }).frame(width: 60); Spacer() } } }; Spacer() } } }
}
struct MagicRow: View {
    let icon: String; let title: String; let desc: String; @ObservedObject var engine: SynapseEngine; let feature: String
    var body: some View { HStack { Image(systemName: icon).foregroundColor(.green); VStack(alignment: .leading) { Text(title).foregroundColor(.white); Text(desc).font(.caption).foregroundColor(.gray) }; Spacer(); if feature == "Proximity" { Toggle("", isOn: $engine.isProximityActive).onChange(of: engine.isProximityActive) { val in engine.toggleProximity(active: val) } } } }
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
