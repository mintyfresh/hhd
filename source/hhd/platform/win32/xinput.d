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

