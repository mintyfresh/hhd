module hhd.game.main;

import hhd.math;
import hhd.platform.common;

extern (System) void
gameOutputSound(in ref GameSoundOutputBuffer soundBuffer, int toneHz) nothrow @nogc
{
    enum TONE_VOLUME = 1000.0f;

    static float tSine = 0.0f;

    float tonePeriod = soundBuffer.sampleRate / toneHz;
    short* sampleOutput = cast(short*) soundBuffer.samples;

    foreach (sampleIndex; 0..soundBuffer.sampleCount)
    {
        short sampleValue = cast(short)(sinf(tSine) * TONE_VOLUME);

        *sampleOutput++ = sampleValue;
        *sampleOutput++ = sampleValue;

        tSine += (2.0f * PI) / tonePeriod;
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
gameUpdateAndRender(in ref GameOffscreenBuffer buffer, int xOffset, int yOffset) nothrow @nogc
{
    renderFunkyGradient(buffer, xOffset, yOffset);
}
