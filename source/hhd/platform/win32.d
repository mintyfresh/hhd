module hhd.platform.win32;

debug import core.stdc.stdio;
import core.sys.windows.windows;

extern (Windows) LRESULT
win32WindowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam) nothrow
{
    LRESULT result;

    switch (message)
    {
        // case WM_SIZE:
        // {
        //     debug printf("Message: WM_SIZE\n");
        // }
        // break;

        // case WM_DESTROY:
        // {
        //     debug printf("Message: WM_DESTROY\n");
        // }
        // break;

        // case WM_CLOSE:
        // {
        //     debug printf("Message: WM_CLOSE\n");
        // }
        // break;

        // case WM_ACTIVATEAPP:
        // {
        //     debug printf("Message: WM_ACTIVEAPP\n");
        // }
        // break;

        case WM_PAINT:
        {
            PAINTSTRUCT paint;
            HDC deviceContext = BeginPaint(window, &paint);

            static DWORD operation = WHITENESS;

            PatBlt(
                deviceContext,
                paint.rcPaint.left,
                paint.rcPaint.top,
                paint.rcPaint.right - paint.rcPaint.left,
                paint.rcPaint.bottom - paint.rcPaint.top,
                operation
            );

            if (operation == WHITENESS)
            {
                operation = BLACKNESS;
            }
            else
            {
                operation = WHITENESS;
            }

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

@nogc
int
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
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
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

    while (true)
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
