module hhd.platform.win32;

debug import core.stdc.stdio;
import core.sys.windows.windows;

// TODO: Extract this from global state
__gshared bool isRunning;
__gshared BITMAPINFO bitmapInfo;
__gshared void* bitmapMemory;
__gshared HBITMAP bitmapHandle;
__gshared HDC bitmapDeviceContext;

@nogc
private void
win32ResizeDIBSection(int width, int height) nothrow
{
    // TODO: Bulletproof this
    // Maybe don't free first, free after, then free first if that fails

    if (bitmapHandle)
    {
        DeleteObject(bitmapHandle);
    }

    if (bitmapDeviceContext is null)
    {
        // TODO: Should we recreate this ever?
        bitmapDeviceContext = CreateCompatibleDC(null);
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

    bitmapHandle = CreateDIBSection(
        bitmapDeviceContext,
        &bitmapInfo,
        DIB_RGB_COLORS,
        &bitmapMemory,
        null, 0
    );
}

@nogc
private void
win32UpdateWindow(HDC deviceContext, int x, int y, int width, int height) nothrow
{
    StretchDIBits(
        deviceContext,
        x, y, width, height,
        x, y, width, height, // TODO: input buffer dimensions
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

                PatBlt(
                    deviceContext,
                    paint.rcPaint.left,
                    paint.rcPaint.top,
                    paint.rcPaint.right - paint.rcPaint.left,
                    paint.rcPaint.bottom - paint.rcPaint.top,
                    WHITENESS
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
    catch (Throwable t) // TODO: Remove this in release (only debug can raise exceptions)
    {
        debug
        {
            enum MAX_ERROR_LENGTH = 2500;
            char[MAX_ERROR_LENGTH + 1] buffer;
            string error = t.toString();
            size_t length = error.length > MAX_ERROR_LENGTH ? MAX_ERROR_LENGTH : error.length;
            buffer[0..length] = t.toString()[0..length];
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

    while (isRunning)
    {
        MSG message;
        BOOL result = GetMessage(&message, window, 0, 0);

        if (result > 0)
        {
            TranslateMessage(&message);
            DispatchMessage(&message);
        }
        else
        {
            break;
        }
    }

    return 0;
}
