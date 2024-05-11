module hhd.platform.win32.xinput;

import core.sys.windows.windows;

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
    enum float MAX_THUMB = +32_767.0f;
    enum float MIN_THUMB = -32_768.0f;

    enum SHORT LEFT_THUMB_DEADZONE = 7849;
    enum SHORT RIGHT_THUMB_DEADZONE = 8689;

    WORD wButtons;
    BYTE bLeftTrigger;
    BYTE bRightTrigger;
    SHORT sThumbLX;
    SHORT sThumbLY;
    SHORT sThumbRX;
    SHORT sThumbRY;
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

bool isPressed(in ref XINPUT_GAMEPAD gamepad, WORD button) nothrow @nogc
{
    return (gamepad.wButtons & button) == button;
}

pragma(inline, true)
@property
float leftThumbX(in ref XINPUT_GAMEPAD gamepad) nothrow @nogc
{
    if (gamepad.sThumbLX < 0)
    {
        return gamepad.sThumbLX / -XINPUT_GAMEPAD.MIN_THUMB;
    }
    else if (gamepad.sThumbLX > 0)
    {
        return gamepad.sThumbLX / +XINPUT_GAMEPAD.MAX_THUMB;
    }
    else
    {
        return 0.0f;
    }
}

pragma(inline, true)
@property
float leftThumbY(in ref XINPUT_GAMEPAD gamepad) nothrow @nogc
{
    if (gamepad.sThumbLY < 0)
    {
        return gamepad.sThumbLY / -XINPUT_GAMEPAD.MIN_THUMB;
    }
    else if (gamepad.sThumbLY > 0)
    {
        return gamepad.sThumbLY / +XINPUT_GAMEPAD.MAX_THUMB;
    }
    else
    {
        return 0.0f;
    }
}

pragma(inline, true)
@property
float rightThumbX(in ref XINPUT_GAMEPAD gamepad) nothrow @nogc
{
    if (gamepad.sThumbRX < 0)
    {
        return gamepad.sThumbRX / -XINPUT_GAMEPAD.MIN_THUMB;
    }
    else if (gamepad.sThumbRX > 0)
    {
        return gamepad.sThumbRX / +XINPUT_GAMEPAD.MAX_THUMB;
    }
    else
    {
        return 0.0f;
    }
}

pragma(inline, true)
@property
float rightThumbY(in ref XINPUT_GAMEPAD gamepad) nothrow @nogc
{
    if (gamepad.sThumbRY < 0)
    {
        return gamepad.sThumbRY / -XINPUT_GAMEPAD.MIN_THUMB;
    }
    else if (gamepad.sThumbRY > 0)
    {
        return gamepad.sThumbRY / +XINPUT_GAMEPAD.MAX_THUMB;
    }
    else
    {
        return 0.0f;
    }
}
