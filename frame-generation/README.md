# Frame generation on ArcaneMP 1.15.1: what breaks, measured

ArcaneMP 1.15.1 switches frame generation off at every start because it "crashes the ArcaneMP overlay". These tests show what happens when it stays on, for every frame generation route the game or the driver offers. None of them works. This page has the results, the errors and what we think the cause is. The logs and crash report extracts are in the folders next to it.

Tested 2026-11-24 on ArcaneMP 1.15.1 (b8ce055), Hogwarts Legacy Steam build 2153883, RTX 5060 Ti, driver 621.24, Ryzen 9 5900XT, Windows 11.

## How the tests were run

- No ArcaneMP file was modified.
- The launcher's guard removes the line `r.ChosenFrameGenProvider=...` from the ArcaneMP profile's `GameUserSettings.ini` at every start. For these runs the frame generation lines were written into that file and the file was set read-only. The launcher then logs `Could not replace ... (error 5); frame generation stays on and the game will likely crash at boot`, and the game starts with frame generation on.
- The frame generation lines for AMD and Intel were copied from what the unmodded game writes when the option is chosen in its menu.
- Each run is one launch. Runs 1 to 7 were started through the Forge launcher, run 8 by starting `ArcaneMPLauncher.exe` directly.

## Results

| Run | Folder | Frame generation | Steam overlay | Outcome |
|---|---|---|---|---|
| - | [00-reference-normal-boot](00-reference-normal-boot) | off | on | Normal boot, for comparison. |
| 1 | [01-nvidia-dlss-frame-generation](01-nvidia-dlss-frame-generation) | NVIDIA DLSS-G x4 | on | Freeze. The log stops right before `DX12 hooks installed`. Process at 0 CPU, 260 of 283 threads in wait reason Suspended. |
| 2 | [01-nvidia-dlss-frame-generation](01-nvidia-dlss-frame-generation) | NVIDIA DLSS-G x4 | off | Hooks install, overlay and web manager start, menu view 1 is created. 1.75 s later: fatal GPU error. |
| 8 | [01-nvidia-dlss-frame-generation](01-nvidia-dlss-frame-generation) | NVIDIA DLSS-G x4, client started directly (no Forge launcher) | off | Same point as run 2, fatal GPU error 1.86 s after the menu view. |
| 3 | [02-nvidia-streamline-provider-only](02-nvidia-streamline-provider-only) | Streamline swapchain provider selected, frame generation mode Off | off | Same error and same stack as run 2, 1.90 s after the menu view. |
| 5 | [03-amd-fsr3-frame-generation](03-amd-fsr3-frame-generation) | AMD FSR 3 x2 | off | Same device removal, 1.41 s after the menu view. |
| 7 | [04-intel-xess-frame-generation](04-intel-xess-frame-generation) | Intel XeSS x2 | off | Different. The overlay never starts, the game renders, the client fails to join and then crashes in its own code. |
| 4 | [05-nvidia-smooth-motion](05-nvidia-smooth-motion) | off in game, NVIDIA Smooth Motion (driver) | on | Access violation inside the Steam overlay. Two launches, identical. |
| 6 | [05-nvidia-smooth-motion](05-nvidia-smooth-motion) | off in game, NVIDIA Smooth Motion (driver) | off | Same device removal as run 5, before the web manager started. |

Settings lines used:

```
run 1, 2, 8   r.ChosenFrameGenProvider=FStreamlineD3D12DXGISwapchainProvider
              FrameGeneration=(Mode=Nvidia_DLSSG,NumFramesInterpolated=3,LocStr="STREAMLINE_DLSSG_MODE_X4")
run 3         r.ChosenFrameGenProvider=FStreamlineD3D12DXGISwapchainProvider
              FrameGeneration=(Mode=Off,NumFramesInterpolated=0,LocStr="Off")
run 5         r.ChosenFrameGenProvider=FSR3SwapchainProvider
              FrameGeneration=(Mode=AMD_FFXFI,NumFramesInterpolated=1,LocStr="AMD_FFXFI_MODE_X2")
run 7         r.ChosenFrameGenProvider=FXeFGDXGISwapChainProvider
              FrameGeneration=(Mode=Intel_XeFG,NumFramesInterpolated=1,LocStr="INTEL_XEFG_MODE_X2")
```

## The errors

Runs 2 and 3, from the game's crash report:

```
LowLevelFatalError [Line: 715] Streamline/DLSSG present failed at
...\StreamlineCore\Source\StreamlineD3D12RHI\Private\StreamlineD3D12RHI.cpp:643
with error DXGI_ERROR_DEVICE_REMOVED with Reason: 887A002B
```

Runs 5 and 6:

```
LowLevelFatalError [Line: 715] pResource->Map(Subresource, pReadRange, ...) failed at
...\D3D12RHI\Private\D3D12RHIPrivate.h:1249
with error DXGI_ERROR_DEVICE_REMOVED with Reason: 887A002B
```

Run 8:

```
LowLevelFatalError [Line: 715] Result failed at .../D3D12RHI/Private/D3D12Viewport.cpp:678 with error 80004004
```

`0x887A002B` is `DXGI_ERROR_ACCESS_DENIED`. The Windows SDK describes it as: "The application is trying to use a resource to which it does not have the required access privileges. This is most commonly caused by writing to a shared resource with read-only access."

Stack on `RHIThread` in runs 2 and 3:

```
KERNELBASE.dll+0xC569A
HogwartsLegacy.exe+0x3A475A1 / +0x3A02870 / +0x3F95579 / +0x25D1B81
sl.dlss_g.dll+0x4A5DF / +0x442DD / +0x47B7D / +0x5458D / +0x54791
sl.interposer.dll+0x2A8EF / +0x2A843
HogwartsLegacy.exe+0x3F9F496 / +0x3F9F2A5 / +0x3FA10E8 ...
```

Client log just before the error (run 3):

```
12:52:36.272 DX12 hooks installed (Present 0x7ffa3d4384c0, ExecuteCommandLists 0x7ff990a8f890)
12:52:37.326 D3D12 device ...; Rendering systems initialized
12:52:37.327 ImGui DX12 pipeline format 24, back buffer format 24
12:52:37.465 Web manager initialized (1920x1080)
12:52:37.480 Created view with id 1; front end entered
12:52:39.375 Unhandled exception 0x00008000 ... on thread 'RHIThread'
```

In a normal boot `Load start: fw://arcanemp/index.html` is logged 86 ms after the view is created. In runs 2, 3, 5 and 8 it is never logged.

Run 4 (Smooth Motion with the Steam overlay): `0xC0000005`, read of address 0, at `gameoverlayrenderer64.dll+0x8192F`, 7 ms after `ImGui DX12 pipeline format 24`. Stack: `gameoverlayrenderer64.dll` (4 frames) <- `ArcaneMPClient.dll+0x2518A3` <- `NvPresent64.dll` (5 frames) <- game.

Run 7 (Intel XeSS): after `DX12 hooks installed` none of `D3D12 device`, `Rendering systems initialized`, `ImGui DX12 pipeline` is logged. The game shows its intro. The client connects, 23 log lines from the server's client scripts contain `Web.createView: web view manager is not available`, the client logs `Failed to start client resources; refusing to join`, and then crashes: `0xC0000005 at ArcaneMPClient.dll+0x719C5E`, faulting write of 0x8D.

## Timing

| Run | `ImGui DX12 pipeline` to error | `Created view with id 1` to error |
|---|---|---|
| 2 | 2.05 s | 1.75 s |
| 3 | 2.05 s | 1.90 s |
| 5 | 2.07 s | 1.41 s |
| 8 | 4.18 s (the web engine took 2.3 s to start) | 1.86 s |
| 6 | 2.02 s | web manager not started |

No display driver or application error event is written to the Windows event logs at any of these times.

## What is established

- A frame generation swapchain provider is enough. Frame generation does not have to be generating frames (run 3).
- It is not specific to one vendor. NVIDIA's and AMD's providers end in the same device removal with the same reason code (runs 2, 3, 5), and so does the driver-level Smooth Motion (run 6).
- The Forge launcher is not a factor. The same binaries started directly fail at the same point (run 8). Launcher, client DLL, loader DLL and web engine are byte-identical in both installs.
- The two hooked addresses are the real system functions: `dxgi.dll+0x84C0` (Present) and `D3D12Core.dll+0x3F890` (ExecuteCommandLists), Windows file version 10.0.26100.9818. The hooks sit underneath the frame generation swapchain.
- The web engine is not required for the failure: run 6 failed before the web manager started.
- When the overlay never starts (run 7), the game renders with frame generation and the device is not removed.
- With the Steam overlay loaded, the failure is different and earlier (runs 1 and 4). Run 1 is a single launch and may be timing.

## What we suspect (inference, not proven)

With a frame generation provider active, the game renders to proxy back buffers and the provider owns the real swapchain and its presentation. An overlay that hooks the real `Present` below that layer, and draws into the real back buffer with a queue or state it captured from `ExecuteCommandLists`, touches a resource the provider is using. That would produce this device removal. The D3D12 debug layer or DRED on a development build, with a provider active, should name the offending call.

Run 1 looks like a different problem: a deadlock while the inline hooks are being installed, with about 280 threads running and another overlay present. We did not capture stacks for it.

## Fix directions (from two independent reviews, not tested by us)

1. Draw the overlay above the swapchain provider instead of below it. Hook the game's own viewport present path early at start-up, when the client resolves its patterns and few threads exist, and render into the back buffer the engine is about to present.
2. Or keep a DXGI-level hook, but take the swapchain and its command queue when the swapchain is created (`IDXGIFactory2::CreateSwapChainForHwnd`, whose first parameter is the direct queue), and use Streamline's documented native-interface route for third-party overlays instead of patching `dxgi.dll` after the renderer is live.
3. Either way, avoid installing inline hooks on `dxgi.dll` and `D3D12Core.dll` late in start-up.

## What is in the folders

- `arcanemp-log.txt`: the mod's own log for that boot. User name, account, addresses, device names and ids are replaced by placeholders. The `[AOB] [trace]` pattern lines and the lines written by the public server's scripts are removed; the first lines of each file say how many.
- `crash-context-extract.txt`: selected fields of the game's `CrashContext.runtime-xml` (crash type, error message, versions, GPU and driver, call stack of the crashed thread, module file names). The full crash reports and the memory dumps are not published, because they hold account and machine identifiers. They can be provided privately.
- Run 1 has no crash report: the process froze and was ended by hand.
