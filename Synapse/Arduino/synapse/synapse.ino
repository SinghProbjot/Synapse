#include "USB.h"
#include "USBHIDKeyboard.h"
#include "USBHIDMouse.h"
#include "USBHIDConsumerControl.h"
#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>

#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

USBHIDKeyboard Keyboard;
USBHIDMouse Mouse;
USBHIDConsumerControl Consumer;

BLEServer* pServer = NULL;
bool deviceConnected = false;
bool oldDeviceConnected = false;
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

// --- TRADUTTORE LAYOUT ITALIANO ---
// Mappa i caratteri ricevuti dall'App sui tasti fisici US che generano quel simbolo su Windows/Mac IT
void typeItalianChar(char c) {
  switch (c) {
    case '-': 
      // Su Layout IT, il meno (-) si trova dove c'è lo Slash (/) US
      Keyboard.press('/'); 
      break;
    case '_':
      // Underscore è Shift + Meno (quindi Shift + Slash US)
      Keyboard.press(KEY_LEFT_SHIFT); Keyboard.press('/'); 
      break;
    case '!':
      Keyboard.press(KEY_LEFT_SHIFT); Keyboard.press('1');
      break;
    case '?':
      // Su Layout IT, il ? è a destra dello 0.
      // Sulla tastiera US, a destra dello 0 c'è il Meno (-).
      // Quindi premiamo Shift + Meno US.
      Keyboard.press(KEY_LEFT_SHIFT); Keyboard.press('-'); 
      break;
    case '(':
      Keyboard.press(KEY_LEFT_SHIFT); Keyboard.press('8');
      break;
    case ')':
      Keyboard.press(KEY_LEFT_SHIFT); Keyboard.press('9');
      break;
    case ':':
      Keyboard.press(KEY_LEFT_SHIFT); Keyboard.press('.');
      break;
    case ';':
      // Su Layout IT, il ; è Shift + Virgola
      Keyboard.press(KEY_LEFT_SHIFT); Keyboard.press(',');
      break;
    case '@':
      // Chiocciola su IT è AltGr + ò.
      // La ò si trova dove c'è il ; sulla tastiera US.
      Keyboard.press(KEY_RIGHT_ALT); Keyboard.press(';'); 
      break;
    case '#':
      // Cancelletto su IT è AltGr + à.
      // La à si trova dove c'è ' (apice) sulla tastiera US.
      Keyboard.press(KEY_RIGHT_ALT); Keyboard.press('\'');
      break;
    default:
      // Per lettere e numeri standard, inviamo il carattere direttamente
      Keyboard.write(c);
      return;
  }
  delay(10);
  Keyboard.releaseAll();
}

void processCommand(String command) {
  // 1. MOVIMENTO MOUSE
  if (command.startsWith("MOVE:")) {
    int firstColon = command.indexOf(':');
    int secondColon = command.indexOf(':', firstColon + 1);
    if (secondColon != -1) {
      String xStr = command.substring(firstColon + 1, secondColon);
      String yStr = command.substring(secondColon + 1);
      Mouse.move(xStr.toInt(), yStr.toInt());
    }
    return;
  }

  // 2. CLICK & MEDIA & KEY SPECIALI
  if (command == "CLICK:LEFT")  Mouse.click(MOUSE_LEFT);
  else if (command == "CLICK:RIGHT") Mouse.click(MOUSE_RIGHT);
  else if (command == "MEDIA:VOL_UP") Consumer.press(CONSUMER_CONTROL_VOLUME_INCREMENT);
  else if (command == "MEDIA:VOL_DN") Consumer.press(CONSUMER_CONTROL_VOLUME_DECREMENT);
  else if (command == "MEDIA:MUTE")   Consumer.press(CONSUMER_CONTROL_MUTE);
  else if (command == "MEDIA:PLAY")   Consumer.press(CONSUMER_CONTROL_PLAY_PAUSE);
  else if (command == "KEY:ESC")   { Keyboard.press(KEY_ESC); Keyboard.releaseAll(); }
  else if (command == "KEY:TAB")   { Keyboard.press(KEY_TAB); Keyboard.releaseAll(); }
  else if (command == "KEY:ENTER") { Keyboard.press(KEY_RETURN); Keyboard.releaseAll(); }
  else if (command == "KEY:WIN+L") { Keyboard.press(KEY_LEFT_GUI); Keyboard.press('l'); delay(100); Keyboard.releaseAll(); }
  else if (command == "KEY:ALT+F4") { Keyboard.press(KEY_LEFT_ALT); Keyboard.press(KEY_F4); delay(100); Keyboard.releaseAll(); }
  else if (command.startsWith("CFG:Jiggler:")) {
     if (command.indexOf(":1") != -1) jigglerActive = true; else jigglerActive = false;
  }

  // 3. SCRITTURA TESTO (Con Mappatura Italiana)
  else if (command.length() == 1) {
    char c = command.charAt(0);
    typeItalianChar(c);
  }
}

class MyCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      String rxValue = pCharacteristic->getValue();
      if (rxValue.length() > 0) processCommand(rxValue);
    }
};

void setup() {
  Serial.begin(115200);
  
  USB.productName("Synapse HID IT");
  USB.manufacturerName("Synapse Labs");
  USB.begin();
  
  Keyboard.begin();
  Mouse.begin();
  Consumer.begin();

  BLEDevice::init("Synapse Dongle");
  BLEServer *pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());
  BLEService *pService = pServer->createService(SERVICE_UUID);
  
  BLECharacteristic *pCharacteristic = pService->createCharacteristic(
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
  
  Serial.println("SYNAPSE IT READY");
}

void loop() {
  if (jigglerActive) {
    unsigned long currentMillis = millis();
    if (currentMillis - lastJiggleTime >= JIGGLE_INTERVAL) {
      lastJiggleTime = currentMillis;
      Mouse.move(1, 0); delay(50); Mouse.move(-1, 0);
    }
  }
  if (!deviceConnected && oldDeviceConnected) {
      delay(500); BLEDevice::startAdvertising(); oldDeviceConnected = deviceConnected;
  }
  if (deviceConnected && !oldDeviceConnected) {
      oldDeviceConnected = deviceConnected;
  }
  delay(10); 
}