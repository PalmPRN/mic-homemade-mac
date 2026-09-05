# 🎤 mic-homemade-mac (Ultra-Low Latency)

A lightweight macOS SwiftUI app for real-time microphone passthrough, gain control, and live audio monitoring.  
แอปพลิเคชันส่งสัญญาณเสียงจากไมโครโฟนออกลำโพงสดแบบเรียลไทม์ (Live Passthrough / Monitoring) รองรับการปรับลด Buffer Size เพื่อให้ความหน่วงต่ำที่สุด (Ultra-Low Latency) และไม่มีการบันทึกไฟล์เสียงลงเครื่อง

---

## 📡 Signal Path (สถาปัตยกรรมสัญญาณเสียง)

```text
               macOS CoreAudio
                     │
          ┌──────────▼──────────┐
          │      USB-C Mic      │
          └──────────┬──────────┘
                     │  (Native Sample Rate e.g. 44.1kHz / 48kHz)
                AVAudioEngine
                     │
               ┌─────▼─────┐
               │   Mixer   │
               │           │
               │   Gain    │ 0–200%
               │  Tap RMS  │ Live Meter
               └─────┬─────┘
                     │  (Auto-negotiated Sample Rate)
                Mac Output
                     │
                 Bluetooth / AUX Cable
                     │
                     ▼
               🔊 Marshall Willen
```

---

## 🖥️ หน้าตาโปรแกรม (UI Layout)

```text
┌─────────────────────────────────┐
│       🎤 MIC PASSTHROUGH        │
│                                 │
│ Input                           │
│ USB Microphone             ✓    │
│                                 │
│ Output                          │
│ Marshall Willen            ✓    │
│                                 │
│ Gain                            │
│ ─────────●────────── 100%       │
│                                 │
│ Buffer                          │
│ [ 32 ] [ 64 ] [128] [256]       │
│                                 │
│       🔴 START PASSTHROUGH      │
│                                 │
│        LIVE • NO RECORDING      │
└─────────────────────────────────┘
```

---

## ⚡ วิธีลด Delay ให้เหลือน้อยที่สุด (สำคัญมาก!)

### 1. ⚠️ จุดตาย: อย่าตั้ง Input เป็นลำโพง Bluetooth (Willen)
- เมื่อ macOS เลือกอุปกรณ์ Bluetooth เป็นทั้ง Input (ไมค์) และ Output (ลำโพง) พร้อมกัน ระบบจะลดระดับโปรไฟล์สัญญาณลงเป็น **HFP/SCO (Hands-Free Profile 16kHz)** ส่งผลให้:
  1. เสียงแตก/ทึบเหมือนคุยโทรศัพท์
  2. เกิด Buffer หน่วงซ้อนทับกัน ทำให้เสียง **Delay หนักมาก (ดีเลย์เป็นวินาที)**
- **วิธีแก้:** 
  1. เปิด **System Settings > Sound** (การตั้งค่าระบบ > เสียง)
  2. ที่แท็บ **Input:** ให้เลือกเป็น **USB Microphone** หรือ **MacBook Microphone** (ห้ามเลือก Willen)
  3. ที่แท็บ **Output:** ให้เลือกเป็น **WILLEN**
  *(ในแอปจะมีแถบส้มเตือนทันทีหากตรวจพบว่ากำลังใช้ Bluetooth เป็น Input)*

---

### 2. ปรับ Buffer Size ในแอปเป็น `[32]` หรือ `[64]`
- ตัวแอปมีปุ่มให้เลือกขนาด Hardware I/O Buffer Frame Size:
  - **`32` samples:** ความหน่วงระดับฮาร์ดแวร์เพียง **~0.7 ms**
  - **`64` samples:** ความหน่วงระดับฮาร์ดแวร์เพียง **~1.3 ms**
  - **`128` samples:** ความหน่วงระดับฮาร์ดแวร์ **~2.7 ms**
  - **`256` samples:** เสถียรภาพสูงสุดสำหรับเครื่องที่โหลดงานหนัก
- แอปจะส่งคำสั่งตรงไปยัง CoreAudio ฮาร์ดแวร์ เพื่อบีบ Buffer ให้เล็กที่สุดทันที

---

### 3. ตัวแปรของ Bluetooth กับสาย AUX 3.5mm
- แม้ CoreAudio ภายในเครื่อง Mac จะประมวลผลเสร็จในเสี้ยว 1 ms แต่ลำโพงไร้สายบลูทูธ (Bluetooth Codec เช่น AAC/SBC) จะมี Cache รับส่งคลื่นวิทยุในตัวประมาณ **100–150 ms**
- **ถ้าต้องการ Zero-Delay แบบ Real-time 100% (พูดปุ๊บ ออกปั๊บทันทีเหมือนไมค์งานเวที/คาราโอเกะ):**
  - แนะนำให้เสียบ **สายสัญญาณ AUX 3.5mm** จาก Mac เข้าลำโพง Marshall Willen ความหน่วง Bluetooth จะหายไปทั้งหมดกลายเป็น 0 ms ทันที!

---

## 🚀 ฟีเจอร์ใหม่ใน v2

1. **Auto Sample Rate Negotiation:** รองรับกรณีไมโครโฟน USB ทำงานที่ 44.1 kHz และลำโพงทำงานที่ 48 kHz โดย `AVAudioEngine` จะแปลงสัญญาณให้อัตโนมัติ ไม่เกิดอาการเสียงกระตุกหรือ Engine Crash
2. **Gain Slider (0% - 200%):** เพิ่ม/ลดความดังของสัญญาณไมโครโฟนสดได้แบบเรียลไทม์
3. **Hardware Device Auto-detection:** ตรวจสอบอุปกรณ์ Input/Output อัตโนมัติ และอัปเดตชื่อทันทีหากมีการเสียบ/ถอดอุปกรณ์ใน macOS
4. **Live Audio Meter:** มีแถบวัดระดับเสียงไมโครโฟนแบบเรียลไทม์ ยืนยันได้ทันทีว่าไมค์จับเสียงได้แล้ว
5. **Dynamic Buffer Switching:** ปรับเปลี่ยน Buffer Size ได้ทันทีระหว่างทำงาน

---

## 🚀 วิธีติดตั้งเป็นแอปใน Mac (/Applications)

คุณสามารถ Build และติดตั้งเป็นแอปในเครื่องได้ง่ายๆ ด้วยคำสั่งเดียว:

```bash
./install_app.sh
```

สคริปต์จะทำการ:
1. Compile เป็น Release binary ที่มีความเร็วสูงสุด
2. บรรจุเป็น `mic-homemade-mac.app` พร้อมตั้งค่า Info.plist และ Entitlements ขอสิทธิ์ไมโครโฟน
3. คัดลอกไปติดตั้งที่ `/Applications/mic-homemade-mac.app` ให้ทันที
4. สามารถกดเปิดจาก **Launchpad**, **Spotlight (⌘ + Space)** หรือโฟลเดอร์ Applications ได้ทันที

---

## 🛠️ วิธีการรันผ่าน Xcode (สำหรับนักพัฒนา)

1. ดับเบิลคลิกเปิด [Package.swift](file:///Users/phiriya.ntmp/Work/zeen-development/MicPassthrough_Xcode/Package.swift) ใน Xcode
2. กด **Run (<kbd>⌘ Cmd</kbd> + <kbd>R</kbd>)**
3. ปรับระดับ Gain และเลือก Buffer `64` หรือ `32`
4. กด **START PASSTHROUGH** และเริ่มพูดได้ทันที!

