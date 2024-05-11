module hhd.platform.win32.main;

import core.sys.windows.windows;

import hhd.math;
import hhd.platform.common;
import hhd.platform.win32.direct_sound;
import hhd.platform.win32.types;
import hhd.platform.win32.xinput;
import hhd.util;

debug
{
    import core.exception;
    import std.stdio;
}

/+ TODO:
 + - Save game data
 + - Get handle to executable
 + - Asset loading paths
 + - Threading and job system
 +   - Worker threads
 +   - Job queue
 +   - Sleep functions
 + - Raw input
 + - Multi-monitor support
 + - Fullscreen support
 + - Cursor control and visibility
 + - Handle being minimized/backgrounded
 + - Controller rumble
 + - Blit optimization (hardware rendering?)
 + - Keyboard layouts and input mappings
 + - Gamepad deadzones
 + - More!!
 +/

/// XInput libraries in order of preference
private immutable const(char)*[] X_INPUT_LIBRARIES = [
    "xinput1_4.dll",
    "xinput1_3.dll",
    "xinput9_1_0.dll"
];

__gshared private
{
    // TODO: Extract this from global state
    bool globalIsRunning;
    Win32OffscreenBuffer globalBackBuffer;
    LPDIRECTSOUNDBUFFER globalSecondaryBuffer;
}

private void
win32LoadXInput() nothrow @nogc
{
    HMODULE xInputLibrary;

    static foreach (library; X_INPUT_LIBRARIES)
    {
        if (xInputLibrary is null)
        {
            xInputLibrary = LoadLibrary(library);

            debug if (xInputLibrary)
            {
                import std.string : fromStringz;
                writeln("Loaded XInput library: ", library.fromStringz());
            }
        }
    }

    if (xInputLibrary)
    {
        XInputGetState = cast(procXInputGetState) GetProcAddress(xInputLibrary, "XInputGetState");
        XInputSetState = cast(procXInputSetState) GetProcAddress(xInputLibrary, "XInputSetState");

        debug
        {
            writefln("XInputGetState: %#x", XInputGetState);
            writefln("XInputSetState: %#x", XInputSetState);
        }
    }
}

private void
win32ClearSoundBuffer(ref Win32SoundOutput soundOutput) nothrow @nogc
{
    void*[2] region;
    DWORD[2] regionSize;

    HRESULT locked = globalSecondaryBuffer.Lock(
        0, soundOutput.secondaryBufferSize,
        &region[0], &regionSize[0],
        &region[1], &regionSize[1],
        0 /* flags */
    );

    if (SUCCEEDED(locked))
    {
        ubyte* outputSamples;

        static foreach (index; 0..2)
        {
            outputSamples = cast(ubyte*) region[index];
            outputSamples[0..regionSize[index]] = 0;
        }

        globalSecondaryBuffer.Unlock(
            region[0], regionSize[0],
            region[1], regionSize[1]
        );
    }
    else
    {
        debug writeln("Failed to lock sound buffer for clearing");
    }
}

private void
win32FillSoundBuffer(
    ref Win32SoundOutput soundOutput,
    in ref GameSoundOutputBuffer sourceBuffer,
    uint byteToLock,
    uint bytesToWrite
) nothrow @nogc
{
    void*[2] region;
    DWORD[2] regionSize;

    HRESULT locked = globalSecondaryBuffer.Lock(
        byteToLock, bytesToWrite,
        &region[0], &regionSize[0],
        &region[1], &regionSize[1],
        0 /* flags */
    );

    if (SUCCEEDED(locked))
    {
        DWORD sampleCount;
        size_t inputIndex;
        short* outputSamples;
        static foreach (index; 0..2)
        {
            outputSamples = cast(short*) region[index];
            sampleCount = regionSize[index] / soundOutput.bytesPerSample;

            foreach (sampleIndex; 0..sampleCount)
            {
                *outputSamples++ = sourceBuffer.samples[inputIndex++];
                *outputSamples++ = sourceBuffer.samples[inputIndex++];

                soundOutput.currentSampleIndex++;
            }
        }

        globalSecondaryBuffer.Unlock(
            region[0], regionSize[0],
            region[1], regionSize[1]
        );
    }
    else
    {
        // TODO: Handle this state
    }
}

private void
win32InitDirectSound(HWND window, DWORD sampleRate, DWORD bufferSize) nothrow @nogc
{
    HMODULE directSoundLibrary = LoadLibrary("dsound.dll");
    debug writeln("Loaded DirectSound library: ", "dsound.dll");

    if (directSoundLibrary)
    {
        auto DirectSoundCreate = cast(procDirectSoundCreate) GetProcAddress(directSoundLibrary, "DirectSoundCreate");

        if (!DirectSoundCreate)
        {
            // TODO: User might have no sound device?
            // How should be handle this?
            debug writeln("Failed to acquire ref to DirectSoundCreate");
            return;
        }

        LPDIRECTSOUND directSound;
        HRESULT result = DirectSoundCreate(null, &directSound, null);

        if (SUCCEEDED(result))
        {
            debug writefln("DirectSound object created: %#x", cast(void*) directSound);

            enum WORD CHANNELS_COUNT = 2; // stereo
            enum WORD BITS_PER_SAMPLE = ushort.sizeof * 8; // 16-bit stereo
            enum WORD BLOCK_ALIGN = (CHANNELS_COUNT * BITS_PER_SAMPLE) / 8; // 4 bytes per sample

            WAVEFORMATEX waveFormat = {
                wFormatTag:      WAVE_FORMAT_PCM,
                nChannels:       CHANNELS_COUNT,
                nSamplesPerSec:  sampleRate,
                wBitsPerSample:  BITS_PER_SAMPLE,
                nAvgBytesPerSec: sampleRate * BLOCK_ALIGN,
                nBlockAlign:     BLOCK_ALIGN
            };

            result = directSound.SetCooperativeLevel(window, DSSCL_PRIORITY);

            if (SUCCEEDED(result))
            {
                debug writeln("DirectSound cooperative level set");

                DSBUFFERDESC primaryBufferDesc = {
                    dwSize:  DSBUFFERDESC.sizeof,
                    dwFlags: DSBCAPS_PRIMARYBUFFER
                };

                LPDIRECTSOUNDBUFFER primaryBuffer;
                if (SUCCEEDED(directSound.CreateSoundBuffer(&primaryBufferDesc, &primaryBuffer, null)))
                {
                    debug writefln("Primary buffer created: %#x", cast(void*) primaryBuffer);

                    result = primaryBuffer.SetFormat(&waveFormat);
                    debug assert(SUCCEEDED(result), "Failed to set primary buffer format");
                }

                DSBUFFERDESC secondaryBufferDesc = {
                    dwSize:        DSBUFFERDESC.sizeof,
                    dwFlags:       DSBCAPS_GETCURRENTPOSITION2,
                    dwBufferBytes: bufferSize,
                    lpwfxFormat:   &waveFormat
                };

                if (SUCCEEDED(directSound.CreateSoundBuffer(&secondaryBufferDesc, &globalSecondaryBuffer, null)))
                {
                    debug writefln("Secondary buffer created: %#x", cast(void*) globalSecondaryBuffer);
                }
            }
            else
            {
                debug writeln("Failed to set DirectSound cooperative level: ", result);
            }
        }
        else
        {
            debug writeln("Failed to create DirectSound object: ", result);
        }
    }
    else
    {
        // TODO: How should be handle this?
        debug writeln("Failed to load DirectSound library");
    }
}

private Win32WindowDimensions
win32GetWindowDimensions(HWND window) nothrow @nogc
in
{
    assert(window, "Invalid window handle");
}
do
{
    Win32WindowDimensions result;

    RECT clientRect;
    GetClientRect(window, &clientRect);

    result.width = clientRect.right - clientRect.left;
    result.height = clientRect.bottom - clientRect.top;

    return result;
}

pragma(inline, true)
private uint
win32CreatePixel(uint red, uint green, uint blue) pure nothrow @nogc
{
    // Windows pixel are weird:
    // 0x xx RR GG BB (little endian)
    return (red << 16) | (green << 8) | (blue << 0);
}

private void
win32ResizeDIBSection(ref Win32OffscreenBuffer buffer, int width, int height) nothrow @nogc
{
    // TODO: Bulletproof this
    // Maybe don't free first, free after, then free first if that fails

    if (buffer.memory)
    {
        VirtualFree(buffer.memory, 0, MEM_RELEASE);
    }

    BITMAPINFOHEADER bitmapHeader = {
        biSize: BITMAPINFOHEADER.sizeof,
        biWidth: width,
        biHeight: -height,
        biPlanes: 1,
        biBitCount: 32,
        biCompression: BI_RGB
    };
    buffer.info.bmiHeader = bitmapHeader;

    debug
    {
        assert(bitmapHeader.biXPelsPerMeter == 0, "Expected 0");
        assert(bitmapHeader.biYPelsPerMeter == 0, "Expected 0");
    }

    buffer.memory = VirtualAlloc(
        null,
        buffer.memorySize,
        MEM_COMMIT,
        PAGE_READWRITE
    );

    debug
    {
        assert(buffer.memory, "Failed to allocate memory for bitmap");
    }

    // TODO: Probably clear this to black
}

private void
win32BlitBufferToWindow(
    in ref Win32OffscreenBuffer buffer,
    HDC deviceContext,
    LONG windowWidth, LONG windowHeight
) nothrow @nogc
{
    // TODO: Aspect ratio correction

    StretchDIBits(
        deviceContext,
        0, 0, windowWidth, windowHeight,
        0, 0, buffer.width, buffer.height,
        buffer.memory, &buffer.info,
        DIB_RGB_COLORS, SRCCOPY
    );
}

pragma(inline, true) private long
win32GetPerformanceCounter() nothrow @nogc
{
    LARGE_INTEGER result;
    QueryPerformanceCounter(&result);

    return result.QuadPart;
}

pragma(inline, true) private long
win32GetPerformanceFrequency() nothrow @nogc
{
    LARGE_INTEGER result;
    QueryPerformanceFrequency(&result);

    return result.QuadPart;
}

pragma(inline, true) private ulong
win32GetCycleCounter() nothrow @nogc
{
    asm nothrow @nogc
    {
        naked;
        rdtsc;
        ret;
    }
}

extern (Windows) LRESULT
win32WindowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam) nothrow @nogc
{
    LRESULT result;

    switch (message)
    {
        case WM_CLOSE:
        {
            // TODO: Prompt the user to confirm
            globalIsRunning = false;
        }
        break;

        case WM_DESTROY:
        {
            // TODO: Was this an error?
            globalIsRunning = false;
        }
        break;

        case WM_KEYUP:
        case WM_KEYDOWN:
        case WM_SYSKEYUP:
        case WM_SYSKEYDOWN:
        {
            // TODO: Handle keyboard input
            uint vkCode = cast(uint) wParam;

            /// Was this key down before this event?
            bool prevDown = (lParam & (1 << 30)) != 0;
            /// Is this key currently down?
            bool currDown = (lParam & (1 << 31)) == 0;

            /// Was the ALT modifier key pressed?
            bool altKey = (lParam & (1 << 29)) != 0;

            if (currDown != prevDown)
            {
                switch (vkCode)
                {
                    case VK_ESCAPE:
                    {
                        // TODO: Prompt the user to confirm
                        globalIsRunning = false;
                    }
                    break;

                    case VK_F4:
                    {
                        // NOTE: User explicitly closed the window
                        // We probably don't need to prompt the user?
                        if (altKey)
                        {
                            globalIsRunning = false;
                        }
                    }
                    break;

                    default:
                    {
                        // TODO: Add handling for remaining keys
                        debug writefln("Unhandled key: %c (%#x)", cast(char) vkCode, vkCode);
                    }
                    break;
                }
            }
        }
        break;

        case WM_PAINT:
        {
            PAINTSTRUCT paint;
            HDC deviceContext = BeginPaint(window, &paint);

            auto dimensions = win32GetWindowDimensions(window);

            win32BlitBufferToWindow(
                globalBackBuffer, deviceContext,
                dimensions.width, dimensions.height
            );

            EndPaint(window, &paint);
        }
        break;

        default:
        {
            result = DefWindowProc(window, message, wParam, lParam);
        }
    }

    return result;
}

private void
win32ProcessXInputButton(
    ref GameButtonInput newState,
    in ref GameButtonInput oldState,
    in ref XINPUT_GAMEPAD gamepad,
    WORD button
) nothrow @nogc
{
    newState.isDown = gamepad.isPressed(button);
    newState.transitionsCount = oldState.isDown != newState.isDown ? 1 : 0;
}

extern (Windows) int
main() nothrow @nogc
{
    HINSTANCE instance = GetModuleHandle(NULL);

    debug
    {
        assert(instance, "Failed to acquire HINSTANCE");
        writefln("HINSTANCE: %#x", instance);
    }

    win32LoadXInput();
    win32ResizeDIBSection(globalBackBuffer, 1280, 720);

    debug
    {
        // NOTE: In debug mode, `debug { }` blocks might raise assert errors
        // Windows doesn't like it when you throw exceptions from the window proc, especially D exceptions.
        // Handle them here and exit gracefully.
        WNDPROC windowProc = (window, message, wParam, lParam) nothrow @nogc {
            LRESULT result;

            try
            {
                result = win32WindowProc(window, message, wParam, lParam);
            }
            catch (core.exception.AssertError error)
            {
                debug writeln("Error: ", error);
                PostQuitMessage(-1);
            }

            return result;
        };
    }
    else
    {
        // NOTE: In release mode, `nothrow` means no exceptions can be thrown.
        WNDPROC windowProc = &win32WindowProc;
    }

    WNDCLASS windowClass = {
        style: CS_HREDRAW | CS_VREDRAW | CS_OWNDC,
        hInstance: instance,
        lpszClassName: "HHDWindowClass",
        lpfnWndProc: windowProc
    };

    ATOM registerWindowResult = RegisterClass(&windowClass);

    debug
    {
        assert(registerWindowResult, "Failed to register window class.");
        writefln("Regsitered window class: %#x", registerWindowResult);
    }

    HWND window = CreateWindowEx(
        0,
        windowClass.lpszClassName,
        "HHD",
        WS_OVERLAPPEDWINDOW | WS_VISIBLE,
        CW_USEDEFAULT, CW_USEDEFAULT,
        CW_USEDEFAULT, CW_USEDEFAULT,
        null, null,
        instance,
        null
    );

    debug
    {
        assert(window, "Failed to create window.");
        writefln("Created window: %#x", window);
    }

    // NOTE: Since we're using `CS_OWNDC`,
    // we can get the device context once and use it for the lifetime of the window
    HDC deviceContext = GetDC(window);

    Win32SoundOutput soundOutput;

    soundOutput.sampleRate = 48_000;
    soundOutput.bytesPerSample = 4;
    soundOutput.secondaryBufferSize = soundOutput.sampleRate * soundOutput.bytesPerSample;
    soundOutput.latencyInSamples = soundOutput.sampleRate / 15;

    win32InitDirectSound(window, soundOutput.sampleRate, soundOutput.secondaryBufferSize);

    if (globalSecondaryBuffer)
    {
        win32ClearSoundBuffer(soundOutput);
        globalSecondaryBuffer.Play(0, 0, DSBPLAY_LOOPING);
    }
    else debug
    {
        writeln("No sound output available.");
    }

    globalIsRunning = true;

    // TODO: Do we need this much space?
    short* gameSoundSamples = cast(short*) VirtualAlloc(
        null,
        soundOutput.secondaryBufferSize,
        MEM_RESERVE | MEM_COMMIT,
        PAGE_READWRITE
    );

    immutable long perfCounterFrequency = win32GetPerformanceFrequency();
    long lastFrameCounter = win32GetPerformanceCounter();
    ulong lastCycleCounter = win32GetCycleCounter();

    GameInput[2] gameInput;
    uint currInputIndex = 0;
    uint lastInputIndex = 1;

    GameMemory gameMemory;

    debug
    {
        version (Win64)
        {
            // NOTE: In debug mode, we ask for well-known addresses to simplify debugging
            // (All temporary and permanent memory objects should be placed at the same addresses every time)
            enum LPVOID PERMANENT_STORAGE_ADDRESS = cast(LPVOID) 1.terabytes;
            enum LPVOID TRANSIENT_STORAGE_ADDRESS = cast(LPVOID) 2.terabytes;
        }
        else
        {
            // TODO: Figure out where to put these on 32-bit platforms
            enum LPVOID PERMANENT_STORAGE_ADDRESS = cast(LPVOID) 0;
            enum LPVOID TRANSIENT_STORAGE_ADDRESS = cast(LPVOID) 0;
        }
    }
    else
    {
        // NOTE: In release mode, use whatever address is available
        enum LPVOID PERMANENT_STORAGE_ADDRESS = cast(LPVOID) 0;
        enum LPVOID TRANSIENT_STORAGE_ADDRESS = cast(LPVOID) 0;
    }

    gameMemory.permanentStorageSize = 64.megabytes;
    gameMemory.permanentStorage = VirtualAlloc(
        PERMANENT_STORAGE_ADDRESS,
        gameMemory.permanentStorageSize,
        MEM_RESERVE | MEM_COMMIT,
        PAGE_READWRITE
    );

    debug
    {
        assert(gameMemory.permanentStorage, "Failed to allocate permanent storage");
        writefln("Allocated permanent storage: %#x", gameMemory.permanentStorage);
    }

    gameMemory.transientStorageSize = 2.gigabytes;
    gameMemory.transientStorage = VirtualAlloc(
        TRANSIENT_STORAGE_ADDRESS,
        gameMemory.transientStorageSize,
        MEM_RESERVE | MEM_COMMIT,
        PAGE_READWRITE
    );

    debug
    {
        assert(gameMemory.transientStorage, "Failed to allocate transient storage");
        writefln("Allocated transient storage: %#x", gameMemory.transientStorage);
    }

    while (globalIsRunning)
    {
        MSG message;
        while (PeekMessage(&message, null, 0, 0, PM_REMOVE))
        {
            if (message.message == WM_QUIT)
            {
                globalIsRunning = false;
            }

            TranslateMessage(&message);
            DispatchMessage(&message);
        }

        static assert(
            XUSER_MAX_COUNT <= GAME_INPUT_CONTROLLERS_COUNT,
            "XUSER_MAX_COUNT must be less than or equal to GAME_INPUT_CONTROLLERS_COUNT"
        );

        // TODO: Should this be polled more frequently?
        foreach (userIndex; 0..XUSER_MAX_COUNT)
        {
            GameControllerInput* newController = &gameInput[currInputIndex].controllers[userIndex];
            GameControllerInput* oldController = &gameInput[lastInputIndex].controllers[userIndex];

            XINPUT_STATE state;
            if (XInputGetState(userIndex, &state) == ERROR_SUCCESS)
            {
                newController.isConnected = true;

                win32ProcessXInputButton(
                    newController.aButton, oldController.aButton,
                    state.gamepad, XINPUT_GAMEPAD_A
                );
                win32ProcessXInputButton(
                    newController.bButton, oldController.bButton,
                    state.gamepad, XINPUT_GAMEPAD_B
                );
                win32ProcessXInputButton(
                    newController.xButton, oldController.xButton,
                    state.gamepad, XINPUT_GAMEPAD_X
                );
                win32ProcessXInputButton(
                    newController.yButton, oldController.yButton,
                    state.gamepad, XINPUT_GAMEPAD_Y
                );

                win32ProcessXInputButton(
                    newController.dpadUpButton, oldController.dpadUpButton,
                    state.gamepad, XINPUT_GAMEPAD_DPAD_UP
                );
                win32ProcessXInputButton(
                    newController.dpadDownButton, oldController.dpadDownButton,
                    state.gamepad, XINPUT_GAMEPAD_DPAD_DOWN
                );
                win32ProcessXInputButton(
                    newController.dpadLeftButton, oldController.dpadLeftButton,
                    state.gamepad, XINPUT_GAMEPAD_DPAD_LEFT
                );
                win32ProcessXInputButton(
                    newController.dpadRightButton, oldController.dpadRightButton,
                    state.gamepad, XINPUT_GAMEPAD_DPAD_RIGHT
                );

                win32ProcessXInputButton(
                    newController.startButton, oldController.startButton,
                    state.gamepad, XINPUT_GAMEPAD_START
                );
                win32ProcessXInputButton(
                    newController.backButton, oldController.backButton,
                    state.gamepad, XINPUT_GAMEPAD_BACK
                );

                win32ProcessXInputButton(
                    newController.leftShoulderButton, oldController.leftShoulderButton,
                    state.gamepad, XINPUT_GAMEPAD_LEFT_SHOULDER
                );
                win32ProcessXInputButton(
                    newController.rightShoulderButton, oldController.rightShoulderButton,
                    state.gamepad, XINPUT_GAMEPAD_RIGHT_SHOULDER
                );

                newController.leftStick.isAnalog = true;
                newController.leftStick.startX = oldController.leftStick.endX;
                newController.leftStick.startY = oldController.leftStick.endY;
                newController.leftStick.endX = state.gamepad.leftThumbX;
                newController.leftStick.endY = state.gamepad.leftThumbY;

                newController.rightStick.isAnalog = true;
                newController.rightStick.startX = oldController.rightStick.endX;
                newController.rightStick.startY = oldController.rightStick.endY;
                newController.rightStick.endX = state.gamepad.rightThumbX;
                newController.rightStick.endY = state.gamepad.rightThumbY;
                // TODO: Handle deadzones on thumbsticks
            }
            else
            {
                // NOTE: Controller not connected
                // TODO: Display or handle controllers going away?
                newController.isConnected = false;
            }

            debug
            {
                if (newController.isConnected && !oldController.isConnected)
                {
                    writefln("Controller %d connected.", userIndex);
                }
            }
        }

        bool soundIsValid;
        DWORD byteToLock, bytesToWrite;
        DWORD playCursor, writeCursor, targetCursor;
        // TODO: Tighten up sound logic so we know where should be writing to
        // and can predict the time spent in the game update
        if (globalSecondaryBuffer && SUCCEEDED(globalSecondaryBuffer.GetCurrentPosition(&playCursor, &writeCursor)))
        {
            byteToLock = (soundOutput.currentSampleIndex * soundOutput.bytesPerSample)
                       % soundOutput.secondaryBufferSize;

            targetCursor = (playCursor + (soundOutput.latencyInSamples * soundOutput.bytesPerSample))
                         % soundOutput.secondaryBufferSize;

            if (byteToLock > targetCursor)
            {
                bytesToWrite = (soundOutput.secondaryBufferSize - byteToLock) + targetCursor;
            }
            else
            {
                bytesToWrite = targetCursor - byteToLock;
            }

            soundIsValid = true;
        }

        GameOffscreenBuffer gameOffscreenBuffer = {
            memory: globalBackBuffer.memory,
            width:  globalBackBuffer.width,
            height: globalBackBuffer.height,
            pitch:  globalBackBuffer.pitch
        };
        gameUpdateAndRender(gameMemory, gameInput[currInputIndex], gameOffscreenBuffer);

        GameSoundOutputBuffer gameSoundBuffer = {
            samples:     gameSoundSamples,
            sampleRate:  soundOutput.sampleRate,
            sampleCount: bytesToWrite / soundOutput.bytesPerSample
        };
        // TODO: Allow sample offsets here for more robust platform options
        gameOutputSound(gameMemory, gameSoundBuffer);

        if (soundIsValid)
        {
            win32FillSoundBuffer(soundOutput, gameSoundBuffer, byteToLock, bytesToWrite);
        }

        auto dimensions = win32GetWindowDimensions(window);

        win32BlitBufferToWindow(
            globalBackBuffer, deviceContext,
            dimensions.width, dimensions.height
        );

        ulong thisCycleCounter = win32GetCycleCounter();
        long thisFrameCounter = win32GetPerformanceCounter();
        long cyclesElapsed = thisCycleCounter - lastCycleCounter;
        long counterElapsed = thisFrameCounter - lastFrameCounter;

        float millisPerFrame = (1000.0f * counterElapsed) / perfCounterFrequency;
        float fps = cast(float)(perfCounterFrequency) / cast(float)(counterElapsed);

        debug
        {
            enum float MEGACYCLE = 1_000_000.0f;
            writefln("Frame time: %.2fms/f (%.2f FPS) %.2fMC/f", millisPerFrame, fps, cyclesElapsed / MEGACYCLE);
        }

        lastFrameCounter = thisFrameCounter;
        lastCycleCounter = thisCycleCounter;

        // Swap input indices
        currInputIndex = 1 - currInputIndex;
        lastInputIndex = 1 - lastInputIndex;
    }

    return 0;
}

version (D_BetterC)
{
    extern (C) int _d_run_main(int, char**)
    {
        return main();
    }
}
else
{
    // Debug mode configuration
    shared static this()
    {
        // Disable GC and collection during debug mode
        // All memory should be manually managed
        import core.memory : GC;
        GC.disable();
    }
}
