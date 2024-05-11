module hhd.platform.common;

struct GameOffscreenBuffer
{
    void* memory; // NOTE: Pixels are always 32-bits wide, Memory Order BB GG RR XX

    int width;
    int height;
    int pitch;
}

struct GameSoundOutputBuffer
{
    short* samples;

    int sampleRate;
    int sampleCount;
}

enum GameButton : uint
{
    dpadUp,
    dpadDown,
    dpadLeft,
    dpadRight,
    start,
    back,
    a,
    b,
    x,
    y,
    leftShoulder,
    rightShoulder
}

enum GameStick : uint
{
    left = 0,
    right = 1
}

struct GameButtonInput
{
    bool isDown;
    uint transitionsCount;

    @property
    bool isUp() const nothrow @nogc
    {
        return !isDown;
    }

    @property
    bool wasPressed() const nothrow @nogc
    {
        return isDown && transitionsCount > 0;
    }

    @property
    bool wasReleased() const nothrow @nogc
    {
        return !isDown && transitionsCount > 0;
    }
}

struct GameStickInput
{
    bool isAnalog;

    float startX = 0.0;
    float startY = 0.0;

    float endX = 0.0;
    float endY = 0.0;
}

enum uint GAME_BUTTONS_COUNT = GameButton.max + 1;
enum uint GAME_STICKS_COUNT = GameStick.max + 1;

struct GameControllerInput
{
    bool isConnected;

    union
    {
        GameButtonInput[GAME_BUTTONS_COUNT] buttons;
        struct
        {
            static foreach (i; 0..GAME_BUTTONS_COUNT)
            {
                mixin("GameButtonInput " ~ __traits(allMembers, GameButton)[i] ~ "Button;");
            }
        }
    }

    union
    {
        GameStickInput[GAME_STICKS_COUNT] sticks;
        struct
        {
            GameStickInput leftStick;
            GameStickInput rightStick;
        }
    }
}

enum GAME_INPUT_CONTROLLERS_COUNT = 4;

struct GameInput
{
    GameControllerInput[GAME_INPUT_CONTROLLERS_COUNT] controllers;
}

extern (System) void gameOutputSound(in ref GameSoundOutputBuffer soundBuffer) nothrow @nogc;
extern (System) void gameUpdateAndRender(in ref GameInput input, in ref GameOffscreenBuffer buffer) nothrow @nogc;
