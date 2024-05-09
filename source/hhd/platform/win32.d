module hhd.platform.win32;

import core.sys.windows.windows;

debug
{
    import core.exception;
    import core.stdc.stdio;
}

// TODO: Extract this from global state
__gshared bool isRunning;
__gshared BITMAPINFO bitmapInfo;
__gshared void* bitmapMemory;

@nogc
private void
renderFunkyGradient(int xOffset, int yOffset) nothrow
{
    uint width = bitmapInfo.bmiHeader.biWidth;
    uint height = bitmapInfo.bmiHeader.biHeight;
    uint bytesPerPixel = 4;

    uint pitch = width * bytesPerPixel;
    ubyte* row = cast(ubyte*) bitmapMemory;

    foreach (y; 0..height)
    {
        ubyte* pixel = cast(ubyte*) row;

        foreach (x; 0..width)
        {
            *pixel++ = cast(ubyte)(x + xOffset);
            *pixel++ = cast(ubyte)(y + yOffset);
            *pixel++ = 0;
            *pixel++ = 0;
        }

        row += pitch;
    }
}

@nogc
private void
win32ResizeDIBSection(int width, int height) nothrow
{
    // TODO: Bulletproof this
    // Maybe don't free first, free after, then free first if that fails

    if (bitmapMemory)
    {
        VirtualFree(bitmapMemory, 0, MEM_RELEASE);
    }

    BITMAPINFOHEADER bitmapHeader = {
        biSize: BITMAPINFOHEADER.sizeof,
        biWidth: width,
        biHeight: height,
        biPlanes: 1,
        biBitCount: 32,
        biCompression: BI_RGB
    };
    bitmapInfo.bmiHeader = bitmapHeader;

    debug
    {
        assert(bitmapHeader.biXPelsPerMeter == 0, "Expected 0");
        assert(bitmapHeader.biYPelsPerMeter == 0, "Expected 0");
    }

    enum bytesPerPixel = 4;
    auto bitmapMemorySize = width * height * bytesPerPixel;

    bitmapMemory = VirtualAlloc(
        null,
        bitmapMemorySize,
        MEM_COMMIT,
        PAGE_READWRITE
    );

    debug
    {
        assert(bitmapMemory, "Failed to allocate memory for bitmap");
    }

    // TODO: Probably clear this to black
}

@nogc
private void
win32UpdateWindow(HDC deviceContext, in ref RECT windowRect, int x, int y, int width, int height) nothrow
{
    int bitmapWidth = bitmapInfo.bmiHeader.biWidth;
    int bitmapHeight = bitmapInfo.bmiHeader.biHeight;
    int windowWidth = windowRect.right - windowRect.left;
    int windowHeight = windowRect.bottom - windowRect.top;

    StretchDIBits(
        deviceContext,
        0, 0, windowWidth, windowHeight,
        0, 0, bitmapWidth, bitmapHeight,
        bitmapMemory, &bitmapInfo,
        DIB_RGB_COLORS, SRCCOPY
    );
}

@nogc
extern (Windows) LRESULT
win32WindowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam) nothrow
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

            case WM_SIZE:
            {
                RECT clientRect;
                GetClientRect(window, &clientRect);

                int width = clientRect.right - clientRect.left;
                int height = clientRect.bottom - clientRect.top;

                win32ResizeDIBSection(width, height);
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

                win32UpdateWindow(
                    deviceContext,
                    paint.rcPaint,
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

@nogc
extern (Windows) int
main() nothrow
{
    HINSTANCE instance = GetModuleHandle(NULL);

    debug
    {
        assert(instance, "Failed to acquire HINSTANCE");
        printf("HINSTANCE: %p\n", instance);
    }

    WNDCLASS windowClass = {
        style: CS_OWNDC | CS_HREDRAW | CS_VREDRAW,
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
        null,
        null,
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

        renderFunkyGradient(xOffset, yOffset);
        xOffset++;
        yOffset++;
    
        HDC deviceContext = GetDC(window);
        scope (exit) ReleaseDC(window, deviceContext);

        RECT windowRect;
        GetClientRect(window, &windowRect);

        win32UpdateWindow(deviceContext, windowRect, 0, 0, 0, 0);
    }

    return 0;
}
