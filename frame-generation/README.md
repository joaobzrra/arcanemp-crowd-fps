# Frame generation on ArcaneMP 1.15.1: test results

ArcaneMP 1.15.1 disables frame generation at every start because frame generation "crashes the ArcaneMP overlay". These tests keep it selected and try every frame generation option in the game (NVIDIA DLSS, AMD FSR 3, Intel XeSS) plus NVIDIA's driver-level Smooth Motion. Every one of them fails with ArcaneMP. This page reports the results, the errors and the suspected cause. The logs and crash report extracts are in the folders linked in the results table.

Tested 2026-11-24 on ArcaneMP 1.15.1 (b8ce055), Hogwarts Legacy Steam build 2153883, RTX 5060 Ti, driver 621.24, Ryzen 9 5900XT, Windows 11.

## How the tests were run

- No ArcaneMP file was modified.
- At every start, `ArcaneMPLauncher.exe` removes the line `r.ChosenFrameGenProvider=...` from the ArcaneMP profile's `GameUserSettings.ini`. For runs 1, 2, 3, 5, 7 and 8 we wrote the frame generation lines listed below into that file and set it read-only. The launcher then logs `Could not replace ... (error 5); frame generation stays on and the game will likely crash at boot`, and the game starts with those lines in effect.
- For runs 4 and 6 the file was left alone (frame generation off in the game) and Smooth Motion was switched on for the game in the NVIDIA app.
- The NVIDIA lines are the ones the Forge launcher's frame generation option writes. The AMD and Intel lines are the ones the unmodded game writes when that option is chosen in its menu.
- Each run is one launch, except run 4, which is two launches with the same result. Runs 1 to 7 were started through the Forge launcher. Run 8 started `ArcaneMPLauncher.exe` directly, from a second install of the same files.
- We did not measure whether extra frames were actually being generated. Every run failed before the overlay started or within seconds of it.

## Results

| Run | Folder | Frame generation | Steam overlay | Outcome |
|---|---|---|---|---|
| - | [00-reference-normal-boot](00-reference-normal-boot) | off | on | Normal boot, for comparison. |
| 1 | [01-nvidia-dlss-frame-generation](01-nvidia-dlss-frame-generation) | NVIDIA DLSS-G x4 | on | Freeze. The log stops before `DX12 hooks installed` appears. CPU usage is 0; 260 of 283 threads have wait reason Suspended. |
| 2 | [01-nvidia-dlss-frame-generation](01-nvidia-dlss-frame-generation) | NVIDIA DLSS-G x4 | off | The hooks install, the overlay and the web manager start, menu view 1 is created. 1.75 s after that: fatal GPU error (device removed, reason 887A002B). |
| 8 | [01-nvidia-dlss-frame-generation](01-nvidia-dlss-frame-generation) | NVIDIA DLSS-G x4, `ArcaneMPLauncher.exe` started directly (no Forge launcher) | off | Same stage as run 2: fatal GPU error 1.86 s after menu view 1 is created. The error code is different (80004004). |
| 3 | [02-nvidia-streamline-provider-only](02-nvidia-streamline-provider-only) | Streamline swapchain provider selected, frame generation mode Off | off | Same error and same stack as run 2, 1.90 s after menu view 1 is created. |
| 5 | [03-amd-fsr3-frame-generation](03-amd-fsr3-frame-generation) | AMD FSR 3 x2 | off | Device removed with the same reason code as runs 2 and 3, 1.41 s after menu view 1 is created. |
| 7 | [04-intel-xess-frame-generation](04-intel-xess-frame-generation) | Intel XeSS x2 | off | The overlay never starts. The game renders, but the client fails to join the server and then crashes in `ArcaneMPClient.dll`. |
| 4 | [05-nvidia-smooth-motion](05-nvidia-smooth-motion) | off in game, NVIDIA Smooth Motion (driver) | on | Access violation inside the Steam overlay (`gameoverlayrenderer64.dll`). Two launches, same result. |
| 6 | [05-nvidia-smooth-motion](05-nvidia-smooth-motion) | off in game, NVIDIA Smooth Motion (driver) | off | Device removed with the same reason code as run 5, before the web manager started. |

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

`0x80004004` is `E_ABORT`. We do not know why run 8 reported this code instead of the device removal of run 2. It was one launch.

Stack on `RHIThread` in runs 2 and 3, crash frame first:

```
KERNELBASE.dll+0xC569A
HogwartsLegacy.exe+0x3A475A1 / +0x3A02870 / +0x3F95579 / +0x25D1B81
sl.dlss_g.dll+0x4A5DF / +0x442DD / +0x47B7D / +0x5458D / +0x54791
sl.interposer.dll+0x2A8EF / +0x2A843
HogwartsLegacy.exe+0x3F9F496 / +0x3F9F2A5 / +0x3FA10E8 ...
```

Client log before the error in run 3, shortened:

```
12:52:36.272 DX12 hooks installed (Present 0x7ffa3d4384c0, ExecuteCommandLists 0x7ff990a8f890)
12:52:37.326 D3D12 device ...; Rendering systems initialized
12:52:37.327 ImGui DX12 pipeline format 24, back buffer format 24
12:52:37.465 Web manager initialized (1920x1080)
12:52:37.480 Created view with id 1; front end entered
12:52:39.375 Unhandled exception 0x00008000 ... on thread 'RHIThread'
```

In a normal boot, `Load start: fw://arcanemp/index.html` is logged 86 ms after the view is created. In runs 2, 3, 5 and 8 it is never logged.

Run 4 (Smooth Motion with the Steam overlay): `0xC0000005`, a read of address 0, at `gameoverlayrenderer64.dll+0x8192F`, 7 ms after `ImGui DX12 pipeline format 24`. Stack, crash frame first: `gameoverlayrenderer64.dll` (4 frames) <- `ArcaneMPClient.dll+0x2518A3` <- `NvPresent64.dll` (5 frames) <- game.

Run 7 (Intel XeSS): after `DX12 hooks installed`, none of `D3D12 device`, `Rendering systems initialized` or `ImGui DX12 pipeline` is logged. The game shows its intro and the client connects to the server. The server's client scripts then produce 23 log lines containing `Web.createView: web view manager is not available`. The client logs `Failed to start client resources; refusing to join`, then crashes: `0xC0000005 at ArcaneMPClient.dll+0x719C5E`, a write to address 0x8D.

## Timing

| Run | From `ImGui DX12 pipeline` to the error | From `Created view with id 1` to the error |
|---|---|---|
| 2 | 2.05 s | 1.75 s |
| 3 | 2.05 s | 1.90 s |
| 5 | 2.07 s | 1.41 s |
| 8 | 4.18 s (2.3 s passed between the ImGui line and `Web manager initialized`) | 1.86 s |
| 6 | 2.02 s | no view: the web manager had not started |

No display driver or application error event was written to the Windows event logs at any of these times.

## What is established

- Selecting a frame generation swapchain provider is enough to cause the failure, even with the frame generation mode set to Off (run 3).
- The failure is not vendor-specific. NVIDIA's and AMD's providers (runs 2, 3, 5) and driver-level Smooth Motion (run 6) all end in a device removal with the same reason code.
- The failure does not need the Forge launcher. The same files started directly fail at the same stage (run 8), with a different error code. `ArcaneMPLauncher.exe`, `ArcaneMPClient.dll`, `FrameworkLoaderData.dll` and `libcef.dll` are byte-identical (SHA-256) in the Forge install and in the second install.
- The two addresses in the client's `DX12 hooks installed` line, which it labels Present and ExecuteCommandLists, resolve to `dxgi.dll+0x84C0` and `D3D12Core.dll+0x3F890`. Both DLLs have file version 10.0.26100.9818. The hooks are on the system functions themselves.
- In run 4 the driver's Smooth Motion module calls into the ArcaneMP hook, which calls into the Steam overlay: `NvPresent64.dll` -> `ArcaneMPClient.dll` -> `gameoverlayrenderer64.dll`.
- Run 6 failed before `Web manager initialized` was logged.
- In run 7 the overlay never started, the game rendered with the XeSS provider selected, and the device was not removed.
- With the Steam overlay loaded, the failures are different and happen earlier (runs 1 and 4). Run 1 was tested once.

## What we suspect (inference, not proven)

- With a frame generation provider active, the game renders to proxy back buffers, and the provider owns the real swapchain and presents it. The overlay hooks the real `Present`, below the provider, and draws into the real back buffer using a command queue it saw in `ExecuteCommandLists`. It would then be using a resource that the provider is using. This could explain the device removal.
- Because run 6 failed before the web manager started, the overlay's ImGui/DX12 drawing is the more likely trigger, not the web views.
- Run 1 may be a different problem: a deadlock while the inline hooks are installed, with about 280 threads in the process and another overlay loaded. It may depend on timing. We did not capture stacks for it.
- The D3D12 debug layer, on a development build with a provider selected, may identify the offending call.

## Fix directions (suggestions, not tested by us)

1. Draw the overlay above the swapchain provider instead of below it. Hook the game's own viewport present path early at start-up, when the client resolves its patterns and few threads exist. Render into the back buffer the engine is about to present. This is the only direction here that would cover all the cases tested.
2. Or keep a DXGI-level hook. Capture the swapchain and its command queue when the swapchain is created (`IDXGIFactory2::CreateSwapChainForHwnd`, whose first parameter is the direct queue). For NVIDIA's in-game frame generation, use Streamline's documented native-interface route for third-party overlays instead of patching `dxgi.dll` after the renderer has started. This route does not cover FSR 3, XeSS or Smooth Motion.
3. Either way, avoid installing inline hooks on `dxgi.dll` and `D3D12Core.dll` late in start-up.

## What is in the folders

- `arcanemp-log.txt`: the mod's log for that boot. User name, account, IP addresses, device names and ids are replaced by placeholders. The `[AOB] [trace]` pattern lines and the lines written by the public server's scripts are removed. Each file starts with the number of lines removed.
- `crash-context-extract.txt`: selected fields of the game's `CrashContext.runtime-xml` (crash type, error message, versions, GPU and driver, call stack of the crashed thread, module file names). The full crash reports and the memory dumps hold account and machine identifiers, so they are not published. We can provide them privately.
- Run 1 has no crash report: the process froze and was ended by hand.
