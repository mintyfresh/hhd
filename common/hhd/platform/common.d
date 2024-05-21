module common.hhd.platform.common;

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

enum GameKey : uint
{
    w,
    a,
    s,
    d,
    q,
    e,
    space,
    escape
}

enum uint GAME_KEYS_COUNT = GameKey.max + 1;

struct GameKeyInput
{
    bool isDown;
    uint transitionsCount;

    // TODO: These look identical to the GameButtonInput
    // Extract these into a mixin or a common struct?

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

struct GameKeyboardInput
{
    bool isConnected;

    union
    {
        GameKeyInput[GAME_KEYS_COUNT] keys;
        struct
        {
            static foreach (i; 0..GAME_KEYS_COUNT)
            {
                mixin("GameKeyInput " ~ __traits(allMembers, GameKey)[i] ~ "Key;");
            }
        }
    }
}

enum GAME_INPUT_CONTROLLERS_COUNT = 4;
enum GAME_INPUT_KEYBOARDS_COUNT = 1;

struct GameInput
{
    GameControllerInput[GAME_INPUT_CONTROLLERS_COUNT] controllers;
    GameKeyboardInput[GAME_INPUT_KEYBOARDS_COUNT] keyboards;
}

// NOTE: These are only for development purposes
// They are synchronous, unsafe, and blocking
// It also doesn't handle failed writes
debug
{
    // Platform layer APIs
    extern (System) nothrow @nogc
    {
        alias DebugReadEntireFileProc = void[] function(const(char)* fileName);
        alias DebugWriteEntireFileProc = bool function(const(char)* fileName, void[] buffer);
        alias DebugFreeFileMemoryProc = bool function(void[] memory);
    }
}

struct GameMemory
{
    bool isInitialized;

    // NOTE: All memory must be zeroed at startup
    size_t permanentStorageSize;
    void* permanentStorage;

    // NOTE: All memory must be zeroed at startup
    size_t transientStorageSize;
    void* transientStorage;

    debug
    {
        DebugReadEntireFileProc debugReadEntireFile;
        DebugWriteEntireFileProc debugWriteEntireFile;
        DebugFreeFileMemoryProc debugFreeFileMemory;
    }

    @property
    T* permanent(T)(size_t offset = 0) nothrow @nogc
    in
    {
        assert(permanentStorage !is null, "Permanent storage is not initialized");
        assert(offset + T.sizeof <= permanentStorageSize, "Permanent storage is not large enough");
    }
    do
    {
        return cast(T*)(permanentStorage + offset);
    }
}

// Game layer APIs
extern (System) nothrow @nogc
{
    alias GameOutputSoundProc = void function(
        scope ref GameMemory memory,
        scope ref GameSoundOutputBuffer soundBuffer
    );

    alias GameUpdateAndRenderProc = void function(
        scope ref GameMemory memory,
        in ref GameInput input,
        in ref GameOffscreenBuffer buffer
    );
}

