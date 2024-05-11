module hhd.game.main;

import hhd.math;
import hhd.platform.common;

static int toneHz = 256;

extern (System) void
gameOutputSound(in ref GameSoundOutputBuffer soundBuffer) nothrow @nogc
{
    enum TONE_VOLUME = 1000.0f;

    static float tSine = 0.0f;

    // TODO: What do we do if toneHz is zero?
    float tonePeriod = toneHz != 0
        ? soundBuffer.sampleRate / toneHz
        : 0.0f;
    short* sampleOutput = cast(short*) soundBuffer.samples;

    foreach (sampleIndex; 0..soundBuffer.sampleCount)
    {
        short sampleValue = cast(short)(sinf(tSine) * TONE_VOLUME);

        *sampleOutput++ = sampleValue;
        *sampleOutput++ = sampleValue;

        tSine += tonePeriod != 0.0f
            ? (2.0f * PI) / tonePeriod
            : 0.0f;
    }
}

pragma(inline, true)
private uint
createBRGPixel(uint red, uint green, uint blue) pure nothrow @nogc
{
    return (red << 16) | (green << 8) | (blue << 0);
}

private void
renderFunkyGradient(in ref GameOffscreenBuffer buffer, int xOffset, int yOffset) nothrow @nogc
{
    ubyte* row = cast(ubyte*) buffer.memory;

    foreach (y; 0..buffer.height)
    {
        uint* pixel = cast(uint*) row;

        foreach (x; 0..buffer.width)
        {
            ubyte blue  = cast(ubyte)(x + xOffset);
            ubyte green = cast(ubyte)(y + yOffset);

            *pixel++ = createBRGPixel(0, green, blue);
        }

        row += buffer.pitch;
    }
}

extern (System) void
gameUpdateAndRender(in ref GameInput input, in ref GameOffscreenBuffer buffer) nothrow @nogc
{
    static int xOffset = 0, yOffset = 0;

    GameControllerInput controllerInput = input.controllers[0];

    if (controllerInput.leftStick.isAnalog)
    {
        // TODO: Analog input handling
        toneHz = cast(int)(256.0f + 256.0f * controllerInput.leftStick.endX);
        yOffset += cast(int)(10.0f * controllerInput.leftStick.endY);
    }
    else
    {
        // TODO: Digital input handling
    }

    if (controllerInput.xButton.isDown)
    {
        xOffset += 10;
    }
    if (controllerInput.bButton.isDown)
    {
        xOffset -= 10;
    }

    renderFunkyGradient(buffer, xOffset, yOffset);
}
