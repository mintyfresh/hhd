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

__gshared private
{
    // TODO: Extract this from global state
    bool globalIsRunning;
    bool globalDebugPause;
    Win32OffscreenBuffer globalBackBuffer;
    LPDIRECTSOUNDBUFFER globalSecondaryBuffer;
}

enum float MILLIS_PER_SECOND = 1000.0f;

/// Mapping between platform-specific XInput buttons and Game buttons
private enum Win32ControllerButtonMapping[] CONTROLLER_BUTTON_MAPPINGS = [
    { GameButton.a,             XINPUT_GAMEPAD_A },
    { GameButton.b,             XINPUT_GAMEPAD_B },
    { GameButton.x,             XINPUT_GAMEPAD_X },
    { GameButton.y,             XINPUT_GAMEPAD_Y },
    { GameButton.dpadUp,        XINPUT_GAMEPAD_DPAD_UP },
    { GameButton.dpadDown,      XINPUT_GAMEPAD_DPAD_DOWN },
    { GameButton.dpadLeft,      XINPUT_GAMEPAD_DPAD_LEFT },
    { GameButton.dpadRight,     XINPUT_GAMEPAD_DPAD_RIGHT },
    { GameButton.start,         XINPUT_GAMEPAD_START },
    { GameButton.back,          XINPUT_GAMEPAD_BACK },
    { GameButton.leftShoulder,  XINPUT_GAMEPAD_LEFT_SHOULDER },
    { GameButton.rightShoulder, XINPUT_GAMEPAD_RIGHT_SHOULDER }
];

// Base addresses for permanent and transient storage
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

/// XInput libraries in order of preference
private immutable const(char)*[] X_INPUT_LIBRARIES = [
    "xinput1_4.dll",
    "xinput1_3.dll",
    "xinput9_1_0.dll"
];

extern (System) nothrow @nogc
{
    // Debug-only functions
    // See: hhd.platform.common
    debug
    {
        /// See: hhd.platform.common.debugReadEntireFile
        void[] debugReadEntireFile(const(char)* fileName)
        {
            assert(fileName, "File name is null");

            HANDLE file = CreateFileA(
                fileName,
                GENERIC_READ,
                FILE_SHARE_READ,
                null,
                OPEN_EXISTING,
                FILE_ATTRIBUTE_NORMAL,
                null
            );

            if (file == INVALID_HANDLE_VALUE)
            {
                debug writeln("Failed to open file: ", fileName);
                return null;
            }

            scope (exit)
            {
                CloseHandle(file);
            }

            LARGE_INTEGER rawFileSize;
            if (!GetFileSizeEx(file, &rawFileSize))
            {
                debug writeln("Failed to get file size: ", fileName);
                return null;
            }

            // TODO: Handle large files
            assert(rawFileSize.QuadPart <= DWORD.max, "File is too large (greater than 4GB)");
            DWORD fileSize = cast(DWORD) rawFileSize.QuadPart;

            void* fileMemory = VirtualAlloc(
                null,
                fileSize,
                MEM_RESERVE | MEM_COMMIT,
                PAGE_READWRITE
            );

            if (!fileMemory)
            {
                debug writefln("Failed to allocate memory for file: %s (%d bytes)", fileName, fileSize);
                return null;
            }

            DWORD bytesRead;
            if (!ReadFile(file, fileMemory, fileSize, &bytesRead, null) || bytesRead != fileSize)
            {
                debug writefln("Failed to read file: %s (%d bytes)", fileName, fileSize);
                VirtualFree(fileMemory, 0, MEM_RELEASE); // Free memory before returning

                return null;
            }

            return fileMemory[0..fileSize];
        }

        /// See: hhd.platform.common.debugWriteEntireFile
        bool debugWriteEntireFile(const(char)* fileName, void[] buffer)
        {
            assert(fileName, "File name is null");
            assert(buffer, "Buffer is null");

            HANDLE file = CreateFileA(
                fileName,
                GENERIC_WRITE,
                0,
                null,
                CREATE_ALWAYS,
                FILE_ATTRIBUTE_NORMAL,
                null
            );

            if (file == INVALID_HANDLE_VALUE)
            {
                debug writeln("Failed to create or open file: ", fileName);
                return false;
            }

            scope (exit)
            {
                CloseHandle(file);
            }

            DWORD bytesWritten;
            DWORD bytesToWrite = cast(DWORD) buffer.length;
            if (!WriteFile(file, buffer.ptr, bytesToWrite, &bytesWritten, null) || bytesWritten != bytesToWrite)
            {
                debug writefln("Failed to write file: %s (%d bytes)", fileName, buffer.length);
                return false;
            }

            return true;
        }

        /// See: hhd.platform.common.debugFreeFileMemory
        bool debugFreeFileMemory(void[] memory)
        {
            return VirtualFree(memory.ptr, 0, MEM_RELEASE) != 0;
        }
    }
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
    scope ref Win32SoundOutput soundOutput,
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

pragma(inline, true)
private uint
win32CreateBRGPixel(uint red, uint green, uint blue) pure nothrow @nogc
{
    return (red << 16) | (green << 8) | (blue << 0);
}

private void
win32DrawVerticalLine(
    in ref Win32OffscreenBuffer buffer,
    int x,
    int top,
    int bottom,
    uint colour
) nothrow @nogc
{
    if (top < 0)
    {
        top = 0;
    }

    if (bottom > buffer.height)
    {
        bottom = buffer.height;
    }

    if (x >= 0 && x < buffer.width)
    {
        ubyte* pixel = cast(ubyte*)(buffer.memory) + (x * buffer.BYTES_PER_PIXEL) + (top * buffer.pitch);

        foreach (int y; top..bottom)
        {
            *(cast(uint*) pixel) = colour;
            pixel += buffer.pitch;
        }
    }
}

private void
win32DebugSyncDisplay(
    in ref Win32OffscreenBuffer buffer,
    in ref Win32SoundOutput soundOutput,
    in DWORD[] playCursors,
    in DWORD[] writeCursors,
    in int currentCursorIndex,
    float targetMillisPerUpdate
) nothrow @nogc
in
{
    assert(playCursors.length == writeCursors.length, "Mismatched cursor buffer lengths");
}
do
{
    // TODO: Draw where we're writing to the sound buffer

    enum int PAD_X = 16;
    enum int PAD_Y = 16;
    enum int LINE_HEIGHT = 64;

    immutable float bufferRatio = cast(float)(buffer.width - (2 * PAD_X))
                                / cast(float)(soundOutput.secondaryBufferSize);

    enum int TOP = PAD_Y;
    enum int BOTTOM = PAD_Y + LINE_HEIGHT;

    void win32DrawSoundBufferMarker(DWORD cursor, uint colour, bool current)
    {
        int top = TOP;
        int bottom = BOTTOM;

        if (current)
        {
            top += LINE_HEIGHT + PAD_Y;
            bottom += LINE_HEIGHT + PAD_Y;
        }

        int cursorX = cast(int)(PAD_X + (bufferRatio * cast(float)(cursor)));
        win32DrawVerticalLine(buffer, cursorX, top, bottom, colour);
    }

    foreach (index, playCursor; playCursors)
    {
        DWORD writeCursor = writeCursors[index];

        uint playColour = win32CreateBRGPixel(255, 255, 255);
        uint writeColour = win32CreateBRGPixel(255, 0, 0);

        win32DrawSoundBufferMarker(playCursor, playColour, index == currentCursorIndex);
        win32DrawSoundBufferMarker(writeCursor, writeColour, index == currentCursorIndex);
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
            assert(false, "Keyboard input should be handled in win32ProcessWindowMessages");
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
win32ProcessKeyboardMessage(scope ref GameKeyInput input, bool isDown) nothrow @nogc
in
{
    assert(input.isDown != isDown, "Key state should change");
}
do
{
    input.isDown = isDown;
    input.transitionsCount++;
}

private void
win32ProcessWindowMessages(HWND window, scope ref GameKeyboardInput input) nothrow @nogc
{
    MSG message;
    while (PeekMessage(&message, null, 0, 0, PM_REMOVE))
    {
        switch (message.message)
        {
            case WM_QUIT:
            {
                globalIsRunning = false;
            }
            break;

            case WM_KEYUP:
            case WM_KEYDOWN:
            case WM_SYSKEYUP:
            case WM_SYSKEYDOWN:
            {
                // TODO: Handle keyboard input
                uint vkCode = cast(uint) message.wParam;

                /// Was this key down before this event?
                bool prevDown = (message.lParam & (1 << 30)) != 0;
                /// Is this key currently down?
                bool currDown = (message.lParam & (1 << 31)) == 0;

                /// Was the ALT modifier key pressed?
                bool altKey = (message.lParam & (1 << 29)) != 0;

                if (currDown != prevDown)
                {
                    switch (vkCode)
                    {
                        case VK_ESCAPE:
                        {
                            // TODO: Process this as game input
                            globalIsRunning = false;
                        }
                        break;

                        case 'W':
                        {
                            win32ProcessKeyboardMessage(input.keys[GameKey.w], currDown);
                        }
                        break;

                        case 'A':
                        {
                            win32ProcessKeyboardMessage(input.keys[GameKey.a], currDown);
                        }
                        break;

                        case 'S':
                        {
                            win32ProcessKeyboardMessage(input.keys[GameKey.s], currDown);
                        }
                        break;

                        case 'D':
                        {
                            win32ProcessKeyboardMessage(input.keys[GameKey.d], currDown);
                        }
                        break;

                        case 'Q':
                        {
                            win32ProcessKeyboardMessage(input.keys[GameKey.q], currDown);
                        }
                        break;

                        case 'E':
                        {
                            win32ProcessKeyboardMessage(input.keys[GameKey.e], currDown);
                        }
                        break;

                        case VK_SPACE:
                        {
                            win32ProcessKeyboardMessage(input.keys[GameKey.space], currDown);
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

                        case 'P':
                        {
                            if (currDown)
                            {
                                globalDebugPause = !globalDebugPause;
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

            default:
            {
                TranslateMessage(&message);
                DispatchMessage(&message);
            }
        }
    }
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

private void
win32ProcessXInputStick(
    ref GameStickInput newState,
    in ref GameStickInput oldState,
    float stickX, float stickY
) nothrow @nogc
{
    newState.startX = oldState.endX;
    newState.startY = oldState.endY;
    newState.endX   = stickX;
    newState.endY   = stickY;
}

private void
win32AllocateGameMemory(scope ref GameMemory memory) nothrow @nogc
{
    memory.permanentStorageSize = 64.megabytes;
    memory.permanentStorage = VirtualAlloc(
        PERMANENT_STORAGE_ADDRESS,
        memory.permanentStorageSize,
        MEM_RESERVE | MEM_COMMIT,
        PAGE_READWRITE
    );

    debug
    {
        assert(memory.permanentStorage, "Failed to allocate permanent storage");
        writefln("Allocated permanent storage: %#x", memory.permanentStorage);
    }

    memory.transientStorageSize = 2.gigabytes;
    memory.transientStorage = VirtualAlloc(
        TRANSIENT_STORAGE_ADDRESS,
        memory.transientStorageSize,
        MEM_RESERVE | MEM_COMMIT,
        PAGE_READWRITE
    );

    debug
    {
        assert(memory.transientStorage, "Failed to allocate transient storage");
        writefln("Allocated transient storage: %#x", memory.transientStorage);
    }
}

extern (Windows) int
main() nothrow @nogc
{
    HINSTANCE instance = GetModuleHandle(null);

    debug
    {
        assert(instance, "Failed to acquire HINSTANCE");
        writefln("HINSTANCE: %#x", instance);
    }

    HANDLE process = GetCurrentProcess();
    if (!SetPriorityClass(process, HIGH_PRIORITY_CLASS))
    {
        debug writeln("Failed to set process priority");
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

    enum DWORD GAME_UPDATE_HZ = 60; // TODO: Query this from the system?
    enum float TARGET_MILLIS_PER_UPDATE = MILLIS_PER_SECOND / GAME_UPDATE_HZ;

    // NOTE: Since we're using `CS_OWNDC`,
    // we can get the device context once and use it for the lifetime of the window
    HDC deviceContext = GetDC(window);

    Win32SoundOutput soundOutput;

    soundOutput.sampleRate = 48_000;
    soundOutput.bytesPerSample = 4;
    soundOutput.secondaryBufferSize = soundOutput.sampleRate * soundOutput.bytesPerSample;
    soundOutput.latencyInSamples = 3 * (soundOutput.sampleRate / GAME_UPDATE_HZ);
    // TODO: Determine the what lowest reasonable value is
    soundOutput.safetyBytes = soundOutput.bytesPerSecond / (GAME_UPDATE_HZ / 3);

    win32InitDirectSound(window, soundOutput.sampleRate, soundOutput.secondaryBufferSize);

    // NOTE: We might not have sound output available
    // `globalSecondaryBuffer` will be null if that's the case
    if (globalSecondaryBuffer)
    {
        win32ClearSoundBuffer(soundOutput);
        globalSecondaryBuffer.Play(0, 0, DSBPLAY_LOOPING);
    }
    else
    {
        debug writeln("No sound output available.");
    }

    globalIsRunning = true;

    // TODO: Do we need this much space?
    // TODO: Should we consolidate this with the game memory?
    short* gameSoundSamples = cast(short*) VirtualAlloc(
        null,
        soundOutput.secondaryBufferSize,
        MEM_RESERVE | MEM_COMMIT,
        PAGE_READWRITE
    );

    enum UINT REQUESTED_SCHEDULER_RESOLUTION = 1; // 1ms
    // NOTE: Request Windows scheduler to give us 1ms resolution
    // This is used to sleep precisely the thread between frames
    immutable bool isTimerHighResolution = timeBeginPeriod(REQUESTED_SCHEDULER_RESOLUTION) == TIMERR_NOERROR;

    if (isTimerHighResolution)
    {
        debug writeln("Set timer resolution to 1ms");
    }
    else
    {
        debug writeln("Failed to set timer resolution");
    }

    scope (exit)
    {
        // NOTE: Windows documentation specifically says to call `timeEndPeriod` when done
        // Not sure what the purpose of that is, but we'll do it anyway
        isTimerHighResolution && timeEndPeriod(REQUESTED_SCHEDULER_RESOLUTION);
    }

    TIMECAPS timerCapabilities;
    if (timeGetDevCaps(&timerCapabilities, TIMECAPS.sizeof) == TIMERR_NOERROR)
    {
        debug writefln("Timer resolution: %dms - %dms", timerCapabilities.wPeriodMin, timerCapabilities.wPeriodMax);
    }
    else
    {
        debug writeln("Failed to get timer resolution");
    }

    // NOTE: Add a bit of slop to the minimum duration in case the OS misbehaves
    // We'll take the hit and spinlock for an extra millisecond if we have to
    immutable UINT minSleepInMillis = timerCapabilities.wPeriodMin;

    GameInput[2] gameInput;
    uint currInputIndex = 0;
    uint prevInputIndex = 1;

    GameMemory gameMemory;
    win32AllocateGameMemory(gameMemory);

    bool soundIsValid;
    immutable long perfCounterFrequency = win32GetPerformanceFrequency();
    long prevFrameTimer = win32GetPerformanceCounter();
    ulong prevCycleCount = win32GetCycleCounter();

    while (globalIsRunning)
    {
        // NOTE: Preserving the key-down state from the previous frame
        // The `isDown` flag should only be changed when the key is pressed or released
        static foreach (keyboardIndex; 0..GAME_INPUT_KEYBOARDS_COUNT)
        {
            static foreach (keyIndex; 0..GAME_KEYS_COUNT)
            {
                gameInput[currInputIndex].keyboards[keyboardIndex].keys[keyIndex].isDown =
                    gameInput[prevInputIndex].keyboards[keyboardIndex].keys[keyIndex].isDown;
            }
        }

        win32ProcessWindowMessages(window, gameInput[currInputIndex].keyboards[0]);

        static assert(
            XUSER_MAX_COUNT <= GAME_INPUT_CONTROLLERS_COUNT,
            "XUSER_MAX_COUNT must be less than or equal to GAME_INPUT_CONTROLLERS_COUNT"
        );

        if (globalDebugPause)
        {
            // NOTE: Pause the game
            continue;
        }

        // TODO: Should this be polled more frequently?
        foreach (userIndex; 0..XUSER_MAX_COUNT)
        {
            GameControllerInput* newController = &gameInput[currInputIndex].controllers[userIndex];
            GameControllerInput* oldController = &gameInput[prevInputIndex].controllers[userIndex];

            XINPUT_STATE state;
            if (XInputGetState(userIndex, &state) == ERROR_SUCCESS)
            {
                newController.isConnected = true;

                static foreach (mapping; CONTROLLER_BUTTON_MAPPINGS)
                {
                    win32ProcessXInputButton(
                        newController.buttons[mapping.gameButton],
                        oldController.buttons[mapping.gameButton],
                        state.gamepad, mapping.xInputButton
                    );
                }

                win32ProcessXInputStick(
                    newController.leftStick,
                    oldController.leftStick,
                    state.gamepad.leftThumbX,
                    state.gamepad.leftThumbY
                );

                win32ProcessXInputStick(
                    newController.rightStick,
                    oldController.rightStick,
                    state.gamepad.rightThumbX,
                    state.gamepad.rightThumbY
                );
            }
            else
            {
                // NOTE: Controller not connected
                // TODO: Display or handle controllers going away?
                // TODO: Reduce polling on disconnected controllers
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

        GameOffscreenBuffer gameOffscreenBuffer = {
            memory: globalBackBuffer.memory,
            width:  globalBackBuffer.width,
            height: globalBackBuffer.height,
            pitch:  globalBackBuffer.pitch
        };
        gameUpdateAndRender(gameMemory, gameInput[currInputIndex], gameOffscreenBuffer);

        DWORD playCursor;
        DWORD writeCursor;
        if (globalSecondaryBuffer && SUCCEEDED(globalSecondaryBuffer.GetCurrentPosition(&playCursor, &writeCursor)))
        {
            if (!soundIsValid)
            {
                soundOutput.currentSampleIndex = writeCursor / soundOutput.bytesPerSample;
                soundIsValid = true;
            }

            DWORD byteToLock;
            byteToLock = (soundOutput.currentSampleIndex * soundOutput.bytesPerSample)
                       % soundOutput.secondaryBufferSize;

            DWORD expectedSoundBytesPerFrame = soundOutput.bytesPerSecond / GAME_UPDATE_HZ;
            DWORD expectedFrameBoundaryByte = playCursor + expectedSoundBytesPerFrame;

            DWORD safeWriteCursor = writeCursor;
            if (safeWriteCursor < playCursor)
            {
                safeWriteCursor += soundOutput.secondaryBufferSize;
            }

            debug
            {
                assert(safeWriteCursor >= playCursor, "Write cursor should be ahead of play cursor");
            }

            safeWriteCursor += soundOutput.safetyBytes;

            bool audioIsLowLatency = safeWriteCursor < expectedFrameBoundaryByte;

            DWORD targetCursor;
            if (audioIsLowLatency)
            {
                targetCursor = expectedFrameBoundaryByte + expectedSoundBytesPerFrame;
            }
            else
            {
                targetCursor = writeCursor + expectedSoundBytesPerFrame + soundOutput.safetyBytes;
            }

            debug
            {
                writeln("audioIsLowLatency: ", audioIsLowLatency);
            }

            targetCursor %= soundOutput.secondaryBufferSize;

            DWORD bytesToWrite;
            if (byteToLock > targetCursor)
            {
                bytesToWrite = (soundOutput.secondaryBufferSize - byteToLock) + targetCursor;
            }
            else
            {
                bytesToWrite = targetCursor - byteToLock;
            }

            GameSoundOutputBuffer gameSoundBuffer = {
                samples:     gameSoundSamples,
                sampleRate:  soundOutput.sampleRate,
                sampleCount: bytesToWrite / soundOutput.bytesPerSample
            };

            gameOutputSound(gameMemory, gameSoundBuffer);

            win32FillSoundBuffer(soundOutput, gameSoundBuffer, byteToLock, bytesToWrite);
        }
        else
        {
            soundIsValid = false;
        }

        long postUpdateFrameTimer = win32GetPerformanceCounter();
        long postUpdateTimerElapsed = postUpdateFrameTimer - prevFrameTimer;
        float millisPerFrame = (MILLIS_PER_SECOND * postUpdateTimerElapsed) / perfCounterFrequency;

        // Sync to our target frame rate
        if (millisPerFrame < TARGET_MILLIS_PER_UPDATE)
        {
            uint millisToSleep = cast(uint)(TARGET_MILLIS_PER_UPDATE - millisPerFrame);

            // TODO: Should we do something other than a spinlock if we don't have a high resolution timer?
            if (isTimerHighResolution && millisToSleep >= minSleepInMillis)
            {
                Sleep(cast(DWORD)(millisToSleep - 0.5f));
            }

            // Spin until we're ready to blit the frame
            do
            {
                postUpdateFrameTimer = win32GetPerformanceCounter();
                postUpdateTimerElapsed = postUpdateFrameTimer - prevFrameTimer;
                millisPerFrame = (MILLIS_PER_SECOND * postUpdateTimerElapsed) / perfCounterFrequency;
            }
            while (millisPerFrame < TARGET_MILLIS_PER_UPDATE);
        }
        else
        {
            // TODO: Handle missed frame rate
            debug writeln("Missed frame rate!");
        }

        // NOTE: Snapshot the time just before we present the frame
        long presentFrameTimer = win32GetPerformanceCounter();
        long presentTimerElapsed = presentFrameTimer - prevFrameTimer;
        ulong presentCycleCount = win32GetCycleCounter();

        debug
        {
            static size_t debugFrameIndex;
            static DWORD[GAME_UPDATE_HZ / 2] debugPlayCursorPrev, debugWriteCursorPrev;

            win32DebugSyncDisplay(
                globalBackBuffer, soundOutput,
                debugPlayCursorPrev,
                debugWriteCursorPrev,
                cast(int)(debugFrameIndex - 1),
                TARGET_MILLIS_PER_UPDATE
            );
        }

        const dimensions = win32GetWindowDimensions(window);
        win32BlitBufferToWindow(globalBackBuffer, deviceContext, dimensions.tuple);

        debug
        {
            if (globalSecondaryBuffer)
            {
                debugPlayCursorPrev[debugFrameIndex] = playCursor;
                debugWriteCursorPrev[debugFrameIndex] = writeCursor;
                debugFrameIndex = (debugFrameIndex + 1) % (GAME_UPDATE_HZ / 2);
            }
        }

        debug
        {
            enum float MEGACYCLE = 1_000_000.0f;

            long cyclesElapsed = presentCycleCount - prevCycleCount;
            millisPerFrame = (MILLIS_PER_SECOND * presentTimerElapsed) / perfCounterFrequency;
            float fps = cast(float)(perfCounterFrequency) / cast(float)(presentTimerElapsed);

            writefln("Frame time: %.02fms/f (%.02f FPS) %.02fMC/f", millisPerFrame, fps, cyclesElapsed / MEGACYCLE);
        }

        prevFrameTimer = presentFrameTimer;
        prevCycleCount = presentCycleCount;

        // Swap input indices
        currInputIndex = 1 - currInputIndex;
        prevInputIndex = 1 - prevInputIndex;
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
