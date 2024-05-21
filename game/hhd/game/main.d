module hhd.game.main;

import hhd.math;
import hhd.platform.common;

struct GameState
{
    int toneHz;
    int xOffset;
    int yOffset;

    float tSine;
}

export extern (System)
void gameOutputSound(
    scope ref GameMemory memory,
    scope ref GameSoundOutputBuffer soundBuffer
) nothrow @nogc
{
    enum TONE_VOLUME = 2500.0f;
    GameState* gameState = memory.permanent!(GameState);

    // TODO: What do we do if toneHz is zero?
    float tonePeriod = gameState.toneHz != 0
        ? soundBuffer.sampleRate / gameState.toneHz
        : 0.0f;

    size_t sampleIndex = 0;
    foreach (_; 0..soundBuffer.sampleCount)
    {
        short sampleValue = cast(short)(sinf(gameState.tSine) * TONE_VOLUME);

        soundBuffer.samples[sampleIndex++] = sampleValue;
        soundBuffer.samples[sampleIndex++] = sampleValue;

        gameState.tSine += tonePeriod != 0.0f
            ? (2.0f * PI) / tonePeriod
            : 0.0f;

        if (gameState.tSine > 2.0f * PI)
        {
            gameState.tSine -= 2.0f * PI;
        }
    }
}

pragma(inline, true)
private uint createBRGPixel(uint red, uint green, uint blue) pure nothrow @nogc
{
    return (red << 16) | (green << 8) | (blue << 0);
}

private void renderFunkyGradient(in ref GameOffscreenBuffer buffer, int xOffset, int yOffset) nothrow @nogc
{
    ubyte* row = cast(ubyte*) buffer.memory;

    foreach (y; 0..buffer.height)
    {
        uint* pixel = cast(uint*) row;

        foreach (x; 0..buffer.width)
        {
            ubyte blue  = cast(ubyte)(x + xOffset);
            ubyte green = cast(ubyte)(y + yOffset);

            *pixel++ = createBRGPixel(green, 0, blue);
        }

        row += buffer.pitch;
    }
}

export extern (System)
void gameUpdateAndRender(
    scope ref GameMemory memory,
    in ref GameInput input,
    in ref GameOffscreenBuffer buffer
) nothrow @nogc
{
    GameState* gameState = memory.permanent!(GameState);

    // TODO: Should this be a separate initialize hook?
    if (!memory.isInitialized)
    {
        gameState.toneHz  = 512;
        gameState.xOffset = 0;
        gameState.yOffset = 0;
        gameState.tSine   = 0.0f;

        memory.isInitialized = true;

        debug
        {
            void[] data = memory.debugReadEntireFile(__FILE__);
            assert(data.length > 0, "Failed to read file.");

            memory.debugWriteEntireFile("tmp/debug.tmp", data);
            memory.debugFreeFileMemory(data);
        }
    }

    // TODO: Handle the rest of the controllers
    GameControllerInput controllerInput = input.controllers[0];

    // TODO: Handle the rest of the keyboards
    GameKeyboardInput keyboardInput = input.keyboards[0];

    if (controllerInput.isConnected)
    {
        // TODO: Analog input handling
        gameState.toneHz = cast(int)(256.0f + 256.0f * controllerInput.leftStick.endX);
        gameState.yOffset += cast(int)(10.0f * controllerInput.leftStick.endY);
    }

    if (keyboardInput.wKey.isDown)
    {
        gameState.yOffset -= 10;
    }
    if (keyboardInput.sKey.isDown)
    {
        gameState.yOffset += 10;
    }

    if (keyboardInput.qKey.isDown)
    {
        gameState.toneHz += 10;
    }
    else if (keyboardInput.eKey.isDown)
    {
        gameState.toneHz -= 10;
    }

    if (controllerInput.xButton.isDown || keyboardInput.dKey.isDown)
    {
        gameState.xOffset += 10;
    }
    if (controllerInput.bButton.isDown || keyboardInput.aKey.isDown)
    {
        gameState.xOffset -= 10;
    }

    renderFunkyGradient(buffer, gameState.xOffset, gameState.yOffset);
}
