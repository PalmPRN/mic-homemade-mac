# mic-homemade-mac

A minimal macOS SwiftUI app for live microphone monitoring.

## Signal path

USB-C Microphone -> macOS Core Audio -> App -> Mac output -> Marshall Willen

This app does NOT record audio to disk.

## Xcode

1. Open `MicPassthrough` in Xcode.
2. Create a new macOS App target if needed, or add these Swift files to a macOS SwiftUI App.
3. Set the app target's Info > Custom macOS Application Target Properties to include:
   `Privacy - Microphone Usage Description`
4. In macOS System Settings > Sound:
   - Input: your USB-C microphone
   - Output: Marshall Willen
5. Run the app and press START.
6. Allow microphone permission when macOS asks.

## Important

Bluetooth output is normally the largest source of audible latency. The app itself does not write recordings, but the exact end-to-end latency depends heavily on the Bluetooth output device and macOS audio route.

If the app reports no input, verify that the USB microphone is selected as the macOS input device.
