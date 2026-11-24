# Frame generation on ArcaneMP 1.15.1: test results

ArcaneMP 1.15.1 disables frame generation at every start because frame generation "crashes the ArcaneMP overlay". These tests keep it selected and try every frame generation option in the game (NVIDIA DLSS, AMD FSR 3, Intel XeSS) plus NVIDIA's driver-level Smooth Motion. Every one of them fails with ArcaneMP. With the Direct3D 12 debug layer forced on, Windows reports why: a command list that writes to the swap chain's back buffer is executed on a command queue that does not own that buffer, and the device is removed a few milliseconds later. This page reports the results, the errors and what we suspect beyond that. The logs, debug layer output and crash report extracts are in the folders linked in the results table.

Tested 2026-11-24 on ArcaneMP 1.15.1 (b8ce055), Hogwarts Legacy Steam build 2153883, RTX 5060 Ti, driver 621.24, Ryzen 9 5900XT, Windows 11.

## How the tests were run

- No ArcaneMP file was modified.
- At every start, `ArcaneMPLauncher.exe` removes the line `r.ChosenFrameGenProvider=...` from the ArcaneMP profile's `GameUserSettings.ini`. For runs 1, 2, 3, 5, 7 and 8 we wrote the frame generation lines listed below into that file and set it read-only. The launcher then logs `Could not replace ... (error 5); frame generation stays on and the game will likely crash at boot`, and the game starts with those lines in effect.
- For runs 4 and 6 the file was left alone (frame generation off in the game) and Smooth Motion was switched on for the game in the NVIDIA app.
- The NVIDIA lines are the ones the Forge launcher's frame generation option writes. The AMD and Intel lines are the ones the unmodded game writes when that option is chosen in its menu.
- Each run is one launch, except run 4, which is two launches with the same result. Runs 1 to 7 were started through the Forge launcher. Run 8 started `ArcaneMPLauncher.exe` directly, from a second install of the same files.
- Runs 9, 10 and 11 used the second install with the Direct3D 12 debug layer forced on from outside the game: `d3dconfig apps --add hogwartslegacy.exe`, `d3dconfig apps --add arcanemplauncher.exe`, `d3dconfig debug-layer debug-layer-mode=force-on` (Windows Graphics Tools, same file version as `D3D12Core.dll`). The debug layer's messages were captured from the process's Win32 debug output. The Steam overlay was loaded in these three runs.
- We did not measure whether extra frames were actually being generated. Every run with a frame generation option failed before the overlay started or within seconds of it.

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
| 9 | [06-d3d12-debug-layer](06-d3d12-debug-layer) | off, debug layer forced on | on | Normal boot to the menu. 96,101 debug layer messages; none of the three messages quoted below. |
| 10 | [06-d3d12-debug-layer](06-d3d12-debug-layer) | NVIDIA DLSS-G x4, debug layer forced on | on | Debug layer error #907, device removed 5 ms later, then the same fatal GPU error as run 8 (80004004). |
| 11 | [06-d3d12-debug-layer](06-d3d12-debug-layer) | AMD FSR 3 x2, debug layer forced on | on | The same error #907, device removed 3 ms later, then an access violation in the Steam overlay at the same address as run 4. |

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

## What the Direct3D 12 debug layer reports

Run 10 (NVIDIA DLSS-G x4). Addresses shortened:

```
14:00:29.042  [client log] Overlay scaled for a 1920x1080 back buffer behind a 1920x1080 window
14:00:29.052  D3D12 ERROR: ID3D12CommandQueue1::ExecuteCommandLists: A command list, which writes to a
              swapchain back buffer, may only be executed on the command queue associated with that buffer.
              Swap Chain: 0x..:'Unnamed Object' - Swap Chain Buffer: 0x..:'Unnamed ID3D12Resource Object'
              - Swap Chain Buffer's Command Queue: 0x..:'nv.sl.dlss_g.cmdQ.pacer'
              - Attempted Execution Command Queue: 0x..:'nv.sl.dlss_g.cmdQ.game'
              [ STATE_SETTING ERROR #907: EXECUTECOMMANDLISTS_WRONGSWAPCHAINBUFFERREFERENCE]
14:00:29.057  D3D12: Removing Device.
14:00:29.058  D3D12 ERROR: ID3D12Device::RemoveDevice: Device removal has been triggered for the following
              reason (DXGI_ERROR_ACCESS_DENIED: The application attempted to use a resource it does not
              access to. This could be, for example, rendering to a texture while only having read access.).
              [ EXECUTION ERROR #232: DEVICE_REMOVAL_PROCESS_AT_FAULT]
```

Run 11 (AMD FSR 3 x2):

```
14:02:43.689  [client log] Overlay scaled for a 1920x1080 back buffer behind a 1920x1080 window
14:02:43.699  D3D12 ERROR: ... A command list, which writes to a swapchain back buffer, may only be
              executed on the command queue associated with that buffer. ...
              - Swap Chain Buffer's Command Queue: 0x..:'AMD FSR PresentQueue'
              - Attempted Execution Command Queue: 0x..:'Unnamed ID3D12CommandQueue Object'
              [ STATE_SETTING ERROR #907: EXECUTECOMMANDLISTS_WRONGSWAPCHAINBUFFERREFERENCE]
14:02:43.702  D3D12: Removing Device.
14:02:43.703  D3D12 ERROR: ID3D12Device::RemoveDevice: ... (DXGI_ERROR_ACCESS_DENIED ...)
              [ EXECUTION ERROR #232: DEVICE_REMOVAL_PROCESS_AT_FAULT]
14:02:43.707  [client log] Unhandled exception 0xC0000005 at gameoverlayrenderer64.dll+0x8192F
```

Counts of these messages per run: error #907 0 / 1 / 1 and `Removing Device` 0 / 1 / 1 in runs 9 / 10 / 11. The messages of run 9, a normal boot, are summarised in `d3d12-debug-summary.txt`.

In the same output the debug layer names the buffers the game itself renders to when a provider is selected: `nv.sl.dlss_g.tex2d.fake-swapchain-buffer` in run 10 and `AMD FSR Replacement BackBuffer` in run 11.

Run 10 also has, 32 ms before error #907, three `CopyResource` source-state errors (#538) that are in neither run 9 nor run 11. They did not remove the device.

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

- The device removal follows Direct3D 12 error #907 (`EXECUTECOMMANDLISTS_WRONGSWAPCHAINBUFFERREFERENCE`) by 3 to 5 ms: a command list that writes to the swap chain's back buffer is executed on a command queue other than the one the buffer belongs to (runs 10 and 11).
- The buffer belongs to the frame generation provider's own queue (`nv.sl.dlss_g.cmdQ.pacer`, `AMD FSR PresentQueue`). The command list is executed on a different queue: the one Streamline names `nv.sl.dlss_g.cmdQ.game` in run 10, an unnamed queue in run 11.
- With a provider selected, the game itself renders to a replacement buffer, which the debug layer shows by name (`nv.sl.dlss_g.tex2d.fake-swapchain-buffer`, `AMD FSR Replacement BackBuffer`).
- Error #907 is reported 10 ms after the client logs `Overlay scaled for a 1920x1080 back buffer` (runs 10 and 11). It does not occur with frame generation off (run 9).
- Selecting a frame generation swapchain provider is enough to cause the failure, even with the frame generation mode set to Off (run 3).
- The failure is not vendor-specific. NVIDIA's and AMD's providers (runs 2, 3, 5) and driver-level Smooth Motion (run 6) all end in a device removal with the same reason code.
- The failure does not need the Forge launcher. The same files started directly fail at the same stage (run 8), with a different error code. `ArcaneMPLauncher.exe`, `ArcaneMPClient.dll`, `FrameworkLoaderData.dll` and `libcef.dll` are byte-identical (SHA-256) in the Forge install and in the second install.
- The two addresses in the client's `DX12 hooks installed` line, which it labels Present and ExecuteCommandLists, resolve to `dxgi.dll+0x84C0` and `D3D12Core.dll+0x3F890`. Both DLLs have file version 10.0.26100.9818. The hooks are on the system functions themselves.
- In run 4 the driver's Smooth Motion module calls into the ArcaneMP hook, which calls into the Steam overlay: `NvPresent64.dll` -> `ArcaneMPClient.dll` -> `gameoverlayrenderer64.dll`.
- Run 6 failed before `Web manager initialized` was logged.
- In run 7 the overlay never started, the game rendered with the XeSS provider selected, and the device was not removed.
- With the Steam overlay loaded, runs 1 and 4 failed differently and earlier. Run 1 was tested once. Runs 10 and 11 also had the Steam overlay loaded and did not freeze like run 1.
- The access violation of run 4, at `gameoverlayrenderer64.dll+0x8192F`, also occurs in run 11, 5 ms after the device was removed.

## What we suspect (inference, not proven)

- The command list of error #907 is the overlay's. The debug layer does not say which module submitted it. Our reasons: it comes 10 ms after the overlay's first log line about the back buffer; the game renders to the replacement buffer, not to the real one; and the client's hooks are on the system `Present` and `ExecuteCommandLists`, where the real swap chain and the game's queue are both visible. The overlay would be drawing into the real back buffer and executing on the queue it saw in `ExecuteCommandLists`, which is the game's queue and not the provider's.
- Because run 6 failed before the web manager started, the overlay's ImGui/DX12 drawing is the more likely source, not the web views.
- Run 4 is probably the same device removal, seen from inside the Steam overlay (see run 11).
- Run 1 may be a different problem: a deadlock while the inline hooks are installed, with about 280 threads in the process and another overlay loaded. It may depend on timing. We did not capture stacks for it, and it did not happen again in runs 10 and 11.

## Fix directions (suggestions, not tested by us)

What error #907 asks for: a command list that writes to a swap chain back buffer must be executed on the queue that buffer belongs to. With a frame generation provider, that queue is the provider's, not the game's.

1. Draw the overlay above the swapchain provider instead of below it. Hook the game's own viewport present path early at start-up, when the client resolves its patterns and few threads exist. Render into the buffer the engine is about to present, which is the provider's replacement buffer when one is selected, on the game's queue. This is the only direction here that would cover all the cases tested.
2. Or keep a DXGI-level hook. Capture the swapchain and its command queue when the swapchain is created (`IDXGIFactory2::CreateSwapChainForHwnd`, whose first parameter is the direct queue). For NVIDIA's in-game frame generation, use Streamline's documented native-interface route for third-party overlays instead of patching `dxgi.dll` after the renderer has started. This route does not cover FSR 3, XeSS or Smooth Motion.
3. Either way, avoid installing inline hooks on `dxgi.dll` and `D3D12Core.dll` late in start-up.

## What is in the folders

- `arcanemp-log.txt`: the mod's log for that boot. User name, account, IP addresses, device names and ids are replaced by placeholders. The `[AOB] [trace]` pattern lines and the lines written by the public server's scripts are removed. Each file starts with the number of lines removed.
- `crash-context-extract.txt`: selected fields of the game's `CrashContext.runtime-xml` (crash type, error message, versions, GPU and driver, call stack of the crashed thread, module file names). The full crash reports and the memory dumps hold account and machine identifiers, so they are not published. We can provide them privately.
- `d3d12-debug-output.txt` (runs 10 and 11): the game process's Win32 debug output with the debug layer forced on. It holds the debug layer's messages and NVIDIA Streamline's own log lines. `d3d12-debug-summary.txt` (run 9): the same for a normal boot, grouped by message with counts, because the full output is 96,633 lines.
- Run 1 has no crash report: the process froze and was ended by hand. Run 9 has none because it did not crash.
