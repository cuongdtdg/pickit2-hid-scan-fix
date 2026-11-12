# PICkit 2 modern Windows HID scan fix

An unofficial, minimal compatibility patch for the legacy Microchip PICkit 2
Programmer v2.61 application.

## Symptom

Windows detects PICkit 2 as a healthy HID device (`VID_04D8&PID_0033`), but
the original application displays:

> PICkit 2 not found. Check USB connections and use Tools -> Check Communication to retry.

This can happen on modern Windows computers with many HID interfaces, even
when the USB cable, port, and Windows HID driver are working correctly.

## Root cause

The official v2.61 source stops enumerating after the first 20 HID interfaces.
If PICkit 2 appears later in the Windows HID list, the program never examines
it. The legacy code also opens unrelated HID interfaces while searching, which
can make startup slow or unresponsive on current systems.

## What the patch changes

The patch is deliberately small:

1. Raises the HID enumeration safety cap from 20 to 256.
2. Filters device paths by the requested VID/PID before opening a HID handle.
3. Stops scanning when Windows reports that there are no more HID interfaces.

It does **not** change programming algorithms, target-device data, USB
commands, or PICkit 2 firmware.

## Build

Run Windows PowerShell from this repository:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\build.ps1
```

The script:

- downloads the official PICkit 2 v2.61 PC application source from Microchip;
- verifies the downloaded ZIP with SHA-256;
- applies the minimal HID patch;
- builds the x86 Release configuration with the installed .NET Framework
  MSBuild;
- places the runnable files in `dist\PICkit 2 HID Fix`.

Keep these files together when running the application:

- `PICkit2V2.exe`
- `PK2DeviceFile.dat`
- `PK2V023200.hex`

## Recovering PICkit 2 firmware

Only do this if PICkit 2 is in bootloader mode or the application reports that
it has no operating system.

1. Disconnect PICkit 2 from the target ICSP circuit.
2. Unplug USB.
3. Hold the PICkit 2 pushbutton while reconnecting USB.
4. Release the button after the Busy LED starts blinking.
5. Open the patched application.
6. Select **Tools -> Download PICkit 2 Operating System**.
7. Select `PK2V023200.hex` and do not disconnect USB until programming and
   verification finish.

## Vietnamese summary / Tóm tắt tiếng Việt

Bản PICkit 2 v2.61 gốc chỉ quét 20 thiết bị HID đầu tiên. Trên máy Windows hiện
đại có nhiều chuột, bàn phím và HID khác, PICkit 2 có thể nằm ngoài giới hạn đó
nên phần mềm báo `PICkit 2 not found` dù Device Manager vẫn nhận bình thường.

Bản vá tăng giới hạn quét, lọc đúng `VID_04D8/PID_0033` trước khi mở thiết bị và
dừng khi Windows báo hết danh sách. Bản vá không thay đổi thuật toán nạp PIC.

## Licensing and trademarks

This repository contains only the independently written patch, build script,
and documentation. It does not redistribute Microchip source code, firmware,
device databases, manuals, or compiled binaries. Those files are downloaded
from Microchip by the build script.

The MIT License in this repository applies only to this repository's original
material. It does not grant rights to Microchip material. PICkit and Microchip
are trademarks of Microchip Technology Inc. This project is unofficial and is
not endorsed by Microchip.

Official product page: <https://www.microchip.com/en-us/development-tool/PG164120>
