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

    enum BYTE TRIGGER_THRESHOLD = 30;

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
    return calculateThumbValue!(XINPUT_GAMEPAD.LEFT_THUMB_DEADZONE)(gamepad.sThumbLX);
}

pragma(inline, true)
@property
float leftThumbY(in ref XINPUT_GAMEPAD gamepad) nothrow @nogc
{
    return calculateThumbValue!(XINPUT_GAMEPAD.LEFT_THUMB_DEADZONE)(gamepad.sThumbLY);
}

pragma(inline, true)
@property
float rightThumbX(in ref XINPUT_GAMEPAD gamepad) nothrow @nogc
{
    return calculateThumbValue!(XINPUT_GAMEPAD.RIGHT_THUMB_DEADZONE)(gamepad.sThumbRX);
}

pragma(inline, true)
@property
float rightThumbY(in ref XINPUT_GAMEPAD gamepad) nothrow @nogc
{
    return calculateThumbValue!(XINPUT_GAMEPAD.RIGHT_THUMB_DEADZONE)(gamepad.sThumbRY);
}

pragma(inline, true)
private float calculateThumbValue(SHORT deadzone)(SHORT thumbValue) nothrow @nogc
{
    static assert(deadzone >= 0, "Deadzone must be non-negative.");

    if (thumbValue < -(deadzone + 1))
    {
        // NOTE: thumbValue and MIN_THUMB are both negative here
        // Flip the sign of MIN_THUMB to so our quotient is negative
        return (thumbValue + deadzone) / (-XINPUT_GAMEPAD.MIN_THUMB - deadzone);
    }
    else if (thumbValue > deadzone)
    {
        return (thumbValue - deadzone) / (+XINPUT_GAMEPAD.MAX_THUMB - deadzone);
    }
    else
    {
        return 0.0f;
    }
}
