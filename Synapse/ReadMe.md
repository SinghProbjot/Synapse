<p align="center">
  <img src="https://img.shields.io/badge/iOS-16.0%2B-007AFF?style=flat-square&logo=apple&logoColor=white" alt="iOS 16+" />
  <img src="https://img.shields.io/badge/Swift-5.0-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 5.0" />
  <img src="https://img.shields.io/badge/Hardware-ESP32--S3-E7352C?style=flat-square&logo=espressif&logoColor=white" alt="ESP32-S3" />
  <br/>
  <img src="https://img.shields.io/badge/Feature-Universal_Input-blue?style=flat-square" alt="Universal Input" />
  <img src="https://img.shields.io/badge/Feature-Motion_Control-blue?style=flat-square" alt="Motion Control" />
  <img src="https://img.shields.io/badge/Feature-Voice_Bridge-blue?style=flat-square" alt="Voice Bridge" />
  <img src="https://img.shields.io/badge/Feature-Macro_Deck-blue?style=flat-square" alt="Macro Deck" />
  <img src="https://img.shields.io/badge/Protocol-BLE_5.0-green?style=flat-square" alt="BLE 5.0" />
  <img src="https://img.shields.io/badge/Protocol-USB_HID-green?style=flat-square" alt="USB HID" />
</p>

<div align="center">
  <img src="path/to/your/logo_banner.png" alt="Synapse Logo Banner" width="100%">
</div>

# Synapse

**Advanced BLE-to-USB HID Interface System**

Synapse è un ecosistema hardware–software progettato per trasformare dispositivi iOS in periferiche di input universali ad alta precisione. Il sistema agisce come un ponte digitale, permettendo il controllo remoto di qualsiasi dispositivo dotato di porta USB (PC, Server, Smart TV, Console) senza la necessità di installare driver o software lato client.

## Architecture & Infrastructure

Il sistema si basa su un'architettura **Client-Bridge-Host**. L'iPhone agisce come controller intelligente, elaborando gli input (touch, voce, giroscopio) e trasmettendoli via Bluetooth Low Energy (BLE) a un dongle hardware proprietario. Il dongle decodifica i pacchetti e simula segnali USB HID standard verso il dispositivo target.

### Data Flow Diagram

```mermaid
graph LR
    subgraph iOS_Client [Synapse Mobile App]
        A[Touch Interface] --> P[Processor]
        G[Gyroscope/Sensors] --> P
        M[Macro Logic] --> P
        P -- Encrypted BLE Packet --> T[BLE Transmitter]
    end

    subgraph Hardware_Bridge [ESP32-S3 Dongle]
        R[BLE Receiver] --> C[Microcontroller Unit]
        C -- HID Report Descriptor --> U[USB Interface]
    end

    subgraph Target_Host [PC / Server / TV]
        U --> K[Keyboard Driver]
        U --> MS[Mouse Driver]
        U --> MM[Multimedia Driver]
    end
