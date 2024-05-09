module hhd.platform.win32;

import core.sys.windows.windows;

debug
{
    import core.exception;
    import core.stdc.stdio;
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

private
{
    // TODO: Extract this from global state
    __gshared bool isRunning;
    __gshared Win32OffscreenBuffer globalBackBuffer;
}

private Win32WindowDimensions
win32GetWindowDimensions(HWND window) nothrow @nogc
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
win32DrawBufferToWindow(
    HDC deviceContext, in ref Win32OffscreenBuffer buffer,
    LONG windowWidth, LONG windowHeight,
    int x, int y, int width, int height
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

extern (Windows)
LRESULT
win32WindowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam) nothrow @nogc
{
    LRESULT result;

    try
    {
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

            // case WM_ACTIVATEAPP:
            // {
            //     debug printf("Message: WM_ACTIVEAPP\n");
            // }
            // break;

            case WM_PAINT:
            {
                PAINTSTRUCT paint;
                HDC deviceContext = BeginPaint(window, &paint);

                auto dimensions = win32GetWindowDimensions(window);

                win32DrawBufferToWindow(
                    deviceContext, globalBackBuffer,
                    dimensions.width, dimensions.height,
                    paint.rcPaint.left, paint.rcPaint.top,
                    paint.rcPaint.right, paint.rcPaint.bottom
                );

                EndPaint(window, &paint);
            }
            break;

            default:
            {
                result = DefWindowProc(window, message, wParam, lParam);
            }
        }
    }
    catch (core.exception.AssertError e) // TODO: Remove this in release (only debug can raise exceptions)
    {
        debug
        {
            enum MAX_ERROR_LENGTH = 2500;
            char[MAX_ERROR_LENGTH + 1] buffer;
            string error = e.toString();
            size_t length = error.length > MAX_ERROR_LENGTH ? MAX_ERROR_LENGTH : error.length;
            buffer[0..length] = error[0..length];
            buffer[$ - 1] = 0; // Ensure null-termination
            printf("Error: %s\n", buffer.ptr);
        }

        PostQuitMessage(-1);
    }

    return result;
}

extern (Windows)
int
main() nothrow @nogc
{
    HINSTANCE instance = GetModuleHandle(NULL);

    debug
    {
        assert(instance, "Failed to acquire HINSTANCE");
        printf("HINSTANCE: %p\n", instance);
    }

    win32ResizeDIBSection(globalBackBuffer, 1280, 720);

    WNDCLASS windowClass = {
        style: CS_HREDRAW | CS_VREDRAW,
        hInstance: instance,
        lpszClassName: "HHDWindowClass",
        lpfnWndProc: &win32WindowProc
    };

    ATOM registerWindowResult = RegisterClass(&windowClass);

    debug
    {
        assert(registerWindowResult, "Failed to register window class.");
        printf("Regsitered window class: %d\n", registerWindowResult);
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
        printf("Created window successfully\n");
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

        renderFunkyGradient(globalBackBuffer, xOffset, yOffset);
        xOffset++;
        yOffset++;
    
        HDC deviceContext = GetDC(window);
        scope (exit) ReleaseDC(window, deviceContext);

        auto dimensions = win32GetWindowDimensions(window);

        win32DrawBufferToWindow(
            deviceContext, globalBackBuffer,
            dimensions.width, dimensions.height,
            0, 0, 0, 0
        );
    }

    return 0;
}
