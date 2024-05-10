module hhd.platform.win32.main;

import core.sys.windows.windows;
import core.sys.windows.com;

import hhd.platform.win32.direct_sound;
import hhd.platform.win32.xinput;

debug
{
    import core.exception;
    import std.stdio;
}

// TODO: Implement math functions
import core.stdc.math : sinf;
enum float PI = 3.14159265359f;

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

private
{
    enum WORD CHANNELS_COUNT = 2; // stereo
    enum WORD BITS_PER_SAMPLE = ushort.sizeof * 8; // 16-bit stereo
    enum WORD BLOCK_ALIGN = (CHANNELS_COUNT * BITS_PER_SAMPLE) / 8; // 4 bytes per sample
}

struct Win32SoundOutput
{
    int sampleRate;
    int bytesPerSample;
    int secondaryBufferSize;

    int toneHz;
    short toneVolume;
    int tonePeriod;

    uint currentSampleIndex;

    @property
    enum ushort channelsCount = 2; 
}

private void
win32FillSoundBuffer(ref Win32SoundOutput soundOutput, uint byteToLock, uint bytesToWrite) nothrow @nogc
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
        short* sampleOutput;
        static foreach (index; 0..2)
        {
            sampleCount = regionSize[index] / soundOutput.bytesPerSample;
            sampleOutput = cast(short*) region[index];

            foreach (sampleIndex; 0..sampleCount)
            {
                float t = 2.0f * PI * cast(float) soundOutput.currentSampleIndex / cast(float) soundOutput.tonePeriod;
                short sampleValue = cast(short)(sinf(t) * soundOutput.toneVolume);

                *sampleOutput++ = sampleValue;
                *sampleOutput++ = sampleValue;

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

struct Win32OffscreenBuffer
{
    BITMAPINFO info;
    void* memory;

    @property
    enum LONG BYTES_PER_PIXEL = 4;

    @property
    pragma(inline, true)
    LONG width() const nothrow @nogc
    {
        return info.bmiHeader.biWidth;
    }

    @property
    pragma(inline, true)
    LONG height() const nothrow @nogc
    {
        return -info.bmiHeader.biHeight;
    }

    @property
    pragma(inline, true)
    LONG pitch() const nothrow @nogc
    {
        return width * BYTES_PER_PIXEL;
    }

    @property
    pragma(inline, true)
    size_t memorySize() const nothrow @nogc
    {
        return width * height * BYTES_PER_PIXEL;
    }
}

struct Win32WindowDimensions
{
    LONG width;
    LONG height;
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
renderFunkyGradient(in ref Win32OffscreenBuffer buffer, int xOffset, int yOffset) nothrow @nogc
{
    ubyte* row = cast(ubyte*) buffer.memory;

    foreach (y; 0..buffer.height)
    {
        uint* pixel = cast(uint*) row;

        foreach (x; 0..buffer.width)
        {
            ubyte blue  = cast(ubyte)(x + xOffset);
            ubyte green = cast(ubyte)(y + yOffset);

            *pixel++ = win32CreatePixel(0, green, blue);
        }

        row += buffer.pitch;
    }
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

    int xOffset = 0;
    int yOffset = 0;

    Win32SoundOutput soundOutput;

    soundOutput.sampleRate = 48_000;
    soundOutput.bytesPerSample = 4;
    soundOutput.secondaryBufferSize = soundOutput.sampleRate * soundOutput.bytesPerSample;
    soundOutput.toneHz = 530;
    soundOutput.toneVolume = 500;
    soundOutput.tonePeriod = soundOutput.sampleRate / soundOutput.toneHz;
    soundOutput.currentSampleIndex = 0;

    win32InitDirectSound(window, soundOutput.sampleRate, soundOutput.secondaryBufferSize);

    if (globalSecondaryBuffer)
    {
        win32FillSoundBuffer(soundOutput, 0, soundOutput.secondaryBufferSize);
        globalSecondaryBuffer.Play(0, 0, DSBPLAY_LOOPING);
    }
    else debug
    {
        writeln("No sound output available.");
    }

    globalIsRunning = true;

    immutable long perfCounterFrequency = win32GetPerformanceFrequency();
    long lastFrameCounter = win32GetPerformanceCounter();
    ulong lastCycleCounter = win32GetCycleCounter();

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

        // TODO: Should this be polled more frequently?
        foreach (userIndex; 0..XUSER_MAX_COUNT)
        {
            XINPUT_STATE state;
            if (XInputGetState(userIndex, &state) == ERROR_SUCCESS)
            {
                // NOTE: Controller connected
                bool dpadUp = state.gamepad.isPressed(XINPUT_GAMEPAD_DPAD_UP);
                bool dpadDown = state.gamepad.isPressed(XINPUT_GAMEPAD_DPAD_DOWN);
                bool dpadLeft = state.gamepad.isPressed(XINPUT_GAMEPAD_DPAD_LEFT);
                bool dpadRight = state.gamepad.isPressed(XINPUT_GAMEPAD_DPAD_RIGHT);

                bool start = state.gamepad.isPressed(XINPUT_GAMEPAD_START);
                bool back = state.gamepad.isPressed(XINPUT_GAMEPAD_BACK);

                bool leftShoulder = state.gamepad.isPressed(XINPUT_GAMEPAD_LEFT_SHOULDER);
                bool rightShoulder = state.gamepad.isPressed(XINPUT_GAMEPAD_RIGHT_SHOULDER);

                bool aButton = state.gamepad.isPressed(XINPUT_GAMEPAD_A);
                bool bButton = state.gamepad.isPressed(XINPUT_GAMEPAD_B);
                bool xButton = state.gamepad.isPressed(XINPUT_GAMEPAD_X);
                bool yButton = state.gamepad.isPressed(XINPUT_GAMEPAD_Y);

                SHORT stickX = state.gamepad.sThumbLX;
                SHORT stickY = state.gamepad.sThumbLY;
            }
            else
            {
                // NOTE: Controller not connected
                // TODO: Display or handle controllers going away?
            }
        }

        renderFunkyGradient(globalBackBuffer, xOffset, yOffset);
        xOffset++;
        yOffset++;

        DWORD playCursor;
        DWORD writeCursor;
        if (globalSecondaryBuffer && SUCCEEDED(globalSecondaryBuffer.GetCurrentPosition(&playCursor, &writeCursor)))
        {
            DWORD byteToLock = (soundOutput.currentSampleIndex * soundOutput.bytesPerSample)
                             % soundOutput.secondaryBufferSize;
            DWORD bytesToWrite;

            // TODO: Change this to using a lower latency offset from the playcursor
            if (byteToLock > playCursor)
            {
                bytesToWrite = (soundOutput.secondaryBufferSize - byteToLock) + playCursor;
            }
            else
            {
                bytesToWrite = playCursor - byteToLock;
            }

            win32FillSoundBuffer(soundOutput, byteToLock, bytesToWrite);
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
    }

    return 0;
}
