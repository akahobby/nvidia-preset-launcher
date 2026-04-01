## NVIDIA Preset Launcher

Simple NVIDIA Profile Inspector presets for common RTX GPU generations, plus a DLSS-MFG preset for RTX 50‑series and a “no preset” safety option.

The launcher is a single `.bat` file that:

- Auto‑elevates to Administrator.
- Downloads the selected preset PowerShell script from this repo.
- Ensures NVIDIA Profile Inspector is available.
- Imports a `.nip` profile into the driver.
- Optionally toggles legacy sharpen and opens NVIDIA Control Panel.

---

## Requirements

- Windows 10/11
- NVIDIA GPU + drivers
- PowerShell
- Internet access (for downloading the preset scripts and Inspector)
- NVIDIA Control Panel installed

You do **not** need to download NVIDIA Profile Inspector manually – the scripts will fetch `Inspector.exe` into your `Documents\NvidiaProfileInspector` folder if it’s missing.

---

## Presets

All presets work via NVIDIA Profile Inspector profiles (embedded `.nip` XML):

- **Preset 50 – RTX 50 Series (Dynamic MFG)**  
  Script: `Nvidia-Preset-50.ps1`  
  - Target: RTX 50‑series only.
  - Enables **Dynamic DLSS Multi‑Frame Generation (up to 6x)**.
  - Enables shader cache + **Pre‑Compile Shader Options** baseline for smoother shader compilation.
  - Keeps DLSS model/preset behavior out of the game’s way – intended as a baseline, not a forced DLSS preset.

- **Preset M – RTX 40 Series**  
  Script: `Nvidia-Preset-M.ps1`  
  - Tune for modern 40‑series cards.
  - Adjusts latency, VRR, anisotropic filtering, and DLSS‑SR override settings.

- **Preset K – RTX 20 / 30 Series**  
  Script: `Nvidia-Preset-K.ps1`  
  - Similar philosophy as M, but tuned for older RTX generations.

- **Preset NP – No DLSS preset**  
  Script: `Nvidia-Preset-NP.ps1`  
  - “Safe” profile without any forced DLSS preset behavior.
  - Good for titles where driver‑side DLSS overrides can cause issues (black screens, weird scaling, etc.).
  - Keeps your general quality / latency / VRR tweaks, but lets the game fully own DLSS.

Each PowerShell preset offers:

- `1) NVIDIA Settings: On (Recommended)` – apply the custom profile.
- `2) NVIDIA Settings: Default` – restore a clean base profile.

---

## How to Use

1. **Download** `Nvidia_Preset_Launcher.bat` (and optionally place it next to your presets locally).
2. **Run as Administrator** (the script will auto‑prompt if not).
3. In the menu, pick your option:

   - `[1] Preset 50  - RTX 50 Series (Dynamic MFG)`
   - `[2] Preset M   - RTX 40 Series`
   - `[3] Preset K   - RTX 20 / 30 Series`
   - `[4] Preset NP  - No DLSS preset`
   - `[5] Exit`

4. The launcher will:
   - Download the corresponding `Nvidia-Preset-*.ps1` from GitHub.
   - Ensure `Inspector.exe` exists (download if needed).
   - Import the `.nip` profile into the driver.
   - Optionally open NVIDIA Control Panel so you can visually confirm the changes.

---

## Notes / Safety

- If you run a preset on a GPU that doesn’t support some flags (e.g. DLSS‑MFG on non‑50 GPUs), the driver simply **ignores unsupported bits** and applies the rest.
- If a game misbehaves with frame‑gen or DLSS overrides, run **Preset NP** and choose `2) NVIDIA Settings: Default` inside it to reset the profile.
- All changes are driver‑side; you can always revert by:
  - Using a **Default** option in any preset script, or
  - Resetting profiles in NVIDIA Profile Inspector / NVIDIA Control Panel.

---

## Troubleshooting

- **Nothing seems to change**
  - Make sure you ran the launcher as Administrator.
  - Confirm the correct profile is active in NVIDIA Profile Inspector.
- **Game shows black screen / weird DLSS behavior**
  - Re‑apply **Preset NP** and/or use its **Default** option.
- **Inspector not found**
  - Scripts auto‑download Inspector into `Documents\NvidiaProfileInspector`.  
    Delete and re‑run a preset if you want to force a fresh copy.
