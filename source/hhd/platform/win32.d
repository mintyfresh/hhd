module hhd.platform.win32;

import core.sys.windows.windows;

debug
{
    import core.exception;
    import std.stdio;
}

enum : WORD
{
    XINPUT_GAMEPAD_DPAD_UP = 0x0001,
    XINPUT_GAMEPAD_DPAD_DOWN = 0x0002,
    XINPUT_GAMEPAD_DPAD_LEFT = 0x0004,
    XINPUT_GAMEPAD_DPAD_RIGHT = 0x0008,
    XINPUT_GAMEPAD_START = 0x0010,
    XINPUT_GAMEPAD_BACK = 0x0020,
    XINPUT_GAMEPAD_LEFT_THUMB = 0x0040,
    XINPUT_GAMEPAD_RIGHT_THUMB = 0x0080,
    XINPUT_GAMEPAD_LEFT_SHOULDER = 0x0100,
    XINPUT_GAMEPAD_RIGHT_SHOULDER = 0x0200,
    XINPUT_GAMEPAD_A = 0x1000,
    XINPUT_GAMEPAD_B = 0x2000,
    XINPUT_GAMEPAD_X = 0x4000,
    XINPUT_GAMEPAD_Y = 0x8000
}

struct XINPUT_GAMEPAD
{
    WORD wButtons;
    BYTE bLeftTrigger;
    BYTE bRightTrigger;
    SHORT sThumbLX;
    SHORT sThumbLY;
    SHORT sThumbRX;
    SHORT sThumbRY;

    bool isPressed(WORD button) const nothrow @nogc
    {
        return (wButtons & button) == button;
    }
}

struct XINPUT_STATE
{
    DWORD dwPacketNumber;
    XINPUT_GAMEPAD gamepad;
}

struct XINPUT_VIBRATION
{
    WORD wLeftMotorSpeed;
    WORD wRightMotorSpeed;
}

extern (Windows) nothrow @nogc
{
    alias procXInputGetState = DWORD function(DWORD dwUserIndex, XINPUT_STATE* pState);
    alias procXInputSetState = DWORD function(DWORD dwUserIndex, XINPUT_VIBRATION* pVibration);
}

__gshared
{
    procXInputGetState XInputGetState = (DWORD, XINPUT_STATE*) => ERROR_DEVICE_NOT_CONNECTED;
    procXInputSetState XInputSetState = (DWORD, XINPUT_VIBRATION*) => ERROR_DEVICE_NOT_CONNECTED;
}

enum DWORD XUSER_MAX_COUNT = 4;

/// XInput libraries in order of preference
private immutable const(char)*[] X_INPUT_LIBRARIES = [
    "xinput1_4.dll",
    "xinput1_3.dll",
    "xinput9_1_0.dll"
];

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

__gshared private
{
    // TODO: Extract this from global state
    bool isRunning;
    Win32OffscreenBuffer globalBackBuffer;
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
win32CreatePixel(uint red, uint green, uint blue) nothrow @nogc
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

extern (Windows) LRESULT
win32WindowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam) nothrow @nogc
{
    LRESULT result;

    switch (message)
    {
        case WM_CLOSE:
        {
            // TODO: Prompt the user to confirm
            isRunning = false;
        }
        break;

        case WM_DESTROY:
        {
            // TODO: Was this an error?
            isRunning = false;
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

            if (currDown != prevDown)
            {
                switch (vkCode)
                {
                    case VK_ESCAPE:
                    {
                        // TODO: Prompt the user to confirm
                        isRunning = false;
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
        style: CS_HREDRAW | CS_VREDRAW,
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

    isRunning = true;

    int xOffset = 0;
    int yOffset = 0;

    while (isRunning)
    {
        MSG message;
        while (PeekMessage(&message, null, 0, 0, PM_REMOVE))
        {
            if (message.message == WM_QUIT)
            {
                isRunning = false;
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
    
        HDC deviceContext = GetDC(window);
        scope (exit) ReleaseDC(window, deviceContext);

        auto dimensions = win32GetWindowDimensions(window);

        win32BlitBufferToWindow(
            globalBackBuffer, deviceContext,
            dimensions.width, dimensions.height
        );
    }

    return 0;
}
