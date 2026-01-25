#include "USB.h"
#include "USBHIDKeyboard.h"
#include "USBHIDMouse.h"
#include "USBHIDConsumerControl.h"
#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>

// --- UUID SINAPSE ---
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

USBHIDKeyboard Keyboard;
USBHIDMouse Mouse;
USBHIDConsumerControl Consumer;

BLEServer* pServer = NULL;
BLECharacteristic* pCharacteristic = NULL;
bool deviceConnected = false;
bool oldDeviceConnected = false;

// Feature Jiggler
bool jigglerActive = false;
unsigned long lastJiggleTime = 0;
const unsigned long JIGGLE_INTERVAL = 60000; 

class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      Serial.println(">>> CLIENT CONNESSO <<<");
    };

    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      Serial.println(">>> CLIENT DISCONNESSO <<<");
      BLEDevice::startAdvertising(); 
    }
};

void processCommand(String command) {
  // 1. MOVIMENTO MOUSE REALE (Trackpad & Gyro)
  // Formato atteso: "MOVE:10:-5"
  if (command.startsWith("MOVE:")) {
    int firstColon = command.indexOf(':');
    int secondColon = command.indexOf(':', firstColon + 1);
    
    if (secondColon != -1) {
      String xStr = command.substring(firstColon + 1, secondColon);
      String yStr = command.substring(secondColon + 1);
      
      // Conversione Stringa -> Intero
      int x = xStr.toInt();
      int y = yStr.toInt();
      
      Mouse.move(x, y);
    }
    return;
  }

  // 2. CLICK MOUSE
  if (command == "CLICK:LEFT")  Mouse.click(MOUSE_LEFT);
  else if (command == "CLICK:RIGHT") Mouse.click(MOUSE_RIGHT);

  // 3. MEDIA CONTROL
  else if (command == "MEDIA:VOL_UP") Consumer.press(CONSUMER_CONTROL_VOLUME_INCREMENT);
  else if (command == "MEDIA:VOL_DN") Consumer.press(CONSUMER_CONTROL_VOLUME_DECREMENT);
  else if (command == "MEDIA:MUTE")   Consumer.press(CONSUMER_CONTROL_MUTE);
  else if (command == "MEDIA:PLAY")   Consumer.press(CONSUMER_CONTROL_PLAY_PAUSE);
  
  // 4. TASTI SPECIALI (Macro e Navigazione)
  else if (command == "KEY:ESC")   { Keyboard.press(KEY_ESC); Keyboard.releaseAll(); }
  else if (command == "KEY:TAB")   { Keyboard.press(KEY_TAB); Keyboard.releaseAll(); }
  else if (command == "KEY:ENTER") { Keyboard.press(KEY_RETURN); Keyboard.releaseAll(); }
  else if (command == "KEY:WIN+L") { 
    Keyboard.press(KEY_LEFT_GUI); Keyboard.press('l'); delay(100); Keyboard.releaseAll();
  }
  else if (command == "KEY:ALT+F4") {
    Keyboard.press(KEY_LEFT_ALT); Keyboard.press(KEY_F4); delay(100); Keyboard.releaseAll();
  }
  
  // 5. CONFIGURAZIONI MAGIC
  else if (command.startsWith("CFG:Jiggler:")) {
     if (command.indexOf(":1") != -1) jigglerActive = true;
     else jigglerActive = false;
  }

  // 6. SCRITTURA TASTIERA REALE (Lettere singole)
  // Se arriva "a", "b", "C", scrive quel carattere
  else if (command.length() == 1) {
    Keyboard.write(command.charAt(0));
  }
}

class MyCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      String rxValue = pCharacteristic->getValue();
      if (rxValue.length() > 0) {
        processCommand(rxValue);
      }
    }
};

void setup() {
  Serial.begin(115200);
  
  // NOME USB REALE (Cosi il Mac la vede bella)
  USB.productName("Synapse HID");
  USB.manufacturerName("Synapse Labs");
  USB.begin();
  
  Keyboard.begin();
  Mouse.begin();
  Consumer.begin();

  BLEDevice::init("Synapse Dongle");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());
  BLEService *pService = pServer->createService(SERVICE_UUID);
  
  // Abilitiamo PROPERTY_WRITE_NR per velocità massima (fondamentale per il mouse fluido)
  pCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID,
                      BLECharacteristic::PROPERTY_READ   |
                      BLECharacteristic::PROPERTY_WRITE  |
                      BLECharacteristic::PROPERTY_WRITE_NR |
                      BLECharacteristic::PROPERTY_NOTIFY 
                    );
  pCharacteristic->setCallbacks(new MyCallbacks());
  pService->start();
  
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06); 
  BLEDevice::startAdvertising();
  
  Serial.println("SYNAPSE OS v3.0 READY");
}

void loop() {
  // LOGICA JIGGLER
  if (jigglerActive) {
    unsigned long currentMillis = millis();
    if (currentMillis - lastJiggleTime >= JIGGLE_INTERVAL) {
      lastJiggleTime = currentMillis;
      Mouse.move(1, 0); delay(50); Mouse.move(-1, 0);
    }
  }

  // AUTORECONNECT
  if (!deviceConnected && oldDeviceConnected) {
      delay(500); pServer->startAdvertising(); oldDeviceConnected = deviceConnected;
  }
  if (deviceConnected && !oldDeviceConnected) {
      oldDeviceConnected = deviceConnected;
  }
  delay(10); 
}